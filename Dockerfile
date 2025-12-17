FROM apache/superset:latest

USER root

# Install system dependencies needed for some Python packages
RUN apt-get update && apt-get install -y \
    build-essential \
    default-libmysqlclient-dev \
    libpq-dev \
    gcc \
    g++ \
    libffi-dev \
    python3-dev \
    pkg-config \
    netcat-openbsd \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Copy requirements file into image
COPY requirements-custom-docker.txt /app/requirements.txt

# Ensure pip is available inside /app/.venv, then install requirements into that venv
# Use python -m ensurepip to bootstrap pip if missing, then upgrade pip, then install requirements
RUN if [ -x /app/.venv/bin/python ]; then \
      /app/.venv/bin/python -m ensurepip --upgrade || true; \
      /app/.venv/bin/python -m pip install --upgrade pip setuptools wheel || true; \
      /app/.venv/bin/python -m pip install --no-cache-dir --timeout=300 -r /app/requirements.txt ; \
    else \
      # Fallback: install into system python if venv not present
      python3 -m pip install --upgrade pip setuptools wheel ; \
      python3 -m pip install --no-cache-dir --timeout=300 -r /app/requirements.txt ; \
    fi

# --- NEW SECTIONS START HERE (CRITICAL FOR RENDER) ---

# 4. Copy the Superset Config
# We must copy from your local 'config/' folder to where Superset looks (/app/pythonpath)
COPY config/superset_config.py /app/pythonpath/superset_config.py

# 5. Copy the startup script & make it executable
COPY superset-init.sh /app/superset-init.sh
RUN chmod +x /app/superset-init.sh

# --- NEW SECTIONS END HERE ---

USER superset

# 6. Set the entrypoint to our custom init script
# This forces Render to run your migration script every time it starts
ENTRYPOINT ["/app/superset-init.sh"]