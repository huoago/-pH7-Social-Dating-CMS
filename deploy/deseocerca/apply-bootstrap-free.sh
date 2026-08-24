#!/usr/bin/env bash
set -euo pipefail
REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
ENV_FILE="${DESEOCERCA_ENV_FILE:-$REMOTE_DIR/.env}"
COMPOSE_FILE="$REMOTE_DIR/deploy/deseocerca/compose.free.yml"

read_env_value() {
  local key="$1"
  local line
  line="$(grep -m1 -E "^${key}=" "$ENV_FILE" || true)"
  [ -n "$line" ] || return 1
  printf '%s' "${line#*=}"
}

TIDB_USER="$(read_env_value TIDB_USERNAME)" || { echo "TIDB_USERNAME missing." >&2; exit 1; }
TIDB_DATABASE="$(read_env_value TIDB_DATABASE)" || { echo "TIDB_DATABASE missing." >&2; exit 1; }

cd "$REMOTE_DIR"
compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
"${compose[@]}" exec -T app test -s /var/www/html/_constants.php || {
  echo "Complete the browser installer first." >&2
  exit 1
}
db_prefix="$("${compose[@]}" exec -T app php -r '$c=parse_ini_file("/var/www/html/_protected/app/configs/config.ini", true); echo $c["database"]["prefix"] ?? "";')"
[ "$db_prefix" = "ph7_" ] || { echo "bootstrap.sql requires prefix ph7_." >&2; exit 1; }

"${compose[@]}" run --rm --no-deps -T --entrypoint mysql db-client \
  --host=db-tls --port=3306 --user="$TIDB_USER" "$TIDB_DATABASE" \
  < deploy/deseocerca/bootstrap.sql

"${compose[@]}" exec -T app php deploy/deseocerca/verify-runtime.php
echo "DeseoCerca free-tier bootstrap applied and verified."
