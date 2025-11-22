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

USER superset
