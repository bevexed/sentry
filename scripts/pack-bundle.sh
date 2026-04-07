#!/bin/bash
# ============================================
# 将所有部署文件打包为一个压缩包，方便拷贝到生产环境
# 在联网环境执行 pull-and-export.sh 后执行此脚本
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
BUNDLE_NAME="sentry-offline-bundle.tar.gz"

cd "${PROJECT_DIR}"

if [ ! -d "sentry-images" ]; then
    echo "[ERROR] sentry-images/ 目录不存在，请先执行 scripts/pull-and-export.sh"
    exit 1
fi

echo "打包部署文件..."

tar czf "${BUNDLE_NAME}" \
    docker-compose.yml \
    sentry.conf.py \
    .env \
    nginx.conf \
    relay/config.yml \
    clickhouse/ \
    patches/ \
    scripts/ \
    sentry-images/

# 注意：不打包 relay/credentials.json，凭据在部署时由 deploy-offline.sh 自动生成

echo ""
echo "打包完成: ${BUNDLE_NAME}"
ls -lh "${BUNDLE_NAME}"
echo ""
echo "将此文件拷贝到生产环境后解压："
echo "  tar xzf ${BUNDLE_NAME}"
echo "  chmod +x scripts/*.sh"
echo "  bash scripts/deploy-offline.sh"
