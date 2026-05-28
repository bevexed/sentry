#!/bin/bash
# ============================================
# Sentry 数据自动清理脚本（基于 DROP PARTITION）
# 直接删除过期分区，立刻释放磁盘，无需等待 mutation
# 用法: ./scripts/cleanup-data.sh [保留天数]
# 默认保留 14 天
# ============================================

set -e

# 保留天数，默认 14
RETENTION_DAYS=${1:-14}
CLICKHOUSE_CONTAINER="sentry-clickhouse-1"

echo "=========================================="
echo "Sentry 数据清理（DROP PARTITION 模式）"
echo "保留最近 ${RETENTION_DAYS} 天的数据"
echo "=========================================="

# 检查 ClickHouse 容器是否运行
if ! docker ps --format '{{.Names}}' | grep -q "${CLICKHOUSE_CONTAINER}"; then
  echo "错误: ClickHouse 容器未运行"
  exit 1
fi

# ClickHouse 客户端封装
ch() {
  docker exec "${CLICKHOUSE_CONTAINER}" clickhouse-client "$@"
}

# 清理一张表的过期分区
# 参数: $1=表名 $2=用于时间判断的列（默认用 system.parts.max_time，故此参数仅做记录）
cleanup_table() {
  local table="$1"

  # 表不存在直接跳过
  if ! ch --query "EXISTS TABLE ${table}" 2>/dev/null | grep -q "^1$"; then
    echo "⚠ ${table}: 表不存在，跳过"
    return
  fi

  echo ""
  echo ">>> 处理表: ${table}"

  # 查询所有「最大时间早于保留期」的活跃分区（不去重: 同 partition_id 多 part 会被 GROUP 合并）
  local partitions
  partitions=$(ch --query "
    SELECT partition_id
    FROM system.parts
    WHERE database = 'default'
      AND table = '${table}'
      AND active = 1
      AND partition_id != 'all'
    GROUP BY partition_id
    HAVING max(max_time) < now() - INTERVAL ${RETENTION_DAYS} DAY
    ORDER BY partition_id
  ")

  if [ -z "${partitions}" ]; then
    echo "  无过期分区"
    return
  fi

  local count
  count=$(echo "${partitions}" | wc -l | tr -d ' ')
  echo "  发现 ${count} 个过期分区，开始 DROP..."

  local ok=0
  local fail=0
  while IFS= read -r pid; do
    [ -z "${pid}" ] && continue
    if ch --query "ALTER TABLE ${table} DROP PARTITION ID '${pid}'" 2>/tmp/ch_err; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
      echo "  ✗ DROP PARTITION ID '${pid}' 失败:"
      sed 's/^/      /' /tmp/ch_err
    fi
  done <<< "${partitions}"

  echo "  完成: 成功 ${ok}, 失败 ${fail}"
}

# 各业务表清理
cleanup_table "errors_local"
cleanup_table "transactions_local"
cleanup_table "replays_local"
cleanup_table "spans_local"
cleanup_table "outcomes_raw_local"
cleanup_table "outcomes_hourly_local"

# 清理已分离的旧 parts，立刻释放磁盘
echo ""
echo ">>> 清理 detached parts 与旧 parts"
ch --query "SYSTEM DROP DETACHED PARTS" 2>/dev/null || true

# 输出最终各表占用，便于核对
echo ""
echo ">>> 当前各表磁盘占用 TOP 15"
ch --query "
SELECT database, table,
       formatReadableSize(sum(bytes_on_disk)) AS size,
       sum(rows) AS rows
FROM system.parts
WHERE active
GROUP BY database, table
ORDER BY sum(bytes_on_disk) DESC
LIMIT 15
FORMAT PrettyCompact"

echo ""
echo "=========================================="
echo "清理完成！"
echo "提示: 物理文件删除受 old_parts_lifetime (默认 8 分钟) 控制"
echo "=========================================="
