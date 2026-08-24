#!/usr/bin/env bash
set -Eeuo pipefail

REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
ENV_FILE="${DESEOCERCA_ENV_FILE:-$REMOTE_DIR/.env}"
COMPOSE_FILE="$REMOTE_DIR/deploy/deseocerca/compose.staging.yml"
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

previous_sha="$(read_state previous_sha)"
previous_site_b64="$(read_state previous_site_address_b64)"
if [[ ! "$previous_sha" =~ ^[a-f0-9]{40}$ ]]; then
  echo "Stored previous_sha is invalid." >&2
  exit 1
fi

cd "$REMOTE_DIR"
git cat-file -e "${previous_sha}^{commit}"

# Preserve the current state before rolling code backwards. Database restore is
# intentionally not automatic because it can destroy data created after cutover.
DESEOCERCA_DIR="$REMOTE_DIR" bash "$REMOTE_DIR/deploy/deseocerca/backup.sh"

if [ "$RESTORE_SITE" = true ]; then
  previous_site="$(printf '%s' "$previous_site_b64" | base64 -d)"
  SITE_VALUE="$previous_site" python3 - <<'PY' \
    | python3 "$REMOTE_DIR/deploy/deseocerca/update-env.py" "$ENV_FILE"
import json
import os
print(json.dumps({"STAGING_SITE_ADDRESS": os.environ["SITE_VALUE"]}))
PY
fi

git checkout --detach "$previous_sha"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --build --remove-orphans

compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
for service in db app caddy lifecycle; do
  "${compose[@]}" ps --status running --services | grep -qx "$service" || {
    echo "Rollback service is not running: $service" >&2
    exit 1
  }
done
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
