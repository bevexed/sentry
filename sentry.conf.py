# 自定义 Sentry 配置，挂载到容器 /etc/sentry/sentry.conf.py
# 继承默认配置
import os

from sentry.conf.server import *
from sentry.utils.types import Bool

env = os.environ.get

# ============ 数据库 ============
postgres = env("SENTRY_POSTGRES_HOST") or (env("POSTGRES_PORT_5432_TCP_ADDR") and "postgres")
if postgres:
    DATABASES = {
        "default": {
            "ENGINE": "sentry.db.postgres",
            "NAME": (env("SENTRY_DB_NAME") or env("POSTGRES_ENV_POSTGRES_USER") or "postgres"),
            "USER": (env("SENTRY_DB_USER") or env("POSTGRES_ENV_POSTGRES_USER") or "postgres"),
            "PASSWORD": (env("SENTRY_DB_PASSWORD") or env("POSTGRES_ENV_POSTGRES_PASSWORD") or ""),
            "HOST": postgres,
            "PORT": (env("SENTRY_POSTGRES_PORT") or ""),
        }
    }

# ============ Redis ============
redis = env("SENTRY_REDIS_HOST") or (env("REDIS_PORT_6379_TCP_ADDR") and "redis")
if not redis:
    raise Exception(
        "Error: REDIS_PORT_6379_TCP_ADDR (or SENTRY_REDIS_HOST) is undefined"
    )

redis_password = env("SENTRY_REDIS_PASSWORD") or ""
redis_port = env("SENTRY_REDIS_PORT") or "6379"
redis_db = env("SENTRY_REDIS_DB") or "0"

SENTRY_OPTIONS.update(
    {
        "redis.clusters": {
            "default": {
                "hosts": {
                    0: {
                        "host": redis,
                        "password": redis_password,
                        "port": redis_port,
                        "db": redis_db,
                    }
                }
            }
        }
    }
)

# ============ 缓存 ============
SENTRY_CACHE = "sentry.cache.redis.RedisCache"

