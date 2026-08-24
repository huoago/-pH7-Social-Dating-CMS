#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
ENV_FILE="${DESEOCERCA_ENV_FILE:-$REMOTE_DIR/.env}"
BACKUP_DIR="${DESEOCERCA_BACKUP_DIR:-/var/backups/deseocerca}"
PASSPHRASE_FILE="${DESEOCERCA_BACKUP_PASSPHRASE_FILE:-/root/deseocerca-backup-passphrase}"
RETENTION_DAYS="${DESEOCERCA_BACKUP_RETENTION_DAYS:-7}"
COMPOSE_FILE="$REMOTE_DIR/deploy/deseocerca/compose.free.yml"

for required in "$ENV_FILE" "$PASSPHRASE_FILE" "$COMPOSE_FILE"; do
  [ -e "$required" ] || { echo "Missing required backup input: $required" >&2; exit 1; }
done
command -v docker >/dev/null 2>&1 || { echo "Docker is required." >&2; exit 1; }

read_env_value() {
  local key="$1"
  local line
  line="$(grep -m1 -E "^${key}=" "$ENV_FILE" || true)"
  [ -n "$line" ] || return 1
  printf '%s' "${line#*=}"
}

TIDB_USER="$(read_env_value TIDB_USERNAME)" || { echo "TIDB_USERNAME missing." >&2; exit 1; }
TIDB_DATABASE="$(read_env_value TIDB_DATABASE)" || { echo "TIDB_DATABASE missing." >&2; exit 1; }
[[ "$TIDB_DATABASE" =~ ^[A-Za-z0-9_$-]{1,64}$ ]] || { echo "Unsafe TIDB_DATABASE." >&2; exit 1; }
[[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || { echo "Retention must be numeric." >&2; exit 1; }

install -d -m 0700 "$BACKUP_DIR"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
cd "$REMOTE_DIR"
compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

for service in db-tls app; do
  "${compose[@]}" ps --status running --services | grep -qx "$service" || {
    echo "Cannot back up: $service is not running." >&2
    exit 1
  }
done

"${compose[@]}" run --rm --no-deps -T --entrypoint mysqldump db-client \
  --host=db-tls --port=3306 --user="$TIDB_USER" \
  --single-transaction --quick --skip-lock-tables --set-gtid-purged=OFF --no-tablespaces \
  "$TIDB_DATABASE" > "$tmp_dir/database.sql"

"${compose[@]}" exec -T app tar -czf - \
  -C /var/www/html data _protected/data _protected/app/configs _repository/module \
  -C /var/lib/deseocerca runtime > "$tmp_dir/application-data.tar.gz"

cat > "$tmp_dir/manifest.txt" <<EOF
service=DeseoCerca
created_at_utc=$timestamp
branch=deseocerca-v1
mysql_database=$TIDB_DATABASE
database_backend=tidb-cloud-starter
format=deseocerca-backup-v1
EOF

archive="$BACKUP_DIR/deseocerca-$timestamp.tar.gz.enc"
tar -C "$tmp_dir" -czf - database.sql application-data.tar.gz manifest.txt \
  | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt \
      -pass "file:$PASSPHRASE_FILE" -out "$archive"
sha256sum "$archive" > "$archive.sha256"
chmod 600 "$archive" "$archive.sha256"

find "$BACKUP_DIR" -type f \
  \( -name 'deseocerca-*.tar.gz.enc' -o -name 'deseocerca-*.tar.gz.enc.sha256' \) \
  -mtime "+$RETENTION_DAYS" -delete

echo "DeseoCerca free-tier backup created: $archive"
