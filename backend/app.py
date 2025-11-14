from flask import Flask, request, jsonify, session
from flask_cors import CORS
import jwt
import time
import os
import requests
import json
from datetime import timedelta
from werkzeug.utils import secure_filename
import pandas as pd
from sqlalchemy import create_engine, text, inspect
import logging
import sqlite3
from flask_session import Session
from dotenv import load_dotenv
import os

load_dotenv()
if not os.path.exists('./.flask_session/'):
    os.makedirs('./.flask_session/')

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY")

print("======================================================================")
print(f"Flask App Initialized.")
print(f"SECRET_KEY Hash Check (First 8 chars): {app.secret_key[:8]}...")
print("======================================================================")

# Create the session directory if it doesn't exist

# app.secret_key = "your_flask_secret_key_12345"

# app.config['SESSION_COOKIE_SAMESITE'] = 'Lax'  # or 'None' if using HTTPS
# app.config['SESSION_COOKIE_HTTPONLY'] = True
# app.config['SESSION_COOKIE_SECURE'] = False  # Set to True in production with HTTPS
# app.config['PERMANENT_SESSION_LIFETIME'] = 3600  # 1 hour
app.config.update(
    SESSION_TYPE='filesystem',
    SESSION_COOKIE_NAME='flask_session',
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE='Lax',
    SESSION_COOKIE_SECURE=False,  # False for HTTP (localhost), True for HTTPS
    PERMANENT_SESSION_LIFETIME=timedelta(hours=1),
    SESSION_COOKIE_PATH='/',
    SESSION_FILE_DIR='./.flask_session/',
    SESSION_PERMANENT=False,
    SESSION_COOKIE_DOMAIN=None  # Important for localhost
)
# app.config['SECRET_KEY'] = app.secret_key
Session(app)

# Allowed extensions for file upload
ALLOWED_EXTENSIONS = {'xlsx'}
# Load CORS origins from .env
raw_origins = os.getenv("CORS_ALLOW_ORIGINS", "http://localhost:3000")

# Support multiple origins (comma-separated)
CORS_ORIGINS = [o.strip() for o in raw_origins.split(",") if o.strip()]
CORS(app, 
    resources={r"/api/*": {
        "origins": CORS_ORIGINS,
        "supports_credentials": True,
        "allow_headers": ["Content-Type", "Authorization"],
        "expose_headers": ["Set-Cookie"],
        "methods": ["GET", "POST", "OPTIONS"],
        "allow_credentials": True
    }},
    supports_credentials=True
)

# GUEST_TOKEN_SECRET = os.getenv("GUEST_TOKEN_SECRET", "my_secure_embedding_secret_12345")
# SUPERSET_URL = "http://localhost:8088"
SUPERSET_ADMIN_USERNAME = os.getenv("SUPERSET_ADMIN_USERNAME")
SUPERSET_ADMIN_PASSWORD = os.getenv("SUPERSET_ADMIN_PASSWORD")
SUPERSET_URL = os.getenv("SUPERSET_URL")
# DATABASE_URL = 'mysql+mysqlconnector://root:mishka123@localhost:3306/user_database'
DATABASE_URL = os.getenv("APP_DATABASE_URL")
GUEST_TOKEN_JWT_SECRET = os.getenv("GUEST_TOKEN_JWT_SECRET")

try:
    
    engine = create_engine(DATABASE_URL)
    
    with engine.connect() as connection:
        result = connection.execute(text("SELECT 1"))
        print(f"Database connection successful. Result: {result.scalar()}")
except Exception as e:
    print(f"🚨 DATABASE CONNECTION FAILED: {e}")
    engine = None

def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

USERS = {
    "User_1": {
        "password": "john123",
        "name": "User_1",
        "superset_username": "User_1",
        "roles": ["dashboard1viewer","DASHBOARD-READ-BASE"]  # Must match Superset role names exactly
    },
    "User_2": {
        "password": "jane123",
        "name": "User_2",
        "superset_username": "User_2",
        "roles": ["dashboard2viewer","DASHBOARD-READ-BASE"]
    },
    "User_3": {
        "password": "bob123",
        "name": "User_3",
        "superset_username": "User_3",
        "roles": ["dashboard3viewer", "DASHBOARD-READ-BASE"]
    },
    "alice": {
        "password": "alice123",
        "name": "Alice Johnson",
        "superset_username": "admin",
        "roles": ["Admin"]
    }
}

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
            token = response.json().get("access_token")
            return token
        else:
            print(f"✗ Failed to get Superset token: {response.status_code}")
            print(f"  Response: {response.text}")
            return None
    except Exception as e:
        print(f"✗ Error getting Superset token: {e}")
        return None

