# Sentry Self-Hosted (Docker Compose)

基于 Docker Compose 的 Sentry 自托管部署方案。

## 架构组件

| 组件 | 端口 | 说明 |
|------|------|------|
| **Relay** | 3000 | SDK 事件接收入口 |
| **Sentry Web** | 9000 | Web UI 和管理 API |
| **Sentry Worker** | - | 后台异步任务处理 |
| **Sentry Cron** | - | 定时任务调度 |
| **PostgreSQL** | 5432 | 主数据库 |
| **Redis** | 6379 | 缓存和消息队列 |
| **Kafka + Zookeeper** | 9092 | 事件流处理 |
| **ClickHouse** | 8123 | 事件数据列式存储 |
| **Snuba** | 1218 | 事件查询引擎 |

## 系统要求

- Docker >= 20.10
- Docker Compose >= 2.0
- 内存 >= 8GB（推荐 16GB）
- 磁盘 >= 20GB

## 快速开始

### 1. 配置环境变量

编辑 `.env` 文件，修改以下关键配置：

- `SENTRY_SECRET_KEY` — 生成密钥: `python3 -c "import secrets; print(secrets.token_hex(25))"`
- `POSTGRES_PASSWORD` — 数据库密码
- `SENTRY_ADMIN_EMAIL` — 管理员邮箱
- `SENTRY_ADMIN_PASSWORD` — 管理员密码

### 2. 启动服务

> ⚠️ **必须按顺序启动**，不能直接 `docker compose up -d`，否则数据库迁移和账号创建可能因依赖服务未就绪而失败。

```bash
# 第一步：启动基础设施
docker compose up -d redis postgres zookeeper kafka clickhouse
sleep 30  # 等待基础设施就绪

# 第二步：初始化数据库（Snuba + Sentry）
docker compose up snuba-bootstrap
docker compose up snuba-migrate
docker compose up sentry-init           # Sentry 数据库迁移，耗时较长
docker compose up sentry-create-admin   # 创建管理员账号

# 第三步：启动所有服务
docker compose up -d
```

`.env` 中的 `SENTRY_ADMIN_EMAIL` 和 `SENTRY_ADMIN_PASSWORD` **仅在 `sentry-create-admin` 执行时使用**，账号创建后存入 PostgreSQL 数据库。后续修改 `.env` 不会影响已创建的账号。

### 3. 访问 Sentry

