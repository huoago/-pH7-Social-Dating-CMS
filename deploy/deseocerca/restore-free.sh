#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
ENV_FILE="${DESEOCERCA_ENV_FILE:-$REMOTE_DIR/.env}"
PASSPHRASE_FILE="${DESEOCERCA_BACKUP_PASSPHRASE_FILE:-/root/deseocerca-backup-passphrase}"
COMPOSE_FILE="$REMOTE_DIR/deploy/deseocerca/compose.free.yml"

if [ "$#" -ne 2 ] || [ "$2" != "--confirm-restore" ]; then
  echo "Usage: sudo bash deploy/deseocerca/restore-free.sh BACKUP.tar.gz.enc --confirm-restore" >&2
  exit 64
fi
[ "${EUID}" -eq 0 ] || { echo "Run with sudo or as root." >&2; exit 1; }

archive="$1"
checksum_file="$archive.sha256"
for required in "$ENV_FILE" "$PASSPHRASE_FILE" "$archive" "$checksum_file" "$COMPOSE_FILE"; do
  [ -e "$required" ] || { echo "Missing restore input: $required" >&2; exit 1; }
done

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

cd "$(dirname "$archive")"
sha256sum --check "$(basename "$checksum_file")"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -pass "file:$PASSPHRASE_FILE" -in "$archive" | tar -C "$tmp_dir" -xzf -

for member in database.sql application-data.tar.gz manifest.txt; do
  [ -s "$tmp_dir/$member" ] || { echo "Backup missing $member" >&2; exit 1; }
done
grep -qx 'service=DeseoCerca' "$tmp_dir/manifest.txt"
grep -qx 'format=deseocerca-backup-v1' "$tmp_dir/manifest.txt"
manifest_db="$(sed -n 's/^mysql_database=//p' "$tmp_dir/manifest.txt" | head -n1)"
[ "$manifest_db" = "$TIDB_DATABASE" ] || { echo "Backup database mismatch." >&2; exit 1; }

cd "$REMOTE_DIR"
compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
"${compose[@]}" stop caddy lifecycle app || true
"${compose[@]}" up -d db-tls

table_list="$("${compose[@]}" run --rm --no-deps -T --entrypoint mysql db-client \
  --host=db-tls --port=3306 --user="$TIDB_USER" --database="$TIDB_DATABASE" \
  --batch --skip-column-names --execute="SHOW TABLES LIKE 'ph7\\_%';")"
if [ -n "$table_list" ]; then
  drop_sql="SET FOREIGN_KEY_CHECKS=0;"
  while IFS= read -r table; do
    [[ "$table" =~ ^ph7_[A-Za-z0-9_]+$ ]] || { echo "Unsafe table name returned: $table" >&2; exit 1; }
    drop_sql+=" DROP TABLE IF EXISTS \`$table\`;"
  done <<< "$table_list"
  drop_sql+=" SET FOREIGN_KEY_CHECKS=1;"
  printf '%s\n' "$drop_sql" | "${compose[@]}" run --rm --no-deps -T --entrypoint mysql db-client \
    --host=db-tls --port=3306 --user="$TIDB_USER" "$TIDB_DATABASE"
fi

"${compose[@]}" run --rm --no-deps -T --entrypoint mysql db-client \
  --host=db-tls --port=3306 --user="$TIDB_USER" "$TIDB_DATABASE" < "$tmp_dir/database.sql"

cat "$tmp_dir/application-data.tar.gz" \
  | "${compose[@]}" run --rm -T --no-deps --entrypoint sh app -lc '
      set -e
      for path in /var/www/html/data /var/www/html/_protected/data /var/www/html/_protected/app/configs /var/www/html/_repository/module; do
        find "$path" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
      done
      tar -xzf - -C /var/www/html data _protected/data _protected/app/configs _repository/module
    '
cat "$tmp_dir/application-data.tar.gz" \
  | "${compose[@]}" run --rm -T --no-deps --entrypoint sh app -lc '
      set -e
      find /var/lib/deseocerca/runtime -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
      tar -xzf - -C /var/lib/deseocerca runtime
    '

"${compose[@]}" up -d --remove-orphans
for attempt in $(seq 1 30); do
  "${compose[@]}" exec -T app test -s /var/www/html/_constants.php >/dev/null 2>&1 && break
  [ "$attempt" -lt 30 ] || { echo "Restored runtime did not recover _constants.php." >&2; exit 1; }
  sleep 2
done
"${compose[@]}" exec -T app test ! -d /var/www/html/_install
"${compose[@]}" exec -T app php deploy/deseocerca/verify-runtime.php
echo "DeseoCerca free-tier restore completed: $archive"