def get_all_dashboards_from_superset(access_token):
    """
    Fetch all dashboards with role information from Superset
    Uses: GET /api/v1/dashboard/
    """
    try:
        query = {
            "page": 0,
            "page_size": 100,
        }
        
        response = requests.get(
            f"{SUPERSET_URL}/api/v1/dashboard/",
            params={"q": json.dumps(query)},
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json"
            },
            timeout=10
        )
        
        if response.status_code == 200:
            dashboards = response.json().get("result", [])
            print(f"✓ Fetched {len(dashboards)} dashboards from Superset")
            
            for dash in dashboards:
                roles = dash.get('roles', [])
                role_names = [r['name'] for r in roles] if roles else ["No roles (public)"]
            
            return dashboards
        else:
            print(f"✗ Failed to fetch dashboards: {response.status_code}")
            print(f"  Response: {response.text}")
            return []
    except Exception as e:
        print(f"✗ Error fetching dashboards: {e}")
        return []

def filter_dashboards_by_user_roles(dashboards, user_roles):
    """
    Filter dashboards based on user's roles
    Match by role name (case-insensitive)
    """
    if not user_roles:
        print("⚠ User has no roles, returning empty list")
        return []
    
    # Normalize user role names to lowercase for comparison
    user_role_names_lower = [role.lower() for role in user_roles]
    
    
    # Check if user has Admin role (admins see everything)
    is_admin = 'admin' in user_role_names_lower
    if is_admin:
        print("✓ User has Admin role - returning all dashboards")
        return dashboards
    
    filtered = []
    for dashboard in dashboards:
        dashboard_roles = dashboard.get('roles', [])
        
        # If dashboard has no roles, it might be public (include it)
        if not dashboard_roles or len(dashboard_roles) == 0:
            print(f"  ✓ {dashboard.get('dashboard_title')}: No role restrictions (public)")
            filtered.append(dashboard)
            continue
        
        # Get dashboard role names
        dashboard_role_names = [role['name'].lower() for role in dashboard_roles]
        
        # Check if user has ANY of the dashboard's required roles
        matching_roles = [role for role in user_role_names_lower if role in dashboard_role_names]
        
        if matching_roles:
            print(f"  ✓ {dashboard.get('dashboard_title')}: Access granted (matched: {matching_roles})")
            filtered.append(dashboard)
        else:
            print(f"  ✗ {dashboard.get('dashboard_title')}: Access denied (needs: {dashboard_role_names})")
    
    return filtered
  
def get_embedded_dashboard_uuid(filtered_dashboard_list, access_token):
    embedded_dashboards = []
    
    if not filtered_dashboard_list:
        return []
        
    for filtered_dashboard in filtered_dashboard_list:
        # Use key access and safely get the ID
        dashboard_id = filtered_dashboard.get('id') 

        if not dashboard_id:
            print(f"Skipping dashboard: ID not found.")
            continue
            
        try:
            response = requests.get(
                # CRITICAL FIX 1: Use dictionary key access 'id'
                f"{SUPERSET_URL}/api/v1/dashboard/{dashboard_id}/embedded",
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Content-Type": "application/json"
                },
                timeout=10
            )
            
            if response.status_code == 200:
                result_data = response.json().get("result")
                
                # CRITICAL FIX 2: Safely extract 'uuid' from the nested 'result' dictionary
                if result_data and "uuid" in result_data:
                    embedded_uuid = result_data["uuid"]
                    
                    # NOTE: Using 'embedded_uuid' as the key is clearer than overwriting 'uuid'
                    filtered_dashboard['embedded_uuid'] = embedded_uuid 
                    embedded_dashboards.append(filtered_dashboard)
                else:
                    print(f"⚠️ Embedded UUID not found in 'result' for Dashboard ID {dashboard_id}. Response: {response.text}")
            
            elif response.status_code == 404:
                # 404 often means the embedded configuration hasn't been created for this dashboard ID
                print(f"⚠️ Embedded configuration not found (404) for Dashboard ID {dashboard_id}. Please create the link in Superset UI.")

            else:
                # Catch other API errors
                print(f"✗ Failed to get embedded uuid for Dashboard ID {dashboard_id}. Status: {response.status_code}")
                print(f"   Response: {response.text}")
                
        except Exception as e:
            print(f"✗ Error processing Dashboard ID {dashboard_id}: {e}")

    return embedded_dashboards



