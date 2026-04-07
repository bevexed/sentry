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
    "workers": 3,
    "threads": 4,
    "http-keepalive": True,
    "http-chunked-input": True,
    "harakiri": 600,
}

# ============ URL 前缀和 CSRF ============
SENTRY_OPTIONS["system.url-prefix"] = env("SENTRY_URL_PREFIX", "http://localhost:9000")
# CSRF trusted origins - include the URL prefix and common variations
url_prefix = env("SENTRY_URL_PREFIX", "http://localhost:9000")
CSRF_TRUSTED_ORIGINS = [
    url_prefix,
    "http://localhost:9000",  # Always allow localhost
    "http://127.0.0.1:9000",  # Always allow 127.0.0.1
]
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
SENTRY_FEATURES = {
    # 启用 Session Replay
    "organizations:session-replay": True,
}

# ============ Relay ============
SENTRY_USE_RELAY = True

# ============ 邮件（留空，通过 Web UI 配置） ============
SENTRY_OPTIONS["mail.backend"] = "dummy"
SENTRY_OPTIONS["mail.from"] = env("SENTRY_SERVER_EMAIL") or "root@localhost"

# ============ Allowed Hosts (for CSRF protection) ============
ALLOWED_HOSTS = [
    "localhost",
    "127.0.0.1",
    "192.168.158.244",
    "*",  # Allow all hosts (for development/testing)
]
