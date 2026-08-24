#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
ENV_FILE="${DESEOCERCA_ENV_FILE:-$REMOTE_DIR/.env}"
COMPOSE_FILE="$REMOTE_DIR/deploy/deseocerca/compose.free.yml"
FIRST_INSTALL_FILE="${DESEOCERCA_FIRST_INSTALL_FILE:-/root/deseocerca-first-install.txt}"

if [ "${EUID}" -ne 0 ]; then
  echo "Run with sudo or as root." >&2
  exit 1
fi
for required in "$ENV_FILE" "$COMPOSE_FILE"; do
  [ -f "$required" ] || { echo "Missing required file: $required" >&2; exit 1; }
done

read_env_value() {
  python3 - "$ENV_FILE" "$1" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
key = sys.argv[2]
for raw in path.read_text(encoding="utf-8").splitlines():
    if not raw or raw.lstrip().startswith("#") or "=" not in raw:
        continue
    name, value = raw.split("=", 1)
    if name == key:
        print(value)
        raise SystemExit(0)
raise SystemExit(1)
PY
}

tidb_host="$(read_env_value TIDB_HOST)" || { echo "TIDB_HOST is missing." >&2; exit 1; }
tidb_user="$(read_env_value TIDB_USERNAME)" || { echo "TIDB_USERNAME is missing." >&2; exit 1; }
tidb_password="$(read_env_value TIDB_PASSWORD)" || { echo "TIDB_PASSWORD is missing." >&2; exit 1; }
tidb_database="$(read_env_value TIDB_DATABASE)" || { echo "TIDB_DATABASE is missing." >&2; exit 1; }
site_address="$(read_env_value STAGING_SITE_ADDRESS || true)"

[ -n "$tidb_host" ] && [ -n "$tidb_user" ] && [ -n "$tidb_password" ] && [ -n "$tidb_database" ] || {
  echo "TiDB connection values are incomplete." >&2
  exit 1
}
[[ "$tidb_database" =~ ^[A-Za-z0-9_$-]{1,64}$ ]] || { echo "Unsafe TIDB_DATABASE." >&2; exit 1; }

cd "$REMOTE_DIR"
compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

for service in db-tls app; do
  "${compose[@]}" ps --status running --services | grep -qx "$service" || {
    echo "Required service is not running: $service" >&2
    exit 1
  }
done

"${compose[@]}" run --rm --no-deps -T --entrypoint mysql db-client \
  --host=db-tls --port=3306 --user="$tidb_user" --database="$tidb_database" \
  --connect-timeout=10 --execute='SELECT 1' >/dev/null

if "${compose[@]}" exec -T app test -s /var/www/html/_constants.php; then
  rm -f "$FIRST_INSTALL_FILE"
  echo "DeseoCerca is already installed."
  exit 0
fi

"${compose[@]}" exec -T app test -d /var/www/html/_install

install_token=""
if [ -s "$FIRST_INSTALL_FILE" ]; then
  install_token="$(sed -n 's/^INSTALL_ACCESS_TOKEN=//p' "$FIRST_INSTALL_FILE" | head -n1)"
fi

if [[ "$install_token" =~ ^[0-9a-f]{64}$ ]]; then
  token_hash="$(printf '%s' "$install_token" | sha256sum | awk '{print $1}')"
  printf '%s\n' "$token_hash" | "${compose[@]}" exec -T app sh -lc '
      set -e
      mkdir -p /var/www/html/_install/data/caches /var/lib/deseocerca/runtime
      umask 027
      cat > /var/www/html/_install/data/caches/install-token.hash
      cp /var/www/html/_install/data/caches/install-token.hash /var/lib/deseocerca/runtime/install-token.hash
      chmod 0640 /var/www/html/_install/data/caches/install-token.hash /var/lib/deseocerca/runtime/install-token.hash
      chown www-data:www-data /var/www/html/_install/data/caches/install-token.hash /var/lib/deseocerca/runtime/install-token.hash
    '
else
  token_output="$("${compose[@]}" exec -T app php _install/create-install-token.php)"
  install_token="$(printf '%s\n' "$token_output" | grep -E '^[0-9a-f]{64}$' | tail -n1)"
  [[ "$install_token" =~ ^[0-9a-f]{64}$ ]] || { echo "Could not obtain installer access token." >&2; exit 1; }
fi

umask 077
cat > "$FIRST_INSTALL_FILE" <<EOF
DeseoCerca first installation - Google Free Tier + TiDB (root-only)
===================================================================

INSTALL_ACCESS_TOKEN=${install_token}
DB_HOST=db-tls
DB_PORT=3306
DB_NAME=${tidb_database}
DB_USER=${tidb_user}
DB_PASSWORD=${tidb_password}
DB_PREFIX=ph7_
PROTECTED_PATH=/var/www/html/_protected/
BUG_REPORT_EMAIL=admin@deseocerca.com
STAGING_SITE_ADDRESS=${site_address:-:80}

Important
---------
db-tls:3306 is an internal Docker endpoint. HAProxy verifies the public
TiDB Cloud Starter TLS certificate and connects to ${tidb_host}:4000.

Procedure
---------
1. Open the staging site.
2. Enter INSTALL_ACCESS_TOKEN.
3. Keep the protected path shown above.
4. Enter DB_HOST/DB_PORT/DB_NAME/DB_USER/DB_PASSWORD exactly as shown.
5. Keep prefix ph7_ and complete the real administrator account.
6. Finish installation; _install will be removed automatically.
7. Run: cd ${REMOTE_DIR} && sudo bash deploy/deseocerca/apply-bootstrap-free.sh
8. Delete this file after storing required credentials in a password manager.
EOF
chmod 600 "$FIRST_INSTALL_FILE"
echo "Protected first-install instructions written to $FIRST_INSTALL_FILE"
