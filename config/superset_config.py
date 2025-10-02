# SECRET_KEY = 'Sb_rJ7G83swvqj-G5qq343Fw-UA9EqXvKygMGRJeDRNFq4tdT1y9UtcpekiOuuVO'
SECRET_KEY = 'WKlKnTnZFn-AWCWT3qhn8lrHZeMlruXrjw7ZlF6wF9E'
# Add JWT secret for async queries (must be at least 32 bytes)
JWT_ACCESS_TOKEN_EXPIRES = False
SUPERSET_WEBSERVER_TIMEOUT = 300
# # superset_config.py
# WTF_CSRF_ENABLED = False

# Async query JWT secret (at least 32 bytes)
# ASYNC_QUERY_JWT_SECRET = 'my_very_long_async_query_secret_that_is_definitely_more_than_32_bytes_long'

# ----------------------------------------------------------------------
# 1. Feature Flags
# ----------------------------------------------------------------------
FEATURE_FLAGS = {
    "EMBEDDED_SUPERSET": True,
    "EMBEDDABLE_CHARTS": True,
    # "DASHBOARD_CROSS_FILTERS": True,
    # "DASHBOARD_NATIVE_FILTERS": True,
    # # Disable async queries for now to avoid JWT issues
    # # "GLOBAL_ASYNC_QUERIES": True,
    # 'DASHBOARD_RBAC': True,
    # "ENABLE_TEMPLATE_PROCESSING": True,
}

# # ----------------------------------------------------------------------
# # 2. Guest Token/Embedding Security
# # ----------------------------------------------------------------------
# GUEST_TOKEN_JWT_SECRET = 'my_secure_embedding_secret_12345'
# GUEST_TOKEN_JWT_EXP_SECONDS = 600  # 10 minutes
# GUEST_TOKEN_JWT_ALGO = "HS256"
# GUEST_ROLE_NAME = "Gamma"
# # Improve session handling
# PERMANENT_SESSION_LIFETIME = 3600  # 1 hour
# SESSION_COOKIE_HTTPONLY = False
# SESSION_COOKIE_SAMESITE = 'None'
# SESSION_COOKIE_SECURE = False
# GUEST_TOKEN_JWT_AUDIENCE = "superset"

# # ----------------------------------------------------------------------
# # 3. CORS and Iframe Configuration
# # ----------------------------------------------------------------------
# # ENABLE_CORS = True
# # CORS_OPTIONS = {
# #     'supports_credentials': True,
# #     'allow_headers': [
# #         'Content-Type', 
# #         'Authorization', 
# #         'X-CSRFToken', 
# #         'X-Requested-With', 
# #         'GuestToken'
# #     ],
# #     'resources': ['*'],
# #     'origins': [
# #         'http://localhost:3000',  # React dev server
# #         'http://localhost:5000',  # Flask backend
# #         'http://127.0.0.1:3000',
# #         'http://127.0.0.1:5000',
# #     ]
# # }

# # ----------------------------------------------------------------------
# # 4. Security Headers Configuration
# # ----------------------------------------------------------------------
# # Disable Talisman for development (enable and configure properly for production)
# TALISMAN_ENABLED = False

# # Allow embedding in iframes
# OVERRIDE_HTTP_HEADERS = {
#     # 'X-Frame-Options': None  # More secure than ALLOWALL
# }

# # Content Security Policy for embedding
# CSP_FRAME_ANCESTORS = [
#     "'self'",
#     'http://localhost:3000',
#     'http://localhost:5000',
#     'http://127.0.0.1:3000',
#     'http://127.0.0.1:5000',
# ]

# # ----------------------------------------------------------------------
# # 5. Additional Embedding Configuration
# # ----------------------------------------------------------------------
# # Enable public role access (needed for guest tokens)
# PUBLIC_ROLE_LIKE = "Gamma"

# # Ensure guest users can access dashboards
# GUEST_TOKEN_HEADER_NAME = "X-GuestToken"

# # Additional permissions for embedding
# PREVENT_UNSAFE_DB_CONNECTIONS = False
# ENABLE_TEMPLATE_PROCESSING = True

# # Session configuration
# PERMANENT_SESSION_LIFETIME = 600  # 10 minutes

# # Enable debug mode for development
# DEBUG = True
# SQLLAB_ASYNC_TIME_LIMIT_SEC = 600

# EMBEDDING_TRUSTED_DOMAINS = [
#     'http://localhost:3000',
#     'http://127.0.0.1:3000',
# ]