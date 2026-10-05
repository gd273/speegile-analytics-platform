# import os as _os
# from unittest import result
# from flask import Flask, request, jsonify, session
# from flask_cors import CORS
# import jwt
# import time
# import os
# import requests
# import json
# import boto3
# import redis
# from datetime import datetime, timedelta
# from werkzeug.utils import secure_filename
# import pandas as pd
# from sqlalchemy import create_engine, text
# import logging
# from flask_session import Session
# from dotenv import load_dotenv
# from pathlib import Path
# import io
# from tenants_handler import handle_client_orders, handle_shinde_shoes, handle_apparel_store, handle_shinde_shoes_stock, handle_tally_sales,handle_tally_sales_v2, handle_accrec
# from db_utils import log_load_error
# from datetime import datetime
# import threading


# # -------------------- ENV loading & expansion --------------------
# ROOT = Path(__file__).resolve().parents[1]
# DOTENV = ROOT / ".env"
# if DOTENV.exists():
#     load_dotenv(dotenv_path=str(DOTENV), override=False)
# else:
#     load_dotenv(override=False)

# raw_db = os.getenv("APP_DATABASE_URL")
# if raw_db:
#     os.environ["APP_DATABASE_URL"] = _os.path.expandvars(raw_db)

# REDIS_URL                = os.getenv("REDIS_URL", "redis://redis:6379/0")
# SUPERSET_ADMIN_USERNAME  = os.getenv("SUPERSET_ADMIN_USERNAME")
# SUPERSET_ADMIN_PASSWORD  = os.getenv("SUPERSET_ADMIN_PASSWORD")
# SUPERSET_URL             = os.getenv("SUPERSET_URL")
# DATABASE_URL             = os.getenv("APP_DATABASE_URL")
# GUEST_TOKEN_JWT_SECRET   = os.getenv("GUEST_TOKEN_JWT_SECRET")
# AWS_REGION = os.getenv("AWS_REGION", "ap-south-1")  # ✅ single source of truth


# app = Flask(__name__)

# flask_secret = os.getenv("FLASK_SECRET_KEY") or os.getenv("SECRET_KEY") or "dev_fallback_secret_please_change"
# app.secret_key = flask_secret

# print("======================================================================")
# print(f"Flask App Initialized with REDIS Session Storage.")
# print("======================================================================")

# app.config.update(
#     SESSION_TYPE='redis',
#     SESSION_REDIS=redis.from_url(REDIS_URL),
#     SESSION_COOKIE_NAME='flask_session',
#     SESSION_COOKIE_HTTPONLY=True,
#     SESSION_COOKIE_SAMESITE='None',
#     SESSION_COOKIE_SECURE=True,
#     PERMANENT_SESSION_LIFETIME=timedelta(hours=1),
#     SESSION_PERMANENT=False,
#     SESSION_COOKIE_DOMAIN=None
# )
# Session(app)

# raw_origins  = os.getenv("CORS_ALLOW_ORIGINS", "http://localhost:3000,https://frontend-ao4w.onrender.com")
# CORS_ORIGINS = [o.strip() for o in raw_origins.split(",") if o.strip()]
# CORS(app,
#      resources={r"/*": {
#          "origins": CORS_ORIGINS,
#         #  "supports_credentials": True,
#          "allow_headers": ["Content-Type", "Authorization"],
#          "expose_headers": ["Set-Cookie"],
#          "methods": ["GET", "POST", "OPTIONS"],
#         #  "allow_credentials": True
#      }},
#      supports_credentials=True
# )

# #---------------------------------------------------------------------
# # Help to get exact Colour to superset tableau colour scheme
# #---------------------------------------------------------------------

# def resolve_color_scheme(raw):
#     """
#     Resolves a Superset colorScheme value to a hex string.
#     Handles: direct hex, rgb(), rgba(), named schemes.
#     """
#     COLOR_SCHEME_MAP = {
#         "success":         "#439066",
#         "alert":           "#ffa700",
#         "error":           "#e04355",
#         "colorsuccessbg":  "#439066",
#         "colorwarningbg":  "#ffa700",
#         "colorerrorbg":    "#e04355",
#     }
#     if not raw:
#         return None
#     s = str(raw).strip()
#     if s.startswith("#"):
#         return s
#     if s.startswith("rgb("):
#         try:
#             parts = s.replace("rgb(", "").replace(")", "").split(",")
#             r, g, b = [int(p.strip()) for p in parts]
#             return f"#{r:02x}{g:02x}{b:02x}"
#         except Exception:
#             pass
#     if s.startswith("rgba("):
#         try:
#             parts = s.replace("rgba(", "").replace(")", "").split(",")
#             r, g, b = [int(p.strip()) for p in parts[:3]]
#             return f"#{r:02x}{g:02x}{b:02x}"
#         except Exception:
#             pass
#     return COLOR_SCHEME_MAP.get(s.lower())


# ## ---------------------------------------------------------
# # AWS S3 client setup
# # ---------------------------------------------------------
# S3_BUCKET = os.getenv("S3_BUCKET_NAME", "speegile-tenant-upload-file")
# s3_client = boto3.client(
#     's3',
#     aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID"),
#     aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY"),
#     region_name= AWS_REGION
# )

# def upload_file_to_s3(file_bytes, tenant_schema, filename):
#     s3_key = f"speegile-tenant-upload-file/{tenant_schema}/{filename}"
#     s3_url = f"https://{S3_BUCKET}.s3.{os.getenv('AWS_REGION', 'ap-south-1')}.amazonaws.com/{s3_key}"
#     try:
#         from io import BytesIO
#         s3_client.upload_fileobj(
#             BytesIO(file_bytes),
#             S3_BUCKET,
#             s3_key,
#             ExtraArgs={'ContentType': 'application/octet-stream'},
#             Config=boto3.s3.transfer.TransferConfig(
#                 multipart_threshold=10 * 1024 * 1024,
#                 max_concurrency=5
#             )
#         )
#         print(f"DEBUG: File uploaded to S3 → {s3_url}", flush=True)
#         return s3_key, s3_url
#     except Exception as e:
#         print(f"DEBUG: S3 upload failed: {e}", flush=True)
#         return None, None

# # ---------------------------------------------------------
# # DATABASE ENGINE
# # ---------------------------------------------------------
# engine = None
# if DATABASE_URL:
#     try:
#         engine = create_engine(DATABASE_URL)
#         print("Database engine created successfully")
#     except Exception as e:
#         print(f"DATABASE CONNECTION FAILED: {e}")
#         engine = None

# ALLOWED_EXTENSIONS = {'xlsx', 'csv'}

# def allowed_file(filename):
#     return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


# # ---------------------------------------------------------
# # SUPERSET HELPERS
# # ---------------------------------------------------------
# def get_superset_access_token():
#     try:
#         response = requests.post(
#             f"{SUPERSET_URL}/api/v1/security/login",
#             json={
#                 "password": SUPERSET_ADMIN_PASSWORD,
#                 "provider": "db",
#                 "refresh":  True,
#                 "username": SUPERSET_ADMIN_USERNAME
#             },
#             timeout=10
#         )
#         if response.status_code == 200:
#             return response.json().get("access_token")
#         return None
#     except Exception as e:
#         print(f"Error getting Superset token: {e}")
#         return None


# def get_all_dashboards_from_superset(access_token):
#     try:
#         query    = {"page": 0, "page_size": 100}
#         response = requests.get(
#             f"{SUPERSET_URL}/api/v1/dashboard/",
#             params={"q": json.dumps(query)},
#             headers={"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"},
#             timeout=10
#         )
#         if response.status_code == 200:
#             return response.json().get("result", [])
#         return []
#     except Exception as e:
#         return []


# def filter_dashboards_by_user_roles(dashboards, user_roles):
#     if not user_roles:
#         return []
#     user_role_names_lower = [role.lower() for role in user_roles]

#     if 'admin' in user_role_names_lower:
#         return dashboards

#     filtered = []
#     for dashboard in dashboards:
#         dashboard_roles = dashboard.get('roles', [])
#         if not dashboard_roles:
#             filtered.append(dashboard)
#             continue
#         dashboard_role_names = [role['name'].lower() for role in dashboard_roles]
#         if any(role in dashboard_role_names for role in user_role_names_lower):
#             filtered.append(dashboard)

#     return filtered


# def get_embedded_dashboard_uuid(filtered_dashboard_list, access_token):
#     embedded_dashboards = []
#     if not filtered_dashboard_list:
#         return []

#     for filtered_dashboard in filtered_dashboard_list:
#         dashboard_id = filtered_dashboard.get('id')
#         if not dashboard_id:
#             continue
#         try:
#             response = requests.get(
#                 f"{SUPERSET_URL}/api/v1/dashboard/{dashboard_id}/embedded",
#                 headers={"Authorization": f"Bearer {access_token}"},
#                 timeout=10
#             )
#             if response.status_code == 200:
#                 result_data = response.json().get("result")
#                 if result_data and "uuid" in result_data:
#                     filtered_dashboard['embedded_uuid'] = result_data["uuid"]
#                     embedded_dashboards.append(filtered_dashboard)
#         except Exception:
#             pass

#     return embedded_dashboards





# def login_required(f):
#     from functools import wraps
#     @wraps(f)
#     def decorated_function(*args, **kwargs):
#         if 'user' not in session:
#             return jsonify({"error": "Authentication required"}), 401
#         return f(*args, **kwargs)
#     return decorated_function


# # ---------------------------------------------------------
# # AUTH ROUTES
# # ---------------------------------------------------------
# @app.route("/api/login", methods=["POST"])
# def login():
#     data     = request.get_json()
#     username = data.get("username")
#     password = data.get("password")

#     if not username or not password:
#         return jsonify({"error": "Username and password required"}), 400

#     if not engine:
#         return jsonify({"error": "Database unavailable"}), 500

#     try:
#         with engine.connect() as conn:
#             query = text("""
#                 SELECT
#                     u.id, u.name, u.password_hash, u.role, u.superset_username, u.upload_access,
#                     t.schema_name, t.table_name,t.procedure_name, t.function_name,
#                     t.id as tenant_pk,
#                     tpl.logo_url
#                 FROM public.users u
#                 JOIN public.tenants t ON u.tenant_id = t.id
#                 LEFT JOIN public.tenant_templates tpl ON t.id = tpl.tenant_id
#                 WHERE u.email = :u
#             """)
#             user = conn.execute(query, {"u": username}).fetchone()

#             if not user or user.password_hash != password:
#                 return jsonify({"error": "Invalid credentials"}), 401

#             session.clear()
#             session.permanent          = True
#             session['user']            = username
#             session['name']            = user.name
#             session['role']            = user.role
#             session['roles']           = [user.role]
#             session['superset_username'] = user.superset_username
#             session['tenant_schema']   = user.schema_name
#             session['tenant_id']       = user.tenant_pk
#             session['user_id']         = user.id
#             session['logo_url']        = user.logo_url
#             session["upload_access"]   = user.upload_access
#             session["table_name"]      = user.table_name
#             session["procedure_name"]  = user.procedure_name
#             session["function_name"]   = user.function_name
#             print(f"DEBUG: User upload_access for '{username}': {user.upload_access}", flush=True)
#             return jsonify({
#                 "success": True,
#                 "user": {
#                     "username": username,
#                     "name":     user.name,
#                     "roles":    [user.role],
#                     "logo":     user.logo_url
#                 }
#             }), 200

#     except Exception as e:
#         print(f"Login Error: {e}")
#         return jsonify({"error": "Server error during login"}), 500


# @app.route("/api/logout", methods=["POST"])
# def logout():
#     session.clear()
#     return jsonify({"success": True}), 200


# @app.route("/api/check-auth", methods=["GET"])
# def check_auth():
#     if 'user' in session:
#         return jsonify({
#             "authenticated": True,
#             "user": {
#                 "username": session['user'],
#                 "name":     session.get('name'),
#                 "roles":    session.get('roles', []),
#                 "logo":     session.get('logo_url')
#             }
#         }), 200
#     else:
#         return jsonify({"authenticated": False}), 200


# # ---------------------------------------------------------
# # DASHBOARDS
# # ---------------------------------------------------------
# @app.route("/api/dashboards", methods=["GET"])
# @login_required
# def get_filtered_dashboards():
#     user_roles = session.get('roles', [])

#     try:
#         access_token = get_superset_access_token()
#         if not access_token:
#             return jsonify({"error": "Failed to connect to Superset"}), 500

#         print(f"DEBUG: Superset token OK", flush=True)

#         all_dashboards = get_all_dashboards_from_superset(access_token)
#         print(f"DEBUG: Total dashboards: {len(all_dashboards)}", flush=True)

#         filtered = filter_dashboards_by_user_roles(all_dashboards, user_roles)
#         print(f"DEBUG: Filtered dashboards: {len(filtered)}", flush=True)

#         dashboard_list = [{
#             "id":              d.get('id'),
#             "dashboard_title": d.get('dashboard_title'),
#             "url":             d.get('url'),
#             "roles":           [r['name'] for r in d.get('roles', [])]
#         } for d in filtered]

#         embedded_dashboards = get_embedded_dashboard_uuid(dashboard_list, access_token)
#         print(f"DEBUG: Embedded dashboards: {len(embedded_dashboards)}", flush=True)

#         category_map = {}
#         if engine and embedded_dashboards:
#             dashboard_ids = [d.get('id') for d in embedded_dashboards if d.get('id')]
#             try:
#                 with engine.connect() as conn:
#                     rows = conn.execute(text("""
#                         SELECT dashboard_id, category
#                         FROM public.dashboard_category_map
#                         WHERE dashboard_id = ANY(:ids)
#                     """), {"ids": dashboard_ids}).fetchall()
#                 category_map = {row.dashboard_id: row.category for row in rows}
#             except Exception as e:
#                 print(f"DEBUG: category_map error: {e}", flush=True)
#                 category_map = {}

#         for d in embedded_dashboards:
#             d['category'] = category_map.get(d.get('id'), 'General')

#         return jsonify({"success": True, "dashboards": embedded_dashboards}), 200

#     except Exception as e:
#         import traceback
#         traceback.print_exc()
#         return jsonify({"error": str(e)}), 500


# # ---------------------------------------------------------
# # GUEST TOKEN
# # ---------------------------------------------------------
# @app.route("/api/guest-token", methods=["GET"])
# @login_required
# def generate_guest_token():
#     dashboard_id_str  = request.args.get("dashboardId")
#     superset_username = session.get('superset_username')

#     if not dashboard_id_str:
#         return jsonify({"error": "dashboardId is required"}), 400

#     expiration_time = int(time.time()) + 3600

#     payload = {
#         "user": {
#             "username":   superset_username,
#             "first_name": "Guest",
#             "last_name":  "User",
#         },
#         "resources": [{"type": "dashboard", "id": dashboard_id_str}],
#         "rls_rules": [],
#         "exp":  expiration_time,
#         "aud":  "audi",
#         "type": "guest"
#     }

#     try:
#         token = jwt.encode(payload, GUEST_TOKEN_JWT_SECRET, algorithm="HS256")
#         return jsonify({"guestToken": token}), 200
#     except Exception as e:
#         return jsonify({"error": "Failed to encode token"}), 500


# # ---------------------------------------------------------
# # Upload-Excel API
# # ---------------------------------------------------------

# @app.route('/api/upload-excel', methods=['POST'])
# @login_required
# def upload_excel():

#     # ── Session details ───────────────────────────────────
#     tenant_schema  = session.get('tenant_schema')
#     tenant_id      = session.get('tenant_id')
#     user_id        = session.get('user_id', 1)
#     procedure_name = session.get('procedure_name')
#     function_name  = session.get('function_name')
#     # ← ADD: procedure_name and function_name from session
#     # (stored at login time — shown below how to set them)

#     print(f"DEBUG: Tenant Schema: {tenant_schema}", flush=True)
#     print(f"DEBUG: Tenant ID: {tenant_id}",         flush=True)
#     print(f"DEBUG: User ID: {user_id}",             flush=True)

#     # ── Validate file ─────────────────────────────────────
#     if 'excel_file' not in request.files:
#         return jsonify({"success": False, "error": "No file part"}), 400

#     file = request.files['excel_file']
#     if file.filename == '':
#         return jsonify({"success": False, "error": "No selected file"}), 400

#     if engine is None:
#         return jsonify({"success": False, "error": "Database unavailable"}), 503

#     if not tenant_schema:
#         return jsonify({"success": False, "error": "No tenant context found"}), 403

#     if not file or not allowed_file(file.filename):
#         return jsonify({"success": False,
#                         "error": "Invalid file type. Only xlsx and csv allowed"}), 400

#     clean_filename = secure_filename(file.filename)
#     lower_filename = clean_filename.lower()
#     file_ext       = clean_filename.rsplit('.', 1)[1].lower()

#     # ── Read file bytes ONCE in main thread ───────────────
#     # Must happen here — file object closes after response
#     print(f"DEBUG: Reading file bytes...", flush=True)
#     file_bytes  = file.read()
#     file_buffer = io.BytesIO(file_bytes)
#     print(f"DEBUG: File read done. Size={len(file_bytes)} bytes", flush=True)

#     MAX_FILE_SIZE = 100 * 1024 * 1024
#     if len(file_bytes) > MAX_FILE_SIZE:
#         return jsonify({"success": False,
#                         "error": "File too large. Maximum allowed size is 100MB."}), 400

#     # ── Redis lock ────────────────────────────────────────
#     r        = redis.from_url(os.getenv("REDIS_URL"))
#     lock_key = f"upload_lock:{tenant_schema}"
#     lock     = r.set(lock_key, "1", nx=True, ex=600)  # 10 min lock

#     if not lock:
#         return jsonify({
#             "success": False,
#             "error":   "Another upload is already in progress. Please wait."
#         }), 429

#     try:
#         # ── Tenant lookup ─────────────────────────────────
#         print(f"DEBUG: Opening DB connection for tenant lookup...", flush=True)
#         with engine.connect() as conn:
#             tenant_data = conn.execute(text("""
#                 SELECT
#                     id,
#                     tenant_name,
#                     schema_name,
#                     table_name,
#                     fileprefix,
#                     procedure_name,
#                     function_name,
#                     "DomainId"
#                 FROM public.tenants
#                 WHERE schema_name = :schema
#                   AND (
#                       fileprefix IS NULL
#                       OR LOWER(:filename) LIKE LOWER(fileprefix) || '%'
#                   )
#                 ORDER BY LENGTH(fileprefix) DESC
#                 LIMIT 1
#             """), {
#                 "schema":   tenant_schema,
#                 "filename": lower_filename
#             }).mappings().first()

#         print(
#             f"DEBUG: Tenant lookup done. "
#             f"tenant={tenant_data['tenant_name'] if tenant_data else 'NOT FOUND'}",
#             flush=True
#         )

#         if not tenant_data:
#             with engine.connect() as conn:
#                 known_prefixes = conn.execute(text("""
#                     SELECT fileprefix FROM public.tenants
#                     WHERE schema_name = :schema
#                       AND fileprefix IS NOT NULL
#                 """), {"schema": tenant_schema}).scalars().all()
#             prefix_list = ", ".join(f"'{p}'" for p in known_prefixes) \
#                           or "none configured"
#             r.delete(lock_key)
#             return jsonify({
#                 "success": False,
#                 "error":   f"Invalid file name. No configuration found for "
#                            f"'{clean_filename}'. "
#                            f"Expected prefixes: {prefix_list}."
#             }), 400

#         tenant_id         = tenant_data["id"]
#         target_table_name = tenant_data["table_name"]
#         file_prefix       = tenant_data["fileprefix"] or ""
#         tenant_name       = tenant_data["tenant_name"].strip().lower()
#         procedure_name    = tenant_data["procedure_name"]   # ← NEW
#         function_name     = tenant_data["function_name"]    # ← NEW
#         # -------------------------------------------------------------
#         # Detect file type
#         # -------------------------------------------------------------
#         file_prefix_lower = file_prefix.lower()

#         if "inventory" in file_prefix_lower:
#             file_type = "inventory"

#         elif "purchase" in file_prefix_lower:
#             file_type = "purchase"

#         else:
#             file_type = "sales"

#         print(f"DEBUG: Matched prefix   : {file_prefix}", flush=True)
#         print(f"DEBUG: Target table     : {target_table_name}", flush=True)
#         print(f"DEBUG: Detected type    : {file_type}", flush=True)
#         print(f"DEBUG: Tenant name      : {tenant_name}", flush=True)
#         print(f"DEBUG: Procedure name   : {procedure_name}", flush=True)
#         print(f"DEBUG: Function name    : {function_name}", flush=True)

#         # ── Create load_master record ─────────────────────
#         # Done in MAIN thread so we have load_id to return
#         with engine.connect() as load_conn:
#             load_id = load_conn.execute(text("""
#                 INSERT INTO public.load_master
#                     (tenant_id, user_id, filename, status)
#                 VALUES (:tid, :uid, :fname, 'Queued')
#                 RETURNING id
#             """), {
#                 "tid":   tenant_id,
#                 "uid":   user_id,
#                 "fname": clean_filename
#             }).scalar()
#             load_conn.commit()

#         print(f"DEBUG: Load ID created: {load_id}", flush=True)

#         # ── Start background thread ───────────────────────
#         # Pass everything the thread needs — file bytes + all context
#         thread = threading.Thread(
#             target = _process_upload_background,
#             args   = (
#                 file_bytes,
#                 file_ext,
#                 clean_filename,
#                 tenant_schema,
#                 tenant_name,
#                 tenant_id,
#                 target_table_name,
#                 file_type,
#                 load_id,
#                 user_id,
#                 lock_key,
#                 procedure_name,
#                 function_name,
#             ),
#             daemon = True
#         )
#         thread.start()
#         print(f"DEBUG: Background thread started. load_id={load_id}",
#               flush=True)

#         # ── Respond immediately ───────────────────────────
#         return jsonify({
#             "success":   True,
#             "message":   f"File received. "
#                          f"Processing in background.",
#             "load_id":   load_id,
#             "file_type": file_type,
#         }), 202

#     except Exception as e:
#         print(f"DEBUG: Unexpected error in main thread: {e}", flush=True)
#         import traceback; traceback.print_exc()
#         r.delete(lock_key)
#         return jsonify({"success": False, "error": str(e)}), 500


# # ════════════════════════════════════════════════════════
# #  BACKGROUND THREAD FUNCTION
# #  This is your ENTIRE existing processing logic
# #  moved into a function that runs in a thread.
# #  Nothing changed inside — just moved here.
# # ════════════════════════════════════════════════════════
# def _process_upload_background(
#     file_bytes,
#     file_ext,
#     clean_filename,
#     tenant_schema,
#     tenant_name,
#     tenant_id,
#     target_table_name,
#     file_type,
#     load_id,
#     user_id,
#     lock_key,
#     procedure_name,
#     function_name,
# ):
#     r = redis.from_url(os.getenv("REDIS_URL"))

#     # ── Helper: update load_master status using a fresh connection ──
#     # Called at each step so frontend always sees current progress
#     def update_status(new_status):
#         try:
#             with engine.connect() as sc:
#                 sc.execute(text("""
#                     UPDATE public.load_master
#                     SET    status = :status
#                     WHERE  id     = :lid
#                 """), {"status": new_status, "lid": load_id})
#                 sc.commit()
#             print(f"DEBUG: Status → {new_status} (load_id={load_id})",
#                   flush=True)
#         except Exception as e:
#             print(f"DEBUG: Could not update status to {new_status}: {e}",
#                   flush=True)

#     try:
#         file_buffer = io.BytesIO(file_bytes)

#         with engine.connect() as conn:
#             trans = conn.begin()
#             try:

#                 # ── STEP 1: Reading file ──────────────────────────────────
#                 update_status('Reading')

#                 if file_ext == 'xlsx':
#                     xls        = pd.ExcelFile(file_buffer, engine='openpyxl')
#                     dataframes = [
#                         xls.parse(sheet, dtype=str)
#                         for sheet in xls.sheet_names
#                     ]
#                 elif file_ext == 'csv':
#                     file_buffer.seek(0)
#                     dataframes = [
#                         pd.read_csv(file_buffer, dtype=str,
#                                     encoding='utf-8-sig')
#                     ]
#                 else:
#                     raise ValueError("Unsupported file format")


#                 # ── S3 Backup — store original file for audit/history ────
#                 # Non-critical: if S3 fails, processing still continues
#                 try:
#                     s3_key, s3_url = upload_file_to_s3(
#                         file_bytes, tenant_schema, clean_filename
#                     )
#                     if s3_url:
#                         print(f"DEBUG: File backed up to S3 → {s3_url}", flush=True)
#                         # Store S3 URL in load_master if column exists
#                         try:
#                             with engine.connect() as s3_conn:
#                                 s3_conn.execute(text("""
#                                     UPDATE public.load_master
#                                     SET    s3_url = :url
#                                     WHERE  id     = :lid
#                                 """), {"url": s3_url, "lid": load_id})
#                                 s3_conn.commit()
#                         except Exception as s3_db_err:
#                             # Column may not exist yet — non-critical
#                             print(
#                                 f"DEBUG: Could not store S3 URL in load_master "
#                                 f"(non-critical): {s3_db_err}",
#                                 flush=True
#                             )
#                     else:
#                         print("DEBUG: S3 upload returned no URL.", flush=True)
#                 except Exception as s3_err:
#                     print(f"DEBUG: S3 upload failed (non-critical): {s3_err}", flush=True)

#                 # ── STEP 2: Preparing data ────────────────────────────────
#                 update_status('Preparing')

#                 excel_max_date = None
#                 df_original    = None

#                 for df in dataframes:
#                     if df.empty:
#                         continue

#                     df.columns = [c.strip() for c in df.columns]
#                     df         = df.dropna(how='all').reset_index(drop=True)

#                     if df.empty:
#                         raise ValueError(
#                             "Uploaded file contains no data rows."
#                         )

