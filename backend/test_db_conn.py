import os
import sqlalchemy as sa
from dotenv import load_dotenv
from pathlib import Path
from sqlalchemy import text

# Load .env from repo root
BASE = Path(__file__).resolve().parents[1]
load_dotenv(str(BASE / ".env"))

# Expand env vars (handles ${...} style)
url = os.path.expandvars(os.getenv("APP_DATABASE_URL") or "")
print("URL =", url)

# Create engine and test
engine = sa.create_engine(url)
try:
    with engine.connect() as conn:
        print("SELECT 1 ->", conn.execute(text("SELECT 1")).fetchone())
except Exception as e:
    print("ERROR:", e)
