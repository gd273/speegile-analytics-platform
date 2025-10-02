from flask import Flask, request, jsonify
from flask_cors import CORS
import jwt
import time
import os

app = Flask(__name__)
# Allow CORS from React dev server
CORS(app, resources={r"/api/*": {"origins": ["http://localhost:3000"]}})

# This secret must match GUEST_TOKEN_JWT_SECRET in superset_config.py
GUEST_TOKEN_SECRET = os.getenv("GUEST_TOKEN_SECRET", "my_secure_embedding_secret_12345")
print(f"Server initialized with GUEST_TOKEN_SECRET: {GUEST_TOKEN_SECRET}")
print("API Endpoint available: /api/guest-token")
#---------------------------------------------------------------------------------------------------

@app.route("/api/guest-token", methods=["GET"])
def generate_guest_token():
    """
    Generates a JWT Guest Token for embedding a Superset dashboard.
    The frontend (React) is responsible for embedding the dashboard using this token.
    """
    # 1. API Call Start
    print("\n--- API Hit: /api/guest-token (GET) ---")
    
    dashboard_id_str = request.args.get("dashboardId")
    
    # 2. View Input Value
    print(f"Received dashboardId query parameter: {dashboard_id_str}")
    
    if not dashboard_id_str:
        # 3. View Response and Code Process (Error 400)
        print("CODE PROCESS: Validation failed. dashboardId is missing.")
        response = jsonify({"error": "dashboardId is required"})
        print(f"API Response: {response.get_data(as_text=True)} with status 400")
        return response, 400

    # 5. View Payload Values
    expiration_time = int(time.time()) + 600
    payload = {
        "user": {
            "username": "admin",
            "first_name": "Admin",
            "last_name": "User",
        },
        "resources": [
            {
                "type": "dashboard",
                "id": dashboard_id_str
            }
        ],
        "rls": [],  # Row-Level Security filters
        "exp": expiration_time,  # Token valid for 10 minutes
        "aud": "superset"
    }
    print(f"Generated JWT Payload (User/Resources/Exp): admin/{dashboard_id_str}/{expiration_time}")

    try:
        # 6. View Encoding Process
        print(f"CODE PROCESS: Attempting to encode JWT with algorithm HS256 and secret length {len(GUEST_TOKEN_SECRET)}...")
        token = jwt.encode(payload, GUEST_TOKEN_SECRET, algorithm="HS256")
        
    except Exception as e:
        # 7. View Error if Encoding Fails (Error 500)
        print(f"JWT Encoding Error: {e}")
        response = jsonify({"error": "Failed to encode token"})
        print(f"API Response: {response.get_data(as_text=True)} with status 500")
        return response, 500

    # 8. View Final Token and Response
    print("CODE PROCESS: Token successfully encoded.")
    print(f"Generated Guest Token (first 30 chars): {token[:30]}...") # Show a snippet of the token
    
    response = jsonify({
        "guestToken": token
    })
    print(f"API Response: Success with token snippet {token[:10]}... and status 200")
    print("---------------------------------------")
    return response

if __name__ == "__main__":
    print("--- Starting Flask Server ---")
    app.run(host="0.0.0.0", port=5000, debug=True)
    print("-----------------------------")
# from flask import Flask, request, jsonify
# from flask_cors import CORS
# import jwt
# import time
# import os

# app = Flask(__name__)
# # Allow CORS from React dev server
# CORS(app, resources={r"/api/*": {"origins": ["http://localhost:3000"]}})

# # This secret must match GUEST_TOKEN_JWT_SECRET in superset_config.py
# GUEST_TOKEN_SECRET = os.getenv("GUEST_TOKEN_SECRET", "my_secure_embedding_secret_12345")

# @app.route("/api/guest-token", methods=["GET"])
# def generate_guest_token():
#     """
#     Generates a JWT Guest Token for embedding a Superset dashboard.
#     The frontend (React) is responsible for embedding the dashboard using this token.
#     """
#     dashboard_id_str = request.args.get("dashboardId")
#     print("Received dashboardId:", dashboard_id_str)
#     if not dashboard_id_str:
#         return jsonify({"error": "dashboardId is required"}), 400

#     try:
#         dashboard_id = int(dashboard_id_str)
#     except ValueError:
#         return jsonify({"error": "dashboardId must be an integer"}), 400