#                     df_original = df.copy()
#                     print(f"DEBUG: Columns: {list(df.columns)}", flush=True)
#                     print(f"DEBUG: Rows: {len(df)}",             flush=True)

#                     table_columns = conn.execute(text("""
#                         SELECT column_name
#                         FROM   information_schema.columns
#                         WHERE  table_schema = :schema
#                           AND  table_name   = :table
#                     """), {
#                         "schema": tenant_schema,
#                         "table":  target_table_name
#                     }).scalars().all()

#                     print(f"DEBUG: DB columns: {table_columns}", flush=True)

#                     df = df[[
#                         col for col in df.columns
#                         if col in table_columns
#                     ]].copy()

#                     if 'load_id' in table_columns:
#                         df['load_id'] = load_id

#                     print(f"DEBUG: Data prepared for {target_table_name}",
#                           flush=True)

#                 # ── STEP 3: Validating + Processing ──────────────────────
#                 update_status('Processing')

#                 #-------------------------------------------------------------
#                 # Route to correct handler based on tenant name + file type
#                 #-------------------------------------------------------------
#                 if tenant_name == "shinde_shoes" and file_type == "sales":
#                     handle_shinde_shoes(
#                         conn, df, tenant_schema, target_table_name,
#                         load_id, log_load_error, engine
#                     )

#                 # elif tenant_name == "shinde_shoes" and file_type == "inventory":
#                 #     handle_shinde_shoes_stock(
#                 #         conn, df, tenant_schema, target_table_name,
#                 #         load_id, log_load_error, filename=clean_filename
#                 #     )
#                 elif tenant_name == "shinde_shoes" and file_type == "inventory":
#                     handle_shinde_shoes_stock(
#                         conn,
#                         df,
#                         tenant_schema,
#                         target_table_name,
#                         load_id,
#                         log_load_error,
#                         filename=clean_filename,
#                         user_id=user_id
#                     )
#                 elif tenant_name == "apparel_sales":
#                     handle_apparel_store(
#                         conn, df_original, tenant_schema,
#                         load_id, log_load_error
#                     )

#                 elif tenant_name == "siddhesh":
#                     handle_client_orders(
#                         conn, df, tenant_schema, target_table_name,
#                         load_id, log_load_error
#                     )

#                 elif tenant_name == "tally_data":
#                     handle_tally_sales(
#                         conn, df_original, tenant_schema, target_table_name,
#                         load_id, log_load_error
#                     )

#                 elif tenant_name == "tally_data2":
#                     handle_tally_sales_v2(
#                         conn, df_original, tenant_schema, target_table_name,
#                         load_id, log_load_error
#                     )

#                 elif tenant_name == "accrec":
#                     handle_accrec(
#                         conn, df_original, tenant_schema, target_table_name,
#                         load_id, log_load_error
#                     )

#                 else:
#                     # ── No Python handler — generic flow ──────────────────
#                     # Inserts string data into staging table then calls
#                     # the SQL procedure stored in public.tenants
#                     # if not procedure_name:
#                     #     raise ValueError(
#                     #         f"No handler and no procedure_name configured "
#                     #         f"for tenant '{tenant_name}'. "
#                     #         f"Please set procedure_name in public.tenants."
#                     #     )

#                     print(
#                         f"DEBUG: No Python handler for '{tenant_name}'. "
#                         f"Using generic flow → insert strings + call procedure.",
#                         flush=True
#                     )

#                     # Truncate staging table before insert
#                     conn.execute(text(
#                         f'TRUNCATE TABLE "{tenant_schema}".'
#                         f'"{target_table_name}" RESTART IDENTITY'
#                     ))
#                     print(f"DEBUG: Truncated {target_table_name}.", flush=True)

#                     # Insert all data as strings into staging table
#                     df.to_sql(
#                         target_table_name,
#                         con       = conn,
#                         schema    = tenant_schema,
#                         if_exists = 'append',
#                         index     = False
#                     )
#                     print(
#                         f"DEBUG: Inserted {len(df)} rows into "
#                         f"{tenant_schema}.{target_table_name}.",
#                         flush=True
#                     )

#                     # Call SQL procedure — handles type conversion,
#                     # validation, business logic, MV refresh
#                     # conn.execute(
#                     #     text(
#                     #         f'CALL "{tenant_schema}".'
#                     #         f'"{procedure_name}"()'
#                     #     )
#                     # )

#                     if procedure_name:

#                         print(
#                             f"DEBUG: Procedure configured: {procedure_name}",
#                             flush=True
#                         )

#                         conn.execute(
#                             text(
#                                 f'CALL "{tenant_schema}".'
#                                 f'"{procedure_name}"()'
#                             )
#                         )

#                         print(
#                             f"DEBUG: Procedure {procedure_name} done.",
#                             flush=True
#                         )

#                     else:

#                         print(
#                             f"DEBUG: No procedure configured for "
#                             f"{tenant_name}/{file_type}. "
#                             f"Staging upload completed without procedure.",
#                             flush=True
#                         )




#                     print(f"DEBUG: Procedure {procedure_name} done.",
#                           flush=True)

#                 # ── Free RAM immediately after handler finishes ───────────
#                 # Handler is done — df is already inserted into DB.
#                 # Delete large objects from memory so Render doesn't OOM.
#                 import gc
#                 try:
#                     del df
#                 except Exception:
#                     pass
#                 try:
#                     del df_original
#                 except Exception:
#                     pass
#                 try:
#                     del dataframes
#                 except Exception:
#                     pass
#                 try:
#                     del file_buffer
#                 except Exception:
#                     pass
#                 gc.collect()
#                 print("DEBUG: RAM freed after handler.", flush=True)


#                 # ── STEP 4: Saving ────────────────────────────────────────
#                 update_status('Saving')

#                 conn.execute(text("""
#                     UPDATE public.load_master
#                     SET    status = 'Pass'
#                     WHERE  id     = :lid
#                 """), {"lid": load_id})

#                 trans.commit()
#                 print("DEBUG: Transaction committed.", flush=True)

#                 # ── STEP 5: Clearing Superset cache ───────────────────────
#                 update_status('Pass')

#                 try:
#                     for key in r.scan_iter("superset*"):
#                         r.delete(key)
#                     print("DEBUG: Superset cache cleared.", flush=True)
#                 except Exception as cache_err:
#                     print(
#                         f"DEBUG: Cache clear failed (non-critical): "
#                         f"{cache_err}",
#                         flush=True
#                     )

#             except Exception as e:
#                 error_message = str(e)

#                 try:
#                     trans.rollback()
#                 except Exception:
#                     pass

#                 print(f"DEBUG: ERROR in background: {error_message}",
#                       flush=True)
#                 import traceback
#                 traceback.print_exc()

#                 # ── Log error to load_errors (separate connection) ────────
#                 try:
#                     with engine.connect() as error_conn:
#                         log_load_error(
#                             conn=error_conn, load_id=load_id,
#                             error_message=error_message,
#                             row_number=None, column_name=None
#                         )
#                         error_conn.commit()
#                         print(f"DEBUG: Error logged to load_errors. "
#                               f"load_id={load_id}", flush=True)
#                 except Exception as log_err:
#                     print(f"DEBUG: Failed to log error: {log_err}",
#                           flush=True)

#                 # ── Mark load_master as Fail (separate connection) ────────
#                 try:
#                     with engine.connect() as fail_conn:
#                         fail_conn.execute(text("""
#                             UPDATE public.load_master
#                             SET    status = 'Fail'
#                             WHERE  id     = :lid
#                         """), {"lid": load_id})
#                         fail_conn.commit()
#                         print(f"DEBUG: load_master marked Fail. "
#                               f"load_id={load_id}", flush=True)
#                 except Exception as fail_err:
#                     print(f"DEBUG: Could not update status to Fail: "
#                           f"{fail_err}", flush=True)

#     finally:
#         # Always release Redis lock when thread finishes (pass or fail)
#         r.delete(lock_key)
#         print(
#             f"DEBUG: Upload lock released for {tenant_schema}.",
#             flush=True
#         )


# # ════════════════════════════════════════════════════════
# #  POLL ENDPOINT — frontend calls every 3 seconds
# # ════════════════════════════════════════════════════════
# @app.route('/api/upload-status/<int:load_id>', methods=['GET'])
# @login_required
# def upload_status(load_id):
#     with engine.connect() as conn:

#         # ── Get current status from load_master ───────────────────────
#         row = conn.execute(text("""
#             SELECT status, filename
#             FROM   public.load_master
#             WHERE  id = :lid
#         """), {"lid": load_id}).mappings().first()

#         if not row:
#             return jsonify({"status": "unknown"}), 404

#         status = row["status"]

#         # ── If failed, fetch error message from load_errors ───────────
#         error_message = None
#         if status == "Fail":
#             error_row = conn.execute(text("""
#                 SELECT error_message
#                 FROM   public.load_errors
#                 WHERE  load_id   = :lid
#                 ORDER  BY created_at DESC
#                 LIMIT  1
#             """), {"lid": load_id}).mappings().first()

#             if error_row:
#                 error_message = error_row["error_message"]

#     # ── Map each status to a percent and message ──────────────────────
#     # Status flow: Queued → Reading → Preparing → Processing → Saving → Pass
#     PERCENT_MAP = {
#         "Queued":     5,
#         "Reading":    20,
#         "Preparing":  40,
#         "Processing": 65,
#         "Saving":     85,
#         "Pass":       100,
#         "Fail":       0,
#     }

#     MESSAGE_MAP = {
#         "Queued":     "File received, starting...",
#         "Reading":    "Reading file data...",
#         "Preparing":  "Preparing data for processing...",
#         "Processing": "Validating and processing data...",
#         "Saving":     "Saving to database...",
#         "Pass":       "Data uploaded! Your dashboards are ready.",
#         "Fail":       error_message or "Processing failed. Please contact support.",
#     }

#     return jsonify({
#         "status":        status,
#         "percent":       PERCENT_MAP.get(status, 50),
#         "message":       MESSAGE_MAP.get(status, "Processing..."),
#         "error_message": error_message,
#         "load_id":       load_id,
#         "filename":      row["filename"],
#     }), 200







# # ---------------------------------------------------------
# # BRANDING
# # ---------------------------------------------------------
# @app.route("/api/branding", methods=["GET"])
# @login_required
# def get_branding():
#     try:
#         tenant_id = session.get("tenant_id")
#         if not tenant_id:
#             return jsonify({"error": "No tenant context"}), 400

#         with engine.connect() as conn:
#             result = conn.execute(text("""
#                 SELECT logo_url, branding_name
#                 FROM public.tenant_templates
#                 WHERE id = :tid
#             """), {"tid": tenant_id}).mappings().first()

#         if not result:
#             return jsonify({"error": "Branding not found"}), 404

#         return jsonify({
#             "logo_url":     result["logo_url"],
#             "branding_name": result["branding_name"]
#         }), 200

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500


# # ---------------------------------------------------------
# # TRUNCATE TABLE
# # ---------------------------------------------------------
# @app.route('/truncate-data', methods=['GET'])
# def truncate_table_simple():
#     TARGET_SCHEMA = "apparel_sales"
#     TARGET_TABLE  = "t_apparel_sales"

#     try:
#         with engine.connect() as conn:
#             query = text(f'TRUNCATE TABLE "{TARGET_SCHEMA}"."{TARGET_TABLE}" RESTART IDENTITY CASCADE')
#             conn.execute(query)
#             conn.commit()
#             return f"""
#             <div style="font-family:sans-serif; text-align:center; margin-top:100px;">
#                 <h1 style="color:green;">Table Truncated</h1>
#                 <p>All data has been deleted from: <b>{TARGET_SCHEMA}.{TARGET_TABLE}</b></p>
#                 <p>Serial IDs have been reset to 1.</p>
#             </div>
#             """, 200
#     except Exception as e:
#         return f"<h1>Error</h1><p>{str(e)}</p>", 500


# # ---------------------------------------------------------
# # GET ALL CHARTS FOR A DASHBOARD
# # ---------------------------------------------------------


# @app.route("/api/dashboard-charts", methods=["GET"])
# @login_required
# def get_dashboard_charts():
#     dashboard_id = request.args.get("dashboardId")

#     if not dashboard_id:
#         return jsonify({"error": "dashboardId is required"}), 400

#     try:
#         access_token = get_superset_access_token()
#         if not access_token:
#             return jsonify({"error": "Superset auth failed"}), 500

#         response = requests.get(
#             f"{SUPERSET_URL}/api/v1/dashboard/{dashboard_id}/charts",
#             headers={"Authorization": f"Bearer {access_token}"},
#             timeout=15
#         )

#         charts     = response.json().get("result", [])
#         chart_list = []

#         print(f"DEBUG: All chart IDs on dashboard {dashboard_id}: {[c.get('id') for c in charts]}", flush=True)

#         # ── Fetch dashboard metadata for cross-filter scoping ────────
#         dashboard_meta_resp = requests.get(
#             f"{SUPERSET_URL}/api/v1/dashboard/{dashboard_id}",
#             headers={"Authorization": f"Bearer {access_token}"},
#             timeout=15
#         )
#         dashboard_meta = dashboard_meta_resp.json().get("result", {})
#         raw_json_meta  = dashboard_meta.get("json_metadata") or "{}"
#         try:
#             json_metadata = json.loads(raw_json_meta)
#         except Exception:
#             json_metadata = {}

#         print(f"DEBUG json_metadata keys: {list(json_metadata.keys())}", flush=True)
    

#         chart_configuration = json_metadata.get("chart_configuration", {})
        


#         position_json = dashboard_meta.get("position_json", "{}")
#         if isinstance(position_json, str):
#             try:
#                 position_json = json.loads(position_json)
#             except Exception:
#                 position_json = {}

#         #before sending the colour series to the frontend, we need to clean it up and only keep valid hex colors
#         # ── Superset's category → color assignments ──
#         raw_shared = json_metadata.get("shared_label_colors")
#         raw_label  = json_metadata.get("label_colors")

#         def _clean_label_colors(*sources):
#             out = {}
#             for raw in sources:
#                 if isinstance(raw, dict):
#                     for k, v in raw.items():
#                         if isinstance(v, str) and v.startswith("#"):
#                             out[str(k)] = v
#                 # if it's a list or anything else, skip it safely
#             return out

#         superset_label_colors = _clean_label_colors(raw_shared, raw_label)
#         print(f"DEBUG superset_label_colors = {superset_label_colors}", flush=True)
#         print(f"DEBUG color_scheme = {json_metadata.get('color_scheme')}", flush=True)   # ← ADD

#         # ── resolve_scope: converts scope object → list of chart IDs ─
#         def resolve_scope(scope_obj):
#             if not scope_obj or not isinstance(scope_obj, dict):
#                 return None
#             root_path = scope_obj.get("rootPath", [])
#             excluded  = [int(x) for x in scope_obj.get("excluded", [])]

#             # Empty rootPath = whole dashboard → scan ALL chart nodes
#             if not root_path:
#                 all_chart_ids = []
#                 for val in position_json.values():
#                     if isinstance(val, dict) and val.get("type") == "CHART":
#                         cid = val.get("meta", {}).get("chartId")
#                         if cid:
#                             all_chart_ids.append(int(cid))
#                 result = [cid for cid in all_chart_ids if cid not in excluded]
#                 print(f"DEBUG resolve_scope: rootPath=[] → scanned all → {result}", flush=True)
#                 return result

#             # Walk layout tree from each root node
#             def collect(node_id):
#                 found = []
#                 node  = position_json.get(node_id)
#                 if node is None:
#                     if node_id in ("ROOT_ID", "GRID_ID"):
#                         for val in position_json.values():
#                             if isinstance(val, dict) and val.get("type") == "CHART":
#                                 cid = val.get("meta", {}).get("chartId")
#                                 if cid:
#                                     found.append(int(cid))
#                     return found
#                 if node.get("type") == "CHART":
#                     cid = node.get("meta", {}).get("chartId")
#                     if cid:
#                         found.append(int(cid))
#                 for child_id in node.get("children", []):
#                     found.extend(collect(child_id))
#                 return found

#             in_scope = []
#             for root_node_id in root_path:
#                 in_scope.extend(collect(root_node_id))
#             in_scope = [cid for cid in set(in_scope) if cid not in excluded]
#             print(f"DEBUG resolve_scope: rootPath={root_path}, result={in_scope}", flush=True)
#             return in_scope

#         for chart in charts:
#             chart_id    = chart.get("id")
#             detail_resp = requests.get(
#                 f"{SUPERSET_URL}/api/v1/chart/{chart_id}",
#                 headers={"Authorization": f"Bearer {access_token}"},
#                 timeout=10
#             )
#             detail    = detail_resp.json().get("result", {})
#             form_data = detail.get("form_data", {})

#             # ── Step 1: fallback to params if form_data is empty ─────
#             if not form_data:
#                 params_raw = detail.get("params", "{}")
#                 try:
#                     form_data = json.loads(params_raw) if isinstance(params_raw, str) else (params_raw or {})
#                 except Exception:
#                     form_data = {}

#             # ── Step 2: merge params into form_data ──────────────────
#             try:
#                 params_raw = detail.get("params", "{}")
#                 params     = json.loads(params_raw) if isinstance(params_raw, str) else (params_raw or {})
#                 for k, v in params.items():
#                     if k not in form_data:
#                         form_data[k] = v
#             except Exception:
#                 pass

#             # ── Step 3: resolve viz_type ─────────────────────────────
#             viz_type = (
#                 form_data.get("viz_type")
#                 or detail.get("viz_type")
#                 or "echarts_timeseries_bar"
#             )


#             def _normalize_series_type(t):
#                 t = (t or "").lower()
#                 if t == "bar":
#                     return "bar"
#                 if t == "area":
#                     return "area"
#                 return "line"

#             series_types = None
#             if viz_type == "mixed_timeseries":
#                 left_raw  = form_data.get("seriesType")
#                 right_raw = form_data.get("seriesTypeB")
#                 print(f"DEBUG mixed chart {chart_id} raw seriesType/B: {left_raw!r} / {right_raw!r}", flush=True)
#                 series_types = [
#                     _normalize_series_type(left_raw),
#                     _normalize_series_type(right_raw),
#                 ]

#             # ── Step 4: pie threshold debug ──────────────────────────
#             if viz_type == "pie":
#                 print(f"DEBUG pie {chart_id} ALL keys: {list(form_data.keys())}", flush=True)
#                 for k, v in form_data.items():
#                     if "other" in k.lower() or "threshold" in k.lower():
#                         print(f"DEBUG pie {chart_id} threshold key: {k} = {v}", flush=True)

#             # ── Step 5: extract threshold values ─────────────────────
#             percentage_threshold = (
#                 form_data.get("show_labels_threshold")
#                 or form_data.get("percentage_threshold")
#                 or 0
#             ) or 0

#             other_threshold = (
#                 form_data.get("threshold_for_other")
#                 or form_data.get("other_threshold")
#                 or 0
#             ) or 0

#             print(f"DEBUG pie {chart_id}: percentage_threshold={percentage_threshold} other_threshold={other_threshold}", flush=True)
#             print(f"DEBUG chart {chart_id}: percentage_threshold={percentage_threshold} other_threshold={other_threshold}", flush=True)

#             # ── Debug for timeseries/line charts ─────────────────────
#             if 'timeseries' in viz_type.lower() or 'line' in viz_type.lower():
#                 print(f"DEBUG chart {chart_id} form_data keys: {list(form_data.keys())}", flush=True)
#                 print(f"DEBUG chart {chart_id} groupby raw: {form_data.get('groupby')}", flush=True)
#                 print(f"DEBUG chart {chart_id} metrics raw: {form_data.get('metrics', [])[:3]}", flush=True)

#             # ── Helper: extract plain string ──────────────────────────
#             def _extract_col_string(raw):
#                 if not raw:
#                     return ""
#                 if isinstance(raw, str):
#                     return raw.strip()
#                 if isinstance(raw, dict):
#                     return (
#                         raw.get("column_name") or
#                         raw.get("label")       or
#                         raw.get("name")        or
#                         ""
#                     ).strip()
#                 return ""

#             # ── Helper: extract list of plain strings from groupby ───
#             def _col_names(lst):
#                 if isinstance(lst, str):
#                     return [lst] if lst else []
#                 out = []
#                 for item in (lst or []):
#                     if isinstance(item, str):
#                         out.append(item)
#                     elif isinstance(item, dict):
#                         name = (
#                             item.get("column_name")
#                             or item.get("label")
#                             or item.get("name")
#                             or item.get("sqlExpression")
#                             or ""
#                         )
#                         if name:
#                             out.append(name)
#                 return [x for x in out if x]

#             # ── x_axis ────────────────────────────────────────────────
#             x_axis_raw = (
#                 form_data.get("x_axis")
#                 or form_data.get("granularity_sqla")
#                 or ""
#             )
#             x_axis = _extract_col_string(x_axis_raw)

#             if not x_axis:
#                 gb_list = form_data.get("groupby") or []
#                 if gb_list:
#                     x_axis = _extract_col_string(gb_list[0])

#             # ── metrics ───────────────────────────────────────────────
#             metrics_primary   = form_data.get("metrics",   [])
#             metrics_secondary = form_data.get("metrics_b", [])
#             metrics = metrics_primary + (metrics_secondary if metrics_secondary else [])

#             # ── groupby ───────────────────────────────────────────────
#             groupby_raw = (
#                 form_data.get("groupby")
#                 or form_data.get("series_columns")
#                 or form_data.get("dimensions")
#                 or form_data.get("breakdown")
#                 or []
#             )
#             groupby = _col_names(groupby_raw)

#             groupby_rows_raw = (
#                 form_data.get("groupbyRows")
#                 or form_data.get("groupby_rows")
#                 or []
#             )
#             groupby_cols_raw = (
#                 form_data.get("groupbyColumns")
#                 or form_data.get("groupby_cols")
#                 or form_data.get("columns")
#                 or []
#             )

#             groupby_rows = _col_names(groupby_rows_raw)
#             groupby_cols = _col_names(groupby_cols_raw)

#             conditional_formatting = []
#             is_table = viz_type and ("table" in viz_type.lower() or "pivot" in viz_type.lower())
#             column_order = []
#             if is_table:
#                 col_config = form_data.get("column_config") or {}
#                 if isinstance(col_config, dict) and col_config:
#                     column_order = sorted(col_config.keys(),
#                                           key=lambda k: col_config[k].get("index", 999))

#             if is_table:
#                 raw_cf = (
#                     form_data.get("conditional_formatting")
#                     or form_data.get("conditionalFormatting")
#                     or []
#                 )
#                 for rule in (raw_cf or []):
#                     if not isinstance(rule, dict):
#                         continue
#                     col      = rule.get("column") or rule.get("col") or ""
#                     operator = rule.get("operator") or rule.get("op") or ""
#                     target   = rule.get("targetValue")
#                     if target is None:
#                         target = rule.get("target_value")
#                     raw_color = (
#                         rule.get("colorScheme")
#                         or rule.get("color")
#                         or (rule.get("colorScheme", {}) or {}).get("value")
#                         or (rule.get("style", {}) or {}).get("color")
#                     )
#                     color = resolve_color_scheme(raw_color)
#                     if color and col and operator:
#                         conditional_formatting.append({
#                             "column":   col,
#                             "operator": operator,
#                             "value":    float(target) if target is not None else None,
#                             "color":    color,
#                         })

#             print(f"DEBUG chart {chart_id}: conditional_formatting rules = {conditional_formatting}", flush=True)

#             # ── show_cell_bars ────────────────────────────────────────
#             show_cell_bars = bool(form_data.get("show_cell_bars", False)) if is_table else False
#             print(f"DEBUG chart {chart_id}: show_cell_bars = {show_cell_bars}", flush=True)

#             # ── raw_x_axis_column ─────────────────────────────────────
#             raw_x_axis_column = _extract_col_string(
#                 form_data.get("x_axis") or form_data.get("granularity_sqla") or ""
#             )

#             x_axis_is_temporal = bool(
#                 form_data.get("granularity_sqla")
#                 or (raw_x_axis_column and any(
#                     k in raw_x_axis_column.lower()
#                     for k in ["date", "time", "month", "day", "year", "period"]
#                 ))
#             )

#             print(
#                 f"DEBUG chart {chart_id}: viz={viz_type!r} x_axis={x_axis!r} "
#                 f"groupby={groupby} "
#                 f"groupby_rows={groupby_rows} groupby_cols={groupby_cols} "
#                 f"metrics=[{[m if isinstance(m, str) else m.get('label', '?') for m in metrics[:3]]}]",
#                 flush=True,
#             )

#             # ── BigNum conditional colors ─────────────────────────────
#             font_color         = None
#             conditional_colors = []

#             if viz_type and "big_number" in viz_type.lower():

#                 COLOR_SCHEME_MAP = {
#                     "success":           "#22c55e",
#                     "alert":             "#fbbf24",
#                     "error":             "#f87171",
#                     "colorsuccessbg":    "#22c55e",
#                     "colorwarningbg":    "#fbbf24",
#                     "colorerrorbg":      "#f87171",
#                     "successbg":         "#22c55e",
#                     "warningbg":         "#fbbf24",
#                     "errorbg":           "#f87171",
#                     "green":             "#22c55e",
#                     "yellow":            "#fbbf24",
#                     "red":               "#f87171",
#                     "orange":            "#f97316",
#                     "blue":              "#3b82f6",
#                     "purple":            "#a855f7",
#                     "primary":           "#1FA8C9",
#                     "secondary":         "#454E7C",
#                     "danger":            "#f87171",
#                     "warning":           "#fbbf24",
#                     "info":              "#1FA8C9",
#                 }