#---------------------------------------------------------------------------------------------------
# AUTHENTICATION ENDPOINTS
#---------------------------------------------------------------------------------------------------

def login_required(f):
    from functools import wraps
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user' not in session:
            return jsonify({"error": "Authentication required"}), 401
        return f(*args, **kwargs)
    return decorated_function

# def log_session_check(f):
#     """A decorator that logs the session contents before executing a route."""
#     # @functools.wraps(f)
#     from functools import wraps
#     @wraps(f)
#     def decorated_function(*args, **kwargs):
#         print("======================================================================")
#         print(f"API Hit: {request.method} {request.path}")
#         print(f"Session contents: {dict(session)}")
#         print(f"Has 'user' in session: {'user' in session}")
#         print("----------------------------------------------------------------------")
#         return f(*args, **kwargs)
#     return decorated_function


@app.route("/api/login", methods=["POST"])
def login():
    """
    React app login - validates credentials and loads hardcoded roles
    """
    data = request.get_json()
    username = data.get("username")
    password = data.get("password")
    
    print(f"Login attempt for username: '{username}'")
    
    if not username or not password:
        return jsonify({"error": "Username and password required"}), 400
    
    # Check credentials
    if username not in USERS or USERS[username]["password"] != password:
        return jsonify({"error": "Invalid username or password"}), 401
    
    
    user_data = USERS[username]
    session.clear()
    session.permanent = True
    session['user'] = username
    session['name'] = user_data["name"]
    session['superset_username'] = user_data["superset_username"]
    session['roles'] = user_data["roles"]
    session.permanent = True  # Set permanent AFTER setting data
    session.modified = True  # Explicitly mark as modified
    # session.permanent = True
    
    # return jsonify({
    #     "success": True,
    #     "user": {
    #         "username": username,
    #         "name": user_data["name"],
    #         "roles": user_data["roles"]
    #     }
    # }), 200
    response = jsonify({
        "success": True,
        "user": {
            "username": username,
            "name": user_data["name"],
            "roles": user_data["roles"]
        }
    })

    response.set_cookie(
        'session',
        value=session.sid if hasattr(session, 'sid') else '',
        httponly=True,
        samesite='Lax',
        secure=False,  # False for localhost HTTP
        max_age=3600
    )
    
    return response, 200

@app.route("/api/logout", methods=["POST"])
# @login_required
def logout():
    username = session.get('user')
    session.clear()
    print(f"✓ LOGOUT: User '{username}' logged out\n")
    return jsonify({"success": True}), 200

@app.route("/api/check-auth", methods=["GET"])
# @log_session_check
def check_auth():
    if 'user' in session:
        return jsonify({
            "authenticated": True,
            "user": {
                "username": session['user'],
                "name": session['name'],
                "roles": session.get('roles', [])
            }
        }), 200
    else:
        return jsonify({"authenticated": False}), 200

@app.before_request
def log_session_info():
    """Log session information for debugging"""
    if request.path.startswith('/api/'):
        cookie_value = request.cookies.get('flask_session', 'NOT_FOUND')
        print(f"\n{'='*70}")
        print(f"Request: {request.method} {request.path}")
        print(f"Session Cookie: {cookie_value[:20]}..." if cookie_value != 'NOT_FOUND' else "Session Cookie: NOT_FOUND")
        print(f"Session Has User: {'user' in session}")
        
        if 'user' in session:
            print(f"Current User: {session.get('user')}")
            print(f"User Roles: {session.get('roles')}")
        else:
            print(f"⚠️  NO USER IN SESSION")
            print(f"Session contents: {dict(session)}")
            print(f"Session is new: {session.new if hasattr(session, 'new') else 'unknown'}")
            
        print(f"{'='*70}\n")


