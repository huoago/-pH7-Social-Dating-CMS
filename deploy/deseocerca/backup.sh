#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
ENV_FILE="${DESEOCERCA_ENV_FILE:-$REMOTE_DIR/.env}"
BACKUP_DIR="${DESEOCERCA_BACKUP_DIR:-/var/backups/deseocerca}"
PASSPHRASE_FILE="${DESEOCERCA_BACKUP_PASSPHRASE_FILE:-/root/deseocerca-backup-passphrase}"
RETENTION_DAYS="${DESEOCERCA_BACKUP_RETENTION_DAYS:-7}"
COMPOSE_FILE="$REMOTE_DIR/deploy/deseocerca/compose.staging.yml"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing DeseoCerca environment file: $ENV_FILE" >&2
  exit 1
fi
if [ ! -s "$PASSPHRASE_FILE" ]; then
  echo "Missing backup passphrase file: $PASSPHRASE_FILE" >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required for DeseoCerca backup." >&2
  exit 1
fi

set -a
# Generated DeseoCerca values are shell-safe hex/domain strings.
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

: "${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
: "${MYSQL_USER:?MYSQL_USER is required}"
: "${MYSQL_PASSWORD:?MYSQL_PASSWORD is required}"

install -d -m 0700 "$BACKUP_DIR"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

# Verify the database and application are running before creating a backup.
for service in db app; do
  if ! "${compose[@]}" ps --status running --services | grep -qx "$service"; then
    echo "Cannot back up: service $service is not running." >&2
    exit 1
  fi
done

# Database dump uses the non-root application database account.
"${compose[@]}" exec -T \
  -e MYSQL_PWD="$MYSQL_PASSWORD" \
  db mysqldump \
  --single-transaction \
  --quick \
  --routines \
  --triggers \
  --events \
  -u"$MYSQL_USER" \
  "$MYSQL_DATABASE" > "$tmp_dir/database.sql"

# Archive every persistent application mount, including the runtime copy of
# _constants.php. This does not include caches from the immutable image layer.
"${compose[@]}" exec -T app tar -czf - \
  -C /var/www/html \
  data \
  _protected/data \
  _protected/app/configs \
  _repository/module \
  -C /var/lib/deseocerca \
  runtime > "$tmp_dir/application-data.tar.gz"

cat > "$tmp_dir/manifest.txt" <<EOF
service=DeseoCerca
created_at_utc=$timestamp
branch=deseocerca-v1
mysql_database=$MYSQL_DATABASE
format=deseocerca-backup-v1
EOF

archive="$BACKUP_DIR/deseocerca-$timestamp.tar.gz.enc"
tar -C "$tmp_dir" -czf - database.sql application-data.tar.gz manifest.txt \
  | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt \
      -pass "file:$PASSPHRASE_FILE" \
      -out "$archive"

sha256sum "$archive" > "$archive.sha256"
chmod 600 "$archive" "$archive.sha256"

# Keep a small rolling local set. Off-VM/private-object-storage replication is
# still required before production data becomes irreplaceable.
find "$BACKUP_DIR" -type f \
  \( -name 'deseocerca-*.tar.gz.enc' -o -name 'deseocerca-*.tar.gz.enc.sha256' \) \
  -mtime "+$RETENTION_DAYS" -delete

# Optional private OCI Object Storage upload. This requires the OCI CLI and an
# instance-principal policy that grants this VM permission to write the bucket.
if [ -n "${OCI_BACKUP_BUCKET:-}" ]; then
  if ! command -v oci >/dev/null 2>&1; then
    echo "OCI_BACKUP_BUCKET is set but OCI CLI is not installed." >&2
    exit 1
  fi
  oci os object put \
    --auth instance_principal \
    --bucket-name "$OCI_BACKUP_BUCKET" \
    --name "$(basename "$archive")" \
    --file "$archive" \
    --force >/dev/null
  oci os object put \
    --auth instance_principal \
    --bucket-name "$OCI_BACKUP_BUCKET" \
    --name "$(basename "$archive.sha256")" \
    --file "$archive.sha256" \
    --force >/dev/null
fi

echo "DeseoCerca backup created: $archive"