#                 def resolve_color(raw_color):
#                     if not raw_color:
#                         return None
#                     s = str(raw_color).strip()
#                     if s.startswith("#") and len(s) in [4, 7, 9]:
#                         return s
#                     if s.startswith("rgb("):
#                         try:
#                             parts = s.replace("rgb(", "").replace(")", "").split(",")
#                             r, g, b = [int(p.strip()) for p in parts]
#                             return f"#{r:02x}{g:02x}{b:02x}"
#                         except Exception:
#                             pass
#                     if s.startswith("rgba("):
#                         try:
#                             parts = s.replace("rgba(", "").replace(")", "").split(",")
#                             r, g, b = [int(p.strip()) for p in parts[:3]]
#                             return f"#{r:02x}{g:02x}{b:02x}"
#                         except Exception:
#                             pass
#                     return COLOR_SCHEME_MAP.get(s.lower(), None)

#                 # conditional_formatting = (
#                 #     form_data.get("conditional_formatting") or
#                 #     form_data.get("conditionalFormatting") or
#                 #     form_data.get("color_config")          or
#                 #     []
#                 # )

#                 # for rule in (conditional_formatting or []):
#                 #     if not isinstance(rule, dict):
#                 #         continue
#                 #     operator = rule.get("operator", "") or rule.get("op", "")
#                 #     target   = rule.get("targetValue", rule.get("target_value", 0))
#                 #     if not operator or operator in ("None", "none", ""):
#                 #         continue
#                 #     raw_color = (
#                 #         rule.get("colorScheme")              or
#                 #         rule.get("color")                    or
#                 #         rule.get("fontColor")                or
#                 #         rule.get("font_color")               or
#                 #         rule.get("textColor")                or
#                 #         (rule.get("colorScheme", {}) or {}).get("value") or
#                 #         (rule.get("style", {}) or {}).get("color") or
#                 #         None
#                 #     )
#                 #     color = resolve_color(raw_color)
#                 #     if color:
#                 #         conditional_colors.append({
#                 #             "operator":    operator,
#                 #             "targetValue": target,
#                 #             "color":       color,
#                 #         })

#                 # if not conditional_colors:
#                 #     direct_color = (
#                 #         form_data.get("font_color")   or
#                 #         form_data.get("fontColor")    or
#                 #         form_data.get("color")        or
#                 #         None
#                 #     )
#                 #     if direct_color:
#                 #         font_color = resolve_color(direct_color)


#                 conditional_formatting = (
#                     form_data.get("conditional_formatting") or
#                     form_data.get("conditionalFormatting") or
#                     form_data.get("color_config")          or
#                     []
#                 )

#                 # ── DEBUG: log RAW rules before any filtering/resolving ──
#                 print(f"DEBUG bignum {chart_id} RAW conditional_formatting = {conditional_formatting}", flush=True)
#                 for _r in (conditional_formatting or []):
#                     if isinstance(_r, dict):
#                         print(
#                             f"DEBUG bignum {chart_id} RAW rule: "
#                             f"operator={_r.get('operator')!r} "
#                             f"targetValue={_r.get('targetValue')!r} "
#                             f"targetValueLeft={_r.get('targetValueLeft')!r} "
#                             f"targetValueRight={_r.get('targetValueRight')!r} "
#                             f"colorScheme={_r.get('colorScheme')!r} "
#                             f"column={_r.get('column')!r}",
#                             flush=True,
#                         )

#                 for rule in (conditional_formatting or []):
#                     if not isinstance(rule, dict):
#                         continue
#                     operator = rule.get("operator", "") or rule.get("op", "")
#                     target   = rule.get("targetValue", rule.get("target_value", 0))
#                     target_left  = rule.get("targetValueLeft")
#                     target_right = rule.get("targetValueRight")
#                     if not operator or operator in ("None", "none", ""):
#                         continue
#                     raw_color = (
#                         rule.get("colorScheme")              or
#                         rule.get("color")                    or
#                         rule.get("fontColor")                or
#                         rule.get("font_color")               or
#                         rule.get("textColor")                or
#                         (rule.get("colorScheme", {}) or {}).get("value") or
#                         (rule.get("style", {}) or {}).get("color") or
#                         None
#                     )
#                     color = resolve_color(raw_color)
#                     # ── If a token didn't resolve, log it so we can extend the map ──
#                     if not color:
#                         print(f"DEBUG bignum {chart_id}: UNRESOLVED colorScheme={raw_color!r} (rule dropped)", flush=True)
#                         continue
#                     conditional_colors.append({
#                         "operator":         operator,
#                         "targetValue":      target,
#                         "targetValueLeft":  target_left,
#                         "targetValueRight": target_right,
#                         "color":            color,
#                     })

#                 # ── Default font color: ONLY from a real default field, NEVER from rule[0] ──
#                 direct_color = (
#                     form_data.get("font_color") or
#                     form_data.get("fontColor")  or
#                     form_data.get("color")      or
#                     None
#                 )
#                 if direct_color:
#                     font_color = resolve_color(direct_color)
#                 # NOTE: deliberately NOT setting font_color = conditional_colors[0]["color"]
#                 #       That was leaking the first rule's color when no rule matched.

#                 print(
#                     f"DEBUG bignum {chart_id}: "
#                     f"conditional_colors={conditional_colors} "
#                     f"font_color={font_color}",
#                     flush=True
#                 )
#                 # if conditional_colors:
#                 #     font_color = conditional_colors[0]["color"]

#                 print(
#                     f"DEBUG bignum {chart_id}: "
#                     f"conditional_colors={conditional_colors} "
#                     f"font_color={font_color}",
#                     flush=True
#                 )

#             # ── Cross-filter scoping ──────────────────────────────────
#             chart_cfg       = chart_configuration.get(str(chart_id), {})
#             cf_scope_obj    = chart_cfg.get("crossFilters", {}).get("scope")
#             charts_in_scope = None

#             if cf_scope_obj is not None:
#                 if cf_scope_obj == "global":
#                     # Use global_chart_configuration scope
#                     global_cfg  = json_metadata.get("global_chart_configuration", {})
#                     global_scope = global_cfg.get("scope") if global_cfg else None
#                     if global_scope:
#                         resolved = resolve_scope(global_scope)
#                         if resolved is not None:
#                             charts_in_scope = [cid for cid in resolved if cid != chart_id]
#                     else:
#                         charts_in_scope = []
#                 else:
#                     # Explicit scope object
#                     resolved = resolve_scope(cf_scope_obj)
#                     if resolved is not None:
#                         charts_in_scope = [cid for cid in resolved if cid != chart_id]
#                     else:
#                         charts_in_scope = []

#             print(f"DEBUG chart {chart_id}: chartsInScope = {charts_in_scope}", flush=True)
#             print(f"DEBUG chart {chart_id}: cross_filter_scope = {charts_in_scope}", flush=True)
#             print(f"DEBUG chart {chart_id}: cross_filter chartsInScope = {charts_in_scope}", flush=True)

#             # ── Append to chart list ──────────────────────────────────
#             chart_list.append({
#                 "slice_id":               chart_id,
#                 "slice_name":             detail.get("slice_name"),
#                 "viz_type":               viz_type,
#                 "x_axis":                 x_axis,
#                 "metrics":                metrics,
#                 "groupby":                groupby,
#                 "groupby_rows":           groupby_rows,
#                 "groupby_cols":           groupby_cols,
#                 "raw_x_axis_column":      raw_x_axis_column,
#                 "x_axis_is_temporal":     x_axis_is_temporal,
#                 "zoomable":               bool(form_data.get("zoomable", False)),
#                 "font_color":             font_color,
#                 "conditional_colors":     conditional_colors,
#                 "conditional_formatting": conditional_formatting,
#                 "column_order":           column_order,
#                 "show_cell_bars":         show_cell_bars,
#                 "cross_filter_scope":     charts_in_scope,
#                 "percentage_threshold":   percentage_threshold,
#                 "other_threshold":        other_threshold,
#                 "series_colors": superset_label_colors,
#                 "series_types":           series_types,
#             })

#             print(f"DEBUG chart {chart_id}: zoomable = {form_data.get('zoomable')} | viz = {viz_type}", flush=True)

#             if 'bar' in viz_type.lower():
#                 print(f"DEBUG chart {chart_id} bar form_data keys: {list(form_data.keys())}", flush=True)

#         return jsonify({"success": True, "charts": chart_list}), 200

#     except Exception as e:
#         print(f"DEBUG: get_dashboard_charts error: {e}", flush=True)
#         return jsonify({"error": str(e)}), 500
    
# # ---------------------------------------------------------
# # GET ALL CHARTS FOR A DASHBOARD
# # ---------------------------------------------------------

# @app.route("/api/chart-data", methods=["POST"])
# @login_required
# def get_chart_data():
#     body           = request.get_json(force=True, silent=True) or {}
#     slice_id       = body.get("sliceId")
#     date_from      = body.get("dateFrom")   # "2026-01-01" or None
#     date_to        = body.get("dateTo")     # "2026-03-31" or None
#     time_filter_id = body.get("timeFilterId")
#     active_filters = body.get("activeFilters", [])
#     cross_filters  = body.get("crossFilters",  [])

#     print(f"🗓 INCOMING: sliceId={slice_id} dateFrom={date_from} dateTo={date_to} timeFilterId={time_filter_id}", flush=True)
    
#     VALID_OPS = {
#         "IN", "NOT IN", "==", "!=", ">", "<", ">=", "<=",
#         "LIKE", "ILIKE", "IS NULL", "IS NOT NULL", "TEMPORAL_RANGE",
#     }

#     def normalise_filter(f):
#         col = str(f.get("col", "")).strip()
#         op  = str(f.get("op", "IN")).upper().strip()
#         val = f.get("val")
#         if not col: return None
#         if op not in VALID_OPS: op = "IN"
#         if not isinstance(val, list): val = [val]

#         # ── Fix double-wrapped arrays: [['GORAI BRANCH']] → ['GORAI BRANCH'] ──
#         flat = []
#         for v in val:
#             if isinstance(v, list):
#                 flat.extend(v)
#             else:
#                 flat.append(v)
#         val = flat

#         val = [v for v in val if v is not None and v != ""]
#         if not val and op not in ("IS NULL", "IS NOT NULL"): return None
#         return {"col": col, "op": op, "val": val}

#     def resolve_col(col, query):
#         import re as _re

#         candidates = set()
#         for c in query.get("columns", []):
#             if isinstance(c, str):
#                 candidates.add(c)
#             elif isinstance(c, dict):
#                 name = (
#                     c.get("column_name") or
#                     c.get("label") or
#                     c.get("sqlExpression") or ""
#                 )
#                 if name:
#                     candidates.add(name)
#         for f in query.get("filters", []):
#             if f.get("col"):
#                 candidates.add(f["col"])

#         if col in candidates:
#             return col

#         col_lower = col.lower()
#         for candidate in candidates:
#             if candidate.lower() == col_lower:
#                 print(f"DEBUG: Resolved column '{col}' → '{candidate}' (case-insensitive match)", flush=True)
#                 return candidate

#         IS_COLUMN_NAME = _re.compile(r'^\w+$')

#         if not IS_COLUMN_NAME.match(col):
#             already_filtered = {
#                 f.get("col", "").lower()
#                 for f in query.get("filters", [])
#                 if f.get("col")
#             }
#             DATE_KEY_PATTERN = _re.compile(
#                 r'date|time|key|offset|full|month', _re.IGNORECASE
#             )
#             spare_dims = [
#                 c for c in candidates
#                 if not DATE_KEY_PATTERN.search(c)
#                 and c.lower() not in already_filtered
#             ]
#             if len(spare_dims) == 1:
#                 print(
#                     f"DEBUG: Mapping series value '{col}' → dimension col "
#                     f"'{spare_dims[0]}' (smart fallback). Available: {candidates}",
#                     flush=True
#                 )
#                 return spare_dims[0]

#         has_inner_uppercase = any(c.isupper() for c in col[1:]) if len(col) > 1 else False

#         if has_inner_uppercase:
#             print(
#                 f"DEBUG: No match for '{col}' (camelCase). "
#                 f"Available: {candidates}. Returning original.",
#                 flush=True
#             )
#             return col
#         # else:
#         #     print(
#         #         f"DEBUG: No match for '{col}' (title/lower). "
#         #         f"Available: {candidates}. Returning lowercase.",
#         #         flush=True
#         #     )
#         #     return col_lower
#         else:
#             print(
#                 f"DEBUG: No match for '{col}' (not in query columns). "
#                 f"Available: {candidates}. Keeping original case for extra_form_data.",
#                 flush=True
#             )
#             return col  # ← keep original case, don't lowercase

#     def merge_query_results(all_results):
#         def find_dim_col(rows_sample):
#             if not rows_sample:
#                 return None
#             for k, v in rows_sample[0].items():
#                 try:
#                     float(v)
#                 except (TypeError, ValueError):
#                     return k
#             return list(rows_sample[0].keys())[0]

#         merged    = {}
#         dim_col   = None
#         col_order = []

#         for query_rows in all_results:
#             if not query_rows:
#                 continue
#             qd = find_dim_col(query_rows)
#             if dim_col is None:
#                 dim_col = qd
#                 col_order.append(dim_col)
#             for row in query_rows:
#                 dim_val = row.get(dim_col) or row.get(qd)
#                 key     = str(dim_val)
#                 if key not in merged:
#                     merged[key] = {dim_col: dim_val}
#                 for col, val in row.items():
#                     if col == dim_col or col == qd:
#                         continue
#                     merged[key][col] = val
#                     if col not in col_order:
#                         col_order.append(col)

#         rows = list(merged.values())
#         return rows, col_order

#     # ── Detect temporal date column from query ────────────────
#     def detect_temporal_col(query):
#         """
#         Find the date column from the query's existing TEMPORAL_RANGE filter,
#         or fall back to common date column name patterns.
#         """
#         DATE_PATTERN = __import__("re").compile(
#             r'date|time|month|day|year|period|sale_dt|invoice_dt|regd',
#             __import__("re").IGNORECASE
#         )

#         # 1. Check existing TEMPORAL_RANGE filters — only trust it if col looks temporal
#         for f in query.get("filters", []):
#             if f.get("op") == "TEMPORAL_RANGE" and f.get("col"):
#                 col = f["col"]
#                 if DATE_PATTERN.search(col) or col == "__time":
#                     return col

#         # 2. Check adhoc_filters for temporal range
#         for f in query.get("adhoc_filters", []):
#             if f.get("operator") == "TEMPORAL_RANGE" and f.get("subject"):
#                 return f["subject"]

#         # 3. Look through columns for date-like names
#         DATE_PATTERN = __import__("re").compile(
#             r'date|time|month|day|year|period|sale_dt|invoice_dt',
#             __import__("re").IGNORECASE
#         )
#         for c in query.get("columns", []):
#             name = c if isinstance(c, str) else (c.get("column_name") or "")
#             if name and DATE_PATTERN.search(name):
#                 return name

#         return None

#     incoming_filters = []
#     for f in (active_filters + cross_filters):
#         nf = normalise_filter(f)
#         if nf:
#             incoming_filters.append(nf)

#     print(f"DEBUG chart {slice_id}: incoming_filters = {incoming_filters}", flush=True)

#     try:
#         access_token = get_superset_access_token()
#         chart_resp   = requests.get(
#             f"{SUPERSET_URL}/api/v1/chart/{slice_id}",
#             headers={"Authorization": f"Bearer {access_token}"},
#             timeout=10
#         )
#         chart_result = chart_resp.json().get("result", {})
#         raw_context  = chart_result.get("query_context")

#         if not raw_context:
#             params = {}
#             try:
#                 params = json.loads(chart_result.get("params", "{}"))
#             except Exception:
#                 pass

#             datasource_id   = chart_result.get("datasource_id")
#             datasource_type = chart_result.get("datasource_type", "table")

#             if not datasource_id:
#                 return jsonify({"success": True, "data": [], "reason": "No datasource"}), 200

#             all_metrics  = params.get("metrics", [])
#             time_col     = params.get("x_axis") or params.get("granularity_sqla") or ""
#             groupby_cols = params.get("groupby", [])
#             time_range   = params.get("time_range", "No filter")
#             time_grain   = params.get("time_grain_sqla", "P1M")

#             all_columns = []
#             if time_col:
#                 all_columns.append(time_col)
#             for col in groupby_cols:
#                 if col and col not in all_columns:
#                     all_columns.append(col)

#             query_context = {
#                 "datasource": {"id": datasource_id, "type": datasource_type},
#                 "force": False,
#                 "queries": [{
#                     "filters": [],
#                     "extras": {"having": "", "where": "", "time_grain_sqla": time_grain},
#                     "applied_time_extras": {},
#                     "columns":    all_columns,
#                     "metrics":    all_metrics,
#                     "orderby":    [],
#                     "time_range": time_range,
#                     "row_limit":  params.get("row_limit", 10000),
#                     "annotation_layers": [],
#                 }],
#                 "result_format": "json",
#                 "result_type":   "results"
#             }
#         else:
#             query_context = json.loads(raw_context)

#         for q in query_context.get("queries", []):
#             q["row_limit"] = max(q.get("row_limit", 0) or 0, 100000)    

#         # ── Apply filters to every query ──────────────────────
#         for query in query_context.get("queries", []):
            
#             # ── 1. Active + cross filters ─────────────────────
#             if incoming_filters:
#                 resolved_filters = []
#                 for f in incoming_filters:
#                     resolved_col = resolve_col(f["col"], query)
#                     resolved_filters.append({**f, "col": resolved_col})

#                 merged = {}
#                 for f in resolved_filters:
#                     key = (f["col"], f["op"])
#                     if f["op"] == "IN" and key in merged:
#                         existing_vals = merged[key]["val"] if isinstance(merged[key]["val"], list) else [merged[key]["val"]]
#                         new_vals      = f["val"] if isinstance(f["val"], list) else [f["val"]]
#                         merged[key]["val"] = list(dict.fromkeys(existing_vals + new_vals))
#                     else:
#                         merged[key] = dict(f)
#                 resolved_filters = list(merged.values())

#                 print(f"DEBUG chart {slice_id}: resolved_filters after merge = {resolved_filters}", flush=True)

#                 override_cols = {f["col"] for f in resolved_filters}
#                 existing = [
#                     f for f in query.get("filters", [])
#                     if f.get("col") not in override_cols
#                 ]
#                 query["filters"]       = existing + resolved_filters
#                 query_context["force"] = True

#                 for f in resolved_filters:
#                     col  = f["col"]
#                     op   = f.get("op", "IN")
#                     vals = f["val"] if isinstance(f["val"], list) else [f["val"]]

#                     if op == "IN" and vals:
#                         query.setdefault("adhoc_filters", []).append({
#                             "expressionType":   "SIMPLE",
#                             "subject":          col,
#                             "operator":         "IN",
#                             "comparator":       vals,
#                             "clause":           "WHERE",
#                             "filterOptionName": f"cross_filter_{col.replace(' ','_')}",
#                             "isExtra":          True,
#                         })

#                     # ── Also inject via extra_form_data.filters ──────
#                     # This is how Superset natively applies cross-filters
#                     if op == "IN" and vals:
#                         extra_form_data = query_context.get("form_data", {})
#                         if extra_form_data is None:
#                             extra_form_data = {}
#                             query_context["form_data"] = extra_form_data

#                         ef = extra_form_data.setdefault("extra_form_data", {})
#                         ef_filters = ef.setdefault("filters", [])

#                         # Remove any existing filter for same col to avoid duplicates
#                         ef_filters[:] = [
#                             x for x in ef_filters
#                             if x.get("col") != col
#                         ]
#                         ef_filters.append({
#                             "col": col,
#                             "op":  "IN",
#                             "val": vals,
#                         })

#                         print(
#                             f"DEBUG chart {slice_id}: extra_form_data filter injected "
#                             f"→ col={col} val={vals}",
#                             flush=True
#                         )    

#                 print(
#                     f"DEBUG chart {slice_id}: adhoc_filters = "
#                     f"{query.get('adhoc_filters', [])}",
#                     flush=True
#                 )

#                 # ── Inject into extra_form_data.filters (Superset native format) ──
#                 for f in resolved_filters:
#                     col  = f["col"]
#                     op   = f.get("op", "IN")
#                     vals = f["val"] if isinstance(f["val"], list) else [f["val"]]
#                     if op == "IN" and vals:
#                         form_data = query_context.setdefault("form_data", {})
#                         ef        = form_data.setdefault("extra_form_data", {})
#                         ef_filters = ef.setdefault("filters", [])
#                         # Remove existing filter for same col to avoid duplicates
#                         ef_filters[:] = [x for x in ef_filters if x.get("col") != col]
#                         ef_filters.append({"col": col, "op": "IN", "val": vals})
#                         print(
#                             f"DEBUG chart {slice_id}: extra_form_data filter → "
#                             f"col={col} val={vals}",
#                             flush=True
#                         )

#                     # ── 2. Date range filter — outside the for loop ──
#             if date_from and date_to and time_filter_id:
#                 from datetime import datetime, timedelta
#                 d_from = datetime.strptime(date_from, "%Y-%m-%d")
#                 d_to   = datetime.strptime(date_to,   "%Y-%m-%d") + timedelta(days=1)
#                 date_range_val = f"{d_from.strftime('%Y-%m-%d')} : {d_to.strftime('%Y-%m-%d')}"
#                 # date_range_val = f"{date_from} : {date_to}"

#                 for query in query_context.get("queries", []):
#                     # Find existing TEMPORAL_RANGE filter and update it
#                     updated = False
#                     for f in query.get("filters", []):
#                         if f.get("op") == "TEMPORAL_RANGE":
#                             f["val"] = date_range_val
#                             updated = True
#                             break
#                     # If no existing TEMPORAL_RANGE filter, detect column and add one
#                     if not updated:
#                         temporal_col = detect_temporal_col(query)
#                         if temporal_col:
#                             query.setdefault("filters", []).append({
#                                 "col": temporal_col,
#                                 "op":  "TEMPORAL_RANGE",
#                                 "val": date_range_val,
#                             })
#                     query["applied_time_extras"] = {}
#                     query_context["force"] = True

#                 print(f"DEBUG: date range applied → {date_range_val}", flush=True)
#                 print(
#                     f"DEBUG chart {slice_id}: native date filter applied → "
#                     f"id={time_filter_id} value={d_from.strftime('%Y-%m-%d')} : {d_to.strftime('%Y-%m-%d')}",
#                     # f"id={time_filter_id} value={date_range_val}",
#                     flush=True
#                 )


#         data_resp = requests.post(
#             f"{SUPERSET_URL}/api/v1/chart/data",
#             headers={
#                 "Authorization": f"Bearer {access_token}",
#                 "Content-Type":  "application/json"
#             },
#             json=query_context,
#             timeout=30
#         )

#         print(f"DEBUG chart {slice_id}: Superset response status = {data_resp.status_code}", flush=True)

#         result      = data_resp.json()
#         all_results = result.get("result", [])

#         if not all_results:
#             rows     = []
#             colnames = []
#             coltypes = []

#         elif len(all_results) == 1:
#             first_result = all_results[0]
#             rows     = first_result.get("data",     [])
#             colnames = first_result.get("colnames") or (list(rows[0].keys()) if rows else [])
#             coltypes = first_result.get("coltypes", [])

#         else:
#             viz = (query_context.get("form_data", {}) or {}).get("viz_type", "")
#             is_table_viz = "table" in str(viz).lower() or "pivot" in str(viz).lower()

#             if is_table_viz:
#                 best     = max(all_results, key=lambda r: len(r.get("data", [])))
#                 rows     = best.get("data", [])
#                 colnames = best.get("colnames") or (list(rows[0].keys()) if rows else [])
#                 coltypes = best.get("coltypes", [])

#                 # Check other queries for summary/totals row (1 row = totals)
#                 summary_row = None
#                 for r in all_results:
#                     if r is best:
#                         continue
#                     r_data = r.get("data", [])
#                     if len(r_data) == 1:
#                         summary_row = r_data[0]
#                         break

#                 if summary_row:
#                     rows = list(rows) + [{"__summary__": True, **summary_row}]
#                     print(f"DEBUG chart {slice_id}: summary row added → {summary_row}", flush=True)

#                 print(f"DEBUG chart {slice_id}: table chart — using best of {len(all_results)} queries → {len(rows)} rows", flush=True)

#             else:
#                 print(f"DEBUG chart {slice_id}: mixed chart with {len(all_results)} queries — merging", flush=True)
#                 all_data_lists = [r.get("data", []) for r in all_results]
#                 rows, colnames = merge_query_results(all_data_lists)
#                 coltypes = []   # ← this was missing, causing the error

#         print(f"DEBUG chart {slice_id}: rows returned = {len(rows)}", flush=True)

#         return jsonify({
#             "success":  True,
#             "data":     rows,
#             "colnames": colnames,
#             "coltypes": coltypes,
#         }), 200

#     except Exception as e:
#         print(f"DEBUG chart {slice_id} ERROR: {e}", flush=True)
#         import traceback
#         traceback.print_exc()
#         return jsonify({"error": str(e)}), 500

# # ---------------------------------------------------------
# # GET FILTER OPTIONS
# # ---------------------------------------------------------

# @app.route("/api/filter-options", methods=["GET"])
# @login_required
# def get_filter_options():
#     dashboard_id = request.args.get("dashboardId")
#     if not dashboard_id:
#         return jsonify({"error": "dashboardId required"}), 400

#     try:
#         access_token = get_superset_access_token()

#         resp = requests.get(
#             f"{SUPERSET_URL}/api/v1/dashboard/{dashboard_id}",
#             headers={"Authorization": f"Bearer {access_token}"},
#             timeout=10
#         )
#         result        = resp.json().get("result", {})
#         json_metadata = result.get("json_metadata", "{}")
#         if isinstance(json_metadata, str):
#             json_metadata = json.loads(json_metadata)

#         native_filters = json_metadata.get("native_filter_configuration", [])