# ============ Kafka ============
kafka_host = env("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
KAFKA_CLUSTERS = {
    "default": {
        "common": {"bootstrap.servers": kafka_host},
        "producers": {
            "compression.type": "lz4",
            "message.max.bytes": 50000000,
        },
        "consumers": {},
    }
}

# ============ 队列 ============
BROKER_URL = f"redis://{redis_password}@{redis}:{redis_port}/{redis_db}"

# ============ 速率限制 ============
SENTRY_RATELIMITER = "sentry.ratelimits.redis.RedisRateLimiter"

# ============ 缓冲区 ============
SENTRY_BUFFER = "sentry.buffer.redis.RedisBuffer"

# ============ 配额 ============
SENTRY_QUOTAS = "sentry.quotas.redis.RedisQuota"

# ============ 时序数据 ============
SENTRY_TSDB = "sentry.tsdb.redissnuba.RedisSnubaTSDB"

# ============ 摘要 ============
SENTRY_DIGESTS = "sentry.digests.backends.redis.RedisBackend"

# ============ Web 服务 ============
SENTRY_WEB_HOST = "0.0.0.0"
SENTRY_WEB_PORT = 9000
SENTRY_WEB_OPTIONS = {
    "workers": 2,
    "threads": 4,
    "http-keepalive": True,
    "http-chunked-input": True,
    "harakiri": 300,
    # 每个 worker 处理 5000 个请求后自动重启，防止内存泄漏
    "max-requests": 5000,
    "max-requests-delta": 300,
}


# ============ URL 前缀和 CSRF ============
import re

url_prefix = env("SENTRY_URL_PREFIX", "http://localhost:9000")
SENTRY_OPTIONS["system.url-prefix"] = url_prefix

# CSRF trusted origins - 智能配置，自动支持内网访问
CSRF_TRUSTED_ORIGINS = [
    url_prefix,
    "http://localhost:9000",
    "http://127.0.0.1:9000",
]

# 自动添加内网 IP 段支持
# 如果配置了 192.168.x.x，自动允许整个 C 段
if url_prefix and re.search(r'192\.168\.\d+\.\d+', url_prefix):
    base_ip = re.search(r'(192\.168\.\d+\.)', url_prefix).group(1)
    # 添加同一 C 段的所有 IP (1-254)
    for i in range(1, 255):
        CSRF_TRUSTED_ORIGINS.append(f"http://{base_ip}{i}:9000")

# 如果配置了 10.x.x.x，自动允许整个 C 段
elif url_prefix and re.search(r'10\.\d+\.\d+\.\d+', url_prefix):
    base_ip = re.search(r'(10\.\d+\.\d+\.)', url_prefix).group(1)
    for i in range(1, 255):
        CSRF_TRUSTED_ORIGINS.append(f"http://{base_ip}{i}:9000")

# 如果配置了 172.16-31.x.x，自动允许整个 C 段
elif url_prefix and re.search(r'172\.(1[6-9]|2[0-9]|3[0-1])\.\d+\.\d+', url_prefix):
    base_ip = re.search(r'(172\.\d+\.\d+\.)', url_prefix).group(1)
    for i in range(1, 255):
        CSRF_TRUSTED_ORIGINS.append(f"http://{base_ip}{i}:9000")

SECURE_PROXY_SSL_HEADER = None
SESSION_COOKIE_SECURE = False
CSRF_COOKIE_SECURE = False

# ============ 单组织模式 ============
SENTRY_SINGLE_ORGANIZATION = Bool(env("SENTRY_SINGLE_ORGANIZATION", True))

# ============ 密钥 ============
secret_key = env("SENTRY_SECRET_KEY")
if not secret_key:
    raise Exception(
        "Error: SENTRY_SECRET_KEY is undefined, run `generate-secret-key` and set to -e SENTRY_SECRET_KEY"
    )

SENTRY_OPTIONS["system.secret-key"] = secret_key

# ============ 事件流（通过 Kafka 写入 Snuba） ============
SENTRY_EVENTSTREAM = "sentry.eventstream.kafka.backend.KafkaEventStream"

# ============ Feature Flags ============
# 参考官方 self-hosted: https://github.com/getsentry/self-hosted/blob/master/sentry/sentry.conf.example.py
SENTRY_FEATURES = {}
SENTRY_FEATURES["projects:sample-events"] = False
SENTRY_FEATURES.update(
    {
        feature: True
        for feature in (
            # 基础功能
            "organizations:discover",
            "organizations:global-views",
            "organizations:issue-views",
            "organizations:incidents",
            "organizations:integrations-issue-basic",
            "organizations:integrations-issue-sync",
            "organizations:invite-members",
            "organizations:sso-basic",
            "organizations:sso-saml2",
            "organizations:advanced-search",
            "organizations:issue-platform",
            "organizations:monitors",
            "organizations:dashboards-mep",
            "organizations:mep-rollout-flag",
            "organizations:dashboards-rh-widget",
            "organizations:dynamic-sampling",
            "projects:custom-inbound-filters",
            "projects:data-forwarding",
            "projects:discard-groups",
            "projects:plugins",
            "projects:rate-limits",
            "projects:servicehooks",
        )
        # 性能/Tracing/Spans 相关（Pageloads 核心依赖）
        + (
            "organizations:performance-view",
            # organizations:span-stats  # 已禁用：Traces 页面 span 聚合功能
            # organizations:visibility-explore-view  # 已禁用：Traces 页面探索视图
            # organizations:visibility-explore-range-high  # 已禁用：Traces 页面范围探索
            "organizations:transaction-metrics-extraction",
            # organizations:indexed-spans-extraction  # 已禁用：Sentry 25.7.0 兼容性问题
            "organizations:insights-entry-points",
            "organizations:insights-initial-modules",
            "organizations:insights-addon-modules",
            "organizations:insights-modules-use-eap",
            "organizations:starfish-browser-resource-module-image-view",
            "organizations:starfish-browser-resource-module-ui",
            "organizations:starfish-browser-webvitals",
            "organizations:starfish-browser-webvitals-pageoverview-v2",
            "organizations:starfish-browser-webvitals-use-backend-scores",
            "organizations:starfish-mobile-appstart",
            "organizations:performance-calculate-score-relay",
            "organizations:starfish-browser-webvitals-replace-fid-with-inp",
            "organizations:performance-database-view",
            "organizations:performance-screens-view",
            "organizations:on-demand-metrics-extraction",
            "projects:span-metrics-extraction",
            "projects:span-metrics-extraction-addons",
        )
        # Session Replay
        + (
            "organizations:session-replay",
        )
        # User Feedback
        + (
            "organizations:user-feedback-ui",
        )
    }
)

# ============ 数据保留策略（天） ============
SENTRY_OPTIONS["system.event-retention-days"] = 14

# ============ Relay ============
SENTRY_USE_RELAY = True

# ============ 邮件（留空，通过 Web UI 配置） ============
SENTRY_OPTIONS["mail.backend"] = "dummy"
SENTRY_OPTIONS["mail.from"] = env("SENTRY_SERVER_EMAIL") or "root@localhost"

# ============ Allowed Hosts (for CSRF protection) ============
ALLOWED_HOSTS = [
    "localhost",
    "127.0.0.1",
    "192.168.8.89",
    # Docker 内部服务名（Relay 通过 nginx 访问 Sentry Web）
    "nginx",
    "sentry-web",
]