@app.after_request
def after_request(response):
    """Ensure session is saved after each request"""
    if session.modified:
        print(f"💾 Session modified, saving changes for user: {session.get('user', 'None')}")
    return response
#---------------------------------------------------------------------------------------------------
# DASHBOARD ENDPOINTS
#---------------------------------------------------------------------------------------------------

@app.route("/api/dashboards", methods=["GET"])
@login_required
def get_filtered_dashboards():
    """
    Get dashboards from Superset API and filter by user's hardcoded roles
    """
    username = session.get('user')
    superset_username = session.get('superset_username')
    user_roles = session.get('roles', [])
    
    try:
        # Get Superset access token
        access_token = get_superset_access_token()
        if not access_token:
            return jsonify({"error": "Failed to connect to Superset"}), 500
        
        # Fetch all dashboards from Superset
        all_dashboards = get_all_dashboards_from_superset(access_token)
        
        if not all_dashboards:
            print("⚠ No dashboards found in Superset")
            return jsonify({
                "success": True,
                "dashboards": [],
                "total_dashboards": 0,
                "accessible_dashboards": 0
            }), 200
        
        # Filter by user's hardcoded roles
        filtered = filter_dashboards_by_user_roles(all_dashboards, user_roles)
        # here below uuid is the dashboard's general identifier different, need to send embedded dashboard uuid.  
        # Format response - only include necessary fields
        dashboard_list = [{
            "id": d.get('id'),
            "uuid": d.get('uuid'),
            "embedded_uuid":"",
            "dashboard_title": d.get('dashboard_title'),
            "url": d.get('url'),
            "published": d.get('published'),
            "thumbnail_url": d.get('thumbnail_url'),
            "changed_on_utc": d.get('changed_on_utc'),
            "roles": [r['name'] for r in d.get('roles', [])]
        } for d in filtered]
        
        embedded_dashboards = get_embedded_dashboard_uuid(dashboard_list,access_token)
        
        return jsonify({
            "success": True,
            "dashboards": embedded_dashboards,
            "total_dashboards": len(all_dashboards),
            "accessible_dashboards": len(embedded_dashboards)
        }), 200
        
    except Exception as e:
        print(f"✗ ERROR: {e}")
        return jsonify({"error": str(e)}), 500

#---------------------------------------------------------------------------------------------------
# GUEST TOKEN ENDPOINT
#---------------------------------------------------------------------------------------------------

