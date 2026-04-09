#!/bin/bash
# ============================================
# 设置 ClickHouse 表 TTL（数据自动过期）
# 默认保留 30 天
# ============================================

set -e

RETENTION_DAYS=${1:-30}
CLICKHOUSE_CONTAINER="sentry-clickhouse-1"

echo "=========================================="
echo "设置 ClickHouse 表 TTL"
echo "保留最近 ${RETENTION_DAYS} 天的数据"
echo "=========================================="

# 检查容器
if ! docker ps --format '{{.Names}}' | grep -q "${CLICKHOUSE_CONTAINER}"; then
  echo "错误: ClickHouse 容器未运行"
  exit 1
fi

# 设置 TTL 的函数
set_ttl() {
  local table="$1"
  local time_column="$2"
  echo "设置 TTL: ${table}..."
  docker exec "${CLICKHOUSE_CONTAINER}" clickhouse-client --query "
    ALTER TABLE ${table}
    MODIFY TTL ${time_column} + INTERVAL ${RETENTION_DAYS} DAY
  " 2>/dev/null && echo "  ✓ 完成" || echo "  ⚠ 跳过（表不存在或已设置）"
}

# 为各表设置 TTL
set_ttl "replays_local" "timestamp"
set_ttl "errors_local" "timestamp"
set_ttl "transactions_local" "finish_ts"
set_ttl "spans_local" "timestamp"
set_ttl "outcomes_raw_local" "timestamp"
set_ttl "outcomes_hourly_local" "timestamp"

echo ""
echo "=========================================="
echo "TTL 设置完成！"
echo "数据将在 ${RETENTION_DAYS} 天后自动删除"
echo "=========================================="
