#!/bin/sh
# usage: wait-for-db.sh host port timeout_seconds
HOST="$1"
PORT="${2:-5432}"
TIMEOUT="${3:-30}"

echo "Waiting for $HOST:$PORT (timeout ${TIMEOUT}s)..."
while ! nc -z "$HOST" "$PORT" 2>/dev/null; do
  TIMEOUT=$((TIMEOUT-1))
  if [ "$TIMEOUT" -le 0 ]; then
    echo "Timed out waiting for $HOST:$PORT"
    exit 1
  fi
  sleep 1
done
echo "$HOST:$PORT is available"
exit 0