#         def get_distinct_values(dataset_id, column_name):
#             payload = {
#                 "datasource": {"id": dataset_id, "type": "table"},
#                 "force": False,
#                 "queries": [{
#                     "columns":   [column_name],
#                     "metrics":   [],
#                     "filters":   [],
#                     "orderby":   [[column_name, True]],
#                     "row_limit": 500,
#                     "extras":    {"having": "", "where": ""},
#                     "applied_time_extras": {}
#                 }],
#                 "result_format": "json",
#                 "result_type":   "results"
#             }
#             r    = requests.post(
#                 f"{SUPERSET_URL}/api/v1/chart/data",
#                 headers={
#                     "Authorization": f"Bearer {access_token}",
#                     "Content-Type":  "application/json"
#                 },
#                 json=payload,
#                 timeout=15
#             )
#             rows = r.json().get("result", [{}])[0].get("data", [])
#             return [row[column_name] for row in rows if row.get(column_name)]

#         filter_options = []

#         for native_filter in native_filters:
#             filter_type = native_filter.get("filterType")
#             target      = native_filter.get("targets", [{}])[0]
#             col_name    = target.get("column", {}).get("name")
#             dataset_id  = target.get("datasetId")

#             scope_obj     = native_filter.get("scope", {})
#             root_path     = scope_obj.get("rootPath", ["ROOT_ID"])
#             tabs_in_scope = native_filter.get("tabsInScope") or []
#             if not tabs_in_scope:
#                 tabs_in_scope = [p for p in root_path if p.startswith("TAB-")]

#             print(
#                 f"DEBUG filter '{native_filter.get('name')}': "
#                 f"scope={scope_obj}, tabs_in_scope={tabs_in_scope}, "
#                 f"charts_in_scope={native_filter.get('chartsInScope', [])}",
#                 flush=True
#             )

#             if filter_type == "filter_time":
#                 filter_options.append({
#                     "id":            native_filter.get("id"),
#                     "name":          native_filter.get("name"),
#                     "filterType":    "filter_time",
#                     "type":          "date",
#                     "column":        col_name or "",
#                     "values":        [],
#                     "tabsInScope":   tabs_in_scope,
#                     "chartsInScope": native_filter.get("chartsInScope", []),
#                 })

#             elif filter_type in ["filter_select", "filter_groupby"]:
#                 if not col_name or not dataset_id:
#                     continue
#                 values = get_distinct_values(dataset_id, col_name)
#                 filter_options.append({
#                     "id":            native_filter.get("id"),
#                     "name":          native_filter.get("name"),
#                     "type":          "select",
#                     "column":        col_name,
#                     "values":        values,
#                     "tabsInScope":   tabs_in_scope,
#                     "chartsInScope": native_filter.get("chartsInScope", []),
#                 })

#         print(f"DEBUG filter_options: {filter_options}", flush=True)
#         return jsonify({"success": True, "filters": filter_options}), 200

#     except Exception as e:
#         print(f"DEBUG filter_options error: {e}", flush=True)
#         return jsonify({"error": str(e)}), 500


# # ---------------------------------------------------------
# # UPLOAD ACCESS CHECK
# # ---------------------------------------------------------
# @app.route("/api/upload_access", methods=["GET"])
# @login_required
# def check_user_upload_access():
#     tenant_schema = session.get("tenant_schema")
#     if not tenant_schema:
#         return jsonify({"error": "No tenant context"}), 403

#     upload_access = session.get("upload_access", 0)
#     if upload_access == 1:
#         return jsonify({"success": True}), 200
#     else:
#         return jsonify({"success": False, "error": "You do not have upload access."}), 403


# # ---------------------------------------------------------
# # DASHBOARD FILTERS
# # ---------------------------------------------------------
# @app.route("/api/dashboard-filters", methods=["GET"])
# @login_required
# def get_dashboard_filters():
#     dashboard_id = request.args.get("dashboardId")
#     try:
#         access_token = get_superset_access_token()
#         resp         = requests.get(
#             f"{SUPERSET_URL}/api/v1/dashboard/{dashboard_id}",
#             headers={"Authorization": f"Bearer {access_token}"},
#             timeout=10
#         )
#         result        = resp.json().get("result", {})
#         json_metadata = result.get("json_metadata", "{}")
#         if isinstance(json_metadata, str):
#             json_metadata = json.loads(json_metadata)

#         native_filters = json_metadata.get("native_filter_configuration", [])
#         filters_out    = []

#         for f in native_filters:
#             target = f.get("targets", [{}])[0]
#             filters_out.append({
#                 "id":         f.get("id"),
#                 "name":       f.get("name"),
#                 "filterType": f.get("filterType"),
#                 "column":     target.get("column", {}).get("name"),
#                 "datasetId":  target.get("datasetId"),
#             })

#         return jsonify({"success": True, "filters": filters_out}), 200

#     except Exception as e:
#         print(f"DEBUG dashboard-filters error: {e}", flush=True)
#         return jsonify({"error": str(e)}), 500


# # ---------------------------------------------------------
# # DASHBOARD LAYOUT
# # ---------------------------------------------------------
# @app.route("/api/dashboard-layout", methods=["GET"])
# @login_required
# def get_dashboard_layout():
#     dashboard_id = request.args.get("dashboardId")
#     if not dashboard_id:
#         return jsonify({"error": "dashboardId is required"}), 400
#     try:
#         access_token = get_superset_access_token()
#         if not access_token:
#             return jsonify({"error": "Superset auth failed"}), 500

#         resp = requests.get(
#             f"{SUPERSET_URL}/api/v1/dashboard/{dashboard_id}",
#             headers={"Authorization": f"Bearer {access_token}"},
#             timeout=10,
#         )
#         if resp.status_code != 200:
#             return jsonify({"error": f"Superset {resp.status_code}"}), 502

#         result        = resp.json().get("result", {})
#         position_json = result.get("position_json", "{}")
#         if isinstance(position_json, str):
#             try:    position_json = json.loads(position_json)
#             except: position_json = {}

#         return jsonify({"success": True, "layout": position_json}), 200
#     except Exception as e:
#         return jsonify({"error": str(e)}), 500


# # ---------------------------------------------------------
# # DEBUG ROUTES
# # ---------------------------------------------------------
# @app.route("/api/debug-dashboard-meta", methods=["GET"])
# @login_required
# def debug_dashboard_meta():
#     dashboard_id = request.args.get("dashboardId")
#     access_token = get_superset_access_token()

#     resp          = requests.get(
#         f"{SUPERSET_URL}/api/v1/dashboard/{dashboard_id}",
#         headers={"Authorization": f"Bearer {access_token}"},
#         timeout=10
#     )
#     result        = resp.json().get("result", {})
#     json_metadata = result.get("json_metadata", "{}")
#     if isinstance(json_metadata, str):
#         json_metadata = json.loads(json_metadata)

#     print(f"DEBUG meta keys: {list(json_metadata.keys())}", flush=True)
#     print(f"DEBUG native_filter_configuration: {json_metadata.get('native_filter_configuration', 'NOT FOUND')}", flush=True)
#     print(f"DEBUG filter_sets_configuration: {json_metadata.get('filter_sets_configuration', 'NOT FOUND')}", flush=True)
#     print(f"DEBUG full metadata: {json.dumps(json_metadata, indent=2)}", flush=True)

#     return jsonify(json_metadata), 200


# #---------------------------------------------------------------------------------
# # dashboard-date-range
# #---------------------------------------------------------------------------------

# @app.route("/api/debug-layout", methods=["GET"])
# @login_required
# def debug_layout():
#     dashboard_id = request.args.get("dashboardId")
#     if not dashboard_id:
#         return jsonify({"error": "dashboardId required"}), 400

#     try:
#         access_token = get_superset_access_token()
#         if not access_token:
#             return jsonify({"error": "Superset auth failed"}), 500

#         resp          = requests.get(
#             f"{SUPERSET_URL}/api/v1/dashboard/{dashboard_id}",
#             headers={"Authorization": f"Bearer {access_token}"},
#             timeout=10,
#         )
#         result        = resp.json().get("result", {})
#         position_json = result.get("position_json", "{}")
#         if isinstance(position_json, str):
#             position_json = json.loads(position_json)

#         all_types = list(set(
#             v.get("type") for v in position_json.values()
#             if isinstance(v, dict) and v.get("type")
#         ))

#         grid      = position_json.get("GRID_ID") or position_json.get("ROOT_ID") or {}
#         grid_kids = grid.get("children", [])

#         tabs_info = []
#         for k, v in position_json.items():
#             if not isinstance(v, dict): continue
#             if v.get("type") not in ("TABS", "TABS_V2"): continue

#             tabs_list = []
#             for tab_id in v.get("children", []):
#                 tab      = position_json.get(tab_id, {})
#                 tab_rows = []
#                 for row_id in tab.get("children", []):
#                     row = position_json.get(row_id, {})
#                     if row.get("type") != "ROW": continue
#                     chart_ids = []
#                     for child_id in row.get("children", []):
#                         child = position_json.get(child_id, {})
#                         if child.get("type") == "CHART":
#                             chart_ids.append(child.get("meta", {}).get("chartId"))
#                         elif child.get("type") == "COLUMN":
#                             for inner_id in child.get("children", []):
#                                 inner = position_json.get(inner_id, {})
#                                 if inner.get("type") == "CHART":
#                                     chart_ids.append(inner.get("meta", {}).get("chartId"))
#                     tab_rows.append({"row_id": row_id, "chart_ids": chart_ids})
#                 tabs_list.append({
#                     "tab_id":   tab_id,
#                     "tab_type": tab.get("type"),
#                     "name": (
#                         tab.get("meta", {}).get("text")
#                         or tab.get("meta", {}).get("defaultText")
#                         or tab.get("meta", {}).get("tabTextContent")
#                         or "(unnamed)"
#                     ),
#                     "rows": tab_rows,
#                 })
#             tabs_info.append({
#                 "component_id": k,
#                 "type":     v.get("type"),
#                 "in_grid":  k in grid_kids,
#                 "tabs":     tabs_list,
#             })

#         standalone_rows = []
#         for row_id in grid_kids:
#             comp = position_json.get(row_id, {})
#             if comp.get("type") != "ROW": continue
#             chart_ids = []
#             for child_id in comp.get("children", []):
#                 child = position_json.get(child_id, {})
#                 if child.get("type") == "CHART":
#                     chart_ids.append(child.get("meta", {}).get("chartId"))
#             standalone_rows.append({"row_id": row_id, "chart_ids": chart_ids})

#         debug = {
#             "dashboard_id":     dashboard_id,
#             "dashboard_title":  result.get("dashboard_title"),
#             "all_types":        sorted(all_types),
#             "grid_children":    grid_kids,
#             "grid_child_types": [position_json.get(k, {}).get("type") for k in grid_kids],
#             "tabs_found":       len(tabs_info),
#             "tabs_info":        tabs_info,
#             "standalone_rows":  standalone_rows,
#             "diagnosis": (
#                 "✅ TABS found under GRID_ID – parser should work"
#                 if any(t["in_grid"] for t in tabs_info)
#                 else "⚠ TABS exist but NOT direct children of GRID_ID – parser needs full-scan fallback"
#                 if tabs_info
#                 else "❌ No TABS found at all – dashboard has no tabs"
#             ),
#         }

#         print(f"DEBUG debug-layout: {json.dumps(debug, indent=2)[:2000]}", flush=True)
#         return jsonify(debug), 200

#     except Exception as e:
#         import traceback
#         traceback.print_exc()
#         return jsonify({"error": str(e)}), 500


# #-------------------------------------------------------------
# # CLEAR SUPERSET CACHE the lazy way (for development/testing)
# #-------------------------------------------------------------

# @app.route('/api/clear-cache', methods=['POST'])
# @login_required
# def clear_cache():
#     try:
#         r       = redis.from_url(os.getenv("REDIS_URL"))
#         deleted = 0

#         for key in r.scan_iter("superset*"):
#             r.delete(key)
#             deleted += 1

#         print(f"DEBUG: Superset cache cleared. {deleted} keys deleted.",
#               flush=True)

#         return jsonify({
#             "success": True,
#             "message": f"Cache cleared successfully. {deleted} keys removed.",
#             "keys_deleted": deleted,
#         }), 200

#     except Exception as e:
#         print(f"DEBUG: Cache clear failed: {e}", flush=True)
#         return jsonify({
#             "success": False,
#             "error":   str(e),
#         }), 500


# #---------------------------------------------------------
# # cross-filter scope map
# #---------------------------------------------------------
# @app.route("/api/dashboard-cross-filter-scope", methods=["GET"])
# @login_required
# def get_cross_filter_scope():
#     """
#     Returns a map of { chartId -> [list of chart IDs it is allowed to filter] }
#     computed from Superset's json_metadata + position_json.
#     If a chart has no explicit scope configured, it maps to [] (filters nobody).
#     """
#     print(f"DEBUG scope endpoint HIT", flush=True)
#     dashboard_id = request.args.get("dashboardId")
#     if not dashboard_id:
#         return jsonify({"error": "dashboardId required"}), 400

#     try:
#         access_token = get_superset_access_token()
#         resp = requests.get(
#             f"{SUPERSET_URL}/api/v1/dashboard/{dashboard_id}",
#             headers={"Authorization": f"Bearer {access_token}"},
#             timeout=10
#         )
#         result = resp.json().get("result", {})

#         json_metadata = result.get("json_metadata", "{}")
#         position_json = result.get("position_json", "{}")
#         if isinstance(json_metadata, str):
#             json_metadata = json.loads(json_metadata)
#         if isinstance(position_json, str):
#             position_json = json.loads(position_json)

#         # ── ADD THESE DEBUG PRINTS ──────────────────────────────
#         print(f"DEBUG position_json keys: {list(position_json.keys())[:30]}", flush=True)
#         print(f"DEBUG chart_configuration: {json_metadata.get('chart_configuration', {})}", flush=True)
#         print(f"DEBUG global_chart_config: {json_metadata.get('global_chart_configuration', {})}", flush=True)
#         # ────────────────────────────────────────────────────────    

#         cross_filters_enabled = json_metadata.get("cross_filters_enabled", False)
#         if not cross_filters_enabled:
#             return jsonify({"enabled": False, "scope": {}}), 200

#         chart_configuration    = json_metadata.get("chart_configuration", {})
#         global_chart_config    = json_metadata.get("global_chart_configuration", {})

#         # --- Helper: walk position_json tree from a root node ID,
#         #     collect all CHART-type chartIds found underneath it ---
#         # def collect_chart_ids_under(node_id, layout):
#         #     found = []
#         #     node = layout.get(node_id, {})
#         #     if node.get("type") == "CHART":
#         #         chart_id = node.get("meta", {}).get("chartId")
#         #         if chart_id:
#         #             found.append(int(chart_id))
#         #     for child_id in node.get("children", []):
#         #         found.extend(collect_chart_ids_under(child_id, layout))
#         #     return found

#         def collect_chart_ids_under(node_id, layout):
#             found = []
#             node = layout.get(node_id)
#             # If ROOT_ID or GRID_ID not found, scan ALL chart nodes in layout
#             if node is None:
#                 if node_id in ("ROOT_ID", "GRID_ID"):
#                     for key, val in layout.items():
#                         if isinstance(val, dict) and val.get("type") == "CHART":
#                             chart_id = val.get("meta", {}).get("chartId")
#                             if chart_id:
#                                 found.append(int(chart_id))
#                 return found
#             if node.get("type") == "CHART":
#                 chart_id = node.get("meta", {}).get("chartId")
#                 if chart_id:
#                     found.append(int(chart_id))
#             for child_id in node.get("children", []):
#                 found.extend(collect_chart_ids_under(child_id, layout))
#             return found

#         def resolve_scope(scope_obj, layout):
#             if not scope_obj or not isinstance(scope_obj, dict):
#                 return None
#             root_path = scope_obj.get("rootPath", [])
#             excluded  = [int(x) for x in scope_obj.get("excluded", [])]
#             # Empty rootPath = whole dashboard
#             if not root_path:
#                 root_path = ["ROOT_ID"]
#             in_scope = []
#             for root_node_id in root_path:
#                 in_scope.extend(collect_chart_ids_under(root_node_id, layout))
#             in_scope = [cid for cid in set(in_scope) if cid not in excluded]
#             print(f"DEBUG resolve_scope: rootPath={root_path}, result={in_scope}", flush=True)
#             return in_scope

#         # --- Resolve global scope once ---
#         global_scope_obj = global_chart_config.get("scope") if global_chart_config else None
#         global_resolved  = resolve_scope(global_scope_obj, position_json)  # may be None

#         # --- Build the scope map ---
#         scope_map = {}
#         for chart_id_str, config in chart_configuration.items():
#             chart_id   = int(chart_id_str)
#             cf_config  = config.get("crossFilters", {})
#             scope_val  = cf_config.get("scope")

#             if scope_val is None:
#                 # No scope defined at all → your rule: filter nobody
#                 scope_map[chart_id] = []

#             elif scope_val == "global":
#                 # Points to global config
#                 if global_resolved is not None:
#                     # Remove self from scope
#                     scope_map[chart_id] = [cid for cid in global_resolved if cid != chart_id]
#                 else:
#                     # global config also missing → filter nobody
#                     scope_map[chart_id] = []

#             else:
#                 # Explicit {rootPath, excluded} scope object
#                 resolved = resolve_scope(scope_val, position_json)
#                 if resolved is not None:
#                     # Remove self from scope
#                     scope_map[chart_id] = [cid for cid in resolved if cid != chart_id]
#                 else:
#                     scope_map[chart_id] = []

#         return jsonify({"enabled": True, "scope": scope_map}), 200

#     except Exception as e:
#         print(f"ERROR get_cross_filter_scope: {e}", flush=True)
#         return jsonify({"error": str(e)}), 500


# if __name__ == '__main__':
#     app.run(host="0.0.0.0", port=5000, debug=True)



import os as _os
from unittest import result
from flask import Flask, request, jsonify, session
from flask_cors import CORS
import jwt
import time
import os
import requests
import json
import redis
from datetime import datetime, timedelta
from werkzeug.utils import secure_filename
import pandas as pd
from sqlalchemy import create_engine, text
import logging
from flask_session import Session
from dotenv import load_dotenv
from pathlib import Path
import io
import re
from tenants_handler import handle_client_orders, handle_shinde_shoes, handle_apparel_store, handle_shinde_shoes_stock, handle_shinde_shoes_purchase, handle_tally_sales,handle_tally_sales_v2, handle_accrec
from db_utils import log_load_error
from datetime import datetime
import threading


# -------------------- ENV loading & expansion --------------------
ROOT = Path(__file__).resolve().parents[1]
DOTENV = ROOT / ".env"
if DOTENV.exists():
    load_dotenv(dotenv_path=str(DOTENV), override=False)
else:
    load_dotenv(override=False)

raw_db = os.getenv("APP_DATABASE_URL")
if raw_db:
    os.environ["APP_DATABASE_URL"] = _os.path.expandvars(raw_db)

REDIS_URL                = os.getenv("REDIS_URL", "redis://redis:6379/0")
SUPERSET_ADMIN_USERNAME  = os.getenv("SUPERSET_ADMIN_USERNAME")
SUPERSET_ADMIN_PASSWORD  = os.getenv("SUPERSET_ADMIN_PASSWORD")
SUPERSET_URL             = os.getenv("SUPERSET_URL")
DATABASE_URL             = os.getenv("APP_DATABASE_URL")
GUEST_TOKEN_JWT_SECRET   = os.getenv("GUEST_TOKEN_JWT_SECRET")


app = Flask(__name__)

flask_secret = os.getenv("FLASK_SECRET_KEY") or os.getenv("SECRET_KEY") or "dev_fallback_secret_please_change"
app.secret_key = flask_secret

print("======================================================================")
print(f"Flask App Initialized with REDIS Session Storage.")
print("======================================================================")

app.config.update(
    SESSION_TYPE='redis',
    SESSION_REDIS=redis.from_url(REDIS_URL),
    SESSION_COOKIE_NAME='flask_session',
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE='None',
    SESSION_COOKIE_SECURE=True,
    PERMANENT_SESSION_LIFETIME=timedelta(hours=1),
    SESSION_PERMANENT=False,
    SESSION_COOKIE_DOMAIN=None
)
Session(app)

raw_origins  = os.getenv("CORS_ALLOW_ORIGINS", "http://localhost:3000,https://frontend-ao4w.onrender.com")
CORS_ORIGINS = [o.strip() for o in raw_origins.split(",") if o.strip()]
CORS(app,
     resources={r"/*": {
         "origins": CORS_ORIGINS,
         "allow_headers": ["Content-Type", "Authorization"],
         "expose_headers": ["Set-Cookie"],
         "methods": ["GET", "POST", "OPTIONS"],
     }},
     supports_credentials=True
)

#---------------------------------------------------------------------
# Help to get exact Colour to superset tableau colour scheme
#---------------------------------------------------------------------

def resolve_color_scheme(raw):
    """
    Resolves a Superset colorScheme value to a hex string.
    Handles: direct hex, rgb(), rgba(), named schemes.
    """
    COLOR_SCHEME_MAP = {
        "success":         "#439066",
        "alert":           "#ffa700",
        "error":           "#e04355",
        "colorsuccessbg":  "#439066",
        "colorwarningbg":  "#ffa700",
        "colorerrorbg":    "#e04355",
    }
    if not raw:
        return None
    s = str(raw).strip()
    if s.startswith("#"):
        return s
    if s.startswith("rgb("):
        try:
            parts = s.replace("rgb(", "").replace(")", "").split(",")
            r, g, b = [int(p.strip()) for p in parts]
            return f"#{r:02x}{g:02x}{b:02x}"
        except Exception:
            pass
    if s.startswith("rgba("):
        try:
            parts = s.replace("rgba(", "").replace(")", "").split(",")
            r, g, b = [int(p.strip()) for p in parts[:3]]
            return f"#{r:02x}{g:02x}{b:02x}"
        except Exception:
            pass
    return COLOR_SCHEME_MAP.get(s.lower())


# ---------------------------------------------------------
# DATABASE ENGINE
# ---------------------------------------------------------
engine = None
if DATABASE_URL:
    try:
        engine = create_engine(
            DATABASE_URL,
            # Check a pooled connection before using it; replace it if the database dropped it.
            pool_pre_ping=True,
            pool_recycle=300,
            # TCP keepalives: a long query (the dashboard refresh runs for minutes without
            # sending anything) must not look idle to the network between the backend and
            # Render's database, which otherwise cuts the connection silently and leaves the
            # upload waiting forever at "Refreshing".
            connect_args={
                "keepalives":          1,
                "keepalives_idle":     30,
                "keepalives_interval": 10,
                "keepalives_count":    5,
            },
        )
        print("Database engine created successfully")
    except Exception as e:
        print(f"DATABASE CONNECTION FAILED: {e}")
        engine = None

ALLOWED_EXTENSIONS = {'xlsx', 'csv'}

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


# ---------------------------------------------------------
# SUPERSET HELPERS
# ---------------------------------------------------------
# def get_superset_access_token():
#     try:
#         response = requests.post(
#             f"{SUPERSET_URL}/api/v1/security/login",
#             json={
#                 "password": SUPERSET_ADMIN_PASSWORD,
#                 "provider": "db",
#                 "refresh":  True,
#                 "username": SUPERSET_ADMIN_USERNAME
#             },
#             timeout=10
#         )
#         if response.status_code == 200:
#             return response.json().get("access_token")
#         return None
#     except Exception as e:
#         print(f"Error getting Superset token: {e}")
#         return None

# AFTER — remembers the token and only logs in again once it's close to expiring
import time

# ---------------------------------------------------------
# SUPERSET HTTP CLIENT + METADATA CACHE
# One pooled session reuses connections instead of opening a new one per call.
# Chart/dashboard definitions change only when edited in Superset, so they are
# cached in Redis for SUPERSET_META_CACHE_TTL seconds. The prefix deliberately
# does not start with "superset" so the post-upload data-cache purge keeps it.
# ---------------------------------------------------------
from requests.adapters import HTTPAdapter
from concurrent.futures import ThreadPoolExecutor

SUPERSET_HTTP = requests.Session()
SUPERSET_HTTP.mount("http://",  HTTPAdapter(pool_connections=4, pool_maxsize=32))
SUPERSET_HTTP.mount("https://", HTTPAdapter(pool_connections=4, pool_maxsize=32))

META_CACHE_PREFIX = "speegile:meta:"
META_CACHE_TTL    = int(os.getenv("SUPERSET_META_CACHE_TTL", "300"))
_meta_redis       = redis.from_url(REDIS_URL)


def superset_request(method, path, access_token=None, **kwargs):
    """Call the Superset API. If Superset rejects the token (401) — e.g. after a Superset
    restart while the backend still holds a cached token — log in again and retry once.
    Returns the requests.Response."""
    token   = access_token or get_superset_access_token()
    headers = dict(kwargs.pop("headers", {}) or {})
    headers["Authorization"] = f"Bearer {token}"

    resp = SUPERSET_HTTP.request(method, f"{SUPERSET_URL}{path}", headers=headers, **kwargs)

    if resp.status_code == 401:
        print(f"DEBUG: Superset 401 on {path} - getting a fresh token and retrying once", flush=True)
        fresh = get_superset_access_token(force_refresh=True)
        if fresh:
            headers["Authorization"] = f"Bearer {fresh}"
            resp = SUPERSET_HTTP.request(method, f"{SUPERSET_URL}{path}", headers=headers, **kwargs)

    if resp.status_code != 200:
        print(f"DEBUG: Superset {method} {path} failed - status={resp.status_code}, "
              f"body={resp.text[:300]}", flush=True)
    return resp


def superset_get_result(path, access_token, timeout=10, cache=True):
    """GET SUPERSET_URL + path; returns (status_code, result). Caches 200 responses in Redis."""
    key = META_CACHE_PREFIX + path
    if cache:
        try:
            hit = _meta_redis.get(key)
            if hit:
                return 200, json.loads(hit)
        except Exception as e:
            print(f"DEBUG: meta cache read failed for {path}: {e}", flush=True)

    resp = superset_request("GET", path, access_token, timeout=timeout)
    if resp.status_code != 200:
        return resp.status_code, None

    result = resp.json().get("result")
    if cache and result is not None:
        try:
            _meta_redis.setex(key, META_CACHE_TTL, json.dumps(result))
        except Exception as e:
            print(f"DEBUG: meta cache write failed for {path}: {e}", flush=True)
    return 200, result


