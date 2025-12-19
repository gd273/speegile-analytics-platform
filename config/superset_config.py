
# import os

# # ---------------------------------------------------------
# # 1. DATABASE CONNECTION
# # ---------------------------------------------------------
# # Render provides 'DATABASE_URL' automatically. 
# # We check for that first. If not found, we use your local logic.
# DATABASE_URL = os.getenv("DATABASE_URL") 
# if DATABASE_URL and "postgres" in DATABASE_URL:
#     # SQLAlchemy requires 'postgresql://', but Render sometimes gives 'postgres://'
#     SQLALCHEMY_DATABASE_URI = DATABASE_URL.replace("postgres://", "postgresql://")
# else:
#     # Fallback for local dev (or SQLite)
#     SQLALCHEMY_DATABASE_URI = os.getenv("SQLALCHEMY_DATABASE_URI", "sqlite:////app/superset_home/superset.db")

# # ---------------------------------------------------------
# # 2. SECURITY & SECRETS
# # ---------------------------------------------------------
# # CRITICAL: Fetch these from environment in Prod. Fallback to dev defaults if missing.
# SECRET_KEY = os.getenv("SUPERSET_SECRET_KEY")
# if not SECRET_KEY:
#     raise Exception("SUPERSET_SECRET_KEY not set!")
# GUEST_TOKEN_JWT_SECRET = os.getenv("GUEST_TOKEN_JWT_SECRET", "my_secure_embedding_secret_12345")


# WEBDRIVER_TYPE = "chromedriver"
# WEBDRIVER_OPTION_ARGS = [
#     "--headless",
#     "--disable-gpu",
#     "--no-sandbox",
#     "--disable-dev-shm-usage",
# ]
# WEBDRIVER_BASEURL = "http://localhost:8088"
# # ---------------------------------------------------------
# # 3. FEATURE FLAGS
# # ---------------------------------------------------------
# FEATURE_FLAGS = {
#     "EMBEDDED_SUPERSET": True,
#     "ALERT_REPORTS": True,
#     "EMBEDDABLE_CHARTS": True,
#     "DASHBOARD_RBAC": True,
#     "DRILL_BY": True,
#     "ALLOW_FULL_CSV_EXPORT": True,
#     # "ENABLE_DASHBOARD_SCREENSHOT_ENDPOINTS": False,
#     # "ENABLE_DASHBOARD_DOWNLOAD_WEBDRIVER_SCREENSHOT": False,
#     "ENABLE_CHART_DOWNLOAD_WEBDRIVER_SCREENSHOT": True,
#     "ENABLE_DASHBOARD_SCREENSHOT_ENDPOINTS": True,
#     "ENABLE_DASHBOARD_DOWNLOAD_WEBDRIVER_SCREENSHOT": True,

#     # Optional: Allows "Download as Image" button in explore view
#     "DISPLAY_DOWNLOAD_AS_IMAGE": True,
#     "DASHBOARD_VIRTUALIZATION": True,
#     "THUMBNAILS": True,
# }

# # ---------------------------------------------------------
# # 4. EMBEDDING & COOKIES (The tricky part)
# # ---------------------------------------------------------
# # If running on Render/Prod, we need specific cookie settings for embedding to work.
# IS_PRODUCTION = os.getenv("FLASK_ENV") == "production"

# # Guest Token Settings
# GUEST_TOKEN_JWT_EXP_SECONDS = 3600  # 1 hour
# GUEST_TOKEN_JWT_ALGO = "HS256"
# GUEST_TOKEN_HEADER_NAME = "X-GuestToken"
# GUEST_ROLE_NAME = "Admin"
# GUEST_TOKEN_JWT_AUDIENCE = "audi"

# # CORS & Headers
# ENABLE_CORS = True
# # Use the FRONTEND_URL env var if available, otherwise allow all (for dev)
# FRONTEND_URL = os.getenv("FRONTEND_URL", "*") 
# ENABLE_PROXY_FIX = True
# CORS_OPTIONS = {
#     'supports_credentials': True,
#     'allow_headers': ['*'],
#     'resources': ['*'],
#     'origins': [FRONTEND_URL, "http://localhost:3000", "http://127.0.0.1:3000"] if FRONTEND_URL != "*" else ["*"]
# }

