#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
ENV_FILE="${DESEOCERCA_ENV_FILE:-$REMOTE_DIR/.env}"
COMPOSE_FILE="$REMOTE_DIR/deploy/deseocerca/compose.staging.yml"
FIRST_INSTALL_FILE="${DESEOCERCA_FIRST_INSTALL_FILE:-/root/deseocerca-first-install.txt}"

if [ "${EUID}" -ne 0 ]; then
  echo "Run this installer-preparation script with sudo or as root." >&2
  exit 1
fi

for required in "$ENV_FILE" "$COMPOSE_FILE"; do
  if [ ! -f "$required" ]; then
    echo "Missing required staging file: $required" >&2
    exit 1
  fi
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

cd "$REMOTE_DIR"
compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

if ! "${compose[@]}" ps --status running --services | grep -qx app; then
  echo "DeseoCerca app container is not running." >&2
  exit 1
fi

if "${compose[@]}" exec -T app test -s /var/www/html/_constants.php; then
  rm -f "$FIRST_INSTALL_FILE"
  echo "DeseoCerca is already installed; no installer token is required."
  exit 0
fi

if ! "${compose[@]}" exec -T app test -d /var/www/html/_install; then
  echo "Installer directory is unavailable before installation completed." >&2
  exit 1
fi

install_token=""
if [ -s "$FIRST_INSTALL_FILE" ]; then
  install_token="$(sed -n 's/^INSTALL_ACCESS_TOKEN=//p' "$FIRST_INSTALL_FILE" | head -n1)"
fi

if [[ "$install_token" =~ ^[0-9a-f]{64}$ ]]; then
  token_hash="$(printf '%s' "$install_token" | sha256sum | awk '{print $1}')"
  printf '%s\n' "$token_hash" \
    | "${compose[@]}" exec -T app sh -lc '
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
  if [[ ! "$install_token" =~ ^[0-9a-f]{64}$ ]]; then
    echo "Could not obtain a valid pH7 installer access token." >&2
    exit 1
  fi
  "${compose[@]}" exec -T app sh -lc '
      set -e
      cp /var/www/html/_install/data/caches/install-token.hash /var/lib/deseocerca/runtime/install-token.hash
      chmod 0640 /var/www/html/_install/data/caches/install-token.hash /var/lib/deseocerca/runtime/install-token.hash
      chown www-data:www-data /var/www/html/_install/data/caches/install-token.hash /var/lib/deseocerca/runtime/install-token.hash
    '
fi

mysql_database="$(read_env_value MYSQL_DATABASE)"
mysql_user="$(read_env_value MYSQL_USER)"
mysql_password="$(read_env_value MYSQL_PASSWORD)"
site_address="$(read_env_value STAGING_SITE_ADDRESS || true)"

umask 077
cat > "$FIRST_INSTALL_FILE" <<EOF
DeseoCerca first installation (root-only)
========================================

INSTALL_ACCESS_TOKEN=${install_token}
DB_HOST=db
DB_PORT=3306
DB_NAME=${mysql_database}
DB_USER=${mysql_user}
DB_PASSWORD=${mysql_password}
DB_PREFIX=ph7_
PROTECTED_PATH=/var/www/html/_protected/
BUG_REPORT_EMAIL=admin@deseocerca.com
STAGING_SITE_ADDRESS=${site_address:-:80}

Procedure
---------
1. Open the staging site in a browser. Before DNS is configured, use the VM public IPv4.
2. Enter INSTALL_ACCESS_TOKEN when the installer asks for installer access.
3. Accept the pH7 license and keep the protected path shown above.
4. Enter the database values above exactly and keep the prefix ph7_.
5. Complete the site/admin step with the real administrator email and a unique strong password.
6. Finish the installer. The application entrypoint will persist _constants.php and remove _install.
7. Run: cd ${REMOTE_DIR} && bash deploy/deseocerca/apply-bootstrap.sh
8. Delete this root-only file after the first installation and copy any credentials you still need to a separate password manager.
EOF
chmod 600 "$FIRST_INSTALL_FILE"

echo "Prepared the protected first-install instructions at: $FIRST_INSTALL_FILE"
