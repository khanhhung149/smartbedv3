#!/usr/bin/env bash
# Apply every schema file, in order, to the running postgres container.
#
# docker-compose mounts init.sql into /docker-entrypoint-initdb.d, which Postgres
# only executes when the data volume is empty. Any database that already holds
# data therefore never sees a new schema file — that is how smart_watch_data.sql
# ended up unreachable. This script closes that gap: every statement below is
# IF NOT EXISTS, so running it against a live database is safe and repeatable.
#
# Usage (from backend/):
#   set -a && source .env.dev && set +a
#   bash scripts/apply-schema.sh
set -euo pipefail

cd "$(dirname "$0")/.."

: "${POSTGRES_USER:?set it by sourcing .env.dev first}"
: "${POSTGRES_DB:?set it by sourcing .env.dev first}"

CONTAINER="${POSTGRES_CONTAINER:-sleeppad-postgres}"

if ! docker inspect -f '{{.State.Running}}' "$CONTAINER" >/dev/null 2>&1; then
  echo "container '$CONTAINER' is not running — start postgres first" >&2
  exit 1
fi

for f in postgres/init.sql postgres/smart_watch_data.sql postgres/sleep_sessions.sql postgres/samples.sql; do
  echo "-> $f"
  docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 \
    -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$f"
done

echo "schema applied"