# OVERRIDE_HTTP_HEADERS = {
#     "X-Frame-Options": "ALLOWALL",
#     # This tells the browser "It is okay to show this in an iframe on my frontend"
#     "Content-Security-Policy": f"frame-ancestors 'self' {FRONTEND_URL} http://localhost:3000"
# }

# # ---------------------------------------------------------
# # 5. SESSION & COOKIE HARDENING
# # ---------------------------------------------------------
# SESSION_COOKIE_HTTPONLY = True
# SESSION_REFRESH_EACH_REQUEST = False
# SESSION_PROTECTION = None

# # Important: Google Chrome requires SameSite='None' and Secure=True 
# # for iframes (embedding) to work on HTTPS.
# if IS_PRODUCTION:
#     SESSION_COOKIE_SAMESITE = 'None'
#     SESSION_COOKIE_SECURE = True
#     DEBUG = False
# else:
#     # Localhost dev settings
#     SESSION_COOKIE_SAMESITE = 'Lax'
#     SESSION_COOKIE_SECURE = False
#     DEBUG = True

# # ---------------------------------------------------------
# # 6. MISC
# # ---------------------------------------------------------
# TALISMAN_ENABLED = False # Disable Talisman to prevent strict CSP blocking frames
# WTF_CSRF_ENABLED = True
# WTF_CSRF_TIME_LIMIT = None
# FAB_ADD_SECURITY_API = True
# ENABLE_SWAGGER_UI = True
# # ---------------------------------------------------------
# # 7. CACHE CONFIG (Redis) - CRITICAL FOR RENDER
# # ---------------------------------------------------------
# REDIS_URL = os.getenv("REDIS_URL")
# if REDIS_URL:
#     CACHE_CONFIG = {
#         "CACHE_TYPE": "RedisCache",
#         "CACHE_DEFAULT_TIMEOUT": 300,
#         "CACHE_KEY_PREFIX": "superset_",
#         "CACHE_REDIS_URL": REDIS_URL,
#     }
#     DATA_CACHE_CONFIG = CACHE_CONFIG
#     FILTER_STATE_CACHE_CONFIG = CACHE_CONFIG
#     EXPLORE_FORM_DATA_CACHE_CONFIG = CACHE_CONFIG


# # Keep the standard flag just in case
# ENABLE_PROXY_FIX = True
# # 1. Tell Flask that the app lives at /superset
# # This ensures internal links are generated with the prefix
# APPLICATION_ROOT = '/superset'

# # 2. Scope the Session Cookie to /superset
# # Without this, browsers may reject the cookie or clash with the root app
# SESSION_COOKIE_PATH = '/superset'


import os

# ---------------------------------------------------------
# 1. DATABASE CONNECTION
# ---------------------------------------------------------
DATABASE_URL = os.getenv("SQLALCHEMY_DATABASE_URI")
if not DATABASE_URL:
    raise Exception("SQLALCHEMY_DATABASE_URI not found in environment!")

if "postgres" in DATABASE_URL:
    SQLALCHEMY_DATABASE_URI = DATABASE_URL.replace("postgres://", "postgresql://")
else:
    SQLALCHEMY_DATABASE_URI = DATABASE_URL

# ---------------------------------------------------------
# 2. SECURITY & SECRETS
# ---------------------------------------------------------
SECRET_KEY = os.getenv("SUPERSET_SECRET_KEY")
if not SECRET_KEY:
    raise Exception("SUPERSET_SECRET_KEY not set!")

GUEST_TOKEN_JWT_SECRET = os.getenv("GUEST_TOKEN_JWT_SECRET")
if not GUEST_TOKEN_JWT_SECRET:
    raise Exception("GUEST_TOKEN_JWT_SECRET not set!")