浏览器打开 [http://localhost:9000](http://localhost:9000)，使用 `.env` 中配置的管理员账号登录。

### 4. 配置 SDK

SDK 的 DSN 地址需要使用 **Relay 的端口（3000）**，而不是 Sentry Web 的端口（9000）：

```javascript
Sentry.init({
  // DSN 中的主机和端口指向 Relay
  dsn: "http://<your-sentry-key>@localhost:3000/<project-id>",
});
```

> 在 Sentry Web UI 中创建项目后会生成 DSN，将其中的端口 `9000` 改为 `3000` 即可。

## 常用命令

```bash
# 启动所有服务
docker compose up -d

# 停止所有服务
docker compose down

# 停止并删除所有数据（谨慎！）
docker compose down -v

# 查看服务状态
docker compose ps

# 查看某个服务日志
docker compose logs -f sentry-web

# 重启某个服务
docker compose restart sentry-web
```

## 邮件配置

登录 Sentry Web UI 后，在 **Admin → Mail** 页面配置 SMTP 服务器信息。

## 离线部署（生产环境无网络）

适用于 x86 (amd64) 离线服务器部署。

### 步骤 1：联网环境拉取镜像

```bash
# 拉取 amd64 架构镜像并导出为 tar 文件
bash scripts/pull-and-export.sh

# 打包所有文件（镜像 + 配置）为一个压缩包
bash scripts/pack-bundle.sh
```

生成的 `sentry-offline-bundle.tar.gz` 约 8GB。

### 步骤 2：拷贝到生产环境

将 `sentry-offline-bundle.tar.gz` 通过 U 盘/内网传输到生产服务器。

### 步骤 3：生产环境部署

```bash
# 解压
tar xzf sentry-offline-bundle.tar.gz
chmod +x scripts/*.sh

# 修改配置（建议修改密码和密钥）
vim .env

# 一键部署
bash scripts/deploy-offline.sh
```

### 离线部署文件结构

```
sentry-docker/
├── .env                          # 环境变量（密码、密钥）
├── docker-compose.yml            # 服务编排
├── sentry.conf.py                # Sentry 配置（含 Feature Flags）
├── nginx.conf                    # Nginx 反向代理
├── relay/                        # Relay 配置
│   ├── config.yml
│   └── credentials.json
├── clickhouse/                   # ClickHouse 配置
│   ├── users.xml                 # 用户配置
│   └── disable-analyzer.xml      # 禁用新查询分析器（兼容 Snuba）
├── patches/                      # 代码补丁
│   └── replay-ingest.py          # Replay 写入 ClickHouse 的修复补丁
├── scripts/                      # 部署脚本
│   ├── pull-and-export.sh        # 联网环境：拉取+导出镜像
│   ├── pack-bundle.sh            # 联网环境：打包所有文件
│   └── deploy-offline.sh         # 离线环境：导入镜像+初始化+启动
└── sentry-images/                # 导出的 Docker 镜像 tar（脚本生成）
```

## Session Replay 配置

Session Replay 功能需要以下配置才能正常工作：

### Sentry 端

`sentry.conf.py` 中需要启用 Feature Flag：

```python
SENTRY_FEATURES = {
    "organizations:session-replay": True,
}
```

### SDK 端

```javascript
import * as Sentry from "@sentry/react";

Sentry.init({
  dsn: "http://<key>@<host>:9000/<project-id>",
  replaysSessionSampleRate: 0.1,   // 10% 的 session 录制
  replaysOnErrorSampleRate: 1.0,   // 发生错误时 100% 录制
  integrations: [
    Sentry.replayIntegration(),
  ],
});
```

### 已知问题和修复

| 问题 | 原因 | 修复 |
|------|------|------|
| Replay 被 Relay 丢弃 | `organizations:session-replay` Feature Flag 默认关闭 | `sentry.conf.py` 中启用 |
| Replay API 返回 500 | ClickHouse 25.3 新查询分析器与 Snuba SQL 不兼容 | `clickhouse/disable-analyzer.xml` 禁用 analyzer |
| Replay 数据写入 ClickHouse 为空 | Relay 26.3+ 不再向 `ingest-replay-events` 写入完整 replay_event | `patches/replay-ingest.py` 补丁修复 |

## 故障排除

### 管理员账号登录失败

`.env` 中的账号密码仅在首次 `sentry-create-admin` 执行时写入数据库。如果登录不了，手动创建账号：

```bash
# 方法一：通过 docker compose 重新创建（会跳过已存在的账号）
docker compose up sentry-create-admin

# 方法二：手动创建新账号
docker compose exec sentry-web sentry createuser \
  --email admin@example.com \
  --password admin123456 \
  --superuser --no-input

# 方法三：重置已有账号的密码
docker compose exec sentry-web sentry shell -c "
from sentry.models.user import User
u = User.objects.get(email='admin@example.com')
u.set_password('new_password')
u.save()
print('密码已重置')
"
```

### SDK 事件不被收集（迁移到新环境后）

最常见的原因是 **Relay 凭据不匹配**。`relay/credentials.json` 是 Relay 向 Sentry 注册时生成的密钥对，迁移到新环境后数据库是全新的，旧凭据无法通过验证，导致 Relay 拒绝所有 SDK 事件。

```bash
# 1. 停止 Relay
docker compose stop relay

# 2. 删除旧凭据，让 Relay 重新生成（凭据自动写入 relay/ 目录）
del relay\credentials.json          # Windows
# rm relay/credentials.json         # Linux/Mac
docker compose run --rm --no-deps relay credentials generate

# 3. 重启 Relay
docker compose up -d relay
```

> 如果使用了 `scripts/deploy-offline.sh` 部署，脚本已自动处理此步骤。

其他排查步骤：

1. **检查 Relay 日志**：`docker compose logs relay | tail -50`，查看是否有认证错误
2. **检查 SDK DSN**：确认 DSN 中的 host 和端口能从前端访问到
3. **用 curl 测试**：`curl -v http://localhost:9000/api/2/store/` 检查连通性

### Replay 在 UI 中不显示

1. 确认 `sentry.conf.py` 中已启用 `organizations:session-replay` Feature Flag
2. 确认 `sentry-ingest-replay-recordings` 和 `snuba-replays-consumer` 容器正在运行
3. 前端需要**完全刷新页面**让 SDK 创建新的 replay session（旧 session 的首个 segment 可能已丢失）

## 注意事项

- **必须按顺序启动**，不能直接 `docker compose up -d`（详见「快速开始」）
- 生产环境建议修改所有默认密码和 `SENTRY_SECRET_KEY`
- 生产环境建议配置反向代理（如 Nginx）并启用 HTTPS
- ClickHouse 和 Kafka 消耗较多内存，确保服务器资源充足（推荐 16GB+）
- SDK 事件通过 Nginx（端口 9000）上报，Nginx 自动将 SDK 请求转发到 Relay
- 启用 Replay 后，首次需要刷新前端页面让 SDK 创建新的 replay session

