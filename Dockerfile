

# FROM apache/superset:latest
# USER root

# RUN apt-get update && apt-get install -y \
#     pkg-config \
#     default-libmysqlclient-dev \
#     python3-dev \
#     build-essential \
#     && apt-get clean \
#     && rm -rf /var/lib/apt/lists/*

# # Bootstrap pip inside the Superset virtualenv
# RUN /app/.venv/bin/python3 -m ensurepip
# RUN /app/.venv/bin/python3 -m pip install --upgrade pip

# # Install required Python packages inside virtualenv
# RUN /app/.venv/bin/python3 -m pip install \
#     mysqlclient PyMySQL mysql-connector-python psycopg2-binary

# USER superset

FROM apache/superset:latest

USER root

# Install system dependencies needed for MySQL, PostgreSQL, etc.
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

# Install Python packages
COPY requirements-custom-docker.txt /app/requirements.txt
# RUN pip install --no-cache-dir --timeout=300 -r /app/requirements.txt
# RUN bash -c "source /app/.venv/bin/activate && pip install --no-cache-dir --timeout=300 -r /app/requirements.txt"
# RUN /usr/bin/superset-install-db-drivers
RUN pip install --no-cache-dir --timeout=300 -r /app/requirements.txt --target /app/.venv/lib/python3.10/site-packages

USER superset
