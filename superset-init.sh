#!/bin/bash
set -e

echo "Running Superset Init Script..."

# 1. Initialize DB (SAFE to run multiple times)
superset db upgrade

# 2. Init Roles (SAFE to run multiple times)
superset init

# 3. Create Admin (only if env vars are present)
# This will fail harmlessly if the user already exists
if [ "$SUPERSET_ADMIN_USERNAME" ]; then
    echo "Creating admin user $SUPERSET_ADMIN_USERNAME..."
    superset fab create-admin \
        --username "$SUPERSET_ADMIN_USERNAME" \
        --firstname "Superset" \
        --lastname "Admin" \
        --email "admin@example.com" \
        --password "$SUPERSET_ADMIN_PASSWORD" \
        || true
fi

# 4. Start Server
echo "Starting Server..."
/usr/bin/run-server.sh