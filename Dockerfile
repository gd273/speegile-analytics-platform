

FROM apache/superset:latest
USER root

RUN apt-get update && apt-get install -y \
    pkg-config \
    default-libmysqlclient-dev \
    python3-dev \
    build-essential \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Bootstrap pip inside the Superset virtualenv
RUN /app/.venv/bin/python3 -m ensurepip
RUN /app/.venv/bin/python3 -m pip install --upgrade pip

# Install required Python packages inside virtualenv
RUN /app/.venv/bin/python3 -m pip install \
    mysqlclient PyMySQL mysql-connector-python psycopg2-binary

USER superset
