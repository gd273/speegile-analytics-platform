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
    SESSION_COOKIE_SAMESITE='None',
    SESSION_COOKIE_SECURE=True,
    PERMANENT_SESSION_LIFETIME=timedelta(hours=1),
    SESSION_PERMANENT=False,
    SESSION_COOKIE_DOMAIN=None
)
# applies the app config for our sessions
Session(app)

raw_origins = os.getenv("CORS_ALLOW_ORIGINS", "http://localhost:3000")
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
@app.route("/login", methods=["POST"])
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
                FROM public.users u
                JOIN public.tenants t ON u.tenant_id = t.id
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

@app.route("/logout", methods=["POST"])
def logout():
    session.clear()
    return jsonify({"success": True}), 200

@app.route("/check-auth", methods=["GET"])
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
@app.route("/dashboards", methods=["GET"])
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
        
        return jsonify({
            "success": True,
            "dashboards": embedded_dashboards
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ---------------------------------------------------------
# GUEST TOKEN ENDPOINT
# ---------------------------------------------------------
@app.route("/guest-token", methods=["GET"])
@login_required
def generate_guest_token():
    dashboard_id_str = request.args.get("dashboardId")
    superset_username = session.get('superset_username')
    
    if not dashboard_id_str:
        return jsonify({"error": "dashboardId is required"}), 400
    
    expiration_time = int(time.time()) + 300 
    
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

# ---------------------------------------------------------
# UPLOAD EXCEL (Schema Aware)
# ---------------------------------------------------------
@app.route('/upload-excel', methods=['POST'])
@login_required
def upload_excel():
    if 'excel_file' not in request.files:
        return jsonify({"success": False, "error": "No file part"}), 400

    file = request.files['excel_file']
    if file.filename == '':
        return jsonify({"success": False, "error": "No selected file"}), 400

    if engine is None:
        return jsonify({"success": False, "error": "Database unavailable"}), 503
    
    # Get Context
    tenant_schema = session.get('tenant_schema')
    tenant_id = session.get('tenant_id') # We need to make sure login stores this!
    user_id = session.get('user_id', 1) # Fallback, or fetch from session.get('user_id')

    # Quick patch if you haven't updated login to store tenant_id yet:
    # You might need to query it here or add it to session in the /login route.
    if not tenant_id: 
         # temporary lookup for safety
         with engine.connect() as conn:
             tenant_id = conn.execute(text(f"SELECT id FROM public.tenants WHERE schema_name=:s"), {"s":tenant_schema}).scalar()

    if not tenant_schema:
        return jsonify({"success": False, "error": "No tenant context found"}), 403

    if file and allowed_file(file.filename):
        try:
            clean_filename = secure_filename(file.filename)
            timestamp_str = datetime.now().strftime("%Y%m%d_%H%M%S")
            
            # with engine.connect() as conn:
            #     trans = conn.begin()
            #     try:
            #         # 1. CREATE LOAD MASTER ENTRY (Public Schema)
            #         # Status starts as 'Processing'
            #         insert_master = text("""
            #             INSERT INTO public.load_master (tenant_id, user_id, filename, status)
            #             VALUES (:tid, :uid, :fname, 'Processing')
            #             RETURNING id
            #         """)
            #         load_id = conn.execute(insert_master, {
            #             "tid": tenant_id, "uid": user_id, "fname": clean_filename
            #         }).scalar()
                    
            #         # 2. PROCESS FILE (Using Pandas)
            #         xls = pd.ExcelFile(file.stream, engine='openpyxl')
                    
            #         # --- VALIDATION SIMULATION ---
            #         # Here you would check for errors. 
            #         # For MVP, let's assume if it reads, it passes.
            #         # If you find errors, you would:
            #         #   a) Insert into public.load_errors
            #         #   b) Update load_master status = 'Fail'
            #         #   c) trans.commit(), return jsonify({"error": "Validation Failed"})
                    
            #         # 3. IF SUCCESS: ARCHIVE TO S3
            #         # Format: {tenant_id}_{load_id}_{datetime}.xlsx
            #         # new_s3_name = f"{tenant_id}_{load_id}_{timestamp_str}.xlsx"
            #         # s3_key = f"{tenant_schema}/{new_s3_name}"
                    
            #         # Reset file stream to 0 to read bytes for S3
            #         # file.stream.seek(0)
            #         # s3_client.upload_fileobj(file.stream, S3_BUCKET, s3_key)
                    
            #         # 4. SAVE TO PRIVATE DB
            #         # Reset stream again for Pandas
            #         file.stream.seek(0)
                    
            #         base_name = clean_filename.rsplit('.', 1)[0].lower().replace(' ', '_')
            #         results = []

            #         for sheet in xls.sheet_names:
            #             df = xls.parse(sheet)
            #             if df.empty: continue
                        
            #             df.columns = [c.replace(' ', '_').lower() for c in df.columns]
            #             df['load_id'] = load_id  # Traceability
                        
            #             # Naming logic
            #             if len(xls.sheet_names) == 1:
            #                 table_name = base_name
            #             else:
            #                 clean_sheet = sheet.lower().replace(' ', '_')
            #                 table_name = f"{base_name}_{clean_sheet}"

            #             df.to_sql(table_name, con=conn, schema=tenant_schema, if_exists='append', index=False)
            #             results.append(table_name)
                    
            #         # 5. UPDATE STATUS TO PASS
            #         conn.execute(text("UPDATE public.load_master SET status='Pass' WHERE id=:lid"), {"lid": load_id})
                    
            #         trans.commit()
            #         return jsonify({"success": True, "message": "Processed & Archived", "load_id": load_id}), 200
            with engine.connect() as conn:
                trans = conn.begin()
                try:
                    # 1. CREATE LOAD MASTER ENTRY
                    insert_master = text("""
                        INSERT INTO public.load_master (tenant_id, user_id, filename, status)
                        VALUES (:tid, :uid, :fname, 'Processing')
                        RETURNING id
                    """)
                    load_id = conn.execute(insert_master, {
                        "tid": tenant_id, "uid": user_id, "fname": clean_filename
                    }).scalar()

                    # --- NEW LOGIC: FETCH CONFIGURED TABLE NAME ---
                    # We look up the 'table_name' assigned to this tenant in the public.tenants table
                    get_table_query = text("SELECT table_name FROM public.tenants WHERE id = :tid")
                    target_table_name = conn.execute(get_table_query, {"tid": tenant_id}).scalar()

                    if not target_table_name:
                        trans.rollback()
                        return jsonify({"success": False, "error": "No target table configured for this tenant"}), 400
                    # ----------------------------------------------

                    # 2. PROCESS FILE
                    xls = pd.ExcelFile(file.stream, engine='openpyxl')
                    
                    # 4. SAVE TO PRIVATE DB
                    file.stream.seek(0)
                    results = []

                    for sheet in xls.sheet_names:
                        df = xls.parse(sheet)
                        if df.empty: continue
                        
                        # Clean columns to match DB standards
                        df.columns = [c.replace(' ', '_').lower() for c in df.columns]
                        df['load_id'] = load_id  
                        
                        # 3. INSERT INTO THE FETCHED TABLE NAME
                        # We use 'append' because you want to keep adding data to this fixed table.
                        df.to_sql(
                            target_table_name, 
                            con=conn, 
                            schema=tenant_schema, 
                            if_exists='append', 
                            index=False
                        )
                        results.append(target_table_name)
                    
                    # 5. UPDATE STATUS TO PASS
                    conn.execute(text("UPDATE public.load_master SET status='Pass' WHERE id=:lid"), {"lid": load_id})

                    print(f"DEBUG: Target Table Name is: {target_table_name}") # Check if this is None
                    print(f"DEBUG: Sheets found: {xls.sheet_names}")         # Check if it sees your sheets
                    for sheet in xls.sheet_names:
                        df = xls.parse(sheet)
                        print(f"DEBUG: Sheet {sheet} has {len(df)} rows")    # Check if data is actually loaded
                        
                    trans.commit()
                    return jsonify({"success": True, "message": f"Data appended to {target_table_name}", "load_id": load_id}), 200        
                except Exception as inner_e:
                    trans.rollback()
                    # Optional: Log the crash as a 'Fail' status if connection is still alive
                    print(f"Processing Error: {inner_e}")
                    raise inner_e

        except Exception as e:
            return jsonify({"success": False, "error": str(e)}), 500
            
    return jsonify({"success": False, "error": "Invalid file"}), 400

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=5000, debug=True)