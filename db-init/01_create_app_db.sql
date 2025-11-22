-- 1. Create the database (Must be run as a standalone command)
CREATE DATABASE clientdata;

-- 2. Create the user (We can keep the check here if you want, or simplify it)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'client') THEN
    CREATE ROLE client LOGIN PASSWORD 'client123';
  ELSE
    ALTER ROLE client WITH LOGIN PASSWORD 'client123';
  END IF;
END
$$;

-- 3. Grant permissions
GRANT ALL PRIVILEGES ON DATABASE clientdata TO client;
ALTER DATABASE clientdata OWNER TO client;