def clear_superset_meta_cache():
    deleted = 0
    for key in _meta_redis.scan_iter(META_CACHE_PREFIX + "*", count=500):
        _meta_redis.unlink(key)
        deleted += 1
    return deleted


_token_cache = {"access_token": None, "expires_at": 0}
TOKEN_SAFETY_MARGIN = 60  # seconds — refresh a bit before it actually expires

def get_superset_access_token(force_refresh=False):
    now = time.time()
    # If we already have a token that isn't about to expire, reuse it
    if (not force_refresh and _token_cache["access_token"]
            and now < _token_cache["expires_at"] - TOKEN_SAFETY_MARGIN):
        return _token_cache["access_token"]

    try:
        response = SUPERSET_HTTP.post(
            f"{SUPERSET_URL}/api/v1/security/login",
            json={
                "password": SUPERSET_ADMIN_PASSWORD,
                "provider": "db",
                "refresh":  True,
                "username": SUPERSET_ADMIN_USERNAME
            },
            timeout=10
        )
        if response.status_code == 200:
            token = response.json().get("access_token")
            _token_cache["access_token"] = token
            _token_cache["expires_at"]   = now + 3300  # ~55 min — safe under Superset's default 1h token life
            return token
        return None
    except Exception as e:
        print(f"Error getting Superset token: {e}")
        return None

def get_all_dashboards_from_superset(access_token):
    try:
        query    = {"page": 0, "page_size": 100}
        response = superset_request(
            "GET", "/api/v1/dashboard/", access_token,
            params={"q": json.dumps(query)},
            headers={"Content-Type": "application/json"},
            timeout=10
        )
        if response.status_code == 200:
            return response.json().get("result", [])
        return []
    except Exception as e:
        print(f"DEBUG: Superset dashboard list error: {e}", flush=True)
        return []


def filter_dashboards_by_user_roles(dashboards, user_roles):
    if not user_roles:
        return []
    user_role_names_lower = [role.lower() for role in user_roles]

    if 'admin' in user_role_names_lower:
        return dashboards

    filtered = []
    for dashboard in dashboards:
        dashboard_roles = dashboard.get('roles', [])
        if not dashboard_roles:
            filtered.append(dashboard)
            continue
        dashboard_role_names = [role['name'].lower() for role in dashboard_roles]
        if any(role in dashboard_role_names for role in user_role_names_lower):
            filtered.append(dashboard)

    return filtered


def get_embedded_dashboard_uuid(filtered_dashboard_list, access_token):
    if not filtered_dashboard_list:
        return []

    def fetch_embedded(dashboard_id):
        try:
            status, result_data = superset_get_result(
                f"/api/v1/dashboard/{dashboard_id}/embedded", access_token
            )
            if status == 200 and result_data and "uuid" in result_data:
                return result_data["uuid"]
        except Exception:
            pass
        return None

    candidates = [d for d in filtered_dashboard_list if d.get('id')]
    with ThreadPoolExecutor(max_workers=min(8, len(candidates) or 1)) as pool:
        uuids = list(pool.map(lambda d: fetch_embedded(d['id']), candidates))

    embedded_dashboards = []
    for dashboard, uuid in zip(candidates, uuids):
        if uuid:
            dashboard['embedded_uuid'] = uuid
            embedded_dashboards.append(dashboard)
    return embedded_dashboards


def login_required(f):
    from functools import wraps
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user' not in session:
            return jsonify({"error": "Authentication required"}), 401
        return f(*args, **kwargs)
    return decorated_function


# ---------------------------------------------------------
# AUTH ROUTES
# ---------------------------------------------------------
@app.route("/api/login", methods=["POST"])
def login():
    data     = request.get_json()
    username = data.get("username")
    password = data.get("password")

    if not username or not password:
        return jsonify({"error": "Username and password required"}), 400

    if not engine:
        return jsonify({"error": "Database unavailable"}), 500

    try:
        with engine.connect() as conn:
            query = text("""
                SELECT
                    u.id, u.name, u.password_hash, u.role, u.superset_username, u.upload_access,
                    t.schema_name, t.table_name,t.procedure_name, t.function_name,
                    t.id as tenant_pk,
                    tpl.logo_url
                FROM public.users u
                JOIN public.tenants t ON u.tenant_id = t.id
                LEFT JOIN public.tenant_templates tpl ON t.id = tpl.tenant_id
                WHERE u.email = :u
            """)
            user = conn.execute(query, {"u": username}).fetchone()

            if not user or user.password_hash != password:
                return jsonify({"error": "Invalid credentials"}), 401

            session.clear()
            session.permanent          = True
            session['user']            = username
            session['name']            = user.name
            session['role']            = user.role
            session['roles']           = [user.role]
            session['superset_username'] = user.superset_username
            session['tenant_schema']   = user.schema_name
            session['tenant_id']       = user.tenant_pk
            session['user_id']         = user.id
            session['logo_url']        = user.logo_url
            session["upload_access"]   = user.upload_access
            session["table_name"]      = user.table_name
            session["procedure_name"]  = user.procedure_name
            session["function_name"]   = user.function_name
            session["data_cache_id"]   = new_data_cache_id()   # chart data cache: fresh for every login
            print(f"DEBUG: User upload_access for '{username}': {user.upload_access}", flush=True)
            return jsonify({
                "success": True,
                "user": {
                    "username": username,
                    "name":     user.name,
                    "roles":    [user.role],
                    "logo":     user.logo_url
                }
            }), 200

    except Exception as e:
        print(f"Login Error: {e}")
        return jsonify({"error": "Server error during login"}), 500


@app.route("/api/logout", methods=["POST"])
def logout():
    removed = clear_session_chart_cache()   # this login's cached chart data
    print(f"DEBUG: logout - {removed} cached chart entries removed", flush=True)
    session.clear()
    return jsonify({"success": True}), 200


@app.route("/api/check-auth", methods=["GET"])
def check_auth():
    if 'user' in session:
        return jsonify({
            "authenticated": True,
            "user": {
                "username": session['user'],
                "name":     session.get('name'),
                "roles":    session.get('roles', []),
                "logo":     session.get('logo_url')
            }
        }), 200
    else:
        return jsonify({"authenticated": False}), 200


# ---------------------------------------------------------
# Upload-Excel API
# ---------------------------------------------------------

@app.route('/api/upload-excel', methods=['POST'])
@login_required
def upload_excel():

    # ── Session details ───────────────────────────────────
    tenant_schema  = session.get('tenant_schema')
    tenant_id      = session.get('tenant_id')
    user_id        = session.get('user_id', 1)
    procedure_name = session.get('procedure_name')
    function_name  = session.get('function_name')

    print(f"DEBUG: Tenant Schema: {tenant_schema}", flush=True)
    print(f"DEBUG: Tenant ID: {tenant_id}",         flush=True)
    print(f"DEBUG: User ID: {user_id}",             flush=True)

    if 'excel_file' not in request.files:
        return jsonify({"success": False, "error": "No file part"}), 400

    file = request.files['excel_file']
    if file.filename == '':
        return jsonify({"success": False, "error": "No selected file"}), 400

    if engine is None:
        return jsonify({"success": False, "error": "Database unavailable"}), 503

    if not tenant_schema:
        return jsonify({"success": False, "error": "No tenant context found"}), 403

    if not file or not allowed_file(file.filename):
        return jsonify({"success": False,
                        "error": "Invalid file type. Only xlsx and csv allowed"}), 400

    clean_filename = secure_filename(file.filename)
    lower_filename = clean_filename.lower()
    file_ext       = clean_filename.rsplit('.', 1)[1].lower()

    print(f"DEBUG: Reading file bytes...", flush=True)
    file_bytes  = file.read()
    file_buffer = io.BytesIO(file_bytes)
    print(f"DEBUG: File read done. Size={len(file_bytes)} bytes", flush=True)

    MAX_FILE_SIZE = 100 * 1024 * 1024
    if len(file_bytes) > MAX_FILE_SIZE:
        return jsonify({"success": False,
                        "error": "File too large. Maximum allowed size is 100MB."}), 400

    r        = redis.from_url(os.getenv("REDIS_URL"))
    lock_key = f"upload_lock:{tenant_schema}"
    lock     = r.set(lock_key, "1", nx=True, ex=600)  # 10 min lock

    if not lock:
        return jsonify({
            "success": False,
            "error":   "Another upload is already in progress. Please wait."
        }), 429

    try:
        print(f"DEBUG: Opening DB connection for tenant lookup...", flush=True)
        with engine.connect() as conn:
            tenant_data = conn.execute(text("""
                SELECT
                    id,
                    tenant_name,
                    schema_name,
                    table_name,
                    fileprefix,
                    procedure_name,
                    function_name,
                    "DomainId"
                FROM public.tenants
                WHERE schema_name = :schema
                  AND (
                      fileprefix IS NULL
                      OR LOWER(:filename) LIKE LOWER(fileprefix) || '%'
                  )
                ORDER BY LENGTH(fileprefix) DESC
                LIMIT 1
            """), {
                "schema":   tenant_schema,
                "filename": lower_filename
            }).mappings().first()

        print(
            f"DEBUG: Tenant lookup done. "
            f"tenant={tenant_data['tenant_name'] if tenant_data else 'NOT FOUND'}",
            flush=True
        )

        if not tenant_data:
            with engine.connect() as conn:
                known_prefixes = conn.execute(text("""
                    SELECT fileprefix FROM public.tenants
                    WHERE schema_name = :schema
                      AND fileprefix IS NOT NULL
                """), {"schema": tenant_schema}).scalars().all()
            prefix_list = ", ".join(f"'{p}'" for p in known_prefixes) \
                          or "none configured"
            r.delete(lock_key)
            return jsonify({
                "success": False,
                "error":   f"Invalid file name. No configuration found for "
                           f"'{clean_filename}'. "
                           f"Expected prefixes: {prefix_list}."
            }), 400

        tenant_id         = tenant_data["id"]
        target_table_name = tenant_data["table_name"]
        file_prefix       = tenant_data["fileprefix"] or ""
        tenant_name       = tenant_data["tenant_name"].strip().lower()
        procedure_name    = tenant_data["procedure_name"]
        function_name     = tenant_data["function_name"]
        # -------------------------------------------------------------
        # Detect file type
        # -------------------------------------------------------------
        file_prefix_lower = file_prefix.lower()

        if "inventory" in file_prefix_lower:
            file_type = "inventory"

        elif "purchase" in file_prefix_lower:
            file_type = "purchase"

        else:
            file_type = "sales"

        print(f"DEBUG: Matched prefix   : {file_prefix}", flush=True)
        print(f"DEBUG: Target table     : {target_table_name}", flush=True)
        print(f"DEBUG: Detected type    : {file_type}", flush=True)
        print(f"DEBUG: Tenant name      : {tenant_name}", flush=True)
        print(f"DEBUG: Procedure name   : {procedure_name}", flush=True)
        print(f"DEBUG: Function name    : {function_name}", flush=True)

        with engine.connect() as load_conn:
            load_id = load_conn.execute(text("""
                INSERT INTO public.load_master
                    (tenant_id, user_id, filename, status, stage_times)
                VALUES (:tid, :uid, :fname, 'Queued',
                        jsonb_build_object('Queued', clock_timestamp()::timestamp))
                RETURNING id
            """), {
                "tid":   tenant_id,
                "uid":   user_id,
                "fname": clean_filename
            }).scalar()
            load_conn.commit()

        print(f"DEBUG: Load ID created: {load_id}", flush=True)

        thread = threading.Thread(
            target = _process_upload_background,
            args   = (
                file_bytes,
                file_ext,
                clean_filename,
                tenant_schema,
                tenant_name,
                tenant_id,
                target_table_name,
                file_type,
                load_id,
                user_id,
                lock_key,
                procedure_name,
                function_name,
            ),
            daemon = True
        )
        thread.start()
        print(f"DEBUG: Background thread started. load_id={load_id}",
              flush=True)

        return jsonify({
            "success":   True,
            "message":   f"File received. "
                         f"Processing in background.",
            "load_id":   load_id,
            "file_type": file_type,
        }), 202

    except Exception as e:
        print(f"DEBUG: Unexpected error in main thread: {e}", flush=True)
        import traceback; traceback.print_exc()
        r.delete(lock_key)
        return jsonify({"success": False, "error": str(e)}), 500


# ════════════════════════════════════════════════════════
#  UPLOAD HELPERS
# ════════════════════════════════════════════════════════

# Sets the status, records when that status began in stage_times, and stamps
# finished_at on Pass/Fail. Needs db/migrations/001_load_master_timing.sql.
LOAD_STATUS_UPDATE_SQL = text("""
    UPDATE public.load_master
    SET    status      = CAST(:status AS varchar),
           stage_times = stage_times
                         || jsonb_build_object(CAST(:status AS text), clock_timestamp()::timestamp),
           finished_at = CASE WHEN CAST(:status AS text) IN ('Pass', 'Fail')
                              THEN clock_timestamp()::timestamp
                              ELSE finished_at END
    WHERE  id = :lid
""")


def _user_error_message(exc):
    """Plain message for the upload popup. For database errors this is the
    procedure's own RAISE EXCEPTION text (e.g. "Sales file has an invalid
    BillDate in row(s): 4"), without the driver's SQL and context lines."""
    diag = getattr(getattr(exc, "orig", None), "diag", None)
    primary = getattr(diag, "message_primary", None)
    return primary or str(exc)


def refresh_views_after_commit(tenant_schema, load_id=None):
    """Refresh the tenant's materialized views in their own autocommit
    transaction, after the uploaded data is committed."""
    with engine.connect().execution_options(isolation_level="AUTOCOMMIT") as rc:
        # proc_run_log: the refresh's run row gets this load id. Session-level
        # (autocommit has no surrounding transaction), so it is reset afterwards.
        rc.execute(text("SELECT set_config('proc_run.load_id', :lid, false)"),
                   {"lid": str(load_id) if load_id is not None else ""})
        try:
            rc.execute(text(f'CALL "{tenant_schema}".refresh_all_mvs()'))
        finally:
            rc.execute(text("SELECT set_config('proc_run.load_id', '', false)"))
    print(f"DEBUG: refresh_all_mvs done for {tenant_schema}.", flush=True)


def clear_superset_data_cache(redis_client):
    """Delete Superset's cached chart data so dashboards show the new upload.
    UNLINK frees memory in the background and the pipeline batches round trips."""
    deleted = 0
    pipe    = redis_client.pipeline(transaction=False)
    for key in redis_client.scan_iter("superset*", count=1000):
        pipe.unlink(key)
        deleted += 1
        if deleted % 1000 == 0:
            pipe.execute()
    pipe.execute()
    return deleted


def _log_failed_run(load_id, error_message, exc=None, tenant_schema=None):
    """Write a FAILED row in <tenant schema>.proc_run_log, for tenants that have
    that table (only shinde_shoes for now). The procedures' own run rows were
    rolled back with the upload, so this names the procedure that raised the
    error (the innermost function in the database error's context)."""
    if not tenant_schema:
        return
    diag    = getattr(getattr(exc, "orig", None), "diag", None)
    context = getattr(diag, "context", None) or ""
    match   = re.search(r'function ([\w."]+)\(', context)
    proc    = match.group(1).replace('"', '').rpartition(".")[2] if match else "upload"
    try:
        with engine.connect() as run_conn:
            has_log = run_conn.execute(
                text("SELECT to_regclass(:tbl) IS NOT NULL"),
                {"tbl": f'"{tenant_schema}".proc_run_log'}
            ).scalar()
            if not has_log:
                return
            run_conn.execute(text(f"""
                INSERT INTO "{tenant_schema}".proc_run_log
                    (proc_name, load_id, status, started_at,
                     finished_at, duration_sec, error_message, details)
                SELECT CAST(:proc AS text), :lid, 'FAILED', s.t,
                       clock_timestamp(),
                       round(extract(epoch FROM clock_timestamp() - s.t)::numeric, 3),
                       CAST(:err AS text),
                       jsonb_build_object('context', CAST(:ctx AS text))
                FROM  (SELECT COALESCE((stage_times->>'Refreshing')::timestamp,
                                       (stage_times->>'Processing')::timestamp,
                                       started_at) AS t
                       FROM   public.load_master
                       WHERE  id = :lid) s
            """), {"proc": proc, "lid": load_id,
                   "err": error_message, "ctx": context})
            run_conn.commit()
    except Exception as run_err:
        print(f"DEBUG: Could not write proc_run_log FAILED row: {run_err}", flush=True)


def _mark_load_failed(load_id, error_message, exc=None, tenant_schema=None):
    """Record the error in load_errors and set load_master.status = 'Fail'."""
    _log_failed_run(load_id, error_message, exc, tenant_schema)

    try:
        with engine.connect() as error_conn:
            log_load_error(
                conn=error_conn, load_id=load_id,
                error_message=error_message,
                row_number=None, column_name=None
            )
            error_conn.commit()
            print(f"DEBUG: Error logged to load_errors. "
                  f"load_id={load_id}", flush=True)
    except Exception as log_err:
        print(f"DEBUG: Failed to log error: {log_err}", flush=True)

    try:
        with engine.connect() as fail_conn:
            fail_conn.execute(LOAD_STATUS_UPDATE_SQL, {"status": "Fail", "lid": load_id})
            fail_conn.commit()
            print(f"DEBUG: load_master marked Fail. "
                  f"load_id={load_id}", flush=True)
    except Exception as fail_err:
        print(f"DEBUG: Could not update status to Fail: "
              f"{fail_err}", flush=True)


# ════════════════════════════════════════════════════════
#  BACKGROUND THREAD FUNCTION
# ════════════════════════════════════════════════════════
def _process_upload_background(
    file_bytes,
    file_ext,
    clean_filename,
    tenant_schema,
    tenant_name,
    tenant_id,
    target_table_name,
    file_type,
    load_id,
    user_id,
    lock_key,
    procedure_name,
    function_name,
):
    # r = redis.from_url(os.getenv("REDIS_URL"))
    redis_client = redis.from_url(REDIS_URL)
    r = redis_client

    def update_status(new_status, row_count=None):
        try:
            with engine.connect() as sc:
                sc.execute(LOAD_STATUS_UPDATE_SQL, {"status": new_status, "lid": load_id})
                if row_count is not None:
                    sc.execute(text("""
                        UPDATE public.load_master
                        SET    row_count = :n
                        WHERE  id        = :lid
                    """), {"n": row_count, "lid": load_id})
                sc.commit()
            print(f"DEBUG: Status → {new_status} (load_id={load_id})",
                  flush=True)
        except Exception as e:
            print(f"DEBUG: Could not update status to {new_status}: {e}",
                  flush=True)

    try:
        file_buffer = io.BytesIO(file_bytes)

        with engine.connect() as conn:
            trans = conn.begin()
            try:
                # proc_run_log: procedures run in this upload record its load id
                conn.execute(text("SELECT set_config('proc_run.load_id', :lid, true)"),
                             {"lid": str(load_id)})

                update_status('Reading')

                if file_ext == 'xlsx':
                    xls        = pd.ExcelFile(file_buffer, engine='openpyxl')
                    dataframes = [
                        xls.parse(sheet, dtype=str)
                        for sheet in xls.sheet_names
                    ]
                elif file_ext == 'csv':
                    file_buffer.seek(0)
                    dataframes = [
                        pd.read_csv(file_buffer, dtype=str,
                                    encoding='utf-8-sig')
                    ]
                else:
                    raise ValueError("Unsupported file format")

                update_status('Preparing')

                excel_max_date = None
                df_original    = None

                for df in dataframes:
                    if df.empty:
                        continue

                    df.columns = [c.strip() for c in df.columns]
                    df         = df.dropna(how='all').reset_index(drop=True)

                    if df.empty:
                        raise ValueError(
                            "Uploaded file contains no data rows."
                        )

                    df_original = df.copy()
                    print(f"DEBUG: Columns: {list(df.columns)}", flush=True)
                    print(f"DEBUG: Rows: {len(df)}",             flush=True)

                    table_columns = conn.execute(text("""
                        SELECT column_name
                        FROM   information_schema.columns
                        WHERE  table_schema = :schema
                          AND  table_name   = :table
                    """), {
                        "schema": tenant_schema,
                        "table":  target_table_name
                    }).scalars().all()

                    print(f"DEBUG: DB columns: {table_columns}", flush=True)

                    df = df[[
                        col for col in df.columns
                        if col in table_columns
                    ]].copy()

                    if 'load_id' in table_columns:
                        df['load_id'] = load_id

                    print(f"DEBUG: Data prepared for {target_table_name}",
                          flush=True)

                update_status(
                    'Processing',
                    row_count=len(df_original) if df_original is not None else None
                )

                #-------------------------------------------------------------
                # Route to correct handler based on tenant name + file type
                #-------------------------------------------------------------
                if tenant_name == "shinde_shoes" and file_type == "sales":
                    handle_shinde_shoes(
                        conn, df, tenant_schema, target_table_name,
                        load_id, log_load_error, engine,
                        progress=update_status
                    )

                elif tenant_name == "shinde_shoes" and file_type == "inventory":
                    handle_shinde_shoes_stock(
                        conn,
                        df,
                        tenant_schema,
                        target_table_name,
                        load_id,
                        log_load_error,
                        filename=clean_filename,
                        user_id=user_id,
                        progress=update_status
                    )

                # ── NEW: dedicated Purchase branch ─────────────────────
                # Purchase's staging/processing is load_id-scoped
                # (stg_purchase_1 -> sp_validate_purchase_load(load_id) ->
                #  stg_purchase_2 -> sp_process_purchase_load(load_id)),
                # so it can no longer fall through to the generic,
                # zero-argument single-procedure() branch below.
                elif tenant_name == "shinde_shoes" and file_type == "purchase":
                    handle_shinde_shoes_purchase(
                        conn, df, tenant_schema, target_table_name,
                        load_id, log_load_error,
                        progress=update_status
                    )

                elif tenant_name == "apparel_sales":
                    handle_apparel_store(
                        conn, df_original, tenant_schema,
                        load_id, log_load_error
                    )

                elif tenant_name == "siddhesh":
                    handle_client_orders(
                        conn, df, tenant_schema, target_table_name,
                        load_id, log_load_error
                    )

                elif tenant_name == "tally_data":
                    handle_tally_sales(
                        conn, df_original, tenant_schema, target_table_name,
                        load_id, log_load_error
                    )

                elif tenant_name == "tally_data2":
                    handle_tally_sales_v2(
                        conn, df_original, tenant_schema, target_table_name,
                        load_id, log_load_error
                    )

                elif tenant_name == "accrec":
                    handle_accrec(
                        conn, df_original, tenant_schema, target_table_name,
                        load_id, log_load_error
                    )

                else:
                    print(
                        f"DEBUG: No Python handler for '{tenant_name}'. "
                        f"Using generic flow → insert strings + call procedure.",
                        flush=True
                    )

                    conn.execute(text(
                        f'TRUNCATE TABLE "{tenant_schema}".'
                        f'"{target_table_name}" RESTART IDENTITY'
                    ))
                    print(f"DEBUG: Truncated {target_table_name}.", flush=True)

                    df.to_sql(
                        target_table_name,
                        con       = conn,
                        schema    = tenant_schema,
                        if_exists = 'append',
                        index     = False
                    )
                    print(
                        f"DEBUG: Inserted {len(df)} rows into "
                        f"{tenant_schema}.{target_table_name}.",
                        flush=True
                    )

                    if procedure_name:

                        print(
                            f"DEBUG: Procedure configured: {procedure_name}",
                            flush=True
                        )

                        conn.execute(
                            text(
                                f'CALL "{tenant_schema}".'
                                f'"{procedure_name}"()'
                            )
                        )

                        print(
                            f"DEBUG: Procedure {procedure_name} done.",
                            flush=True
                        )

                    else:

                        print(
                            f"DEBUG: No procedure configured for "
                            f"{tenant_name}/{file_type}. "
                            f"Staging upload completed without procedure.",
                            flush=True
                        )

                    print(f"DEBUG: Procedure {procedure_name} done.",
                          flush=True)

                import gc
                try:
                    del df
                except Exception:
                    pass
                try:
                    del df_original
                except Exception:
                    pass
                try:
                    del dataframes
                except Exception:
                    pass
                try:
                    del file_buffer
                except Exception:
                    pass
                gc.collect()
                print("DEBUG: RAM freed after handler.", flush=True)

                update_status('Saving')

                needs_view_refresh = (
                    tenant_name == "shinde_shoes" and file_type == "sales"
                )

                # Committed together with the data, so a crash after this point
                # never leaves the load looking unfinished while data is saved.
                conn.execute(LOAD_STATUS_UPDATE_SQL, {
                    "status": "Refreshing" if needs_view_refresh else "Pass",
                    "lid":    load_id,
                })

                trans.commit()
                print("DEBUG: Transaction committed.", flush=True)

            except Exception as e:
                error_message = _user_error_message(e)

                try:
                    trans.rollback()
                except Exception:
                    pass

                print(f"DEBUG: ERROR in background: {error_message}",
                      flush=True)
                import traceback
                traceback.print_exc()
                _mark_load_failed(load_id, error_message, e, tenant_schema)
                return

        # ── After commit: refresh dashboards' views, then clear the data cache ──
        # Runs outside the upload transaction, so dashboards are only locked
        # while the refresh itself runs, and a refresh failure keeps the data.
        if needs_view_refresh:
            try:
                refresh_views_after_commit(tenant_schema, load_id)
            except Exception as refresh_err:
                print(f"DEBUG: View refresh failed: {refresh_err}", flush=True)
                _mark_load_failed(
                    load_id,
                    "Data was saved, but refreshing the dashboards failed: "
                    f"{refresh_err}",
                    refresh_err,
                    tenant_schema
                )
                return

        try:
            deleted = clear_superset_data_cache(r)
            print(f"DEBUG: Superset cache cleared ({deleted} keys).", flush=True)
            removed = clear_chart_data_cache(tenant_schema)
            print(f"DEBUG: Chart data cache cleared for {tenant_schema} ({removed} keys).", flush=True)
        except Exception as cache_err:
            print(
                f"DEBUG: Cache clear failed (non-critical): "
                f"{cache_err}",
                flush=True
            )

        if needs_view_refresh:
            update_status('Pass')

    finally:
        r.delete(lock_key)
        print(
            f"DEBUG: Upload lock released for {tenant_schema}.",
            flush=True
        )


