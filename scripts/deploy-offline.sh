#!/bin/bash
# ============================================
# 在离线 x86 生产环境中导入镜像并启动 Sentry
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
IMAGES_DIR="${PROJECT_DIR}/sentry-images"

echo "============================================"
echo "Sentry 离线部署工具"
echo "项目目录: ${PROJECT_DIR}"
echo "镜像目录: ${IMAGES_DIR}"
echo "============================================"

# 步骤 1: 导入镜像
echo ""
echo ">>> 步骤 1/5: 导入 Docker 镜像"
if [ ! -d "${IMAGES_DIR}" ]; then
    echo "[ERROR] 镜像目录 ${IMAGES_DIR} 不存在！"
    echo "请确保已将 sentry-images/ 目录拷贝到项目根目录。"
    exit 1
fi

for tarfile in "${IMAGES_DIR}"/*.tar; do
    echo "  导入 $(basename ${tarfile})..."
    docker load -i "${tarfile}"
done
echo "  镜像导入完成"

# 步骤 2: 启动基础设施
echo ""
echo ">>> 步骤 2/5: 启动基础设施服务"
cd "${PROJECT_DIR}"
docker compose up -d redis postgres zookeeper kafka clickhouse
echo "  等待基础设施就绪 (30s)..."
sleep 30

# 步骤 3: 数据库初始化
echo ""
echo ">>> 步骤 3/5: 初始化数据库"

# Snuba 初始化
echo "  Snuba bootstrap..."
docker compose up snuba-bootstrap
echo "  Snuba migrate..."
docker compose up snuba-migrate

# Sentry 初始化
echo "  Sentry 数据库迁移..."
docker compose up sentry-init
echo "  创建管理员账号..."
docker compose up sentry-create-admin

# 步骤 4: 重新生成 Relay 凭据
echo ""
echo ">>> 步骤 4/6: 生成 Relay 凭据"
echo "  删除旧的 Relay 凭据..."
rm -f "${PROJECT_DIR}/relay/credentials.json"
echo "  生成新的 Relay 凭据..."
docker compose run --rm --no-deps relay credentials generate
echo "  Relay 凭据已更新"

# 步骤 5: 启动所有服务
echo ""
echo ">>> 步骤 5/6: 启动所有服务"
docker compose up -d

echo "  等待服务启动 (20s)..."
sleep 20

# 步骤 6: 应用补丁
echo ""
echo ">>> 步骤 6/6: 应用 Replay 补丁"

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
echo "部署完成！"
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
