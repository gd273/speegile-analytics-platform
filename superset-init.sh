#!/bin/bash
set -e

echo "Running Superset Init Script..."

# Wait for database to be ready
echo "Waiting for database..."
sleep 5

# 1. Initialize DB
echo "Initializing database..."
superset db upgrade

# 2. Init Roles
echo "Initializing roles..."
superset init

# 3. Create Admin
if [ "$SUPERSET_ADMIN_USERNAME" ]; then
    echo "Creating admin user $SUPERSET_ADMIN_USERNAME..."
    superset fab create-admin \
        --username "$SUPERSET_ADMIN_USERNAME" \
        --firstname "Superset" \
        --lastname "Admin" \
        --email "$SUPERSET_ADMIN_EMAIL" \
        --password "$SUPERSET_ADMIN_PASSWORD" \
        2>/dev/null || echo "Admin user may already exist"
fi

# 4. Start Server
echo "Starting Gunicorn server..."
gunicorn \
    --bind "0.0.0.0:8088" \
    --access-logfile - \
    --error-logfile - \
    --workers 1 \
    --worker-class gthread \
    --threads 20 \
    --timeout 60 \
    --limit-request-line 0 \
    --limit-request-field_size 0 \
    "superset.app:create_app()"