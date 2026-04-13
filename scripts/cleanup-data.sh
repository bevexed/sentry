#!/bin/bash
# ============================================
# Sentry 数据自动清理脚本
# 定期清理 ClickHouse 中的过期数据
# 用法: ./scripts/cleanup-data.sh [保留天数]
# 默认保留 30 天
# ============================================

set -e

# 保留天数，默认 14
RETENTION_DAYS=${1:-14}
CLICKHOUSE_CONTAINER="sentry-clickhouse-1"

echo "=========================================="
echo "Sentry 数据清理"
echo "保留最近 ${RETENTION_DAYS} 天的数据"
echo "=========================================="

# 检查 ClickHouse 容器是否运行
if ! docker ps --format '{{.Names}}' | grep -q "${CLICKHOUSE_CONTAINER}"; then
  echo "错误: ClickHouse 容器未运行"
  exit 1
fi

# 执行 ClickHouse SQL 清理
run_sql() {
  local desc="$1"
  local sql="$2"
  echo "清理: ${desc}..."
  docker exec "${CLICKHOUSE_CONTAINER}" clickhouse-client --query "${sql}" 2>/dev/null && echo "  ✓ 完成" || echo "  ⚠ 跳过（表可能不存在）"
}

# 清理 Replays 数据
run_sql "Replays" \
  "ALTER TABLE replays_local DELETE WHERE timestamp < now() - INTERVAL ${RETENTION_DAYS} DAY"

# 清理错误事件
run_sql "Errors" \
  "ALTER TABLE errors_local DELETE WHERE timestamp < now() - INTERVAL ${RETENTION_DAYS} DAY"

# 清理 Transactions 性能数据
run_sql "Transactions" \
  "ALTER TABLE transactions_local DELETE WHERE finish_ts < now() - INTERVAL ${RETENTION_DAYS} DAY"

# 清理 Spans 数据
run_sql "Spans" \
  "ALTER TABLE spans_local DELETE WHERE timestamp < now() - INTERVAL ${RETENTION_DAYS} DAY"

# 清理 Outcomes 数据
run_sql "Outcomes" \
  "ALTER TABLE outcomes_raw_local DELETE WHERE timestamp < now() - INTERVAL ${RETENTION_DAYS} DAY"

run_sql "Outcomes Hourly" \
  "ALTER TABLE outcomes_hourly_local DELETE WHERE timestamp < now() - INTERVAL ${RETENTION_DAYS} DAY"

# 强制合并被标记删除的数据（释放磁盘空间）
echo ""
echo "合并已删除数据（释放磁盘空间）..."
for table in replays_local errors_local transactions_local spans_local outcomes_raw_local outcomes_hourly_local; do
  docker exec "${CLICKHOUSE_CONTAINER}" clickhouse-client \
    --query "OPTIMIZE TABLE ${table} FINAL" 2>/dev/null && echo "  ✓ ${table}" || echo "  ⚠ ${table}（跳过）"
done

echo ""
echo "=========================================="
echo "清理完成！"
echo "=========================================="
