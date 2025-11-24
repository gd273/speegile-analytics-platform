
import os

# ---------------------------------------------------------
# 1. DATABASE CONNECTION
# ---------------------------------------------------------
# Render provides 'DATABASE_URL' automatically. 
# We check for that first. If not found, we use your local logic.
DATABASE_URL = os.getenv("DATABASE_URL") 
if DATABASE_URL and "postgres" in DATABASE_URL:
    # SQLAlchemy requires 'postgresql://', but Render sometimes gives 'postgres://'
    SQLALCHEMY_DATABASE_URI = DATABASE_URL.replace("postgres://", "postgresql://")
else:
    # Fallback for local dev (or SQLite)
    SQLALCHEMY_DATABASE_URI = os.getenv("SQLALCHEMY_DATABASE_URI", "sqlite:////app/superset_home/superset.db")

# ---------------------------------------------------------
# 2. SECURITY & SECRETS
# ---------------------------------------------------------
# CRITICAL: Fetch these from environment in Prod. Fallback to dev defaults if missing.
SECRET_KEY = os.getenv("SECRET_KEY", "WKlKnTnZFn-AWCWT3qhn8lrHZeMlruXrjw7ZlF6wF9E")
GUEST_TOKEN_JWT_SECRET = os.getenv("GUEST_TOKEN_JWT_SECRET", "my_secure_embedding_secret_12345")

# ---------------------------------------------------------
# 3. FEATURE FLAGS
# ---------------------------------------------------------
FEATURE_FLAGS = {
    "EMBEDDED_SUPERSET": True,
    "ALERT_REPORTS": True,
    "EMBEDDABLE_CHARTS": True,
    "DASHBOARD_RBAC": True,
    "DRILL_BY": True,
}

# ---------------------------------------------------------
# 4. EMBEDDING & COOKIES (The tricky part)
# ---------------------------------------------------------
# If running on Render/Prod, we need specific cookie settings for embedding to work.
IS_PRODUCTION = os.getenv("FLASK_ENV") == "production"

# Guest Token Settings
GUEST_TOKEN_JWT_EXP_SECONDS = 3600  # 1 hour
GUEST_TOKEN_JWT_ALGO = "HS256"
GUEST_TOKEN_HEADER_NAME = "X-GuestToken"
GUEST_ROLE_NAME = "Gamma"
GUEST_TOKEN_JWT_AUDIENCE = "audi"

# CORS & Headers
ENABLE_CORS = True
# Use the FRONTEND_URL env var if available, otherwise allow all (for dev)
FRONTEND_URL = os.getenv("FRONTEND_URL", "*") 

CORS_OPTIONS = {
    'supports_credentials': True,
    'allow_headers': ['*'],
    'resources': ['*'],
    'origins': [FRONTEND_URL, "http://localhost:3000", "http://127.0.0.1:3000"] if FRONTEND_URL != "*" else ["*"]
}

OVERRIDE_HTTP_HEADERS = {
    "X-Frame-Options": "ALLOWALL",
    # This tells the browser "It is okay to show this in an iframe on my frontend"
    "Content-Security-Policy": f"frame-ancestors 'self' {FRONTEND_URL} http://localhost:3000"
}

# ---------------------------------------------------------
# 5. SESSION & COOKIE HARDENING
# ---------------------------------------------------------
SESSION_COOKIE_HTTPONLY = True
SESSION_REFRESH_EACH_REQUEST = False
SESSION_PROTECTION = None

# Important: Google Chrome requires SameSite='None' and Secure=True 
# for iframes (embedding) to work on HTTPS.
if IS_PRODUCTION:
    SESSION_COOKIE_SAMESITE = 'None'
    SESSION_COOKIE_SECURE = True
    DEBUG = False
else:
    # Localhost dev settings
    SESSION_COOKIE_SAMESITE = 'Lax'
    SESSION_COOKIE_SECURE = False
    DEBUG = True

# ---------------------------------------------------------
# 6. MISC
# ---------------------------------------------------------
TALISMAN_ENABLED = False # Disable Talisman to prevent strict CSP blocking frames
WTF_CSRF_ENABLED = True
WTF_CSRF_TIME_LIMIT = None
FAB_ADD_SECURITY_API = True
ENABLE_SWAGGER_UI = True
# ---------------------------------------------------------
# 7. CACHE CONFIG (Redis) - CRITICAL FOR RENDER
# ---------------------------------------------------------
REDIS_URL = os.getenv("REDIS_URL")
if REDIS_URL:
    CACHE_CONFIG = {
        "CACHE_TYPE": "RedisCache",
        "CACHE_DEFAULT_TIMEOUT": 300,
        "CACHE_KEY_PREFIX": "superset_",
        "CACHE_REDIS_URL": REDIS_URL,
    }
    DATA_CACHE_CONFIG = CACHE_CONFIG
    FILTER_STATE_CACHE_CONFIG = CACHE_CONFIG
    EXPLORE_FORM_DATA_CACHE_CONFIG = CACHE_CONFIG