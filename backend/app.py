import os as _os
from flask import Flask, request, jsonify, session
from flask_cors import CORS
import jwt
import time
import os
import requests
import json
import boto3
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

# -------------------- ENV loading & expansion --------------------
# finds evaluates full path of current file and cd..'s to 2 level up
ROOT = Path(__file__).resolve().parents[1]
DOTENV = ROOT / ".env"
if DOTENV.exists():
    # override = false means, Do NOT overwrite existing environment variables.
    # only set variables that are not already defined
    load_dotenv(dotenv_path=str(DOTENV), override=False)
else:
    load_dotenv(override=False)

# returns None if unset
raw_db = os.getenv("APP_DATABASE_URL")
if raw_db:
    # replace say ${User} with john
    os.environ["APP_DATABASE_URL"] = _os.path.expandvars(raw_db)

REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
# Superset / DB config
SUPERSET_ADMIN_USERNAME = os.getenv("SUPERSET_ADMIN_USERNAME")
SUPERSET_ADMIN_PASSWORD = os.getenv("SUPERSET_ADMIN_PASSWORD")
SUPERSET_URL = os.getenv("SUPERSET_URL")
DATABASE_URL = os.getenv("APP_DATABASE_URL")
GUEST_TOKEN_JWT_SECRET = os.getenv("GUEST_TOKEN_JWT_SECRET")

#Creates a Flask application object
app = Flask(__name__)

# this should be immutable once set, keep it safe. The Flask secret key signs and protects all session/auth data
flask_secret = os.getenv("FLASK_SECRET_KEY") or os.getenv("SECRET_KEY") or "dev_fallback_secret_please_change"
app.secret_key = flask_secret

print("======================================================================")
print(f"Flask App Initialized with REDIS Session Storage.")
print("======================================================================")

#configures how Flask sessions are stored, secured, scoped, and expired.
# server side configuration using redis
app.config.update(
    SESSION_TYPE='redis',
    SESSION_REDIS=redis.from_url(REDIS_URL),
    SESSION_COOKIE_NAME='flask_session',
    SESSION_COOKIE_HTTPONLY=True,
    # SESSION_COOKIE_SAMESITE='LAX',
    SESSION_COOKIE_SAMESITE='None',
    # SESSION_COOKIE_SECURE=False,
    SESSION_COOKIE_SECURE=True,
    PERMANENT_SESSION_LIFETIME=timedelta(hours=1),
    SESSION_PERMANENT=False,
    SESSION_COOKIE_DOMAIN=None
)
# applies the app config for our sessions
Session(app)

raw_origins = os.getenv("CORS_ALLOW_ORIGINS", "http://localhost:3000,https://frontend-ao4w.onrender.com")
CORS_ORIGINS = [o.strip() for o in raw_origins.split(",") if o.strip()]
# allow selected websites to connect to, https methods, headers
CORS(app,
     resources={r"/*": {
         "origins": CORS_ORIGINS,
         "supports_credentials": True,
         "allow_headers": ["Content-Type", "Authorization"],
         "expose_headers": ["Set-Cookie"],
         "methods": ["GET", "POST", "OPTIONS"],
         "allow_credentials": True
     }},
     supports_credentials=True
)

# CORS(
#     app,
#     supports_credentials=True,
#     resources={
#         r"/api/*": {
#             "origins": [
#                 "http://localhost:3000",
#                 "http://127.0.0.1:3000",
#                 "https://frontend-ao4w.onrender.com"
#             ],
#             "methods": ["GET", "POST", "OPTIONS"],
#             "allow_headers": ["Content-Type", "Authorization"],
#             "expose_headers": ["Set-Cookie"],
#         }
#     }
# )

S3_BUCKET = os.getenv("S3_BUCKET_NAME", "client-analytics-data-storage")
# s3 client object
s3_client = boto3.client(
    's3',
    aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID"),
    aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY"),
    region_name=os.getenv("AWS_REGION", "us-east-1")
)

