#!/bin/bash
# ============================================
# 拉取所有 Sentry 所需 Docker 镜像（amd64 架构）并导出为 tar
# 在联网环境中执行此脚本
# ============================================
set -e

PLATFORM="linux/amd64"
EXPORT_DIR="./sentry-images"

# 所有需要的镜像
IMAGES=(
    "getsentry/sentry:latest"
    "getsentry/snuba:latest"
    "getsentry/relay:latest"
    "redis:7"
    "postgres:16"
    "confluentinc/cp-zookeeper:7.6.0"
    "confluentinc/cp-kafka:7.6.0"
    "clickhouse/clickhouse-server:25.3"
    "nginx:alpine"
)

echo "============================================"
echo "Sentry 离线镜像导出工具"
echo "目标架构: ${PLATFORM}"
echo "导出目录: ${EXPORT_DIR}"
echo "============================================"

mkdir -p "${EXPORT_DIR}"

# 拉取所有镜像
echo ""
echo ">>> 步骤 1/2: 拉取镜像"
for img in "${IMAGES[@]}"; do
    echo "  拉取 ${img} (${PLATFORM})..."
    docker pull --platform "${PLATFORM}" "${img}"
done

# 导出镜像为 tar
echo ""
echo ">>> 步骤 2/2: 导出镜像"
for img in "${IMAGES[@]}"; do
    # 将 image 名中的 / 和 : 替换为 _
    filename=$(echo "${img}" | tr '/:' '_')
    tarfile="${EXPORT_DIR}/${filename}.tar"
    echo "  导出 ${img} -> ${tarfile}"
    docker save "${img}" -o "${tarfile}"
done

echo ""
echo "============================================"
echo "镜像导出完成！"
echo ""
echo "导出的文件:"
ls -lh "${EXPORT_DIR}"/*.tar
echo ""
echo "总大小:"
du -sh "${EXPORT_DIR}"
echo ""
echo "下一步: 将以下内容拷贝到生产环境："
echo "  1. ${EXPORT_DIR}/ 目录（所有 tar 文件）"
echo "  2. 项目根目录所有配置文件"
echo "  或者直接打包: tar czf sentry-offline-bundle.tar.gz ${EXPORT_DIR}/ docker-compose.yml sentry.conf.py .env nginx.conf relay/ clickhouse/ patches/ scripts/"
echo "============================================"
