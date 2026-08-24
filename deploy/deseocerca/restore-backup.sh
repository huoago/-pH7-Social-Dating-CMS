#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
ENV_FILE="${DESEOCERCA_ENV_FILE:-$REMOTE_DIR/.env}"
PASSPHRASE_FILE="${DESEOCERCA_BACKUP_PASSPHRASE_FILE:-/root/deseocerca-backup-passphrase}"
COMPOSE_FILE="$REMOTE_DIR/deploy/deseocerca/compose.staging.yml"

usage() {
  cat <<'EOF'
Usage:
  sudo bash deploy/deseocerca/restore-backup.sh /path/to/deseocerca-YYYYMMDDTHHMMSSZ.tar.gz.enc --confirm-restore

This is destructive. It replaces the DeseoCerca database and persistent
application data with the selected encrypted backup.
EOF
}

if [ "$#" -ne 2 ] || [ "$2" != "--confirm-restore" ]; then
  usage >&2
  exit 64
fi

archive="$1"
checksum_file="$archive.sha256"

for required in "$ENV_FILE" "$PASSPHRASE_FILE" "$archive" "$checksum_file" "$COMPOSE_FILE"; do
  if [ ! -e "$required" ]; then
    echo "Missing required restore input: $required" >&2
    exit 1
  fi
done

if [ "${EUID}" -ne 0 ]; then
  echo "Run restore with sudo or as root." >&2
  exit 1
fi

cd "$(dirname "$archive")"
sha256sum --check "$(basename "$checksum_file")"

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

: "${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
: "${MYSQL_USER:?MYSQL_USER is required}"
: "${MYSQL_PASSWORD:?MYSQL_PASSWORD is required}"
: "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -pass "file:$PASSPHRASE_FILE" \
  -in "$archive" \
  | tar -C "$tmp_dir" -xzf -

for required_member in database.sql application-data.tar.gz manifest.txt; do
  if [ ! -s "$tmp_dir/$required_member" ]; then
    echo "Backup is missing required member: $required_member" >&2
    exit 1
  fi
done

if ! grep -qx 'service=DeseoCerca' "$tmp_dir/manifest.txt" \
  || ! grep -qx 'format=deseocerca-backup-v1' "$tmp_dir/manifest.txt"; then
  echo "Backup manifest is not a supported DeseoCerca backup." >&2
  exit 1
fi

manifest_db="$(sed -n 's/^mysql_database=//p' "$tmp_dir/manifest.txt" | head -n1)"
if [ "$manifest_db" != "$MYSQL_DATABASE" ]; then
  echo "Backup database '$manifest_db' does not match configured database '$MYSQL_DATABASE'." >&2
  exit 1
fi

compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

# Remove public traffic and application writers before restoring.
"${compose[@]}" stop caddy lifecycle app || true
"${compose[@]}" up -d db

for attempt in $(seq 1 30); do
  if "${compose[@]}" exec -T \
    -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
    db mysqladmin ping -uroot --silent >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -eq 30 ]; then
    echo "MySQL did not become ready for restore." >&2
    exit 1
  fi
  sleep 2
done

# Replace the database using the root credential generated for this stack.
"${compose[@]}" exec -T \
  -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
  db mysql -uroot -e \
  "DROP DATABASE IF EXISTS \`$MYSQL_DATABASE\`; CREATE DATABASE \`$MYSQL_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; GRANT ALL PRIVILEGES ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%'; FLUSH PRIVILEGES;"

"${compose[@]}" exec -T \
  -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
  db mysql -uroot "$MYSQL_DATABASE" < "$tmp_dir/database.sql"

# Restore application data into the same named volumes used by app/lifecycle.
# The backup archive contains entries rooted at both /var/www/html and
# /var/lib/deseocerca, so it is streamed twice with an explicit member list.
cat "$tmp_dir/application-data.tar.gz" \
  | "${compose[@]}" run --rm -T --no-deps --entrypoint sh app -lc '
      set -e
      rm -rf \
        /var/www/html/data/* \
        /var/www/html/_protected/data/* \
        /var/www/html/_protected/app/configs/* \
        /var/www/html/_repository/module/*
      tar -xzf - -C /var/www/html \
        data _protected/data _protected/app/configs _repository/module
    '

cat "$tmp_dir/application-data.tar.gz" \
  | "${compose[@]}" run --rm -T --no-deps --entrypoint sh app -lc '
      set -e
      rm -rf /var/lib/deseocerca/runtime/*
      tar -xzf - -C /var/lib/deseocerca runtime
    '

"${compose[@]}" up -d --remove-orphans

# Installed backups must come back without the installer and pass runtime checks.
for attempt in $(seq 1 30); do
  if "${compose[@]}" exec -T app test -s /var/www/html/_constants.php >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -eq 30 ]; then
    echo "Restored runtime did not recover _constants.php." >&2
    exit 1
  fi
  sleep 2
done

"${compose[@]}" exec -T app test ! -d /var/www/html/_install
"${compose[@]}" exec -T app php deploy/deseocerca/verify-runtime.php

echo "DeseoCerca restore completed successfully from: $archive"