# ---------------------------------------------------------
# DATABASE ENGINE (Critical for Login & Upload)
# ---------------------------------------------------------
engine = None
if DATABASE_URL:
    try:
        # This does NOT connect to the database yet
        engine = create_engine(DATABASE_URL)
        print("✓ Database engine created successfully")
    except Exception as e:
        print(f"🚨 DATABASE CONNECTION FAILED: {e}")
        engine = None

ALLOWED_EXTENSIONS = {'xlsx'}
def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

# ---------------------------------------------------------
# REMOVED HARDCODED USERS DICTIONARY
# ---------------------------------------------------------

# Helper to get superset token
def get_superset_access_token():
    try:
        response = requests.post(
            f"{SUPERSET_URL}/api/v1/security/login",
            json={
                "password": SUPERSET_ADMIN_PASSWORD,
                "provider": "db",
                "refresh": True,
                "username": SUPERSET_ADMIN_USERNAME
            },
            timeout=10
        )
        if response.status_code == 200:
            return response.json().get("access_token")
        return None
    except Exception as e:
        print(f"✗ Error getting Superset token: {e}")
        return None

# Helper to get dashboards
def get_all_dashboards_from_superset(access_token):
    try:
        query = {"page": 0, "page_size": 100}
        response = requests.get(
            f"{SUPERSET_URL}/api/v1/dashboard/",
            params={"q": json.dumps(query)},
            headers={"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"},
            timeout=10
        )
        if response.status_code == 200:
            return response.json().get("result", [])
        return []
    except Exception as e:
        return []

# Helper to filter dashboards
def filter_dashboards_by_user_roles(dashboards, user_roles):
    if not user_roles: return []
    user_role_names_lower = [role.lower() for role in user_roles]
    
    # Admin bypass
    if 'admin' in user_role_names_lower:
        return dashboards
    
    filtered = []
    for dashboard in dashboards:
        dashboard_roles = dashboard.get('roles', [])
        # Public dashboards
        if not dashboard_roles:
            filtered.append(dashboard)
            continue
        
        # Check roles
        dashboard_role_names = [role['name'].lower() for role in dashboard_roles]
        if any(role in dashboard_role_names for role in user_role_names_lower):
            filtered.append(dashboard)
    
    return filtered

# Helper to get embedded UUID
def get_embedded_dashboard_uuid(filtered_dashboard_list, access_token):
    embedded_dashboards = []
    if not filtered_dashboard_list: return []
        
    for filtered_dashboard in filtered_dashboard_list:
        dashboard_id = filtered_dashboard.get('id')
        if not dashboard_id: continue
            
        try:
            response = requests.get(
                f"{SUPERSET_URL}/api/v1/dashboard/{dashboard_id}/embedded",
                headers={"Authorization": f"Bearer {access_token}"},
                timeout=10
            )
            if response.status_code == 200:
                result_data = response.json().get("result")
                if result_data and "uuid" in result_data:
                    filtered_dashboard['embedded_uuid'] = result_data["uuid"]
                    embedded_dashboards.append(filtered_dashboard)
        except Exception:
            pass

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
# NEW: DB-BASED LOGIN
# ---------------------------------------------------------
@app.route("/api/login", methods=["POST"])
def login():
    data = request.get_json()
    username = data.get("username")
    password = data.get("password")
    
    if not username or not password:
        return jsonify({"error": "Username and password required"}), 400
    
    if not engine:
        return jsonify({"error": "Database unavailable"}), 500

    try:
        with engine.connect() as conn:
            # FIX: We added 't.id as tenant_pk' to the selection
            query = text("""
                SELECT 
                    u.id, u.name, u.password_hash, u.role, u.superset_username, 
                    t.schema_name, 
                    t.id as tenant_pk,  -- <--- VITAL CHANGE
                    tpl.logo_url
                FROM public.user u
                JOIN public.tenant t ON u.tenant_id = t.id
                LEFT JOIN public.tenant_templates tpl ON t.id = tpl.tenant_id
                WHERE u.email = :u
            """)
            
            user = conn.execute(query, {"u": username}).fetchone()
            
            if not user or user.password_hash != password:
                return jsonify({"error": "Invalid credentials"}), 401
            
            session.clear()
            session.permanent = True
            
            session['user'] = username
            session['name'] = user.name
            session['role'] = user.role
            session['roles'] = [user.role] 
            session['superset_username'] = user.superset_username
            
            session['tenant_schema'] = user.schema_name
            session['tenant_id'] = user.tenant_pk  # <--- CORRECTED: Uses the actual Tenant ID
            session['logo_url'] = user.logo_url
            
            return jsonify({
                "success": True,
                "user": {
                    "username": username,
                    "name": user.name,
                    "roles": [user.role],
                    "logo": user.logo_url
                }
            }), 200

    except Exception as e:
        print(f"Login Error: {e}")
        return jsonify({"error": "Server error during login"}), 500

