#!/usr/bin/env bash
set -Eeuo pipefail

REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
ENV_FILE="${DESEOCERCA_ENV_FILE:-$REMOTE_DIR/.env}"
COMPOSE_FILE="${DESEOCERCA_COMPOSE_FILE:-}"
STATE_FILE="${DESEOCERCA_RELEASE_STATE_FILE:-/root/deseocerca-production-release.env}"
RESTORE_SITE=false

if [ "${1:-}" = "--restore-site" ]; then
  RESTORE_SITE=true
elif [ -n "${1:-}" ]; then
  echo "Usage: $0 [--restore-site]" >&2
  exit 2
fi

if [ "${EUID}" -ne 0 ]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi
if [ ! -s "$STATE_FILE" ] || [ ! -d "$REMOTE_DIR/.git" ] || [ ! -f "$ENV_FILE" ]; then
  echo "Production release state is unavailable." >&2
  exit 2
fi

read_state() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$STATE_FILE"
}

read_env_value() {
  local key="$1"
  local line
  line="$(grep -m1 -E "^${key}=" "$ENV_FILE" || true)"
  [ -n "$line" ] || return 1
  printf '%s' "${line#*=}"
}

previous_sha="$(read_state previous_sha)"
previous_site_b64="$(read_state previous_site_address_b64)"
previous_image_b64="$(read_state previous_app_image_b64)"
state_free_tier="$(read_state free_tier)"
if [[ ! "$previous_sha" =~ ^[a-f0-9]{40}$ ]]; then
  echo "Stored previous_sha is invalid." >&2
  exit 1
fi

FREE_TIER=false
if [ "$state_free_tier" = "true" ] || grep -Eq '^TIDB_HOST=.+$' "$ENV_FILE"; then
  FREE_TIER=true
fi
if [ -z "$COMPOSE_FILE" ]; then
  if [ "$FREE_TIER" = true ]; then
    COMPOSE_FILE="$REMOTE_DIR/deploy/deseocerca/compose.free.yml"
  else
    COMPOSE_FILE="$REMOTE_DIR/deploy/deseocerca/compose.staging.yml"
  fi
fi
[ -f "$COMPOSE_FILE" ] || { echo "Missing Compose file: $COMPOSE_FILE" >&2; exit 2; }

update_env_values() {
  local site_value="$1"
  local image_value="$2"
  SITE_VALUE="$site_value" IMAGE_VALUE="$image_value" python3 - <<'PY' \
    | python3 "$REMOTE_DIR/deploy/deseocerca/update-env.py" "$ENV_FILE"
import json
import os
payload = {}
if os.environ.get("SITE_VALUE"):
    payload["STAGING_SITE_ADDRESS"] = os.environ["SITE_VALUE"]
if os.environ.get("IMAGE_VALUE"):
    payload["DESEOCERCA_APP_IMAGE"] = os.environ["IMAGE_VALUE"]
print(json.dumps(payload))
PY
}

cd "$REMOTE_DIR"
git cat-file -e "${previous_sha}^{commit}"

backup_script="$REMOTE_DIR/deploy/deseocerca/backup.sh"
if [ "$FREE_TIER" = true ]; then
  backup_script="$REMOTE_DIR/deploy/deseocerca/backup-free.sh"
fi
DESEOCERCA_DIR="$REMOTE_DIR" bash "$backup_script"

previous_site=""
if [ "$RESTORE_SITE" = true ]; then
  previous_site="$(printf '%s' "$previous_site_b64" | base64 -d)"
fi
previous_image=""
if [ -n "$previous_image_b64" ]; then
  previous_image="$(printf '%s' "$previous_image_b64" | base64 -d)"
fi

if [ "$FREE_TIER" = true ]; then
  if [ -z "$previous_image" ] || ! docker image inspect "$previous_image" >/dev/null 2>&1; then
    candidate="deseocerca-free:$previous_sha"
    if docker image inspect "$candidate" >/dev/null 2>&1; then
      previous_image="$candidate"
    else
      echo "Cannot roll back free-tier application image: no previous immutable image is available." >&2
      exit 1
    fi
  fi
fi

update_env_values "$previous_site" "$previous_image"
git checkout --detach "$previous_sha"
if [ "$FREE_TIER" = true ]; then
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --remove-orphans
else
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --build --remove-orphans
fi

compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
database_service="db"
if "${compose[@]}" config --services | grep -qx db-tls; then
  database_service="db-tls"
fi
for service in "$database_service" app caddy lifecycle; do
  "${compose[@]}" ps --status running --services | grep -qx "$service" || {
    echo "Rollback service is not running: $service" >&2
    exit 1
  }
done
if [ "$database_service" = "db-tls" ]; then
  tidb_user="$(read_env_value TIDB_USERNAME)"
  tidb_database="$(read_env_value TIDB_DATABASE)"
  "${compose[@]}" run --rm --no-deps -T --entrypoint mysql db-client \
    --host=db-tls --port=3306 --user="$tidb_user" --database="$tidb_database" \
    --connect-timeout=10 --execute='SELECT 1' >/dev/null
fi
"${compose[@]}" exec -T app test -s /var/www/html/_constants.php
"${compose[@]}" exec -T app php deploy/deseocerca/verify-runtime.php
"${compose[@]}" exec -T caddy wget -qO- http://app/ >/dev/null

rm -f /root/deseocerca-production-prepared /root/deseocerca-production-verified
printf 'DeseoCerca code rollback completed: %s\n' "$previous_sha"
if [ "$RESTORE_SITE" = true ]; then
  printf 'The previous site address was also restored. Update DNS as appropriate before declaring recovery complete.\n'
else
  printf 'The current public site address was preserved. Database data was not rolled back.\n'
fi
