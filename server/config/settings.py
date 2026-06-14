"""Django settings for ai-maxx-ide server."""

from datetime import timedelta
from pathlib import Path

import environ

from standalone.bootstrap import ensure_runtime, repo_root as bootstrap_repo_root, server_dir

BASE_DIR = server_dir()
REPO_ROOT = bootstrap_repo_root()

ensure_runtime()

env = environ.Env(
    DEBUG=(bool, True),
    BIND_HOST=(str, "127.0.0.1"),
    BIND_PORT=(int, 8000),
    TERMINAL_IDLE_TTL=(int, 3600),
    REMOTE_INPUT_ENABLED=(bool, True),
    REMOTE_WEBRTC_STUB=(bool, False),
    WS_MAX_MESSAGE_BYTES=(int, 4 * 1024 * 1024),
)

environ.Env.read_env(REPO_ROOT / ".env")

SECRET_KEY = env("DJANGO_SECRET_KEY", default="django-insecure-dev-key-change-me")
DEBUG = env("DEBUG")
ALLOWED_HOSTS = env.list("ALLOWED_HOSTS", default=["*"])

API_KEY = env("API_KEY", default="change-me-to-a-long-random-secret")
CURSOR_API_KEY = env("CURSOR_API_KEY", default="")
EXPOSED_DIRECTORIES_ABSOLUTE_PATHS = env.json(
    "EXPOSED_DIRECTORIES_ABSOLUTE_PATHS",
    default=[],
)
BIND_HOST = env("BIND_HOST")
BIND_PORT = env("BIND_PORT")
REDIS_URL = env("REDIS_URL", default="redis://127.0.0.1:6379/0")
TERMINAL_IDLE_TTL = timedelta(seconds=env("TERMINAL_IDLE_TTL"))
REMOTE_INPUT_ENABLED = env("REMOTE_INPUT_ENABLED")
REMOTE_WEBRTC_STUB = env("REMOTE_WEBRTC_STUB")

INSTALLED_APPS = [
    "daphne",
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "channels",
    "core",
    "ide",
    "terminals",
    "dashboard",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "core.middleware.DeviceAuthMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
ASGI_APPLICATION = "config.asgi.application"

from standalone.bootstrap import is_frozen, runtime_root  # noqa: E402

_template_dirs: list[Path] = []
if is_frozen():
    _template_dirs.append(runtime_root() / "dashboard" / "templates")

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": _template_dirs,
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

DATABASES = {
    "default": env.db(
        "DATABASE_URL",
        default=f"sqlite:///{REPO_ROOT / 'data' / 'db.sqlite3'}",
    )
}

# Ensure sqlite parent directory exists for relative DATABASE_URL paths
_db = DATABASES["default"]
if _db["ENGINE"] == "django.db.backends.sqlite3":
    db_path = Path(_db["NAME"])
    if not db_path.is_absolute():
        db_path = (REPO_ROOT / db_path).resolve()
        DATABASES["default"]["NAME"] = str(db_path)
    db_path.parent.mkdir(parents=True, exist_ok=True)
    DATABASES["default"].setdefault("OPTIONS", {})
    DATABASES["default"]["OPTIONS"]["timeout"] = 20

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "/static/"
STATIC_ROOT = REPO_ROOT / "staticfiles"
STATIC_ROOT.mkdir(parents=True, exist_ok=True)
WHITENOISE_USE_FINDERS = DEBUG
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "core.authentication.DeviceAPIKeyAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "core.permissions.IsRegisteredDevice",
    ],
    "UNAUTHENTICATED_USER": None,
    "EXCEPTION_HANDLER": "core.exceptions.api_exception_handler",
}

if DEBUG:
    CHANNEL_LAYERS = {
        "default": {"BACKEND": "channels.layers.InMemoryChannelLayer"},
    }
else:
    CHANNEL_LAYERS = {
        "default": {
            "BACKEND": "channels_redis.core.RedisChannelLayer",
            "CONFIG": {"hosts": [REDIS_URL]},
        },
    }

# Large file sync threshold (1 MiB)
FILE_SYNC_INLINE_MAX_BYTES = 1_048_576
# Max paths per batch content request during background sync phase 2
SYNC_FILES_BATCH_MAX_PATHS = 32
# Outgoing WebSocket JSON frames should stay below this (chunk file/search payloads).
WS_MAX_MESSAGE_BYTES = env("WS_MAX_MESSAGE_BYTES")
