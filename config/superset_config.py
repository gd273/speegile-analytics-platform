SECRET_KEY = 'WKlKnTnZFn-AWCWT3qhn8lrHZeMlruXrjw7ZlF6wF9E'
FEATURE_FLAGS = {
    "EMBEDDED_SUPERSET": True,
    "ALERT_REPORTS": True,
    "EMBEDDABLE_CHARTS": True,
    "DASHBOARD_RBAC": True,
}
GUEST_TOKEN_JWT_SECRET = 'my_secure_embedding_secret_12345'
GUEST_TOKEN_JWT_EXP_SECONDS = 600  # 10 minutes
GUEST_TOKEN_JWT_ALGO = "HS256"
TALISMAN_ENABLED = False
GUEST_TOKEN_HEADER_NAME = "X-GuestToken"
DEBUG = True
GUEST_ROLE_NAME = "Gamma"
GUEST_TOKEN_JWT_SECRET = "my_secure_embedding_secret_12345"
GUEST_TOKEN_JWT_AUDIENCE = "audi"
TALISMAN_ENABLED = False
# DASHBOARD_RBAC = True
OVERRIDE_HTTP_HEADERS = {
    "X-Frame-Options": "ALLOWALL",
    "Content-Security-Policy": "frame-ancestors 'self' http://localhost:3000"
}
ENABLE_CORS = True
CORS_OPTIONS = {
    'supports_credentials': True,
    'allow_headers': ['*'],
    'resources': ['*'],
    'origins': ['*']
}

ALLOWED_REFERRER_DOMAINS = [
    "http://localhost:3000",  # exact match
    "http://localhost:3000/",  # with slash
    "localhost:3000",          # just domain:port
    "http://127.0.0.1:3000",   # optional for dev
    "localhost:5000",
    "localhost:8088"
]

# Keep users logged in for 24 hours
SESSION_COOKIE_DURATION = 86400  # seconds
PERMANENT_SESSION_LIFETIME = 86400
SESSION_REFRESH_EACH_REQUEST = False  # Changed to False
SESSION_PROTECTION = None  # NEW: Disable Flask-Login's session protection
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SECURE = False
SESSION_COOKIE_SAMESITE = 'Lax'


# CSRF configuration
WTF_CSRF_ENABLED = True
WTF_CSRF_TIME_LIMIT = None  # NEW: No expiration on CSRF tokens

FAB_ADD_SECURITY_API = True
ENABLE_SWAGGER_UI = True