#!/bin/bash
set -e

echo "--- 1. Creating Logical Databases (Idempotent) ---"
# We use \gexec to run the CREATE command ONLY if the DB does not exist.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE DATABASE superset_metastore'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'superset_metastore')\gexec
    
    SELECT 'CREATE DATABASE client_analytics'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'client_analytics')\gexec

    GRANT ALL PRIVILEGES ON DATABASE superset_metastore TO "$POSTGRES_USER";
    GRANT ALL PRIVILEGES ON DATABASE client_analytics TO "$POSTGRES_USER";
EOSQL

echo "--- 2. Setting up the Lobby (client_analytics -> public) ---"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "client_analytics" <<-EOSQL
    
    -- A. TENANTS
    CREATE TABLE IF NOT EXISTS tenants (
        id SERIAL PRIMARY KEY,
        tenant_name VARCHAR(255) NOT NULL,
        schema_name VARCHAR(63) UNIQUE NOT NULL,
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    -- B. USERS
    CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        email VARCHAR(255) UNIQUE NOT NULL,
        password_hash VARCHAR(255) NOT NULL,
        name VARCHAR(100),
        role VARCHAR(50) DEFAULT 'viewer',
        tenant_id INTEGER REFERENCES tenants(id),
        superset_username VARCHAR(100),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    -- C. TEMPLATES
    CREATE TABLE IF NOT EXISTS tenant_templates (
        id SERIAL PRIMARY KEY,
        tenant_id INTEGER REFERENCES tenants(id),
        logo_url VARCHAR(500),
        menu_config JSONB
    );

    -- 1. NEW: Load Master (Now in PUBLIC)
    CREATE TABLE IF NOT EXISTS public.load_master (
        id SERIAL PRIMARY KEY,
        tenant_id INTEGER REFERENCES public.tenants(id), -- Added explicit link
        user_id INTEGER REFERENCES public.users(id),
        filename VARCHAR(255),
        status VARCHAR(50) DEFAULT 'Processing', -- 'Pass', 'Fail', 'Processing'
        started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    -- 2. NEW: Load Errors (Now in PUBLIC)
    CREATE TABLE IF NOT EXISTS public.load_errors (
        id SERIAL PRIMARY KEY,
        load_id INTEGER REFERENCES public.load_master(id),
        row_number INTEGER,
        column_name VARCHAR(255),
        error_message TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    -- SEED: Tenant 1 (Green Energy)
    INSERT INTO tenants (tenant_name, schema_name) 
    VALUES ('Green Energy', 'tenant_green_energy')
    ON CONFLICT (schema_name) DO NOTHING; -- Prevents error on restart
    
    INSERT INTO tenant_templates (tenant_id, logo_url) 
    VALUES (1, '/assets/logos/green_energy.png')
    ON CONFLICT DO NOTHING;

    -- SEED: Admin User
    INSERT INTO users (email, password_hash, name, role, tenant_id, superset_username)
    VALUES ('admin', 'admin123', 'Tenant Admin', 'Admin', 1, 'admin')
    ON CONFLICT (email) DO NOTHING;

    -- D. CREATE TENANT SCHEMA
    CREATE SCHEMA IF NOT EXISTS tenant_green_energy;
    

EOSQL

echo "--- Database Init Complete ---"