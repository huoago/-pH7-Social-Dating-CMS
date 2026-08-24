#!/usr/bin/env bash
set -Eeuo pipefail

REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
ENV_FILE="${DESEOCERCA_ENV_FILE:-$REMOTE_DIR/.env}"
COMPOSE_FILE="$REMOTE_DIR/deploy/deseocerca/compose.staging.yml"
STATE_FILE="${DESEOCERCA_RELEASE_STATE_FILE:-/root/deseocerca-production-release.env}"
PREPARED_MARKER="/root/deseocerca-production-prepared"
RELEASE_SHA="${DESEOCERCA_RELEASE_SHA:-}"
PRODUCTION_SITES="${DESEOCERCA_PRODUCTION_SITES:-deseocerca.com www.deseocerca.com}"

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
if [ ! -d "$REMOTE_DIR/.git" ] || [ ! -f "$ENV_FILE" ] || [ ! -f "$COMPOSE_FILE" ]; then
  echo "DeseoCerca staging installation is not prepared on this host." >&2
  exit 2
fi

read_env_value() {
  local key="$1"
  local line
  line="$(grep -m1 -E "^${key}=" "$ENV_FILE" || true)"
  [ -n "$line" ] || return 1
  printf '%s' "${line#*=}"
}

update_site_address() {
  local value="$1"
  SITE_VALUE="$value" python3 - <<'PY' \
    | python3 "$REMOTE_DIR/deploy/deseocerca/update-env.py" "$ENV_FILE"
import json
import os
print(json.dumps({"STAGING_SITE_ADDRESS": os.environ["SITE_VALUE"]}))
PY
}

internal_verify() {
  local -a compose
  compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
  for service in db app caddy lifecycle; do
    "${compose[@]}" ps --status running --services | grep -qx "$service" || {
      echo "Required service is not running: $service" >&2
      return 1
    }
  done
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
previous_site="$(read_env_value STAGING_SITE_ADDRESS)" || {
  echo "STAGING_SITE_ADDRESS is missing from $ENV_FILE." >&2
  exit 1
}
if [ -z "$previous_site" ]; then
  echo "STAGING_SITE_ADDRESS is empty." >&2
  exit 1
fi

# A promotion is allowed only from an already-installed, healthy runtime.
internal_verify

# Create a fresh encrypted recovery point before any release mutation.
DESEOCERCA_DIR="$REMOTE_DIR" bash "$REMOTE_DIR/deploy/deseocerca/backup.sh"
latest_backup="$(find /var/backups/deseocerca -maxdepth 1 -type f -name 'deseocerca-*.tar.gz.enc' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {$1=""; sub(/^ /, ""); print; exit}')"
[ -n "$latest_backup" ] && [ -f "$latest_backup" ] || {
  echo "Promotion backup could not be located." >&2
  exit 1
}

umask 077
previous_site_b64="$(printf '%s' "$previous_site" | base64 -w0)"
backup_b64="$(printf '%s' "$latest_backup" | base64 -w0)"
cat > "$STATE_FILE" <<EOF
service=DeseoCerca
previous_sha=$previous_sha
release_sha=$RELEASE_SHA
previous_site_address_b64=$previous_site_b64
pre_release_backup_b64=$backup_b64
prepared_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
chmod 600 "$STATE_FILE"

switch_started=0
on_error() {
  local status="$?"
  trap - ERR
  if [ "$switch_started" -eq 1 ]; then
    echo "Production preparation failed; restoring the previous Git revision and site address." >&2
    git checkout --detach "$previous_sha" >/dev/null 2>&1 || true
    update_site_address "$previous_site" || true
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --build --remove-orphans || true
  fi
  rm -f "$PREPARED_MARKER"
  exit "$status"
}
trap on_error ERR

# Caddy supports one environment substitution expanding into multiple site
# address tokens, so the same stack can serve apex and www without a second VM.
update_site_address "$PRODUCTION_SITES"
switch_started=1

git checkout --detach "$RELEASE_SHA"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --build --remove-orphans
internal_verify

cat > "$PREPARED_MARKER" <<EOF
service=DeseoCerca
release_sha=$RELEASE_SHA
previous_sha=$previous_sha
production_sites=$PRODUCTION_SITES
prepared_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
chmod 600 "$PREPARED_MARKER"

trap - ERR
printf 'DeseoCerca production preparation completed for %s.\n' "$RELEASE_SHA"
printf 'The application is internally healthy. Do not claim public launch until DNS is switched and the Production Release Gate passes.\n'
