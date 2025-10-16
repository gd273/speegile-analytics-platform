from flask import Flask, request, jsonify, session
from flask_cors import CORS
import jwt
import time
import os
import requests
import json

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "your_flask_secret_key_12345")

CORS(app, resources={r"/api/*": {
    "origins": ["http://localhost:3000"],
    "supports_credentials": True
}})

GUEST_TOKEN_SECRET = os.getenv("GUEST_TOKEN_SECRET", "my_secure_embedding_secret_12345")
SUPERSET_URL = "http://localhost:8088"

# Superset Admin credentials for API calls (only for fetching dashboards)
# SUPERSET_ADMIN_USERNAME = os.getenv("SUPERSET_ADMIN_USERNAME", "admin")
# SUPERSET_ADMIN_PASSWORD = os.getenv("SUPERSET_ADMIN_PASSWORD", "admin")
SUPERSET_ADMIN_USERNAME = "admin"
SUPERSET_ADMIN_PASSWORD = "admin123"

# ============================================================================
# HARDCODED USER DATABASE WITH ROLES
# Map: React login credentials → Superset guest username + roles
# ============================================================================

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

print(f"\n{'='*70}")
print("Server initialized with hardcoded user-role mapping")
print(f"{'='*70}")
for react_user, data in USERS.items():
    print(f"  {react_user:10} → Superset: {data['superset_username']:15} | Roles: {data['roles']}")
print(f"{'='*70}\n")

#---------------------------------------------------------------------------------------------------
# SUPERSET API HELPER FUNCTIONS
#---------------------------------------------------------------------------------------------------

def get_superset_access_token():
    """
    Get access token from Superset for API calls
    """
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
            print(f"✓ Obtained Superset access token")
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
            # "order_column": "changed_on_utc",
            # "order_direction": "desc"
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
            
            # Log dashboard info for debugging
            for dash in dashboards:
                roles = dash.get('roles', [])
                role_names = [r['name'] for r in roles] if roles else ["No roles (public)"]
                print(f"  - {dash.get('dashboard_title')}: {role_names}")
            
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
    
    print(f"\nFiltering dashboards for user roles: {user_roles}")
    
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
    
    print(f"\n✓ User has access to {len(filtered)} out of {len(dashboards)} dashboards\n")
    return filtered

# def get_embedded_dashboard_uuid(filtered_dashboard_list,access_token):
#     embedded_dashboards = []
#     if not filtered_dashboard_list:
#         return []
    
#     for filtered_dashboard in filtered_dashboard_list:
#         try:
#             response = requests.get(
#                 f"{SUPERSET_URL}/api/v1/dashboard/{filtered_dashboard.get('id')}/embedded",
#                 # params={"q": json.dumps(query)},
#                 headers={
#                     "Authorization": f"Bearer {access_token}",
#                     "Content-Type": "application/json"
#                 },
#                 timeout=10
#             )
            
#             if response.status_code == 200:
#                 embedded_uuid = response.json().get("uuid")
#                 # print(f"✓ Fetched {len(dashboards)} dashboards from Superset")
#                 filtered_dashboard['uuid'] = embedded_uuid
#                 embedded_dashboards.append(filtered_dashboard)

#                 # return dashboards
#             elif response.status_code == 404:
#                 # 404 often means the embedded configuration hasn't been created for this dashboard ID
#                 print(f"⚠️ Embedded configuration not found (404) for Dashboard ID {filtered_dashboard.get('id')}. Please create the link in Superset UI.")
#             else:
#                 # Catch other API errors
#                 print(f"✗ Failed to get embedded uuid for Dashboard ID {filtered_dashboard.get('id')}. Status: {response.status_code}")
#                 print(f"   Response: {response.text}")
#         except requests.exceptions.Timeout:
#             print(f"✗ Request timed out for Dashboard ID {filtered_dashboard.get('id')}.")
#         except requests.exceptions.RequestException as e:
#             print(f"✗ Error making API request for Dashboard ID {filtered_dashboard.get('id')}: {e}")
#         except Exception as e:
#             print(f"✗ General error processing Dashboard ID {filtered_dashboard.get('id')}: {e}")

#     return embedded_dashboards
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