#     # Guest token payload required by Superset
#     payload = {
#         "user": {
#             "username": "admin",
#             "first_name": "Admin",
#             "last_name": "User",
#             # "username": "guest_user",
#             # "first_name": "Guest",
#             # "last_name": "User",
#         },
#         "resources": [
#             {
#                 "type": "dashboard",
#                 "id": dashboard_id
#             }
#         ],
#         "rls": [],  # Row-Level Security filters
#         "exp": int(time.time()) + 600  # Token valid for 10 minutes
#     }

#     try:
#         token = jwt.encode(payload, GUEST_TOKEN_SECRET, algorithm="HS256")
#     except Exception as e:
#         print(f"JWT Encoding Error: {e}")
#         return jsonify({"error": "Failed to encode token"}), 500

#     return jsonify({
#         "guestToken": token
#     })

# if __name__ == "__main__":
#     app.run(host="0.0.0.0", port=5000, debug=True)






# from flask import Flask, request, jsonify
# from flask_cors import CORS
# import jwt
# import time
# import os

# app = Flask(__name__)
# # Allow CORS from React dev server
# CORS(app, resources={r"/api/*": {"origins": ["http://localhost:3000"]}})

# # This secret must match GUEST_TOKEN_JWT_SECRET in superset_config.py
# GUEST_TOKEN_SECRET = os.getenv("GUEST_TOKEN_SECRET", "my_secure_embedding_secret_12345")
# print(f"Server initialized with GUEST_TOKEN_SECRET: {GUEST_TOKEN_SECRET}")
# print("API Endpoint available: /api/guest-token")

# @app.route("/api/guest-token", methods=["GET"])
# def generate_guest_token():
#     """
#     Generates a JWT Guest Token for embedding a Superset dashboard.
#     The frontend (React) is responsible for embedding the dashboard using this token.
#     """
#     print("\n--- API Hit: /api/guest-token (GET) ---")
    
#     dashboard_id_str = request.args.get("dashboardId")
#     print(f"Received dashboardId query parameter: {dashboard_id_str}")
    
#     if not dashboard_id_str:
#         print("CODE PROCESS: Validation failed. dashboardId is missing.")
#         response = jsonify({"error": "dashboardId is required"})
#         print(f"API Response: {response.get_data(as_text=True)} with status 400")
#         return response, 400

#     # try:
#     #     dashboard_id = int(dashboard_id_str)
#     #     print(f"CODE PROCESS: Dashboard ID validated as integer: {dashboard_id}")
#     # except ValueError:
#     #     print("CODE PROCESS: Validation failed. dashboardId is not an integer.")
#     #     response = jsonify({"error": "dashboardId must be an integer"})
#     #     print(f"API Response: {response.get_data(as_text=True)} with status 400")
#     #     return response, 400

#     # Guest token payload required by Superset 5.0.0
#     expiration_time = int(time.time()) + 600
#     payload = {
#         "user": {
#             "username": "guest_user",
#             "first_name": "Guest",
#             "last_name": "User",
#         },
#         "resources": [
#             {
#                 "type": "dashboard",
#                 "id": dashboard_id_str  # Integer, not string
#             }
#         ],
#         "rls": [],  # Row-Level Security filters (empty = unrestricted)
#         "exp": expiration_time  # Token valid for 10 minutes
#     }
#     print(f"Generated JWT Payload: guest_user/dashboard-{dashboard_id_str}/exp-{expiration_time}")

#     try:
#         print(f"CODE PROCESS: Encoding JWT with HS256 algorithm...")
#         token = jwt.encode(payload, GUEST_TOKEN_SECRET, algorithm="HS256")
#         print("CODE PROCESS: Token successfully encoded.")
#         print(f"Generated Guest Token (first 30 chars): {token[:30]}...")
#     except Exception as e:
#         print(f"JWT Encoding Error: {e}")
#         response = jsonify({"error": "Failed to encode token"})
#         print(f"API Response: {response.get_data(as_text=True)} with status 500")
#         return response, 500

#     response = jsonify({"guestToken": token})
#     print(f"API Response: Success with status 200")
#     print("---------------------------------------")
#     return response

# if __name__ == "__main__":
#     print("--- Starting Flask Server ---")
#     app.run(host="0.0.0.0", port=5000, debug=True)