# backend/Dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install system deps needed for psycopg2, pandas etc.
RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    gcc \
    netcat-openbsd \
  && rm -rf /var/lib/apt/lists/*

# Copy requirements and install (NOTE: paths are relative to build context ./backend)
COPY backend/requirements.txt /app/requirements.txt

RUN python -m pip install --upgrade pip setuptools wheel
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copy app code (context root -> /app)
COPY . /app

# Make the wait script executable
RUN chmod +x /app/backend/wait-for-db.sh
RUN pip install gunicorn
EXPOSE 5000
# CMD ["sh", "-c", "/app/wait-for-db.sh db 5432 30 && python app.py"]
# CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:5000", "app:app"]
# Do NOT use "flask run"
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "3", "--timeout", "120", "app:app"]