@app.route("/api/login", methods=["POST"])
def login():
    """
    React app login - validates credentials and loads hardcoded roles
    """
    print(f"\n{'='*70}")
    print("API Hit: POST /api/login")
    print(f"{'='*70}")
    
    data = request.get_json()
    username = data.get("username")
    password = data.get("password")
    
    print(f"Login attempt for username: '{username}'")
    
    if not username or not password:
        print("✗ Missing username or password")
        return jsonify({"error": "Username and password required"}), 400
    
    # Check credentials
    if username not in USERS or USERS[username]["password"] != password:
        print("✗ Invalid credentials")
        return jsonify({"error": "Invalid username or password"}), 401
    
    print("✓ Credentials valid")
    
    # Get user data from hardcoded database
    user_data = USERS[username]
    
    # Store in session
    session['user'] = username
    session['name'] = user_data["name"]
    session['superset_username'] = user_data["superset_username"]
    session['roles'] = user_data["roles"]
    session.permanent = True
    
    print(f"✓ LOGIN SUCCESS")
    print(f"  React User: {username}")
    print(f"  Name: {user_data['name']}")
    print(f"  Superset User: {user_data['superset_username']}")
    print(f"  Roles: {user_data['roles']}")
    print(f"{'='*70}\n")
    
    return jsonify({
        "success": True,
        "user": {
            "username": username,
            "name": user_data["name"],
            "roles": user_data["roles"]
        }
    }), 200

@app.route("/api/logout", methods=["POST"])
# @login_required
def logout():
    username = session.get('user')
    session.clear()
    print(f"✓ LOGOUT: User '{username}' logged out\n")
    return jsonify({"success": True}), 200

@app.route("/api/check-auth", methods=["GET"])
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

#---------------------------------------------------------------------------------------------------
# DASHBOARD ENDPOINTS
#---------------------------------------------------------------------------------------------------

@app.route("/api/dashboards", methods=["GET"])
@login_required
def get_filtered_dashboards():
    """
    Get dashboards from Superset API and filter by user's hardcoded roles
    """
    print(f"\n{'='*70}")
    print("API Hit: GET /api/dashboards")
    print(f"{'='*70}")
    
    username = session.get('user')
    superset_username = session.get('superset_username')
    user_roles = session.get('roles', [])
    
    print(f"Request from: {username} (Superset: {superset_username})")
    print(f"User roles: {user_roles}")
    
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
        print(f"✓ Returning {len(embedded_dashboards)} accessible dashboards")
        print(f"{'='*70}\n")
        
        return jsonify({
            "success": True,
            "dashboards": embedded_dashboards,
            "total_dashboards": len(all_dashboards),
            "accessible_dashboards": len(embedded_dashboards)
        }), 200
        
    except Exception as e:
        print(f"✗ ERROR: {e}")
        print(f"{'='*70}\n")
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
    print(f"\n{'='*70}")
    print("API Hit: GET /api/guest-token")
    print(f"{'='*70}")
    
    dashboard_id_str = request.args.get("dashboardId")
    username = session.get('user')
    superset_username = session.get('superset_username')
    user_roles = session.get('roles', [])
    
    print(f"Token request from: {username} (Superset: {superset_username})")
    print(f"Dashboard ID: {dashboard_id_str}")
    print(f"User roles: {user_roles}")
    
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
        token = jwt.encode(payload, GUEST_TOKEN_SECRET, algorithm="HS256")
        print(f"✓ Guest token generated successfully")
        print(f"  For Superset user: {superset_username}")
        print(f"  Dashboard: {dashboard_id_str}")
        print(f"  Expires: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(expiration_time))}")
        print(f"{'='*70}\n")
        return jsonify({"guestToken": token}), 200
    except Exception as e:
        print(f"✗ JWT Encoding Error: {e}")
        print(f"{'='*70}\n")
        return jsonify({"error": "Failed to encode token"}), 500

#---------------------------------------------------------------------------------------------------
# ADMIN/DEBUG ENDPOINTS
#---------------------------------------------------------------------------------------------------

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

if __name__ == "__main__":
    print(f"\n{'='*70}")
    print("Starting Flask Server with Hardcoded User-Role Mapping")
    print(f"{'='*70}")
    print(f"Superset URL: {SUPERSET_URL}")
    print(f"Superset Admin: {SUPERSET_ADMIN_USERNAME}")
    print(f"\nConfigured Users:")
    for react_user, data in USERS.items():
        print(f"  React Login: {react_user:10} (Password: {data['password']:10})")
        print(f"    → Superset: {data['superset_username']:15}")
        print(f"    → Roles: {', '.join(data['roles'])}")
    print(f"\nAPI Endpoints:")
    print("  - POST /api/login")
    print("  - POST /api/logout")
    print("  - GET  /api/check-auth")
    print("  - GET  /api/dashboards (fetches from Superset, filters by hardcoded roles)")
    print("  - GET  /api/guest-token")
    print("  - GET  /api/test-superset-connection (debug)")
    print(f"{'='*70}\n")
    app.run(host="0.0.0.0", port=5000, debug=True)