# ---------------------------------------------------------
# 3. FEATURE FLAGS
# ---------------------------------------------------------
FEATURE_FLAGS = {
    "EMBEDDED_SUPERSET": True,
    "ALERT_REPORTS": False,
    "EMBEDDABLE_CHARTS": True,
    "DASHBOARD_RBAC": True,
    "DRILL_BY": True,
    "ALLOW_FULL_CSV_EXPORT": True,
    "ENABLE_CHART_DOWNLOAD_WEBDRIVER_SCREENSHOT": False,
    "ENABLE_DASHBOARD_SCREENSHOT_ENDPOINTS": False,
    "ENABLE_DASHBOARD_DOWNLOAD_WEBDRIVER_SCREENSHOT": False,
    "DISPLAY_DOWNLOAD_AS_IMAGE": False,
    "DASHBOARD_VIRTUALIZATION": True,
    "THUMBNAILS": False,
    "ROW_LEVEL_SECURITY": True,
}

# ---------------------------------------------------------
# 4. EMBEDDING & COOKIES
# ---------------------------------------------------------
IS_PRODUCTION = os.getenv("FLASK_ENV") == "production"
FORCE_HTTP = os.getenv("FORCE_HTTP", "false").lower() == "true"

# Guest Token Settings
GUEST_TOKEN_JWT_EXP_SECONDS = 3600
GUEST_TOKEN_JWT_ALGO = "HS256"
GUEST_TOKEN_HEADER_NAME = "X-GuestToken"
GUEST_ROLE_NAME = "Admin"
GUEST_TOKEN_JWT_AUDIENCE = "audi"

# CORS & Headers
ENABLE_CORS = True
FRONTEND_URL = os.getenv("FRONTEND_URL", "http://speegile-analytics.ap-south-1.elasticbeanstalk.com")

CORS_OPTIONS = {
    'supports_credentials': True,
    'allow_headers': ['*'],
    'resources': ['*'],
    'origins': [FRONTEND_URL]
}

OVERRIDE_HTTP_HEADERS = {
    "X-Frame-Options": "ALLOWALL",
    "Content-Security-Policy": f"frame-ancestors 'self' {FRONTEND_URL}"
}

# ---------------------------------------------------------
# 5. SESSION & COOKIE SETTINGS
# ---------------------------------------------------------
SESSION_COOKIE_HTTPONLY = True
SESSION_REFRESH_EACH_REQUEST = False
SESSION_PROTECTION = None

# DO NOT set APPLICATION_ROOT or SESSION_COOKIE_PATH
# Nginx handles the /superset prefix via X-Script-Name header

if IS_PRODUCTION and not FORCE_HTTP:
    SESSION_COOKIE_SAMESITE = 'None'
    SESSION_COOKIE_SECURE = True
    DEBUG = False
else:
    SESSION_COOKIE_SAMESITE = 'Lax'
    SESSION_COOKIE_SECURE = False
    DEBUG = True

# ---------------------------------------------------------
# 6. SECURITY
# ---------------------------------------------------------
TALISMAN_ENABLED = False
WTF_CSRF_ENABLED = True
WTF_CSRF_TIME_LIMIT = None
FAB_ADD_SECURITY_API = True
ENABLE_SWAGGER_UI = False

# ---------------------------------------------------------
# 7. CACHE CONFIG (Redis)
# ---------------------------------------------------------
REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")

CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 300,
    "CACHE_KEY_PREFIX": "superset_",
    "CACHE_REDIS_URL": REDIS_URL,
}
DATA_CACHE_CONFIG = CACHE_CONFIG
FILTER_STATE_CACHE_CONFIG = CACHE_CONFIG
EXPLORE_FORM_DATA_CACHE_CONFIG = CACHE_CONFIG

# ---------------------------------------------------------
# 8. PROXY FIX (for AWS ALB)
# ---------------------------------------------------------
ENABLE_PROXY_FIX = True
# SESSION_COOKIE_SECURE = False
# SESSION_COOKIE_SAMESITE = "Lax"


# ---------------------------------------------------------
# Render-only reverse proxy support (SAFE)
# ---------------------------------------------------------
IS_RENDER = os.getenv("RENDER", "").lower() == "true"

if IS_RENDER:
    # Tell Superset it lives under /superset (Render only)
    # APPLICATION_ROOT = "/superset"

    # Generate correct redirects and absolute URLs
    SUPERSET_WEBSERVER_BASEURL = "https://gateway-dev-gwnu.onrender.com/superset"
