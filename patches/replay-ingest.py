"""
Sentry Replay Ingest 补丁
修复 Relay 26.3+ 不再向 ingest-replay-events 写入完整 replay_event 的问题。
此补丁让 sentry-ingest-replay-recordings consumer 在处理录制数据后，
将完整的 replay_event 发布到 ingest-replay-events Kafka topic，
供 Snuba replays consumer 消费写入 ClickHouse。

用法: 在 sentry 容器启动后执行:
  docker exec <container> python3 /patches/replay-ingest.py
"""
import re

TARGET_FILE = "/usr/src/sentry/src/sentry/replays/usecases/ingest/__init__.py"

with open(TARGET_FILE, "r") as f:
    content = f.read()

# 检查是否已经打过补丁
if "publish_replay_event" in content:
    print("[SKIP] 补丁已存在，跳过")
    exit(0)

# 1. 添加 import
old_import = "from sentry.replays.usecases.pack import pack"
new_import = (
    "from sentry.replays.usecases.pack import pack\n"
    "from sentry.replays.lib.kafka import publish_replay_event"
)
content = content.replace(old_import, new_import)

# 2. 在 commit_recording_message 的 emit_replay_events 块之后添加发布逻辑
old_code = '''    # Write to replay-event consumer.
    if recording.actions_event:
        emit_replay_events(
            recording.actions_event,
            recording.context["org_id"],
            project,
            recording.context["replay_id"],
            recording.context["retention_days"],
            recording.replay_event,
        )'''

new_code = old_code + '''

    # 将完整的 replay_event 发布到 ingest-replay-events topic（供 Snuba 消费写入 ClickHouse）
    if recording.replay_event:
        replay_event_message = json.dumps(
            {
                "type": "replay_event",
                "start_time": recording.context["received"],
                "replay_id": recording.context["replay_id"],
                "project_id": recording.context["project_id"],
                "segment_id": recording.context["segment_id"],
                "retention_days": recording.context["retention_days"],
                "payload": recording.replay_event,
            }
        )
        publish_replay_event(replay_event_message)'''

if old_code not in content:
    print("[ERROR] 无法找到目标代码块，补丁无法应用")
    exit(1)

content = content.replace(old_code, new_code)

with open(TARGET_FILE, "w") as f:
    f.write(content)

# 清除 __pycache__
import shutil, os
cache_dir = os.path.join(os.path.dirname(TARGET_FILE), "__pycache__")
if os.path.exists(cache_dir):
    shutil.rmtree(cache_dir)

print("[OK] 补丁已成功应用")
