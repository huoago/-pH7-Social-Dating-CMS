#!/usr/bin/env bash
set -Eeuo pipefail

REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
ENV_FILE="${DESEOCERCA_ENV_FILE:-$REMOTE_DIR/.env}"
COMPOSE_FILE="${DESEOCERCA_COMPOSE_FILE:-}"
STATE_FILE="${DESEOCERCA_RELEASE_STATE_FILE:-/root/deseocerca-production-release.env}"
PREPARED_MARKER="/root/deseocerca-production-prepared"
RELEASE_SHA="${DESEOCERCA_RELEASE_SHA:-}"
PRODUCTION_SITES="${DESEOCERCA_PRODUCTION_SITES:-deseocerca.com www.deseocerca.com}"
PRODUCTION_CANONICAL_HOST="deseocerca.com"

if [ "${EUID}" -ne 0 ]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi
if [[ ! "$RELEASE_SHA" =~ ^[a-f0-9]{40}$ ]]; then
  echo "DESEOCERCA_RELEASE_SHA must be an exact 40-character Git commit SHA." >&2
  exit 2
fi
if [[ "$PRODUCTION_SITES" == *$'\n'* || "$PRODUCTION_SITES" == *$'\r'* ]]; then
  echo "DESEOCERCA_PRODUCTION_SITES must not contain CR/LF characters." >&2
  exit 2
fi
if [ ! -d "$REMOTE_DIR/.git" ] || [ ! -f "$ENV_FILE" ]; then
  echo "DeseoCerca staging installation is not prepared on this host." >&2
  exit 2
fi

FREE_TIER=false
if grep -Eq '^TIDB_HOST=.+$' "$ENV_FILE"; then
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

read_env_value() {
  local key="$1"
  local line
  line="$(grep -m1 -E "^${key}=" "$ENV_FILE" || true)"
  [ -n "$line" ] || return 1
  printf '%s' "${line#*=}"
}

update_env_values() {
  local site_value="$1"
  local image_value="${2:-}"
  local canonical_value="${3:-}"
  SITE_VALUE="$site_value" IMAGE_VALUE="$image_value" CANONICAL_VALUE="$canonical_value" python3 - <<'PY' \
    | python3 "$REMOTE_DIR/deploy/deseocerca/update-env.py" "$ENV_FILE"
import json
import os
payload = {"STAGING_SITE_ADDRESS": os.environ["SITE_VALUE"]}
if os.environ.get("IMAGE_VALUE"):
    payload["DESEOCERCA_APP_IMAGE"] = os.environ["IMAGE_VALUE"]
if os.environ.get("CANONICAL_VALUE"):
    payload["PH7_CANONICAL_HOST"] = os.environ["CANONICAL_VALUE"]
    payload["PH7_CANONICAL_SCHEME"] = "https"
print(json.dumps(payload))
PY
}

compose_up() {
  if [ "$FREE_TIER" = true ]; then
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --remove-orphans
  else
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --build --remove-orphans
  fi
}

internal_verify() {
  local -a compose
  local database_service="db"
  compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
  if "${compose[@]}" config --services | grep -qx db-tls; then
    database_service="db-tls"
  fi
  for service in "$database_service" app caddy lifecycle; do
    "${compose[@]}" ps --status running --services | grep -qx "$service" || {
      echo "Required service is not running: $service" >&2
      return 1
    }
  done
  if [ "$database_service" = "db-tls" ]; then
    local tidb_user tidb_database
    tidb_user="$(read_env_value TIDB_USERNAME)"
    tidb_database="$(read_env_value TIDB_DATABASE)"
    "${compose[@]}" run --rm --no-deps -T --entrypoint mysql db-client \
      --host=db-tls --port=3306 --user="$tidb_user" --database="$tidb_database" \
      --connect-timeout=10 --execute='SELECT 1' >/dev/null
  fi
  "${compose[@]}" exec -T app test -s /var/www/html/_constants.php
  "${compose[@]}" exec -T app test ! -d /var/www/html/_install
  "${compose[@]}" exec -T app php deploy/deseocerca/verify-runtime.php
  "${compose[@]}" exec -T caddy wget -qO- http://app/ >/dev/null
}