# Upload steps shown in the progress popup: status -> (percent, message).
# The background upload writes the status (update_status); the Shinde handlers report
# their own steps (tenants_handler.py, progress=update_status). Other tenants only use
# the generic steps.
UPLOAD_STEPS = {
    "Queued":           (5,   "File received. Starting..."),
    "Reading":          (10,  "Reading the file..."),
    "Preparing":        (15,  "Checking the file columns..."),
    "Processing":       (20,  "Processing the data..."),
    "CheckingDates":    (25,  "Processing the data..."),
    "LoadingRows":      (35,  "Loading the file rows..."),
    "SavingSales":      (50,  "Processing the data..."),
    "UpdatingDates":    (62,  "Updating report dates..."),
    "UpdatingStock":    (70,  "Processing the data..."),
    "SavingStockCount": (55,  "Checking stock rows and updating stock..."),
    "SavingPurchases":  (55,  "Checking bills and updating purchases and stock..."),
    "Saving":           (78,  "Saving everything to the database..."),
    "Refreshing":       (80,  "Data saved. Refreshing dashboards..."),
    "Pass":             (100, "Upload complete. Please refresh the page to see the updated dashboards."),
}

REFRESH_PERCENT_FROM, REFRESH_PERCENT_TO = 80, 99


def _refresh_progress(conn, tenant_schema, refreshing_since):
    """Live progress of the dashboard refresh started for this upload, from
    <tenant schema>.log_refresh (refresh_all_mvs commits after every view).
    Returns (views_done, views_total) or None."""
    if not tenant_schema or not refreshing_since:
        return None
    try:
        if not conn.execute(text("SELECT to_regclass(:t) IS NOT NULL"),
                            {"t": f'"{tenant_schema}".log_refresh'}).scalar():
            return None
        prog = conn.execute(text(f"""
            SELECT mv_refreshed_count,
                   (SELECT count(*) FROM pg_matviews WHERE schemaname = :schema) AS total
            FROM   "{tenant_schema}".log_refresh
            WHERE  started_at >= CAST(:since AS timestamp) - interval '5 seconds'
            ORDER  BY refresh_id DESC
            LIMIT  1
        """), {"schema": tenant_schema, "since": refreshing_since}).first()
        if prog and prog[1]:
            return int(prog[0] or 0), int(prog[1])
    except Exception as e:
        print(f"DEBUG: refresh progress lookup failed: {e}", flush=True)
    return None


# ════════════════════════════════════════════════════════
#  POLL ENDPOINT — frontend calls every 3 seconds
# ════════════════════════════════════════════════════════
@app.route('/api/upload-status/<int:load_id>', methods=['GET'])
@login_required
def upload_status(load_id):
    refresh = None
    with engine.connect() as conn:

        row = conn.execute(text("""
            SELECT status, filename, stage_times->>'Refreshing' AS refreshing_since
            FROM   public.load_master
            WHERE  id = :lid
        """), {"lid": load_id}).mappings().first()

        if not row:
            return jsonify({"status": "unknown"}), 404

        status = row["status"]

        error_message = None
        if status == "Fail":
            error_row = conn.execute(text("""
                SELECT error_message
                FROM   public.load_errors
                WHERE  load_id   = :lid
                ORDER  BY created_at DESC
                LIMIT  1
            """), {"lid": load_id}).mappings().first()

            if error_row:
                error_message = error_row["error_message"]

        if status == "Refreshing":
            refresh = _refresh_progress(conn, session.get("tenant_schema"),
                                        row["refreshing_since"])

    if status == "Fail":
        percent, message = 0, error_message or "Processing failed. Please contact support."
    else:
        percent, message = UPLOAD_STEPS.get(status, (50, "Processing..."))

    if refresh:
        done, total = refresh
        percent = REFRESH_PERCENT_FROM + round(
            (REFRESH_PERCENT_TO - REFRESH_PERCENT_FROM) * min(done, total) / total)
        message = "Data saved. Refreshing dashboards... This can take a few minutes."

    return jsonify({
        "status":        status,
        "percent":       percent,
        "message":       message,
        "error_message": error_message,
        "load_id":       load_id,
        "filename":      row["filename"],
    }), 200


@app.route("/api/dashboards", methods=["GET"])
@login_required
def get_filtered_dashboards():
    user_roles = session.get('roles', [])

    try:
        access_token = get_superset_access_token()
        if not access_token:
            return jsonify({"error": "Failed to connect to Superset"}), 500

        print(f"DEBUG: Superset token OK", flush=True)

        all_dashboards = get_all_dashboards_from_superset(access_token)
        print(f"DEBUG: Total dashboards: {len(all_dashboards)}", flush=True)

        filtered = filter_dashboards_by_user_roles(all_dashboards, user_roles)
        print(f"DEBUG: Filtered dashboards: {len(filtered)}", flush=True)

        dashboard_list = [{
            "id":              d.get('id'),
            "dashboard_title": d.get('dashboard_title'),
            "url":             d.get('url'),
            "roles":           [r['name'] for r in d.get('roles', [])]
        } for d in filtered]

        embedded_dashboards = get_embedded_dashboard_uuid(dashboard_list, access_token)
        print(f"DEBUG: Embedded dashboards: {len(embedded_dashboards)}", flush=True)

        category_map = {}
        if engine and embedded_dashboards:
            dashboard_ids = [d.get('id') for d in embedded_dashboards if d.get('id')]
            try:
                with engine.connect() as conn:
                    rows = conn.execute(text("""
                        SELECT dashboard_id, category
                        FROM public.dashboard_category_map
                        WHERE dashboard_id = ANY(:ids)
                    """), {"ids": dashboard_ids}).fetchall()
                category_map = {row.dashboard_id: row.category for row in rows}
            except Exception as e:
                print(f"DEBUG: category_map error: {e}", flush=True)
                category_map = {}

        for d in embedded_dashboards:
            d['category'] = category_map.get(d.get('id'), 'General')

        return jsonify({"success": True, "dashboards": embedded_dashboards}), 200

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/api/guest-token", methods=["GET"])
@login_required
def generate_guest_token():
    dashboard_id_str  = request.args.get("dashboardId")
    superset_username = session.get('superset_username')

    if not dashboard_id_str:
        return jsonify({"error": "dashboardId is required"}), 400

    expiration_time = int(time.time()) + 3600

    payload = {
        "user": {
            "username":   superset_username,
            "first_name": "Guest",
            "last_name":  "User",
        },
        "resources": [{"type": "dashboard", "id": dashboard_id_str}],
        "rls_rules": [],
        "exp":  expiration_time,
        "aud":  "audi",
        "type": "guest"
    }

    try:
        token = jwt.encode(payload, GUEST_TOKEN_JWT_SECRET, algorithm="HS256")
        return jsonify({"guestToken": token}), 200
    except Exception as e:
        return jsonify({"error": "Failed to encode token"}), 500


