#!/bin/bash
# ============================================
# 启动已在离线 x86 生产环境中部署的 Sentry 服务
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
IMAGES_DIR="${PROJECT_DIR}/sentry-images"

echo "============================================"
echo "Sentry 服务启动工具"
echo "项目目录: ${PROJECT_DIR}"
echo "============================================"

# 步骤 1: 检查环境
echo ""
echo ">>> 步骤 1/5: 检查环境"
if [ ! -f "${PROJECT_DIR}/docker-compose.yml" ]; then
    echo "[ERROR] docker-compose.yml 文件不存在！"
    echo "请确保在正确的项目目录中运行此脚本。"
    exit 1
fi

# 检查必要的镜像是否已加载
echo "  检查必要镜像..."
REQUIRED_IMAGES=(
    "getsentry/sentry"
    "getsentry/snuba"
    "getsentry/relay"
    "postgres"
    "redis"
    "confluentinc/cp-kafka"
    "confluentinc/cp-zookeeper"
    "clickhouse/clickhouse-server"
    "nginx"
)

for image in "${REQUIRED_IMAGES[@]}"; do
    if ! docker image inspect "${image}" >/dev/null 2>&1; then
        echo "[ERROR] 镜像 ${image} 未找到！"
        echo "请先运行 deploy-offline.sh 脚本导入镜像。"
        exit 1
    fi
done
echo "  镜像检查通过"

# 步骤 2: 启动基础设施
echo ""
echo ">>> 步骤 2/5: 启动基础设施服务"
cd "${PROJECT_DIR}"
docker compose up -d redis postgres zookeeper kafka clickhouse
echo "  等待基础设施就绪 (30s)..."
sleep 30

# 步骤 3: 检查基础设施状态
echo ""
echo ">>> 步骤 3/5: 检查基础设施状态"
for service in redis postgres zookeeper kafka clickhouse; do
    status=$(docker compose ps -q "${service}" 2>/dev/null | xargs -I {} docker inspect -f '{{.State.Status}}' {} 2>/dev/null || echo "unknown")
    if [ "${status}" != "running" ]; then
        echo "[WARNING] 服务 ${service} 状态为: ${status}"
    else
        echo "  ${service}: running"
    fi
done

# 步骤 4: 启动所有服务
echo ""
echo ">>> 步骤 4/5: 启动所有服务"
docker compose up -d

echo "  等待服务启动 (20s)..."
sleep 20

# 步骤 5: 应用补丁
echo ""
echo ">>> 步骤 5/5: 应用 Replay 补丁"

# 需要对所有使用 sentry 镜像的容器应用补丁
SENTRY_CONTAINERS=(
    "sentry-docker-sentry-web-1"
    "sentry-docker-sentry-worker-1"
    "sentry-docker-sentry-ingest-replay-recordings-1"
)

for container in "${SENTRY_CONTAINERS[@]}"; do
    echo "  应用补丁到 ${container}..."
    docker cp "${PROJECT_DIR}/patches/replay-ingest.py" "${container}:/tmp/replay-ingest.py"
    docker exec "${container}" python3 /tmp/replay-ingest.py || true
done

# 重启 replay recordings consumer 使补丁生效
echo "  重启 replay recordings consumer..."
docker compose restart sentry-ingest-replay-recordings

echo ""
echo "============================================"
echo "Sentry 服务启动完成！"
echo ""
echo "访问地址: http://<服务器IP>:${SENTRY_PORT:-9000}"
echo "管理员账号: ${SENTRY_ADMIN_EMAIL:-admin@example.com}"
echo "管理员密码: ${SENTRY_ADMIN_PASSWORD:-admin123456}"
echo ""
echo "注意事项："
echo "  1. 首次登录后请在 Settings > Organization 中设置组织名称"
echo "  2. 创建项目后获取 DSN，配置到前端 SDK 中"
echo "  3. SDK 的 DSN 地址中 localhost 需替换为服务器实际 IP"
echo "============================================"