cd "$REMOTE_DIR"
if [ -f .git/shallow ]; then
  git fetch --unshallow origin
fi
git fetch --prune origin '+refs/heads/18.x:refs/remotes/origin/18.x'
git cat-file -e "${RELEASE_SHA}^{commit}"
if ! git merge-base --is-ancestor "$RELEASE_SHA" origin/18.x; then
  echo "Refusing production promotion: $RELEASE_SHA is not on origin/18.x." >&2
  exit 1
fi

previous_sha="$(git rev-parse HEAD)"
previous_site="$(read_env_value STAGING_SITE_ADDRESS)" || { echo "STAGING_SITE_ADDRESS is missing from $ENV_FILE." >&2; exit 1; }
previous_image="$(read_env_value DESEOCERCA_APP_IMAGE || true)"
previous_canonical="$(read_env_value PH7_CANONICAL_HOST || true)"
if [ -z "$previous_site" ]; then
  echo "STAGING_SITE_ADDRESS is empty." >&2
  exit 1
fi

release_image=""
if [ "$FREE_TIER" = true ]; then
  release_image="deseocerca-free:$RELEASE_SHA"
  if ! docker image inspect "$release_image" >/dev/null 2>&1; then
    echo "Refusing free-tier promotion: immutable image $release_image is not loaded on this VM." >&2
    exit 1
  fi
fi

internal_verify

backup_script="$REMOTE_DIR/deploy/deseocerca/backup.sh"
if [ "$FREE_TIER" = true ]; then
  backup_script="$REMOTE_DIR/deploy/deseocerca/backup-free.sh"
fi
DESEOCERCA_DIR="$REMOTE_DIR" bash "$backup_script"
latest_backup="$(find /var/backups/deseocerca -maxdepth 1 -type f -name 'deseocerca-*.tar.gz.enc' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {$1=""; sub(/^ /, ""); print; exit}')"
[ -n "$latest_backup" ] && [ -f "$latest_backup" ] || { echo "Promotion backup could not be located." >&2; exit 1; }

umask 077
previous_site_b64="$(printf '%s' "$previous_site" | base64 -w0)"
backup_b64="$(printf '%s' "$latest_backup" | base64 -w0)"
previous_image_b64="$(printf '%s' "$previous_image" | base64 -w0)"
previous_canonical_b64="$(printf '%s' "$previous_canonical" | base64 -w0)"
cat > "$STATE_FILE" <<EOF
service=DeseoCerca
previous_sha=$previous_sha
release_sha=$RELEASE_SHA
previous_site_address_b64=$previous_site_b64
previous_app_image_b64=$previous_image_b64
previous_canonical_host_b64=$previous_canonical_b64
pre_release_backup_b64=$backup_b64
free_tier=$FREE_TIER
prepared_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
chmod 600 "$STATE_FILE"

switch_started=0
on_error() {
  local status="$?"
  trap - ERR
  if [ "$switch_started" -eq 1 ]; then
    echo "Production preparation failed; restoring the previous Git revision, site address and canonical host." >&2
    git checkout --detach "$previous_sha" >/dev/null 2>&1 || true
    update_env_values "$previous_site" "$previous_image" "$previous_canonical" || true
    compose_up || true
  fi
  rm -f "$PREPARED_MARKER"
  exit "$status"
}
trap on_error ERR

update_env_values "$PRODUCTION_SITES" "$release_image" "$PRODUCTION_CANONICAL_HOST"
switch_started=1

git checkout --detach "$RELEASE_SHA"
compose_up
internal_verify

cat > "$PREPARED_MARKER" <<EOF
service=DeseoCerca
release_sha=$RELEASE_SHA
previous_sha=$previous_sha
production_sites=$PRODUCTION_SITES
canonical_host=$PRODUCTION_CANONICAL_HOST
free_tier=$FREE_TIER
prepared_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
chmod 600 "$PREPARED_MARKER"

trap - ERR
printf 'DeseoCerca production preparation completed for %s.\n' "$RELEASE_SHA"
printf 'The application is internally healthy. Do not claim public launch until DNS is switched and the Production Release Gate passes.\n'