@app.route("/api/branding", methods=["GET"])
@login_required
def get_branding():
    try:
        tenant_id = session.get("tenant_id")
        if not tenant_id:
            return jsonify({"error": "No tenant context"}), 400

        with engine.connect() as conn:
            result = conn.execute(text("""
                SELECT logo_url, branding_name
                FROM public.tenant_templates
                WHERE id = :tid
            """), {"tid": tenant_id}).mappings().first()

        if not result:
            return jsonify({"error": "Branding not found"}), 404

        return jsonify({
            "logo_url":     result["logo_url"],
            "branding_name": result["branding_name"]
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/truncate-data', methods=['GET'])
def truncate_table_simple():
    TARGET_SCHEMA = "apparel_sales"
    TARGET_TABLE  = "t_apparel_sales"

    try:
        with engine.connect() as conn:
            query = text(f'TRUNCATE TABLE "{TARGET_SCHEMA}"."{TARGET_TABLE}" RESTART IDENTITY CASCADE')
            conn.execute(query)
            conn.commit()
            return f"""
            <div style="font-family:sans-serif; text-align:center; margin-top:100px;">
                <h1 style="color:green;">Table Truncated</h1>
                <p>All data has been deleted from: <b>{TARGET_SCHEMA}.{TARGET_TABLE}</b></p>
                <p>Serial IDs have been reset to 1.</p>
            </div>
            """, 200
    except Exception as e:
        return f"<h1>Error</h1><p>{str(e)}</p>", 500


@app.route("/api/dashboard-charts", methods=["GET"])
@login_required
def get_dashboard_charts():
    dashboard_id = request.args.get("dashboardId")

    if not dashboard_id:
        return jsonify({"error": "dashboardId is required"}), 400

    try:
        access_token = get_superset_access_token()
        if not access_token:
            return jsonify({"error": "Superset auth failed"}), 500

        _, charts  = superset_get_result(
            f"/api/v1/dashboard/{dashboard_id}/charts", access_token, timeout=15
        )
        charts     = charts or []
        chart_list = []

        print(f"DEBUG: All chart IDs on dashboard {dashboard_id}: {[c.get('id') for c in charts]}", flush=True)

        _, dashboard_meta = superset_get_result(
            f"/api/v1/dashboard/{dashboard_id}", access_token, timeout=15
        )
        dashboard_meta = dashboard_meta or {}
        raw_json_meta  = dashboard_meta.get("json_metadata") or "{}"
        try:
            json_metadata = json.loads(raw_json_meta)
        except Exception:
            json_metadata = {}

        print(f"DEBUG json_metadata keys: {list(json_metadata.keys())}", flush=True)

        chart_configuration = json_metadata.get("chart_configuration", {})

        position_json = dashboard_meta.get("position_json", "{}")
        if isinstance(position_json, str):
            try:
                position_json = json.loads(position_json)
            except Exception:
                position_json = {}

        raw_shared = json_metadata.get("shared_label_colors")
        raw_label  = json_metadata.get("label_colors")

        def _clean_label_colors(*sources):
            out = {}
            for raw in sources:
                if isinstance(raw, dict):
                    for k, v in raw.items():
                        if isinstance(v, str) and v.startswith("#"):
                            out[str(k)] = v
            return out

        superset_label_colors = _clean_label_colors(raw_shared, raw_label)
        print(f"DEBUG superset_label_colors = {superset_label_colors}", flush=True)
        print(f"DEBUG color_scheme = {json_metadata.get('color_scheme')}", flush=True)

        def resolve_scope(scope_obj):
            if not scope_obj or not isinstance(scope_obj, dict):
                return None
            root_path = scope_obj.get("rootPath", [])
            excluded  = [int(x) for x in scope_obj.get("excluded", [])]

            if not root_path:
                all_chart_ids = []
                for val in position_json.values():
                    if isinstance(val, dict) and val.get("type") == "CHART":
                        cid = val.get("meta", {}).get("chartId")
                        if cid:
                            all_chart_ids.append(int(cid))
                result = [cid for cid in all_chart_ids if cid not in excluded]
                print(f"DEBUG resolve_scope: rootPath=[] -> scanned all -> {result}", flush=True)
                return result

            def collect(node_id):
                found = []
                node  = position_json.get(node_id)
                if node is None:
                    if node_id in ("ROOT_ID", "GRID_ID"):
                        for val in position_json.values():
                            if isinstance(val, dict) and val.get("type") == "CHART":
                                cid = val.get("meta", {}).get("chartId")
                                if cid:
                                    found.append(int(cid))
                    return found
                if node.get("type") == "CHART":
                    cid = node.get("meta", {}).get("chartId")
                    if cid:
                        found.append(int(cid))
                for child_id in node.get("children", []):
                    found.extend(collect(child_id))
                return found

            in_scope = []
            for root_node_id in root_path:
                in_scope.extend(collect(root_node_id))
            in_scope = [cid for cid in set(in_scope) if cid not in excluded]
            print(f"DEBUG resolve_scope: rootPath={root_path}, result={in_scope}", flush=True)
            return in_scope

        # for chart in charts:
        #     chart_id    = chart.get("id")
        #     detail_resp = requests.get(
        #         f"{SUPERSET_URL}/api/v1/chart/{chart_id}",
        #         headers={"Authorization": f"Bearer {access_token}"},
        #         timeout=10
        #     )
        #     detail    = detail_resp.json().get("result", {})

        # AFTER — fetch several at the same time instead of one at a time
        from concurrent.futures import ThreadPoolExecutor, as_completed

        def fetch_chart_detail(chart_id):
            _, detail = superset_get_result(f"/api/v1/chart/{chart_id}", access_token)
            return chart_id, detail or {}

        chart_ids = [c.get("id") for c in charts]
        details_by_id = {}
        with ThreadPoolExecutor(max_workers=min(8, len(chart_ids) or 1)) as pool:
            futures = {pool.submit(fetch_chart_detail, cid): cid for cid in chart_ids}
            for future in as_completed(futures):
                cid, detail = future.result()
                details_by_id[cid] = detail

        for chart in charts:
            chart_id = chart.get("id")
            detail   = details_by_id.get(chart_id, {})
            
            form_data = detail.get("form_data", {})

            if not form_data:
                params_raw = detail.get("params", "{}")
                try:
                    form_data = json.loads(params_raw) if isinstance(params_raw, str) else (params_raw or {})
                except Exception:
                    form_data = {}

            try:
                params_raw = detail.get("params", "{}")
                params     = json.loads(params_raw) if isinstance(params_raw, str) else (params_raw or {})
                for k, v in params.items():
                    if k not in form_data:
                        form_data[k] = v
            except Exception:
                pass

            viz_type = (
                form_data.get("viz_type")
                or detail.get("viz_type")
                or "echarts_timeseries_bar"
            )

            def _normalize_series_type(t):
                t = (t or "").lower()
                if t == "bar":
                    return "bar"
                if t == "area":
                    return "area"
                return "line"

            series_types = None
            if viz_type == "mixed_timeseries":
                left_raw  = form_data.get("seriesType")
                right_raw = form_data.get("seriesTypeB")
                print(f"DEBUG mixed chart {chart_id} raw seriesType/B: {left_raw!r} / {right_raw!r}", flush=True)
                series_types = [
                    _normalize_series_type(left_raw),
                    _normalize_series_type(right_raw),
                ]

            if viz_type == "pie":
                print(f"DEBUG pie {chart_id} ALL keys: {list(form_data.keys())}", flush=True)
                for k, v in form_data.items():
                    if "other" in k.lower() or "threshold" in k.lower():
                        print(f"DEBUG pie {chart_id} threshold key: {k} = {v}", flush=True)

            percentage_threshold = (
                form_data.get("show_labels_threshold")
                or form_data.get("percentage_threshold")
                or 0
            ) or 0

            other_threshold = (
                form_data.get("threshold_for_other")
                or form_data.get("other_threshold")
                or 0
            ) or 0

            print(f"DEBUG pie {chart_id}: percentage_threshold={percentage_threshold} other_threshold={other_threshold}", flush=True)
            print(f"DEBUG chart {chart_id}: percentage_threshold={percentage_threshold} other_threshold={other_threshold}", flush=True)

            if 'timeseries' in viz_type.lower() or 'line' in viz_type.lower():
                print(f"DEBUG chart {chart_id} form_data keys: {list(form_data.keys())}", flush=True)
                print(f"DEBUG chart {chart_id} groupby raw: {form_data.get('groupby')}", flush=True)
                print(f"DEBUG chart {chart_id} metrics raw: {form_data.get('metrics', [])[:3]}", flush=True)

            def _extract_col_string(raw):
                if not raw:
                    return ""
                if isinstance(raw, str):
                    return raw.strip()
                if isinstance(raw, dict):
                    return (
                        raw.get("column_name") or
                        raw.get("label")       or
                        raw.get("name")        or
                        ""
                    ).strip()
                return ""

            def _col_names(lst):
                if isinstance(lst, str):
                    return [lst] if lst else []
                out = []
                for item in (lst or []):
                    if isinstance(item, str):
                        out.append(item)
                    elif isinstance(item, dict):
                        name = (
                            item.get("column_name")
                            or item.get("label")
                            or item.get("name")
                            or item.get("sqlExpression")
                            or ""
                        )
                        if name:
                            out.append(name)
                return [x for x in out if x]

            x_axis_raw = (
                form_data.get("x_axis")
                or form_data.get("granularity_sqla")
                or ""
            )
            x_axis = _extract_col_string(x_axis_raw)

            if not x_axis:
                gb_list = form_data.get("groupby") or []
                if gb_list:
                    x_axis = _extract_col_string(gb_list[0])

            metrics_primary   = form_data.get("metrics",   [])
            metrics_secondary = form_data.get("metrics_b", [])
            metrics = metrics_primary + (metrics_secondary if metrics_secondary else [])

            groupby_raw = (
                form_data.get("groupby")
                or form_data.get("series_columns")
                or form_data.get("dimensions")
                or form_data.get("breakdown")
                or []
            )
            groupby = _col_names(groupby_raw)

            groupby_rows_raw = (
                form_data.get("groupbyRows")
                or form_data.get("groupby_rows")
                or []
            )
            groupby_cols_raw = (
                form_data.get("groupbyColumns")
                or form_data.get("groupby_cols")
                or form_data.get("columns")
                or []
            )

            groupby_rows = _col_names(groupby_rows_raw)
            groupby_cols = _col_names(groupby_cols_raw)

            conditional_formatting = []
            is_table = viz_type and ("table" in viz_type.lower() or "pivot" in viz_type.lower())
            column_order = []
            if is_table:
                col_config = form_data.get("column_config") or {}
                if isinstance(col_config, dict) and col_config:
                    column_order = sorted(col_config.keys(),
                                          key=lambda k: col_config[k].get("index", 999))

            if is_table:
                raw_cf = (
                    form_data.get("conditional_formatting")
                    or form_data.get("conditionalFormatting")
                    or []
                )
                for rule in (raw_cf or []):
                    if not isinstance(rule, dict):
                        continue
                    col      = rule.get("column") or rule.get("col") or ""
                    operator = rule.get("operator") or rule.get("op") or ""
                    target   = rule.get("targetValue")
                    if target is None:
                        target = rule.get("target_value")
                    raw_color = (
                        rule.get("colorScheme")
                        or rule.get("color")
                        or (rule.get("colorScheme", {}) or {}).get("value")
                        or (rule.get("style", {}) or {}).get("color")
                    )
                    color = resolve_color_scheme(raw_color)
                    if color and col and operator:
                        conditional_formatting.append({
                            "column":   col,
                            "operator": operator,
                            "value":    float(target) if target is not None else None,
                            "color":    color,
                        })

            print(f"DEBUG chart {chart_id}: conditional_formatting rules = {conditional_formatting}", flush=True)

            show_cell_bars = bool(form_data.get("show_cell_bars", False)) if is_table else False
            print(f"DEBUG chart {chart_id}: show_cell_bars = {show_cell_bars}", flush=True)

            raw_x_axis_column = _extract_col_string(
                form_data.get("x_axis") or form_data.get("granularity_sqla") or ""
            )

            x_axis_is_temporal = bool(
                form_data.get("granularity_sqla")
                or (raw_x_axis_column and any(
                    k in raw_x_axis_column.lower()
                    for k in ["date", "time", "month", "day", "year", "period"]
                ))
            )

            print(
                f"DEBUG chart {chart_id}: viz={viz_type!r} x_axis={x_axis!r} "
                f"groupby={groupby} "
                f"groupby_rows={groupby_rows} groupby_cols={groupby_cols} "
                f"metrics=[{[m if isinstance(m, str) else m.get('label', '?') for m in metrics[:3]]}]",
                flush=True,
            )

            font_color         = None
            conditional_colors = []

            if viz_type and "big_number" in viz_type.lower():

                COLOR_SCHEME_MAP = {
                    "success":           "#22c55e",
                    "alert":             "#fbbf24",
                    "error":             "#f87171",
                    "colorsuccessbg":    "#22c55e",
                    "colorwarningbg":    "#fbbf24",
                    "colorerrorbg":      "#f87171",
                    "successbg":         "#22c55e",
                    "warningbg":         "#fbbf24",
                    "errorbg":           "#f87171",
                    "green":             "#22c55e",
                    "yellow":            "#fbbf24",
                    "red":               "#f87171",
                    "orange":            "#f97316",
                    "blue":              "#3b82f6",
                    "purple":            "#a855f7",
                    "primary":           "#1FA8C9",
                    "secondary":         "#454E7C",
                    "danger":            "#f87171",
                    "warning":           "#fbbf24",
                    "info":              "#1FA8C9",
                }

                # Superset theme colour families. Superset 6.0 and 6.1 store rule colours as
                # theme tokens such as colorSuccessBg / colorSuccess / colorErrorText /
                # colorWarningBorder: the family decides the colour, the suffix does not.
                THEME_FAMILY_COLORS = {
                    "success": "#22c55e",
                    "error":   "#f87171",
                    "danger":  "#f87171",
                    "warning": "#fbbf24",
                    "alert":   "#fbbf24",
                    "info":    "#1FA8C9",
                    "primary": "#1FA8C9",
                }
                THEME_TOKEN_SUFFIXES = (
                    "bghover", "bgactive", "borderhover", "texthover", "textactive",
                    "bg", "border", "text", "hover", "active",
                )

                def resolve_color(raw_color):
                    if not raw_color:
                        return None
                    # colorScheme can arrive as an object, e.g. {"value": "colorSuccess"}
                    if isinstance(raw_color, dict):
                        raw_color = (raw_color.get("value") or raw_color.get("color")
                                     or raw_color.get("hex"))
                        if not raw_color:
                            return None
                    s = str(raw_color).strip()
                    if s.lower() in COLOR_SCHEME_MAP:
                        return COLOR_SCHEME_MAP[s.lower()]
                    token = s.lower()
                    if token.startswith("color") and len(token) > len("color"):
                        token = token[len("color"):]
                        for suffix in THEME_TOKEN_SUFFIXES:
                            if token.endswith(suffix) and token != suffix:
                                token = token[: -len(suffix)]
                                break
                        if token in THEME_FAMILY_COLORS:
                            return THEME_FAMILY_COLORS[token]
                    if s.startswith("#") and len(s) in [4, 7, 9]:
                        return s
                    if s.startswith("rgb("):
                        try:
                            parts = s.replace("rgb(", "").replace(")", "").split(",")
                            r, g, b = [int(p.strip()) for p in parts]
                            return f"#{r:02x}{g:02x}{b:02x}"
                        except Exception:
                            pass
                    if s.startswith("rgba("):
                        try:
                            parts = s.replace("rgba(", "").replace(")", "").split(",")
                            r, g, b = [int(p.strip()) for p in parts[:3]]
                            return f"#{r:02x}{g:02x}{b:02x}"
                        except Exception:
                            pass
                    return COLOR_SCHEME_MAP.get(s.lower(), None)

                conditional_formatting = (
                    form_data.get("conditional_formatting") or
                    form_data.get("conditionalFormatting") or
                    form_data.get("color_config")          or
                    []
                )

                print(f"DEBUG bignum {chart_id} RAW conditional_formatting = {conditional_formatting}", flush=True)
                for _r in (conditional_formatting or []):
                    if isinstance(_r, dict):
                        print(
                            f"DEBUG bignum {chart_id} RAW rule: "
                            f"operator={_r.get('operator')!r} "
                            f"targetValue={_r.get('targetValue')!r} "
                            f"targetValueLeft={_r.get('targetValueLeft')!r} "
                            f"targetValueRight={_r.get('targetValueRight')!r} "
                            f"colorScheme={_r.get('colorScheme')!r} "
                            f"column={_r.get('column')!r}",
                            flush=True,
                        )

                for rule in (conditional_formatting or []):
                    if not isinstance(rule, dict):
                        continue
                    operator = rule.get("operator", "") or rule.get("op", "")
                    target   = rule.get("targetValue", rule.get("target_value", 0))
                    target_left  = rule.get("targetValueLeft")
                    target_right = rule.get("targetValueRight")
                    if not operator or operator in ("None", "none", ""):
                        continue
                    raw_color = (
                        rule.get("colorScheme")              or
                        rule.get("color")                    or
                        rule.get("fontColor")                or
                        rule.get("font_color")               or
                        rule.get("textColor")                or
                        (rule.get("colorScheme", {}) or {}).get("value") or
                        (rule.get("style", {}) or {}).get("color") or
                        None
                    )
                    color = resolve_color(raw_color)
                    if not color:
                        print(f"DEBUG bignum {chart_id}: UNRESOLVED colorScheme={raw_color!r} (rule dropped)", flush=True)
                        continue
                    # Superset writes ≥ ≤ = ≠ (and ranges like "≤ x ≤"); the app compares
                    # with >= <= == !=, so normalise here. Range operators pass through.
                    operator = {"≥": ">=", "≤": "<=", "=": "==", "≠": "!="}.get(
                        str(operator).strip(), str(operator).strip())
                    conditional_colors.append({
                        "operator":         operator,
                        "targetValue":      target,
                        "targetValueLeft":  target_left,
                        "targetValueRight": target_right,
                        "color":            color,
                    })

                direct_color = (
                    form_data.get("font_color") or
                    form_data.get("fontColor")  or
                    form_data.get("color")      or
                    None
                )
                if direct_color:
                    font_color = resolve_color(direct_color)

                print(
                    f"DEBUG bignum {chart_id}: "
                    f"conditional_colors={conditional_colors} "
                    f"font_color={font_color}",
                    flush=True
                )

            chart_cfg       = chart_configuration.get(str(chart_id), {})
            cf_scope_obj    = chart_cfg.get("crossFilters", {}).get("scope")
            charts_in_scope = None

            if cf_scope_obj is not None:
                if cf_scope_obj == "global":
                    global_cfg  = json_metadata.get("global_chart_configuration", {})
                    global_scope = global_cfg.get("scope") if global_cfg else None
                    if global_scope:
                        resolved = resolve_scope(global_scope)
                        if resolved is not None:
                            charts_in_scope = [cid for cid in resolved if cid != chart_id]
                    else:
                        charts_in_scope = []
                else:
                    resolved = resolve_scope(cf_scope_obj)
                    if resolved is not None:
                        charts_in_scope = [cid for cid in resolved if cid != chart_id]
                    else:
                        charts_in_scope = []

            print(f"DEBUG chart {chart_id}: chartsInScope = {charts_in_scope}", flush=True)
            print(f"DEBUG chart {chart_id}: cross_filter_scope = {charts_in_scope}", flush=True)
            print(f"DEBUG chart {chart_id}: cross_filter chartsInScope = {charts_in_scope}", flush=True)

            chart_list.append({
                "slice_id":               chart_id,
                "slice_name":             detail.get("slice_name"),
                "viz_type":               viz_type,
                "x_axis":                 x_axis,
                "metrics":                metrics,
                "groupby":                groupby,
                "groupby_rows":           groupby_rows,
                "groupby_cols":           groupby_cols,
                "raw_x_axis_column":      raw_x_axis_column,
                "x_axis_is_temporal":     x_axis_is_temporal,
                "zoomable":               bool(form_data.get("zoomable", False)),
                "font_color":             font_color,
                "conditional_colors":     conditional_colors,
                "conditional_formatting": conditional_formatting,
                "column_order":           column_order,
                "show_cell_bars":         show_cell_bars,
                "cross_filter_scope":     charts_in_scope,
                "percentage_threshold":   percentage_threshold,
                "other_threshold":        other_threshold,
                "series_colors": superset_label_colors,
                "series_types":           series_types,
            })

            print(f"DEBUG chart {chart_id}: zoomable = {form_data.get('zoomable')} | viz = {viz_type}", flush=True)

            if 'bar' in viz_type.lower():
                print(f"DEBUG chart {chart_id} bar form_data keys: {list(form_data.keys())}", flush=True)

        return jsonify({"success": True, "charts": chart_list}), 200

    except Exception as e:
        print(f"DEBUG: get_dashboard_charts error: {e}", flush=True)
        return jsonify({"error": str(e)}), 500


# ═════════════════════════════════════════════════════════════════════════════
# CHART DATA — shared query builder + full / paginated / export endpoints
# (v2 — matches the real app.py: uses superset_request / superset_get_result,
#  keeps each chart's own row_limit and force=False for /api/chart-data)
#
#   /api/chart-data        → same behaviour as your previous version
#   /api/chart-data-page   → NEW (GET with query params, POST also accepted):
#                            one page of a flat table — pagination, search and
#                            sort run in Postgres via Superset
#   /api/chart-data-export → NEW (GET/POST): full table as .xlsx (falls back to
#                            .csv), generated by Superset, streamed to the browser
#
# Optional: `pip install flask-compress` (+ add to requirements.txt) to gzip
# JSON responses.
# ═════════════════════════════════════════════════════════════════════════════
import copy
import hashlib
import uuid
import zlib
from flask import Response

try:
    from flask_compress import Compress
    Compress(app)
    print("DEBUG: flask-compress enabled (gzip responses)", flush=True)
except ImportError:
    print("DEBUG: flask-compress not installed - responses are not gzipped", flush=True)


DEFAULT_CHART_ROW_LIMIT = 10000   # used only when a chart has no row_limit of its own
TABLE_MAX_ROWS          = 100000  # ceiling for the row count and for Excel export
SERVER_PAGE_MAX_SIZE    = 500     # hard cap on rows per page request
SEARCH_MAX_LEN          = 100

_VALID_FILTER_OPS = {
    "IN", "NOT IN", "==", "!=", ">", "<", ">=", "<=",
    "LIKE", "ILIKE", "IS NULL", "IS NOT NULL", "TEMPORAL_RANGE",
}


class ChartQueryError(Exception):
    def __init__(self, message, status=500):
        super().__init__(message)
        self.status = status


# ═════════════════════════════════════════════════════════════════════════════
# CHART DATA CACHE — server side, per login session (Redis)
#
#   First time a chart is shown in a login session → built from Superset and
#   stored here. Every later request for the SAME chart with the SAME
#   filters/dates/page (tab switch, revisiting a dashboard) is answered
#   straight from Redis — no Superset call, no database query.
#
#   Key:  speegile:chartdata:<tenant_schema>:<login id>:<hash of the request>
#
#   Cleared when:
#     • the user logs out                 → only that login's entries
#     • a file upload finishes            → every entry of that tenant (new data)
#     • /api/clear-cache is called        → every entry of that tenant
#     • CHART_DATA_CACHE_TTL expires      → safety net (default 1 hour = session life)
#   A new login gets a new login id, so it always starts with fresh data.
#
#   Entries are zlib-compressed (~10x smaller); a response bigger than
#   CHART_DATA_CACHE_MAX_KB after compression is served but not stored, so a
#   single huge result can never fill Redis.
# ═════════════════════════════════════════════════════════════════════════════
CHART_CACHE_PREFIX      = "speegile:chartdata:"
CHART_DATA_CACHE_TTL    = int(os.getenv("CHART_DATA_CACHE_TTL", "3600"))
CHART_DATA_CACHE_MAX_KB = int(os.getenv("CHART_DATA_CACHE_MAX_KB", "2048"))
_chart_cache_redis      = _meta_redis   # the shared Redis client defined with the Superset helpers


def new_data_cache_id():
    """Called at login: a fresh id, so each login starts with an empty cache."""
    return uuid.uuid4().hex


def _session_cache_id():
    # Sessions created before this deploy have no id yet → give them one.
    cid = session.get("data_cache_id")
    if not cid:
        cid = new_data_cache_id()
        session["data_cache_id"] = cid
    return cid


def _chart_cache_key(namespace, body):
    tenant = session.get("tenant_schema") or "_"
    normalised = json.dumps(body, sort_keys=True, default=str, separators=(",", ":"))
    digest = hashlib.sha256(f"{namespace}|{normalised}".encode("utf-8")).hexdigest()
    return f"{CHART_CACHE_PREFIX}{tenant}:{_session_cache_id()}:{digest}"


def _delete_by_pattern(pattern):
    deleted = 0
    pipe = _chart_cache_redis.pipeline(transaction=False)
    for key in _chart_cache_redis.scan_iter(pattern, count=1000):
        pipe.unlink(key)
        deleted += 1
        if deleted % 1000 == 0:
            pipe.execute()
    pipe.execute()
    return deleted


def clear_chart_data_cache(tenant_schema=None):
    """All cached chart data of one tenant (after an upload), or of everyone."""
    try:
        pattern = f"{CHART_CACHE_PREFIX}{tenant_schema}:*" if tenant_schema else f"{CHART_CACHE_PREFIX}*"
        return _delete_by_pattern(pattern)
    except Exception as e:
        print(f"DEBUG: chart data cache clear failed: {e}", flush=True)
        return 0


def clear_session_chart_cache():
    """Cached chart data of the current login only (at logout)."""
    cid = session.get("data_cache_id")
    if not cid:
        return 0
    try:
        tenant = session.get("tenant_schema") or "_"
        return _delete_by_pattern(f"{CHART_CACHE_PREFIX}{tenant}:{cid}:*")
    except Exception as e:
        print(f"DEBUG: session chart cache clear failed: {e}", flush=True)
        return 0


def _serve_with_chart_cache(namespace, body, compute):
    """
    Return the cached response for this exact request if there is one;
    otherwise run compute() -> (payload_dict, status), store successful
    results, and return them. Redis problems never break a chart: on any
    cache error the chart is simply built normally.
    """
    key = None
    try:
        key = _chart_cache_key(namespace, body)
        hit = _chart_cache_redis.get(key)
        if hit:
            print(f"DEBUG chart cache HIT  {namespace} slice={body.get('sliceId')}", flush=True)
            return Response(zlib.decompress(hit), mimetype="application/json",
                            headers={"X-Chart-Cache": "HIT"})
    except Exception as e:
        print(f"DEBUG chart cache read failed ({namespace}): {e}", flush=True)

    payload, status = compute()
    if status != 200 or not isinstance(payload, dict) or not payload.get("success"):
        return jsonify(payload), status

    raw = json.dumps(payload, separators=(",", ":"), default=str).encode("utf-8")
    if key:
        try:
            packed = zlib.compress(raw, 6)
            if len(packed) <= CHART_DATA_CACHE_MAX_KB * 1024:
                _chart_cache_redis.setex(key, CHART_DATA_CACHE_TTL, packed)
                print(f"DEBUG chart cache MISS {namespace} slice={body.get('sliceId')} "
                      f"stored {len(packed) // 1024} KB", flush=True)
            else:
                print(f"DEBUG chart cache SKIP {namespace} slice={body.get('sliceId')} "
                      f"({len(packed) // 1024} KB compressed > {CHART_DATA_CACHE_MAX_KB} KB limit)", flush=True)
        except Exception as e:
            print(f"DEBUG chart cache write failed ({namespace}): {e}", flush=True)

    return Response(raw, mimetype="application/json", headers={"X-Chart-Cache": "MISS"})


# ── Helpers moved out of get_chart_data() so all three endpoints share them ──

def _normalise_filter(f):
    col = str(f.get("col", "")).strip()
    op  = str(f.get("op", "IN")).upper().strip()
    val = f.get("val")
    if not col:
        return None
    if op not in _VALID_FILTER_OPS:
        op = "IN"
    if not isinstance(val, list):
        val = [val]

    flat = []
    for v in val:
        if isinstance(v, list):
            flat.extend(v)
        else:
            flat.append(v)
    val = flat

    val = [v for v in val if v is not None and v != ""]
    if not val and op not in ("IS NULL", "IS NOT NULL"):
        return None
    return {"col": col, "op": op, "val": val}


def _resolve_col(col, query):
    candidates = set()
    for c in query.get("columns", []):
        if isinstance(c, str):
            candidates.add(c)
        elif isinstance(c, dict):
            name = (
                c.get("column_name") or
                c.get("label") or
                c.get("sqlExpression") or ""
            )
            if name:
                candidates.add(name)
    for f in query.get("filters", []):
        if f.get("col"):
            candidates.add(f["col"])

    if col in candidates:
        return col

    col_lower = col.lower()
    for candidate in candidates:
        if candidate.lower() == col_lower:
            print(f"DEBUG: Resolved column '{col}' -> '{candidate}' (case-insensitive match)", flush=True)
            return candidate

    IS_COLUMN_NAME = re.compile(r'^\w+$')

    if not IS_COLUMN_NAME.match(col):
        already_filtered = {
            f.get("col", "").lower()
            for f in query.get("filters", [])
            if f.get("col")
        }
        DATE_KEY_PATTERN = re.compile(r'date|time|key|offset|full|month', re.IGNORECASE)
        spare_dims = [
            c for c in candidates
            if not DATE_KEY_PATTERN.search(c)
            and c.lower() not in already_filtered
        ]
        if len(spare_dims) == 1:
            print(
                f"DEBUG: Mapping series value '{col}' -> dimension col "
                f"'{spare_dims[0]}' (smart fallback). Available: {candidates}",
                flush=True
            )
            return spare_dims[0]

    has_inner_uppercase = any(c.isupper() for c in col[1:]) if len(col) > 1 else False
    if has_inner_uppercase:
        print(f"DEBUG: No match for '{col}' (camelCase). Available: {candidates}. Returning original.", flush=True)
    else:
        print(f"DEBUG: No match for '{col}' (not in query columns). Available: {candidates}. Keeping original case for extra_form_data.", flush=True)
    return col


def _merge_query_results(all_results):
    def find_dim_col(rows_sample):
        if not rows_sample:
            return None
        for k, v in rows_sample[0].items():
            try:
                float(v)
            except (TypeError, ValueError):
                return k
        return list(rows_sample[0].keys())[0]

    merged    = {}
    dim_col   = None
    col_order = []

    for query_rows in all_results:
        if not query_rows:
            continue
        qd = find_dim_col(query_rows)
        if dim_col is None:
            dim_col = qd
            col_order.append(dim_col)
        for row in query_rows:
            dim_val = row.get(dim_col) or row.get(qd)
            key     = str(dim_val)
            if key not in merged:
                merged[key] = {dim_col: dim_val}
            for col, val in row.items():
                if col == dim_col or col == qd:
                    continue
                merged[key][col] = val
                if col not in col_order:
                    col_order.append(col)

    return list(merged.values()), col_order


def _detect_temporal_col(query):
    DATE_PATTERN = re.compile(
        r'date|time|month|day|year|period|sale_dt|invoice_dt|regd', re.IGNORECASE
    )
    for f in query.get("filters", []):
        if f.get("op") == "TEMPORAL_RANGE" and f.get("col"):
            col = f["col"]
            if DATE_PATTERN.search(col) or col == "__time":
                return col

    for f in query.get("adhoc_filters", []):
        if f.get("operator") == "TEMPORAL_RANGE" and f.get("subject"):
            return f["subject"]

    DATE_PATTERN = re.compile(
        r'date|time|month|day|year|period|sale_dt|invoice_dt', re.IGNORECASE
    )
    for c in query.get("columns", []):
        name = c if isinstance(c, str) else (c.get("column_name") or "")
        if name and DATE_PATTERN.search(name):
            return name
    return None


def _post_chart_data(access_token, query_context, timeout):
    """POST /api/v1/chart/data through the shared pooled session (retries once on 401)."""
    return superset_request(
        "POST", "/api/v1/chart/data", access_token,
        headers={"Content-Type": "application/json"},
        json=query_context,
        timeout=timeout,
    )


def _build_chart_query_context(body):
    """
    Everything get_chart_data() used to do BEFORE calling Superset:
    load the chart's saved query_context (from the Redis meta cache), then
    apply native filters, cross filters and the dashboard date range.

    Returns (query_context, chart_viz_type, access_token).
    query_context is None when the chart has no datasource.
    Does NOT touch row_limit — each endpoint sets its own.
    """
    slice_id       = body.get("sliceId")
    date_from      = body.get("dateFrom")
    date_to        = body.get("dateTo")
    time_filter_id = body.get("timeFilterId")
    active_filters = body.get("activeFilters", []) or []
    cross_filters  = body.get("crossFilters",  []) or []

    print(f"INCOMING: sliceId={slice_id} dateFrom={date_from} dateTo={date_to} timeFilterId={time_filter_id}", flush=True)

    if not slice_id:
        raise ChartQueryError("sliceId is required", 400)

    incoming_filters = []
    for f in (active_filters + cross_filters):
        nf = _normalise_filter(f)
        if nf:
            incoming_filters.append(nf)
    print(f"DEBUG chart {slice_id}: incoming_filters = {incoming_filters}", flush=True)

    access_token = get_superset_access_token()
    _, chart_result = superset_get_result(f"/api/v1/chart/{slice_id}", access_token)
    chart_result = chart_result or {}
    raw_context  = chart_result.get("query_context")
    params       = {}

    if not raw_context:
        try:
            params = json.loads(chart_result.get("params", "{}"))
        except Exception:
            pass

        datasource_id   = chart_result.get("datasource_id")
        datasource_type = chart_result.get("datasource_type", "table")
        if not datasource_id:
            return None, "", access_token

        all_metrics  = params.get("metrics", [])
        time_col     = params.get("x_axis") or params.get("granularity_sqla") or ""
        groupby_cols = params.get("groupby", [])
        time_range   = params.get("time_range", "No filter")
        time_grain   = params.get("time_grain_sqla", "P1M")

        all_columns = []
        if time_col:
            all_columns.append(time_col)
        for col in groupby_cols:
            if col and col not in all_columns:
                all_columns.append(col)

        query_context = {
            "datasource": {"id": datasource_id, "type": datasource_type},
            "force": False,
            "queries": [{
                "filters": [],
                "extras": {"having": "", "where": "", "time_grain_sqla": time_grain},
                "applied_time_extras": {},
                "columns":    all_columns,
                "metrics":    all_metrics,
                "orderby":    [],
                "time_range": time_range,
                "row_limit":  params.get("row_limit", DEFAULT_CHART_ROW_LIMIT),
                "annotation_layers": [],
            }],
            "result_format": "json",
            "result_type":   "results"
        }
    else:
        query_context = json.loads(raw_context)

    chart_viz_type = (
        chart_result.get("viz_type")
        or (chart_result.get("form_data") or {}).get("viz_type")
        or params.get("viz_type")
        or ""
    )

    # Let Superset serve cached results; filters and dates are part of its cache key.
    query_context["force"] = False

    # ── Native + cross filters ───────────────────────────────────────────────
    if incoming_filters:
        for query in query_context.get("queries", []):
            resolved_filters = [
                {**f, "col": _resolve_col(f["col"], query)} for f in incoming_filters
            ]

            merged = {}
            for f in resolved_filters:
                key = (f["col"], f["op"])
                if f["op"] == "IN" and key in merged:
                    existing_vals = merged[key]["val"] if isinstance(merged[key]["val"], list) else [merged[key]["val"]]
                    new_vals      = f["val"] if isinstance(f["val"], list) else [f["val"]]
                    merged[key]["val"] = list(dict.fromkeys(existing_vals + new_vals))
                else:
                    merged[key] = dict(f)
            resolved_filters = list(merged.values())
            print(f"DEBUG chart {slice_id}: resolved_filters after merge = {resolved_filters}", flush=True)

            override_cols = {f["col"] for f in resolved_filters}
            existing = [f for f in query.get("filters", []) if f.get("col") not in override_cols]
            query["filters"] = existing + resolved_filters

            for f in resolved_filters:
                col  = f["col"]
                op   = f.get("op", "IN")
                vals = f["val"] if isinstance(f["val"], list) else [f["val"]]
                if op == "IN" and vals:
                    query.setdefault("adhoc_filters", []).append({
                        "expressionType":   "SIMPLE",
                        "subject":          col,
                        "operator":         "IN",
                        "comparator":       vals,
                        "clause":           "WHERE",
                        "filterOptionName": f"cross_filter_{col.replace(' ', '_')}",
                        "isExtra":          True,
                    })
                    form_data = query_context.get("form_data") or {}
                    query_context["form_data"] = form_data
                    ef         = form_data.setdefault("extra_form_data", {})
                    ef_filters = ef.setdefault("filters", [])
                    ef_filters[:] = [x for x in ef_filters if x.get("col") != col]
                    ef_filters.append({"col": col, "op": "IN", "val": vals})
                    print(f"DEBUG chart {slice_id}: extra_form_data filter -> col={col} val={vals}", flush=True)

            print(f"DEBUG chart {slice_id}: adhoc_filters = {query.get('adhoc_filters', [])}", flush=True)

    # ── Dashboard date range ─────────────────────────────────────────────────
    if date_from and date_to and time_filter_id:
        d_from = datetime.strptime(date_from, "%Y-%m-%d")
        d_to   = datetime.strptime(date_to,   "%Y-%m-%d") + timedelta(days=1)
        date_range_val = f"{d_from.strftime('%Y-%m-%d')} : {d_to.strftime('%Y-%m-%d')}"

        for query in query_context.get("queries", []):
            updated = False
            for f in query.get("filters", []):
                if f.get("op") == "TEMPORAL_RANGE":
                    f["val"] = date_range_val
                    updated = True
                    break
            if not updated:
                temporal_col = _detect_temporal_col(query)
                if temporal_col:
                    query.setdefault("filters", []).append({
                        "col": temporal_col,
                        "op":  "TEMPORAL_RANGE",
                        "val": date_range_val,
                    })
            query["applied_time_extras"] = {}

        print(f"DEBUG: date range applied -> {date_range_val}", flush=True)
        print(
            f"DEBUG chart {slice_id}: native date filter applied -> "
            f"id={time_filter_id} value={d_from.strftime('%Y-%m-%d')} : {d_to.strftime('%Y-%m-%d')}",
            flush=True
        )

    return query_context, chart_viz_type, access_token


# ═════════════════════════════════════════════════════════════════════════════
# /api/chart-data  — full result (all non-table charts + pivot tables)
# Same behaviour as your previous version: each chart keeps its own row_limit
# (10000 only when missing), Superset cache allowed (force=False).
# ═════════════════════════════════════════════════════════════════════════════
@app.route("/api/chart-data", methods=["POST"])
@login_required
def get_chart_data():
    body = request.get_json(force=True, silent=True) or {}
    return _serve_with_chart_cache("chart-data", body, lambda: _compute_chart_data(body))


def _compute_chart_data(body):
    slice_id = body.get("sliceId")

    try:
        query_context, _viz, access_token = _build_chart_query_context(body)
        if query_context is None:
            return ({"success": True, "data": [], "reason": "No datasource"}), 200

        # Keep each chart's own row_limit (set in Superset); only fill it when missing.
        for q in query_context.get("queries", []):
            if not q.get("row_limit"):
                q["row_limit"] = DEFAULT_CHART_ROW_LIMIT

        data_resp = _post_chart_data(access_token, query_context, timeout=30)
        print(f"DEBUG chart {slice_id}: Superset response status = {data_resp.status_code}", flush=True)
        if data_resp.status_code != 200:
            # Report the failure instead of returning an empty chart, so a
            # temporary Superset error is never stored in the chart cache.
            return {"error": f"Superset error: {_superset_error_text(data_resp)}"}, 502

        result      = data_resp.json()
        all_results = result.get("result", [])

        if not all_results:
            rows, colnames, coltypes = [], [], []

        elif len(all_results) == 1:
            first_result = all_results[0]
            rows     = first_result.get("data", [])
            colnames = first_result.get("colnames") or (list(rows[0].keys()) if rows else [])
            coltypes = first_result.get("coltypes", [])

        else:
            viz = (query_context.get("form_data", {}) or {}).get("viz_type", "")
            is_table_viz = "table" in str(viz).lower() or "pivot" in str(viz).lower()

            if is_table_viz:
                best     = max(all_results, key=lambda r: len(r.get("data", [])))
                rows     = best.get("data", [])
                colnames = best.get("colnames") or (list(rows[0].keys()) if rows else [])
                coltypes = best.get("coltypes", [])

                summary_row = None
                for r in all_results:
                    if r is best:
                        continue
                    r_data = r.get("data", [])
                    if len(r_data) == 1:
                        summary_row = r_data[0]
                        break

                if summary_row:
                    rows = list(rows) + [{"__summary__": True, **summary_row}]
                    print(f"DEBUG chart {slice_id}: summary row added -> {summary_row}", flush=True)

                print(f"DEBUG chart {slice_id}: table chart - using best of {len(all_results)} queries -> {len(rows)} rows", flush=True)
            else:
                print(f"DEBUG chart {slice_id}: mixed chart with {len(all_results)} queries - merging", flush=True)
                rows, colnames = _merge_query_results([r.get("data", []) for r in all_results])
                coltypes = []

        print(f"DEBUG chart {slice_id}: rows returned = {len(rows)}", flush=True)

        return ({
            "success":  True,
            "data":     rows,
            "colnames": colnames,
            "coltypes": coltypes,
        }), 200

    except ChartQueryError as e:
        return ({"error": str(e)}), e.status
    except Exception as e:
        print(f"DEBUG chart {slice_id} ERROR: {e}", flush=True)
        import traceback
        traceback.print_exc()
        return ({"error": str(e)}), 500


# ═════════════════════════════════════════════════════════════════════════════
# Server-side pagination helpers
# ═════════════════════════════════════════════════════════════════════════════

def _label_of(item):
    """Label for a column/metric that may be a plain string or an adhoc dict."""
    if isinstance(item, str):
        return item
    if isinstance(item, dict):
        return (item.get("label") or item.get("column_name")
                or item.get("metric_name") or item.get("sqlExpression") or "")
    return ""


def _split_table_queries(query_context):
    """
    A Superset table chart's query_context can hold:
      - the main query (columns + metrics)
      - a totals query (no columns, only metrics) when "Show totals" is on
      - a rowcount query (is_rowcount) when Superset's own server pagination is on
    Returns (main_query, totals_query_or_None). Rowcount queries are dropped —
    we build our own.
    """
    queries = [q for q in query_context.get("queries", []) if not q.get("is_rowcount")]
    if not queries:
        raise ChartQueryError("Chart has no queries", 400)

    main = next((q for q in queries if q.get("columns")), queries[0])
    totals = next(
        (q for q in queries if q is not main and not q.get("columns") and q.get("metrics")),
        None,
    )
    return main, totals


def _apply_sort(query, sort_col, sort_dir):
    """Sort by a metric or column that already exists in the query.
    Unknown names are ignored — client-sent names never go into SQL directly."""
    if not sort_col or sort_dir not in ("asc", "desc"):
        return
    ascending = sort_dir == "asc"
    for m in query.get("metrics") or []:
        if _label_of(m) == sort_col:
            query["orderby"] = [[m, ascending]]
            return
    for c in query.get("columns") or []:
        if _label_of(c) == sort_col:
            query["orderby"] = [[c, ascending]]
            return
    print(f"DEBUG page: sort column '{sort_col}' not in query - ignored", flush=True)


def _dataset_columns(datasource_id, access_token):
    """{column_name: sql_expression_or_None} for the dataset.
    Read through superset_get_result, so it uses the Redis meta cache.
    Used so search only ever puts real dataset columns into SQL, and uses the
    expression for calculated columns."""
    _, result = superset_get_result(f"/api/v1/dataset/{datasource_id}", access_token)
    out = {}
    for c in (result or {}).get("columns", []) or []:
        name = c.get("column_name")
        if name:
            out[name] = (c.get("expression") or "").strip() or None
    if not out:
        print(f"DEBUG page: dataset {datasource_id} column lookup returned nothing", flush=True)
    return out


def _search_where_clause(query_context, query, search, access_token):
    """
    Builds:  (CAST("col1" AS TEXT) ILIKE '%term%' OR CAST(<expr> AS TEXT) ILIKE '%term%' ...)
    over the dimension columns of the query. Returns None when nothing searchable.
    """
    search = (search or "").strip()[:SEARCH_MAX_LEN]
    if not search:
        return None

    ds_id   = (query_context.get("datasource") or {}).get("id")
    ds_cols = _dataset_columns(ds_id, access_token) if ds_id else {}
    if not ds_cols:
        return None

    # Escape for a Postgres string literal + LIKE wildcards (backslash is LIKE's default escape)
    term = (search.replace("\\", "\\\\")
                  .replace("%", "\\%")
                  .replace("_", "\\_")
                  .replace("'", "''"))

    parts = []
    for c in query.get("columns") or []:
        name = c if isinstance(c, str) else (c.get("column_name") if isinstance(c, dict) else None)
        if not name or name not in ds_cols:
            continue                                    # adhoc/unknown column → skip
        expr = ds_cols[name]
        if expr:
            sql_col = f"({expr})"                       # calculated column
        else:
            quoted  = name.replace('"', '""')
            sql_col = f'"{quoted}"'                     # physical column
        parts.append(f"CAST({sql_col} AS TEXT) ILIKE '%{term}%'")

    if not parts:
        return None
    return "(" + " OR ".join(parts) + ")"


def _add_where(query, clause):
    if not clause:
        return
    extras = query.get("extras") or {}
    query["extras"] = extras
    existing = (extras.get("where") or "").strip()
    extras["where"] = f"({existing}) AND {clause}" if existing else clause


def _extract_rowcount(res):
    data = (res or {}).get("data") or []
    if data and isinstance(data[0], dict):
        row = data[0]
        if "rowcount" in row:
            return int(row["rowcount"] or 0)
        for v in row.values():
            try:
                return int(v)
            except (TypeError, ValueError):
                continue
    return None


def _superset_error_text(resp):
    try:
        j = resp.json()
        return j.get("message") or j.get("errors") or resp.text[:500]
    except Exception:
        return resp.text[:500]


# ═════════════════════════════════════════════════════════════════════════════
# Reading the request — query parameters (GET) or JSON body (POST)
#
# GET /api/chart-data-page?sliceId=42&page=1&pageSize=100&search=nike
#        &sortCol=net_amount&sortDir=desc
#        &dateFrom=2025-04-01&dateTo=2025-09-30&timeFilterId=NATIVE_FILTER-x
#        &activeFilters=[{"col":"centername","op":"IN","val":["Pune"]}]   (URL-encoded JSON)
#        &crossFilters=[]
#
# Filters are lists of objects, so they travel as ONE JSON-encoded parameter
# each. POST with the same fields as a JSON body is still accepted — the
# frontend falls back to it when the URL would get too long.
# ═════════════════════════════════════════════════════════════════════════════
def _json_list_arg(name):
    raw = request.args.get(name)
    if not raw:
        return []
    try:
        value = json.loads(raw)
    except ValueError:
        raise ChartQueryError(f"'{name}' must be a JSON-encoded array", 400)
    if not isinstance(value, list):
        raise ChartQueryError(f"'{name}' must be a JSON-encoded array", 400)
    return value


def _read_chart_request():
    if request.method == "GET":
        a = request.args
        return {
            "sliceId":       a.get("sliceId", type=int),
            "dateFrom":      a.get("dateFrom") or None,
            "dateTo":        a.get("dateTo") or None,
            "timeFilterId":  a.get("timeFilterId") or None,
            "activeFilters": _json_list_arg("activeFilters"),
            "crossFilters":  _json_list_arg("crossFilters"),
            "page":          a.get("page", "0"),
            "pageSize":      a.get("pageSize", "100"),
            "search":        a.get("search", ""),
            "sortCol":       a.get("sortCol") or None,
            "sortDir":       a.get("sortDir") or None,
        }
    return request.get_json(force=True, silent=True) or {}


# ═════════════════════════════════════════════════════════════════════════════
# /api/chart-data-page  — ONE page of a flat table
#
# Response:
#   { success, data: [...rows of this page], colnames, coltypes,
#     total, totalIsEstimate, page, pageSize, summary: {...} | null }
# ═════════════════════════════════════════════════════════════════════════════
@app.route("/api/chart-data-page", methods=["GET", "POST"])
@login_required
def get_chart_data_page():
    try:
        body = _read_chart_request()
    except ChartQueryError as e:
        return jsonify({"error": str(e)}), e.status
    return _serve_with_chart_cache("chart-data-page", body, lambda: _compute_chart_data_page(body))


def _compute_chart_data_page(body):
    slice_id = body.get("sliceId")

    try:
        page      = max(int(body.get("page", 0) or 0), 0)
        page_size = min(max(int(body.get("pageSize", 100) or 100), 1), SERVER_PAGE_MAX_SIZE)
    except (TypeError, ValueError):
        return ({"error": "page and pageSize must be integers"}), 400

    search   = body.get("search") or ""
    sort_col = body.get("sortCol")
    sort_dir = body.get("sortDir")

    try:
        query_context, _viz, access_token = _build_chart_query_context(body)
        if query_context is None:
            return ({"success": True, "data": [], "colnames": [], "coltypes": [],
                            "total": 0, "totalIsEstimate": False, "page": 0,
                            "pageSize": page_size, "summary": None}), 200

        main, totals = _split_table_queries(query_context)

        # Search — same WHERE on the page, the count and the totals,
        # so "N rows" and the totals row both reflect the search.
        where = _search_where_clause(query_context, main, search, access_token)
        _add_where(main, where)
        if totals is not None:
            _add_where(totals, where)

        _apply_sort(main, sort_col, sort_dir)

        count_q = copy.deepcopy(main)
        count_q.update({
            "is_rowcount":     True,
            "row_limit":       TABLE_MAX_ROWS,   # Superset counts inside this limit
            "row_offset":      0,
            "orderby":         [],
            "post_processing": [],
        })

        main["row_limit"]  = page_size
        main["row_offset"] = page * page_size

        query_context["queries"]       = [main, count_q] + ([totals] if totals is not None else [])
        query_context["result_format"] = "json"
        query_context["result_type"]   = "full"

        data_resp = _post_chart_data(access_token, query_context, timeout=60)
        if data_resp.status_code != 200:
            msg = _superset_error_text(data_resp)
            print(f"DEBUG page chart {slice_id}: Superset {data_resp.status_code}: {msg}", flush=True)
            return ({"error": f"Superset error: {msg}"}), 502

        results    = data_resp.json().get("result", []) or []
        page_res   = results[0] if len(results) > 0 else {}
        count_res  = results[1] if len(results) > 1 else {}
        totals_res = results[2] if len(results) > 2 else None

        rows     = page_res.get("data", []) or []
        colnames = page_res.get("colnames") or (list(rows[0].keys()) if rows else [])
        coltypes = page_res.get("coltypes", []) or []

        total = _extract_rowcount(count_res)
        total_is_estimate = False
        if total is None:
            # Fallback: at least this many rows exist; if the page is full,
            # pretend there is one more page so "next" stays enabled.
            total = page * page_size + len(rows) + (page_size if len(rows) == page_size else 0)
            total_is_estimate = True

        summary = None
        if totals_res:
            t_data = totals_res.get("data") or []
            if len(t_data) == 1:
                summary = t_data[0]

        print(f"DEBUG page chart {slice_id}: page={page} size={page_size} rows={len(rows)} "
              f"total={total} search={search!r} sort={sort_col}/{sort_dir}", flush=True)

        return ({
            "success":         True,
            "data":            rows,
            "colnames":        colnames,
            "coltypes":        coltypes,
            "total":           total,
            "totalIsEstimate": total_is_estimate,
            "page":            page,
            "pageSize":        page_size,
            "summary":         summary,
        }), 200

    except ChartQueryError as e:
        return ({"error": str(e)}), e.status
    except Exception as e:
        print(f"DEBUG page chart {slice_id} ERROR: {e}", flush=True)
        import traceback
        traceback.print_exc()
        return ({"error": str(e)}), 500


# ═════════════════════════════════════════════════════════════════════════════
# /api/chart-data-export  — the whole (filtered/searched/sorted) table as a file
# Superset builds the file; Flask only relays the bytes. Tries .xlsx first,
# falls back to .csv on Superset versions without XLSX support.
# ═════════════════════════════════════════════════════════════════════════════
_EXPORT_MIMETYPES = {
    "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "csv":  "text/csv; charset=utf-8",
}


@app.route("/api/chart-data-export", methods=["GET", "POST"])
@login_required
def export_chart_data():
    try:
        body = _read_chart_request()      # same params as /chart-data-page (page/pageSize ignored)
    except ChartQueryError as e:
        return jsonify({"error": str(e)}), e.status
    slice_id = body.get("sliceId")

    try:
        query_context, _viz, access_token = _build_chart_query_context(body)
        if query_context is None:
            return jsonify({"error": "Chart has no datasource"}), 400

        main, _totals = _split_table_queries(query_context)
        _add_where(main, _search_where_clause(query_context, main, body.get("search"), access_token))
        _apply_sort(main, body.get("sortCol"), body.get("sortDir"))
        main["row_limit"]  = TABLE_MAX_ROWS
        main["row_offset"] = 0

        # Only the main query — with several queries Superset returns a .zip
        query_context["queries"]     = [main]
        query_context["result_type"] = "full"

        last_error = "unknown error"
        for fmt in ("xlsx", "csv"):
            query_context["result_format"] = fmt
            resp = _post_chart_data(access_token, query_context, timeout=300)
            if resp.status_code == 200 and resp.content:
                print(f"DEBUG export chart {slice_id}: {fmt}, {len(resp.content)} bytes", flush=True)
                return Response(
                    resp.content,
                    mimetype=_EXPORT_MIMETYPES[fmt],
                    headers={"Content-Disposition": f'attachment; filename="table_{slice_id}.{fmt}"'},
                )
            last_error = _superset_error_text(resp)
            print(f"DEBUG export chart {slice_id}: {fmt} failed ({resp.status_code}): {last_error}", flush=True)

        return jsonify({"error": f"Export failed: {last_error}"}), 502

    except ChartQueryError as e:
        return jsonify({"error": str(e)}), e.status
    except Exception as e:
        print(f"DEBUG export chart {slice_id} ERROR: {e}", flush=True)
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/api/filter-options", methods=["GET"])
@login_required
def get_filter_options():
    dashboard_id = request.args.get("dashboardId")
    if not dashboard_id:
        return jsonify({"error": "dashboardId required"}), 400

    try:
        access_token = get_superset_access_token()

        _, result     = superset_get_result(f"/api/v1/dashboard/{dashboard_id}", access_token)
        result        = result or {}
        json_metadata = result.get("json_metadata", "{}")
        if isinstance(json_metadata, str):
            json_metadata = json.loads(json_metadata)

        native_filters = json_metadata.get("native_filter_configuration", [])

        def get_distinct_values(dataset_id, column_name):
            payload = {
                "datasource": {"id": dataset_id, "type": "table"},
                "force": False,
                "queries": [{
                    "columns":   [column_name],
                    "metrics":   [],
                    "filters":   [],
                    "orderby":   [[column_name, True]],
                    "row_limit": 500,
                    "extras":    {"having": "", "where": ""},
                    "applied_time_extras": {}
                }],
                "result_format": "json",
                "result_type":   "results"
            }
            r    = superset_request(
                "POST", "/api/v1/chart/data", access_token,
                headers={"Content-Type": "application/json"},
                json=payload,
                timeout=15
            )
            rows = r.json().get("result", [{}])[0].get("data", [])
            return [row[column_name] for row in rows if row.get(column_name)]

        def safe_distinct_values(target_key):
            dataset_id, column_name = target_key
            try:
                return get_distinct_values(dataset_id, column_name)
            except Exception as e:
                print(f"DEBUG filter values failed for {column_name}: {e}", flush=True)
                return []

        # Fetch the values for every select filter in parallel instead of one by one.
        select_targets = []
        for native_filter in native_filters:
            if native_filter.get("filterType") in ["filter_select", "filter_groupby"]:
                target = native_filter.get("targets", [{}])[0]
                key    = (target.get("datasetId"), target.get("column", {}).get("name"))
                if key[0] and key[1] and key not in select_targets:
                    select_targets.append(key)

        values_by_target = {}
        if select_targets:
            with ThreadPoolExecutor(max_workers=min(8, len(select_targets))) as pool:
                values_by_target = dict(zip(select_targets, pool.map(safe_distinct_values, select_targets)))

        filter_options = []

        for native_filter in native_filters:
            filter_type = native_filter.get("filterType")
            target      = native_filter.get("targets", [{}])[0]
            col_name    = target.get("column", {}).get("name")
            dataset_id  = target.get("datasetId")

            scope_obj     = native_filter.get("scope", {})
            root_path     = scope_obj.get("rootPath", ["ROOT_ID"])
            tabs_in_scope = native_filter.get("tabsInScope") or []
            if not tabs_in_scope:
                tabs_in_scope = [p for p in root_path if p.startswith("TAB-")]

            print(
                f"DEBUG filter '{native_filter.get('name')}': "
                f"scope={scope_obj}, tabs_in_scope={tabs_in_scope}, "
                f"charts_in_scope={native_filter.get('chartsInScope', [])}",
                flush=True
            )

            if filter_type == "filter_time":
                filter_options.append({
                    "id":            native_filter.get("id"),
                    "name":          native_filter.get("name"),
                    "filterType":    "filter_time",
                    "type":          "date",
                    "column":        col_name or "",
                    "values":        [],
                    "tabsInScope":   tabs_in_scope,
                    "chartsInScope": native_filter.get("chartsInScope", []),
                })

            elif filter_type in ["filter_select", "filter_groupby"]:
                if not col_name or not dataset_id:
                    continue
                values = values_by_target.get((dataset_id, col_name), [])
                filter_options.append({
                    "id":            native_filter.get("id"),
                    "name":          native_filter.get("name"),
                    "type":          "select",
                    "column":        col_name,
                    "values":        values,
                    "tabsInScope":   tabs_in_scope,
                    "chartsInScope": native_filter.get("chartsInScope", []),
                })

        print(f"DEBUG filter_options: {filter_options}", flush=True)
        return jsonify({"success": True, "filters": filter_options}), 200

    except Exception as e:
        print(f"DEBUG filter_options error: {e}", flush=True)
        return jsonify({"error": str(e)}), 500


@app.route("/api/upload_access", methods=["GET"])
@login_required
def check_user_upload_access():
    tenant_schema = session.get("tenant_schema")
    if not tenant_schema:
        return jsonify({"error": "No tenant context"}), 403

    upload_access = session.get("upload_access", 0)
    if upload_access == 1:
        return jsonify({"success": True}), 200
    else:
        return jsonify({"success": False, "error": "You do not have upload access."}), 403


@app.route("/api/dashboard-filters", methods=["GET"])
@login_required
def get_dashboard_filters():
    dashboard_id = request.args.get("dashboardId")
    try:
        access_token = get_superset_access_token()
        _, result     = superset_get_result(f"/api/v1/dashboard/{dashboard_id}", access_token)
        result        = result or {}
        json_metadata = result.get("json_metadata", "{}")
        if isinstance(json_metadata, str):
            json_metadata = json.loads(json_metadata)

        native_filters = json_metadata.get("native_filter_configuration", [])
        filters_out    = []

        for f in native_filters:
            target = f.get("targets", [{}])[0]
            filters_out.append({
                "id":         f.get("id"),
                "name":       f.get("name"),
                "filterType": f.get("filterType"),
                "column":     target.get("column", {}).get("name"),
                "datasetId":  target.get("datasetId"),
            })

        return jsonify({"success": True, "filters": filters_out}), 200

    except Exception as e:
        print(f"DEBUG dashboard-filters error: {e}", flush=True)
        return jsonify({"error": str(e)}), 500


@app.route("/api/dashboard-layout", methods=["GET"])
@login_required
def get_dashboard_layout():
    dashboard_id = request.args.get("dashboardId")
    if not dashboard_id:
        return jsonify({"error": "dashboardId is required"}), 400
    try:
        access_token = get_superset_access_token()
        if not access_token:
            return jsonify({"error": "Superset auth failed"}), 500

        status, result = superset_get_result(f"/api/v1/dashboard/{dashboard_id}", access_token)
        if status != 200:
            return jsonify({"error": f"Superset {status}"}), 502

        result        = result or {}
        position_json = result.get("position_json", "{}")
        if isinstance(position_json, str):
            try:    position_json = json.loads(position_json)
            except: position_json = {}

        return jsonify({"success": True, "layout": position_json}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/debug-dashboard-meta", methods=["GET"])
@login_required
def debug_dashboard_meta():
    dashboard_id = request.args.get("dashboardId")
    access_token = get_superset_access_token()

    # Debug route: always read live from Superset, never from the cache.
    _, result     = superset_get_result(f"/api/v1/dashboard/{dashboard_id}", access_token, cache=False)
    result        = result or {}
    json_metadata = result.get("json_metadata", "{}")
    if isinstance(json_metadata, str):
        json_metadata = json.loads(json_metadata)

    print(f"DEBUG meta keys: {list(json_metadata.keys())}", flush=True)
    print(f"DEBUG native_filter_configuration: {json_metadata.get('native_filter_configuration', 'NOT FOUND')}", flush=True)
    print(f"DEBUG filter_sets_configuration: {json_metadata.get('filter_sets_configuration', 'NOT FOUND')}", flush=True)
    print(f"DEBUG full metadata: {json.dumps(json_metadata, indent=2)}", flush=True)

    return jsonify(json_metadata), 200


@app.route("/api/debug-layout", methods=["GET"])
@login_required
def debug_layout():
    dashboard_id = request.args.get("dashboardId")
    if not dashboard_id:
        return jsonify({"error": "dashboardId required"}), 400

    try:
        access_token = get_superset_access_token()
        if not access_token:
            return jsonify({"error": "Superset auth failed"}), 500

        # Debug route: always read live from Superset, never from the cache.
        _, result     = superset_get_result(f"/api/v1/dashboard/{dashboard_id}", access_token, cache=False)
        result        = result or {}
        position_json = result.get("position_json", "{}")
        if isinstance(position_json, str):
            position_json = json.loads(position_json)

        all_types = list(set(
            v.get("type") for v in position_json.values()
            if isinstance(v, dict) and v.get("type")
        ))

        grid      = position_json.get("GRID_ID") or position_json.get("ROOT_ID") or {}
        grid_kids = grid.get("children", [])

        tabs_info = []
        for k, v in position_json.items():
            if not isinstance(v, dict): continue
            if v.get("type") not in ("TABS", "TABS_V2"): continue

            tabs_list = []
            for tab_id in v.get("children", []):
                tab      = position_json.get(tab_id, {})
                tab_rows = []
                for row_id in tab.get("children", []):
                    row = position_json.get(row_id, {})
                    if row.get("type") != "ROW": continue
                    chart_ids = []
                    for child_id in row.get("children", []):
                        child = position_json.get(child_id, {})
                        if child.get("type") == "CHART":
                            chart_ids.append(child.get("meta", {}).get("chartId"))
                        elif child.get("type") == "COLUMN":
                            for inner_id in child.get("children", []):
                                inner = position_json.get(inner_id, {})
                                if inner.get("type") == "CHART":
                                    chart_ids.append(inner.get("meta", {}).get("chartId"))
                    tab_rows.append({"row_id": row_id, "chart_ids": chart_ids})
                tabs_list.append({
                    "tab_id":   tab_id,
                    "tab_type": tab.get("type"),
                    "name": (
                        tab.get("meta", {}).get("text")
                        or tab.get("meta", {}).get("defaultText")
                        or tab.get("meta", {}).get("tabTextContent")
                        or "(unnamed)"
                    ),
                    "rows": tab_rows,
                })
            tabs_info.append({
                "component_id": k,
                "type":     v.get("type"),
                "in_grid":  k in grid_kids,
                "tabs":     tabs_list,
            })

        standalone_rows = []
        for row_id in grid_kids:
            comp = position_json.get(row_id, {})
            if comp.get("type") != "ROW": continue
            chart_ids = []
            for child_id in comp.get("children", []):
                child = position_json.get(child_id, {})
                if child.get("type") == "CHART":
                    chart_ids.append(child.get("meta", {}).get("chartId"))
            standalone_rows.append({"row_id": row_id, "chart_ids": chart_ids})

        debug = {
            "dashboard_id":     dashboard_id,
            "dashboard_title":  result.get("dashboard_title"),
            "all_types":        sorted(all_types),
            "grid_children":    grid_kids,
            "grid_child_types": [position_json.get(k, {}).get("type") for k in grid_kids],
            "tabs_found":       len(tabs_info),
            "tabs_info":        tabs_info,
            "standalone_rows":  standalone_rows,
            "diagnosis": (
                "TABS found under GRID_ID - parser should work"
                if any(t["in_grid"] for t in tabs_info)
                else "TABS exist but NOT direct children of GRID_ID - parser needs full-scan fallback"
                if tabs_info
                else "No TABS found at all - dashboard has no tabs"
            ),
        }

        print(f"DEBUG debug-layout: {json.dumps(debug, indent=2)[:2000]}", flush=True)
        return jsonify(debug), 200

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route('/api/clear-cache', methods=['POST'])
@login_required
def clear_cache():
    try:
        r       = redis.from_url(os.getenv("REDIS_URL"))
        deleted = 0

        for key in r.scan_iter("superset*"):
            r.delete(key)
            deleted += 1

        deleted += clear_superset_meta_cache()
        deleted += clear_chart_data_cache(session.get("tenant_schema"))

        print(f"DEBUG: Superset cache cleared. {deleted} keys deleted.",
              flush=True)

        return jsonify({
            "success": True,
            "message": f"Cache cleared successfully. {deleted} keys removed.",
            "keys_deleted": deleted,
        }), 200

    except Exception as e:
        print(f"DEBUG: Cache clear failed: {e}", flush=True)
        return jsonify({
            "success": False,
            "error":   str(e),
        }), 500


@app.route("/api/dashboard-cross-filter-scope", methods=["GET"])
@login_required
def get_cross_filter_scope():
    print(f"DEBUG scope endpoint HIT", flush=True)
    dashboard_id = request.args.get("dashboardId")
    if not dashboard_id:
        return jsonify({"error": "dashboardId required"}), 400

    try:
        access_token = get_superset_access_token()
        _, result = superset_get_result(f"/api/v1/dashboard/{dashboard_id}", access_token)
        result    = result or {}

        json_metadata = result.get("json_metadata", "{}")
        position_json = result.get("position_json", "{}")
        if isinstance(json_metadata, str):
            json_metadata = json.loads(json_metadata)
        if isinstance(position_json, str):
            position_json = json.loads(position_json)

        print(f"DEBUG position_json keys: {list(position_json.keys())[:30]}", flush=True)
        print(f"DEBUG chart_configuration: {json_metadata.get('chart_configuration', {})}", flush=True)
        print(f"DEBUG global_chart_config: {json_metadata.get('global_chart_configuration', {})}", flush=True)

        cross_filters_enabled = json_metadata.get("cross_filters_enabled", False)
        if not cross_filters_enabled:
            return jsonify({"enabled": False, "scope": {}}), 200

        chart_configuration    = json_metadata.get("chart_configuration", {})
        global_chart_config    = json_metadata.get("global_chart_configuration", {})

        def collect_chart_ids_under(node_id, layout):
            found = []
            node = layout.get(node_id)
            if node is None:
                if node_id in ("ROOT_ID", "GRID_ID"):
                    for key, val in layout.items():
                        if isinstance(val, dict) and val.get("type") == "CHART":
                            chart_id = val.get("meta", {}).get("chartId")
                            if chart_id:
                                found.append(int(chart_id))
                return found
            if node.get("type") == "CHART":
                chart_id = node.get("meta", {}).get("chartId")
                if chart_id:
                    found.append(int(chart_id))
            for child_id in node.get("children", []):
                found.extend(collect_chart_ids_under(child_id, layout))
            return found

        def resolve_scope(scope_obj, layout):
            if not scope_obj or not isinstance(scope_obj, dict):
                return None
            root_path = scope_obj.get("rootPath", [])
            excluded  = [int(x) for x in scope_obj.get("excluded", [])]
            if not root_path:
                root_path = ["ROOT_ID"]
            in_scope = []
            for root_node_id in root_path:
                in_scope.extend(collect_chart_ids_under(root_node_id, layout))
            in_scope = [cid for cid in set(in_scope) if cid not in excluded]
            print(f"DEBUG resolve_scope: rootPath={root_path}, result={in_scope}", flush=True)
            return in_scope

        global_scope_obj = global_chart_config.get("scope") if global_chart_config else None
        global_resolved  = resolve_scope(global_scope_obj, position_json)

        scope_map = {}
        for chart_id_str, config in chart_configuration.items():
            chart_id   = int(chart_id_str)
            cf_config  = config.get("crossFilters", {})
            scope_val  = cf_config.get("scope")

            if scope_val is None:
                scope_map[chart_id] = []

            elif scope_val == "global":
                if global_resolved is not None:
                    scope_map[chart_id] = [cid for cid in global_resolved if cid != chart_id]
                else:
                    scope_map[chart_id] = []

            else:
                resolved = resolve_scope(scope_val, position_json)
                if resolved is not None:
                    scope_map[chart_id] = [cid for cid in resolved if cid != chart_id]
                else:
                    scope_map[chart_id] = []

        return jsonify({"enabled": True, "scope": scope_map}), 200

    except Exception as e:
        print(f"ERROR get_cross_filter_scope: {e}", flush=True)
        return jsonify({"error": str(e)}), 500



if __name__ == '__main__':
    app.run(host="0.0.0.0", port=5000, debug=True)