@app.route("/api/logout", methods=["POST"])
def logout():
    session.clear()
    return jsonify({"success": True}), 200

@app.route("/api/check-auth", methods=["GET"])
def check_auth():
    if 'user' in session:
        return jsonify({
            "authenticated": True,
            "user": {
                "username": session['user'],
                "name": session.get('name'),
                "roles": session.get('roles', []),
                "logo": session.get('logo_url')
            }
        }), 200
    else:
        return jsonify({"authenticated": False}), 200

# ---------------------------------------------------------
# DASHBOARDS ENDPOINT
# ---------------------------------------------------------
@app.route("/api/dashboards", methods=["GET"])
@login_required
def get_filtered_dashboards():
    user_roles = session.get('roles', [])
    
    try:
        access_token = get_superset_access_token()
        if not access_token:
            return jsonify({"error": "Failed to connect to Superset"}), 500
        
        all_dashboards = get_all_dashboards_from_superset(access_token)
        filtered = filter_dashboards_by_user_roles(all_dashboards, user_roles)
        
        dashboard_list = [{
            "id": d.get('id'),
            "dashboard_title": d.get('dashboard_title'),
            "url": d.get('url'),
            "roles": [r['name'] for r in d.get('roles', [])]
        } for d in filtered]
        
        embedded_dashboards = get_embedded_dashboard_uuid(dashboard_list, access_token)

        # --- Fetch categories from DB ---
        category_map = {}
        if engine and embedded_dashboards:
            dashboard_ids = [d.get('id') for d in embedded_dashboards if d.get('id')]
            with engine.connect() as conn:
                rows = conn.execute(text("""
                    SELECT dashboard_id, category
                    FROM public.dashboard_category_map
                    WHERE dashboard_id = ANY(:ids)
                """), {"ids": dashboard_ids}).fetchall()
                category_map = {row.dashboard_id: row.category for row in rows}

        # Attach category to each dashboard
        for d in embedded_dashboards:
            d['category'] = category_map.get(d.get('id'), 'General')
        
        return jsonify({
            "success": True,
            "dashboards": embedded_dashboards
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ---------------------------------------------------------
# GUEST TOKEN ENDPOINT
# ---------------------------------------------------------
@app.route("/api/guest-token", methods=["GET"])
@login_required
def generate_guest_token():
    dashboard_id_str = request.args.get("dashboardId")
    superset_username = session.get('superset_username')
    
    if not dashboard_id_str:
        return jsonify({"error": "dashboardId is required"}), 400

    # ✅ FIX 1: Increased from 300 → 3600 (1 hour)
    expiration_time = int(time.time()) + 3600 
    
    payload = {
        "user": {
            "username": superset_username, 
            "first_name": "Guest",
            "last_name": "User",
        },
        "resources": [{"type": "dashboard", "id": dashboard_id_str}],
        "rls_rules": [],
        "exp": expiration_time,
        "aud": "audi",
        "type": "guest"
    }
    
    try:
        token = jwt.encode(payload, GUEST_TOKEN_JWT_SECRET, algorithm="HS256")
        return jsonify({"guestToken": token}), 200
    except Exception as e:
        return jsonify({"error": "Failed to encode token"}), 500



# @app.route('/api/upload-excel', methods=['POST'])
# @login_required
# def upload_excel():

#     tenant_schema = session.get('tenant_schema')
#     tenant_id = session.get('tenant_id')
#     user_id = session.get('user_id', 1)

#     print(f"DEBUG: Tenant Schema: {tenant_schema}", flush=True)
#     print(f"DEBUG: Tenant ID: {tenant_id}", flush=True)
#     print(f"DEBUG: User ID: {user_id}", flush=True)

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
#         return jsonify({"success": False, "error": "Invalid file type. Only xlsx and csv allowed"}), 400

#     # Read file before opening DB connection
#     clean_filename = secure_filename(file.filename)
#     lower_filename = clean_filename.lower()
#     file_ext = clean_filename.rsplit('.', 1)[1].lower()
#     file_bytes = file.read()
#     file_buffer = io.BytesIO(file_bytes)

#     # ─────────────────────────────────────────
#     # Use ONE connection for everything
#     # ─────────────────────────────────────────
#     with engine.connect() as conn:
#         trans = conn.begin()
#         try:
#             # Step 1 - Get tenant data
#             tenant_data = conn.execute(text("""
#                 SELECT 
#                     id,
#                     "tenant_name",
#                     "schema_name",
#                     "table_name",
#                     "fileprefix",
#                     "DomainId"
#                 FROM public.tenant
#                 WHERE schema_name = :schema
#             """), {"schema": tenant_schema}).mappings().first()

#             if not tenant_data:
#                 trans.rollback()
#                 return jsonify({"success": False, "error": "Invalid tenant configuration"}), 400

#             tenant_id = tenant_data["id"]
#             target_table_name = tenant_data["table_name"]
#             file_prefix = tenant_data["fileprefix"]

#             print(f"DEBUG: File prefix expected: {file_prefix}", flush=True)
#             print(f"DEBUG: File name received: {clean_filename}", flush=True)

#             # Step 2 - Validate file prefix
#             if not lower_filename.startswith(file_prefix.lower()):
#                 trans.rollback()
#                 return jsonify({
#                     "success": False,
#                     "error": f"Invalid file name. File must start with prefix '{file_prefix}'.",
#                     "example": f"{file_prefix}_2026_01.xlsx"
#                 }), 400

#             # Step 3 - Create load master entry
#             load_id = conn.execute(text("""
#                 INSERT INTO public.load_master (tenant_id, user_id, filename, status)
#                 VALUES (:tid, :uid, :fname, 'Processing')
#                 RETURNING id
#             """), {
#                 "tid": tenant_id,
#                 "uid": user_id,
#                 "fname": clean_filename
#             }).scalar()

#             print(f"DEBUG: Load ID created: {load_id}", flush=True)

#             # Step 4 - Read file into dataframes
#             if file_ext == 'xlsx':
#                 xls = pd.ExcelFile(file_buffer, engine='openpyxl')
#                 dataframes = [xls.parse(sheet, dtype=str) for sheet in xls.sheet_names]
#             elif file_ext == 'csv':
#                 file_buffer.seek(0)
#                 dataframes = [pd.read_csv(file_buffer, dtype=str)]
#             else:
#                 trans.rollback()
#                 return jsonify({"success": False, "error": "Unsupported file format"}), 400

#             # Step 5 - Process each dataframe
#             excel_max_date = None
#             for df in dataframes:
#                 if df.empty:
#                     continue

#                 df.columns = [c.strip() for c in df.columns]
#                 print(f"DEBUG: Columns in file: {list(df.columns)}", flush=True)

#                 # Get DB columns
#                 table_columns = conn.execute(text("""
#                     SELECT column_name
#                     FROM information_schema.columns
#                     WHERE table_schema = :schema
#                     AND table_name = :table
#                 """), {
#                     "schema": tenant_schema,
#                     "table": target_table_name
#                 }).scalars().all()

#                 print(f"DEBUG: DB columns: {table_columns}", flush=True)

#                 # Filter to matching columns only
#                 df = df[[col for col in df.columns if col in table_columns]].copy()

#                 if 'load_id' in table_columns:
#                     df['load_id'] = load_id

#                 # Date handling
#                 if 'BillDate' in df.columns:
#                     df['BillDate'] = pd.to_datetime(
#                         df['BillDate'], errors='coerce'
#                     ).dt.strftime('%d-%m-%Y')

#                     if df['BillDate'].isna().any():
#                         trans.rollback()
#                         return jsonify({
#                             "success": False,
#                             "error": "Invalid BillDate detected in uploaded file."
#                         }), 400

#                     excel_max_date = pd.to_datetime(
#                         df['BillDate'], format='%d-%m-%Y'
#                     ).max().date()

#                     print(f"DEBUG: Excel max date: {excel_max_date}", flush=True)

#                     # Check against DB max date
#                     db_max_date = conn.execute(text(f"""
#                         SELECT MAX(dd."Fulldate")
#                         FROM "{tenant_schema}"."DimDate" dd
#                         JOIN "{tenant_schema}"."FactSalesMaster" fsd
#                         ON fsd."DateFrKey" = dd."DateKey"
#                     """)).scalar()

#                     print(f"DEBUG: DB max date: {db_max_date}", flush=True)

#                     if db_max_date is not None and excel_max_date <= db_max_date:
#                         trans.rollback()
#                         return jsonify({
#                             "success": False,
#                             "error": f"Data for date {excel_max_date} already exists. Upload data after {db_max_date}."
#                         }), 400

#                 if 'LastPurDate' in df.columns:
#                     df['LastPurDate'] = pd.to_datetime(
#                         df['LastPurDate'], errors='coerce'
#                     ).dt.strftime('%d-%m-%Y')

#                 # Truncate and insert
#                 conn.execute(text(
#                     f'TRUNCATE TABLE "{tenant_schema}"."{target_table_name}" RESTART IDENTITY'
#                 ))

#                 df.to_sql(
#                     target_table_name,
#                     con=conn,
#                     schema=tenant_schema,
#                     if_exists='append',
#                     index=False,
#                     chunksize=1000, # Process 1000 rows at a time
#                     method='multi'
#                 )

#                 print(f"DEBUG: Data inserted into {target_table_name}", flush=True)

#             # Step 6 - Run stored procedures
#             print("DEBUG: Running procedures...", flush=True)

#             conn.execute(text(f"""
#                 CALL "{tenant_schema}".sp_batch_insert_dummy_to_stagging_to_dim(200000, 1, 0)
#             """))

#             if excel_max_date:
#                 conn.execute(text(f"""
#                     CALL "{tenant_schema}".refresh_dimdate_offsets(:max_date)
#                 """), {"max_date": excel_max_date})

#             conn.execute(text(f"""
#                 CALL "{tenant_schema}".refresh_all_mvs()
#             """))

#             # Step 7 - Update load master and commit
#             conn.execute(text("""
#                 UPDATE public.load_master SET status='Pass' WHERE id=:lid
#             """), {"lid": load_id})

#             trans.commit()
#             print("DEBUG: Transaction committed successfully ✅", flush=True)

#             # Clear Superset cache
#             try:
#                 r = redis.from_url(os.getenv("REDIS_URL"))
#                 for key in r.scan_iter("superset*"):
#                     r.delete(key)
#                 print("DEBUG: Superset cache cleared ✅", flush=True)
#             except Exception as cache_err:
#                 print(f"DEBUG: Cache clear failed (non-critical): {cache_err}", flush=True)

#             return jsonify({
#                 "success": True,
#                 # "message": f"Data uploaded successfully to {target_table_name}",
#                 "message": f"Data uploaded successfully. Please Go To The Dashboard",
#                 "load_id": load_id
#             }), 200

#         except Exception as e:
#             try:
#                 trans.rollback()
#             except:
#                 pass
#             print(f"DEBUG: ERROR during upload: {str(e)}", flush=True)
#             import traceback
#             traceback.print_exc()
#             return jsonify({"success": False, "error": str(e)}), 500

@app.route('/api/upload-excel', methods=['POST'])
@login_required
def upload_excel():

    tenant_schema = session.get('tenant_schema')
    tenant_id = session.get('tenant_id')
    user_id = session.get('user_id', 1)

    print(f"DEBUG: Tenant Schema: {tenant_schema}", flush=True)
    print(f"DEBUG: Tenant ID: {tenant_id}", flush=True)
    print(f"DEBUG: User ID: {user_id}", flush=True)

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
        return jsonify({"success": False, "error": "Invalid file type. Only xlsx and csv allowed"}), 400

    # Read file before opening DB connection
    clean_filename = secure_filename(file.filename)
    lower_filename = clean_filename.lower()
    file_ext = clean_filename.rsplit('.', 1)[1].lower()
    file_bytes = file.read()
    file_buffer = io.BytesIO(file_bytes)

    # ─────────────────────────────────────────
    # Use ONE connection for everything
    # ─────────────────────────────────────────
    with engine.connect() as conn:
        trans = conn.begin()
        try:
            # Step 1 - Get tenant data
            tenant_data = conn.execute(text("""
                SELECT 
                    id,
                    "tenant_name",
                    "schema_name",
                    "table_name",
                    "fileprefix",
                    "DomainId"
                FROM public.tenant
                WHERE schema_name = :schema
            """), {"schema": tenant_schema}).mappings().first()

            if not tenant_data:
                trans.rollback()
                return jsonify({"success": False, "error": "Invalid tenant configuration"}), 400

            tenant_id = tenant_data["id"]
            target_table_name = tenant_data["table_name"]
            file_prefix = tenant_data["fileprefix"]

            print(f"DEBUG: File prefix expected: {file_prefix}", flush=True)
            print(f"DEBUG: File name received: {clean_filename}", flush=True)

            # Step 2 - Validate file prefix
            if file_prefix and not lower_filename.startswith(file_prefix.lower()):
                trans.rollback()
                return jsonify({
                    "success": False,
                    "error": f"Invalid file name. File must start with prefix '{file_prefix}'.",
                    "example": f"{file_prefix}_2026_01.xlsx"
                }), 400

            # Step 3 - Create load master entry
            load_id = conn.execute(text("""
                INSERT INTO public.load_master (tenant_id, user_id, filename, status)
                VALUES (:tid, :uid, :fname, 'Processing')
                RETURNING id
            """), {
                "tid": tenant_id,
                "uid": user_id,
                "fname": clean_filename
            }).scalar()

            print(f"DEBUG: Load ID created: {load_id}", flush=True)

            # Step 4 - Read file into dataframes
            if file_ext == 'xlsx':
                xls = pd.ExcelFile(file_buffer, engine='openpyxl')
                dataframes = [xls.parse(sheet, dtype=str) for sheet in xls.sheet_names]
            elif file_ext == 'csv':
                file_buffer.seek(0)
                dataframes = [pd.read_csv(file_buffer, dtype=str)]
            else:
                trans.rollback()
                return jsonify({"success": False, "error": "Unsupported file format"}), 400

            # Step 5 - Process each dataframe
            excel_max_date = None
            for df in dataframes:
                if df.empty:
                    continue

                df.columns = [c.strip() for c in df.columns]
                df_original = df.copy()
                print(f"DEBUG: Columns in file: {list(df.columns)}", flush=True)

                # Get DB columns
                table_columns = conn.execute(text("""
                    SELECT column_name
                    FROM information_schema.columns
                    WHERE table_schema = :schema
                    AND table_name = :table
                """), {
                    "schema": tenant_schema,
                    "table": target_table_name
                }).scalars().all()

                print(f"DEBUG: DB columns: {table_columns}", flush=True)

                # Filter to matching columns only
                df = df[[col for col in df.columns if col in table_columns]].copy()

                if 'load_id' in table_columns:
                    df['load_id'] = load_id

                # Date handling
                if 'BillDate' in df.columns:
                    df['BillDate'] = pd.to_datetime(
                        df['BillDate'], errors='coerce'
                    ).dt.strftime('%d-%m-%Y')

                    if df['BillDate'].isna().any():
                        trans.rollback()
                        return jsonify({
                            "success": False,
                            "error": "Invalid BillDate detected in uploaded file."
                        }), 400

                    excel_max_date = pd.to_datetime(
                        df['BillDate'], format='%d-%m-%Y'
                    ).max().date()

                    print(f"DEBUG: Excel max date: {excel_max_date}", flush=True)

                    # Check against DB max date
                    db_max_date = conn.execute(text(f"""
                        SELECT MAX(dd."Fulldate")
                        FROM "{tenant_schema}"."DimDate" dd
                        JOIN "{tenant_schema}"."FactSalesMaster" fsd
                        ON fsd."DateFrKey" = dd."DateKey"
                    """)).scalar()

                    print(f"DEBUG: DB max date: {db_max_date}", flush=True)

                    if db_max_date is not None and excel_max_date <= db_max_date:
                        trans.rollback()
                        return jsonify({
                            "success": False,
                            "error": f"Data for date {excel_max_date} already exists. Upload data after {db_max_date}."
                        }), 400

                if 'LastPurDate' in df.columns:
                    df['LastPurDate'] = pd.to_datetime(
                        df['LastPurDate'], errors='coerce'
                    ).dt.strftime('%d-%m-%Y')

                

                print(f"DEBUG: Data inserted into {target_table_name}", flush=True)

            # Step 6 - Run stored procedures OR insert based on tenant
            print(f"DEBUG: Tenant name check: {tenant_data['tenant_name']}", flush=True)

            if tenant_data["tenant_name"].strip().lower() == "shinde_shoes":
                # ── Shinde Shoes: run stored procedures ──────────────────
                # Truncate and insert
                conn.execute(text(
                    f'TRUNCATE TABLE "{tenant_schema}"."{target_table_name}" RESTART IDENTITY'
                ))

                df.to_sql(
                    target_table_name,
                    con=conn,
                    schema=tenant_schema,
                    if_exists='append',
                    index=False
                )

                print("DEBUG: Running Shinde Shoes procedures...", flush=True)

                conn.execute(text(f"""
                    CALL "{tenant_schema}".sp_batch_insert_dummy_to_stagging_to_dim(200000, 1, 0)
                """))

                if excel_max_date:
                    conn.execute(text(f"""
                        CALL "{tenant_schema}".refresh_dimdate_offsets(:max_date)
                    """), {"max_date": excel_max_date})

                conn.execute(text(f"""
                    CALL "{tenant_schema}".refresh_all_mvs()
                """))

                print("DEBUG: Shinde Shoes procedures completed ✅", flush=True)

            else:
                # ── Other tenants: insert into apparel_sales table ────────
                print("DEBUG: Inserting into apparel_sales.t_apparel_sales...", flush=True)

                # Clean NaN values before iterating
                df_original = df_original.dropna(how='all')
                df_original = df_original.where(df_original.notna(), None)

                print(f"DEBUG: Clean rows to insert: {len(df_original)}", flush=True)
                print(f"DEBUG: df_original columns: {list(df_original.columns)}", flush=True)
                print(f"DEBUG: df_original first row: {df_original.iloc[0].to_dict()}", flush=True)

                insert_rows = []
                for _, row in df_original.iterrows():
                    if not row.get("Sale ID"):
                        continue
                    insert_rows.append({
                        "sale_id":       row.get("Sale ID"),
                        "location_city": row.get("Location (City)"),
                        "store_name":    row.get("Store Name"),
                        "product":       row.get("Product"),
                        "size":          row.get("Size"),
                        "color":         row.get("Color"),
                        "price_inr":     row.get("Price (INR)"),
                        "quantity_sold": row.get("Quantity Sold"),
                        "date":          row.get("Date"),
                        "sales_rep":     row.get("Sales Rep"),
                        "load_id":       load_id,
                    })

                if insert_rows:
                    conn.execute(
                        text("""
                            INSERT INTO apparel_sales.t_apparel_sales (
                                sale_id,
                                "location_(city)",
                                store_name,
                                product,
                                size,
                                color,
                                "price_(inr)",
                                quantity_sold,
                                date,
                                sales_rep,
                                load_id
                            ) VALUES (
                                :sale_id,
                                :location_city,
                                :store_name,
                                :product,
                                :size,
                                :color,
                                :price_inr,
                                :quantity_sold,
                                :date,
                                :sales_rep,
                                :load_id
                            )
                        """),
                        insert_rows
                    )
                    print(f"DEBUG: Inserted {len(insert_rows)} rows into apparel_sales.t_apparel_sales ✅", flush=True)
                else:
                    print("DEBUG: No rows to insert.", flush=True)

            # Step 7 - Update load master and commit
            conn.execute(text("""
                UPDATE public.load_master SET status='Pass' WHERE id=:lid
            """), {"lid": load_id})

            trans.commit()
            print("DEBUG: Transaction committed successfully ✅", flush=True)

            # Clear Superset cache
            try:
                r = redis.from_url(os.getenv("REDIS_URL"))
                for key in r.scan_iter("superset*"):
                    r.delete(key)
                print("DEBUG: Superset cache cleared ✅", flush=True)
            except Exception as cache_err:
                print(f"DEBUG: Cache clear failed (non-critical): {cache_err}", flush=True)

            return jsonify({
                "success": True,
                "message": f"Data uploaded successfully. Please Go To The Dashboard",
                "load_id": load_id
            }), 200

        except Exception as e:
            try:
                trans.rollback()
            except:
                pass
            print(f"DEBUG: ERROR during upload: {str(e)}", flush=True)
            import traceback
            traceback.print_exc()
            return jsonify({"success": False, "error": str(e)}), 500

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
            "logo_url": result["logo_url"],
            "branding_name": result["branding_name"]
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
#-----------------------------------------------------------------------------------------    


## This Is The External API To Truncate A Table (Hardcoded)
## It Deletes All Data From A Specific Table And Resets The Serial ID Counter
## curently hardcoded to delete the t_apparel_sales table data in upload_data schema

@app.route('/truncate-data', methods=['GET'])
def truncate_table_simple():
    # --- HARDCODED VALUES ---
    TARGET_SCHEMA = "apparel_sales"
    TARGET_TABLE = "t_apparel_sales"
    # ------------------------

    try:
        with engine.connect() as conn:
            # The Query: Truncate the table and reset the ID counter to 1
            query = text(f'TRUNCATE TABLE "{TARGET_SCHEMA}"."{TARGET_TABLE}" RESTART IDENTITY CASCADE')
            
            conn.execute(query)
            conn.commit()
            
            # Simple message for the browser screen
            return f"""
            <div style="font-family:sans-serif; text-align:center; margin-top:100px;">
                <h1 style="color:green;">Table Truncated</h1>
                <p>All data has been deleted from: <b>{TARGET_SCHEMA}.{TARGET_TABLE}</b></p>
                <p>Serial IDs have been reset to 1.</p>
            </div>
            """, 200

    except Exception as e:
        return f"<h1>Error</h1><p>{str(e)}</p>", 500


if __name__ == '__main__':
    app.run(host="0.0.0.0", port=5000, debug=True)