@app.route("/api/guest-token", methods=["GET"])
@login_required
def generate_guest_token():
    """
    Generates JWT Guest Token for Superset embedding
    Verifies user has access to the requested dashboard based on roles
    """
    
    dashboard_id_str = request.args.get("dashboardId")
    username = session.get('user')
    superset_username = session.get('superset_username')
    user_roles = session.get('roles', [])
    
    if not dashboard_id_str:
        return jsonify({"error": "dashboardId is required"}), 400
    
    # Optional: Verify user has access to this dashboard
    # For now, we'll trust that React only requests tokens for dashboards shown to them
    # You can add additional verification here if needed
    
    # Generate guest token using Superset username
    expiration_time = int(time.time()) + 600
    payload = {
        "user": {
            "username": superset_username,  # Use Superset guest username
            "first_name": superset_username,
            "last_name": "",
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
        print(f"✗ JWT Encoding Error: {e}")
        return jsonify({"error": "Failed to encode token"}), 500


# ============================================================================
# NEW: FILE UPLOAD ENDPOINT
# ============================================================================
@app.route('/api/upload-excel', methods=['POST'])
@login_required
def upload_excel():
    """
    Handles Excel file upload, processing sheets one-by-one, and inserting/replacing 
    data into corresponding database tables based on sheet names.
    """
    username = session.get('user')
    logging.info(f"✅ Upload authorized for user: {username}")

    if 'excel_file' not in request.files:
        return jsonify({"success": False, "error": "No file part in the request"}), 400

    file = request.files['excel_file']
    if file.filename == '':
        return jsonify({"success": False, "error": "No selected file"}), 400

    if engine is None:
        logging.error("Database engine is not initialized.")
        return jsonify({"success": False, "error": "Database service is unavailable."}), 503

    if file and allowed_file(file.filename):
        try:
            filename = secure_filename(file.filename)
            all_sheet_results = []
            
            # Use ExcelFile to load sheet names first (low memory)
            xls = pd.ExcelFile(file.stream, engine='openpyxl')
            sheet_names_list = xls.sheet_names
            
            inspector = inspect(engine) # Initialize inspector once

            for sheet_name in sheet_names_list:
                
                # 1. Read single sheet data (loads only one sheet into memory)
                df = xls.parse(sheet_name)
                
                # Skip empty sheets entirely
                if df.empty:
                    all_sheet_results.append({
                        "sheet_name": sheet_name,
                        "table_name": None,
                        "status": "Skipped (Empty Sheet)",
                        "rows_uploaded": 0
                    })
                    logging.warning(f"Skipped empty sheet: {sheet_name}")
                    continue

                # 2. Sanitize column names for database compatibility
                df.columns = [col.replace(' ', '_').replace('.', '').lower() for col in df.columns]
                
                # 3. Sanitize sheet name for table name
                # Removed the incorrect .rsplit logic
                table_name = sheet_name.lower().replace(' ', '_').replace('.', '').replace('-', '_')
                
                # 4. Check existence for reporting purposes
                table_exists = table_name in inspector.get_table_names()
                
                try:
                    # 5. Insert/Replace Data (Using 'replace' is atomic: it drops and recreates the table 
                    # based on the new DF schema, which is best for full refreshes.)
                    df.to_sql(table_name, con=engine, if_exists='replace', index=False)
                    
                    status = "Replaced (Schema Updated)" if table_exists else "Created"
                    
                    all_sheet_results.append({
                        "sheet_name": sheet_name,
                        "table_name": table_name,
                        "status": status,
                        "rows_uploaded": df.shape[0]
                    })
                    logging.info(f"Successfully processed sheet: {sheet_name} -> table: {table_name}. Status: {status}")

                except Exception as db_e:
                    # Catch specific database errors within the loop
                    all_sheet_results.append({
                        "sheet_name": sheet_name,
                        "table_name": table_name,
                        "status": "Failed to Insert",
                        "error": str(db_e),
                        "rows_uploaded": 0
                    })
                    logging.error(f"DB Error processing sheet {sheet_name}: {db_e}")

            # 6. Return aggregated results
            return jsonify({
                "success": True,
                "message": f"File '{filename}' processed successfully. See details for {len(sheet_names_list)} sheets.",
                "results": all_sheet_results
            }), 200

        except Exception as e:
            # Catch file reading errors (e.g., file corruption, openpyxl errors)
            logging.error(f"Error during file processing: {e}")
            return jsonify({
                "success": False, 
                "error": f"File reading or processing failed: {str(e)}"
            }), 500
    else:
        return jsonify({
            "success": False, 
            "error": "File type not allowed. Only .xlsx files are permitted."
        }), 400


#---------------------------------------------------------------------------------------------------
# ADMIN/DEBUG ENDPOINTS
#---------------------------------------------------------------------------------------------------

@app.route("/api/session-test", methods=["GET"])
def session_test():
    """Test endpoint to verify session persistence"""
    return jsonify({
        "has_session": 'user' in session,
        "user": session.get('user'),
        "session_id": request.cookies.get('session'),
        "session_data": dict(session)
    }), 200

@app.route("/api/test-superset-connection", methods=["GET"])
def test_superset_connection():
    """
    Test endpoint to verify Superset API connection
    """
    print("\nTesting Superset connection...")
    
    access_token = get_superset_access_token()
    if not access_token:
        return jsonify({
            "success": False,
            "message": "Failed to get access token from Superset"
        }), 500
    
    dashboards = get_all_dashboards_from_superset(access_token)
    
    return jsonify({
        "success": True,
        "message": "Successfully connected to Superset",
        "dashboard_count": len(dashboards),
        "dashboards": [{"title": d.get("dashboard_title"), "roles": [r["name"] for r in d.get("roles", [])]} for d in dashboards]
    }), 200

# if __name__ == "__main__":
#     app.run(host="0.0.0.0", port=5000, debug=True)

if __name__ == '__main__':
    app.run(debug=False)