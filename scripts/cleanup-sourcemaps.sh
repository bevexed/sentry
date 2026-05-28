#!/bin/bash
# ============================================
# Sentry SourceMap 自动清理脚本
# 按项目维度，仅保留每个项目最新的 N 个 ArtifactBundle（默认 5）
# 用法: ./scripts/cleanup-sourcemaps.sh [保留数量]
# ============================================

set -e

# 每个项目保留的 ArtifactBundle 数量，默认 5
KEEP=${1:-5}
SENTRY_SERVICE="sentry-web"

echo "=========================================="
echo "Sentry SourceMap 清理"
echo "每个项目保留最新 ${KEEP} 个 ArtifactBundle"
echo "=========================================="

# 检查 sentry-web 服务是否运行
if ! docker compose ps --format '{{.Service}} {{.State}}' | grep -q "^${SENTRY_SERVICE} running"; then
  echo "错误: ${SENTRY_SERVICE} 容器未运行，请先启动 Sentry"
  exit 1
fi

# 通过 sentry django shell 执行清理逻辑
docker compose exec -T -e KEEP="${KEEP}" "${SENTRY_SERVICE}" sentry django shell <<'PYEOF'
import os
from sentry.models.project import Project
from sentry.models.artifactbundle import (
    ArtifactBundle,
    ProjectArtifactBundle,
    ReleaseArtifactBundle,
)
from sentry.models.files.file import File

# 每个项目保留的最新 ArtifactBundle 数量
KEEP = int(os.environ.get("KEEP", "5"))

total_deleted_bundles = 0
total_deleted_files = 0

for project in Project.objects.all().iterator():
    # 该项目下所有 ArtifactBundle 按上传时间倒序
    bundle_ids = list(
        ProjectArtifactBundle.objects.filter(project_id=project.id)
        .order_by("-artifact_bundle__date_uploaded")
        .values_list("artifact_bundle_id", flat=True)
    )

    # 去重并保持顺序（同一 bundle 可能因多次关联出现多次）
    seen = set()
    ordered_ids = []
    for bid in bundle_ids:
        if bid in seen:
            continue
        seen.add(bid)
        ordered_ids.append(bid)

    to_delete = ordered_ids[KEEP:]
    if not to_delete:
        continue

    print(
        "项目 {slug} (id={pid}): 共 {total} 个 bundle, 待删除 {n} 个".format(
            slug=project.slug, pid=project.id, total=len(ordered_ids), n=len(to_delete)
        )
    )

    for bid in to_delete:
        try:
            ab = ArtifactBundle.objects.get(id=bid)
        except ArtifactBundle.DoesNotExist:
            continue

        file_id = ab.file_id

        # 先删关联（避免 FK 残留）
        ProjectArtifactBundle.objects.filter(artifact_bundle_id=bid).delete()
        ReleaseArtifactBundle.objects.filter(artifact_bundle_id=bid).delete()
        ab.delete()
        total_deleted_bundles += 1

        # 仅当没有其它 ArtifactBundle 引用同一 File 时，再删除底层 File
        if file_id and not ArtifactBundle.objects.filter(file_id=file_id).exists():
            try:
                f = File.objects.get(id=file_id)
                f.delete()
                total_deleted_files += 1
            except File.DoesNotExist:
                pass

print("=========================================")
print("完成: 删除 {b} 个 ArtifactBundle, {f} 个底层 File".format(
    b=total_deleted_bundles, f=total_deleted_files
))
PYEOF

echo ""
echo "=========================================="
echo "SourceMap 清理完成！"
echo "=========================================="
