#!/usr/bin/env bash
set -euo pipefail

# DeseoCerca zero-monthly-cost VM bootstrap.
# Tested design target: Ubuntu 22.04/24.04 on OCI Always Free A1 (arm64)
# or compatible amd64 VMs. Run once with sudo/root privileges.

REPO_URL="https://github.com/huoago/-pH7-Social-Dating-CMS.git"
BRANCH="deseocerca-v1"
REMOTE_DIR="/opt/deseocerca-staging"
ENV_FILE="$REMOTE_DIR/.env"
SECRETS_FILE="/root/deseocerca-staging-secrets.txt"
STAGING_SITE_ADDRESS="${STAGING_SITE_ADDRESS:-:80}"
MAILER_DSN="${PH7_MAILER_DSN:-}"

if [ "${EUID}" -ne 0 ]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This bootstrap currently supports Debian/Ubuntu apt-based systems." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git gnupg openssl ufw jq

# Install Docker Engine from Docker's official apt repository if needed.
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  arch="$(dpkg --print-architecture)"
  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y --no-install-recommends \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

systemctl enable --now docker

docker compose version >/dev/null

# Add swap only on small-memory fallback VMs (for example 1 GB AMD micro).
mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
if [ "${mem_kb}" -lt 3500000 ] && ! swapon --show | grep -q '^/'; then
  if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
  fi
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Host firewall. OCI/other cloud VCN/security-list ingress must also allow 22/80/443.
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

mkdir -p "$(dirname "$REMOTE_DIR")"
if [ -d "$REMOTE_DIR/.git" ]; then
  git -C "$REMOTE_DIR" fetch --prune origin "$BRANCH"
  git -C "$REMOTE_DIR" checkout -f "$BRANCH"
  git -C "$REMOTE_DIR" reset --hard "origin/$BRANCH"
else
  rm -rf "$REMOTE_DIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$REMOTE_DIR"
fi

# Generate strong database credentials only once.
if [ -f "$ENV_FILE" ]; then
  echo "Existing $ENV_FILE found; preserving current database credentials."
else
  db_password="$(openssl rand -hex 24)"
  db_root_password="$(openssl rand -hex 32)"
  umask 077
  cat > "$ENV_FILE" <<EOF
MYSQL_DATABASE=deseocerca
MYSQL_USER=deseocerca
MYSQL_PASSWORD=${db_password}
MYSQL_ROOT_PASSWORD=${db_root_password}
STAGING_SITE_ADDRESS=${STAGING_SITE_ADDRESS}
PH7_MAILER_DSN=${MAILER_DSN}
EOF
  chmod 600 "$ENV_FILE"

  cat > "$SECRETS_FILE" <<EOF
DeseoCerca staging generated credentials
========================================
DESEOCERCA_STAGING_DB_PASSWORD=${db_password}
DESEOCERCA_STAGING_DB_ROOT_PASSWORD=${db_root_password}
STAGING_SITE_ADDRESS=${STAGING_SITE_ADDRESS}

Keep this root-only file private. Copy the two database values into GitHub Actions
Secrets later if you want GitHub-driven redeployments.
EOF
  chmod 600 "$SECRETS_FILE"
fi

cd "$REMOTE_DIR"
docker compose --env-file .env -f deploy/deseocerca/compose.staging.yml \
  up -d --build --remove-orphans

# Fail if any essential container immediately exits.
sleep 5
compose_cmd=(docker compose --env-file .env -f deploy/deseocerca/compose.staging.yml)
"${compose_cmd[@]}" ps

for service in db app caddy lifecycle; do
  if ! "${compose_cmd[@]}" ps --status running --services | grep -qx "$service"; then
    echo "Service $service is not running." >&2
    "${compose_cmd[@]}" logs --tail=200 "$service" || true
    exit 1
  fi
done

# Local HTTP smoke check. On first boot this should expose the pH7 installer.
for attempt in $(seq 1 30); do
  if curl -fsS http://127.0.0.1/ >/dev/null; then
    break
  fi
  if [ "$attempt" -eq 30 ]; then
    echo "Local HTTP smoke check failed." >&2
    "${compose_cmd[@]}" logs --tail=200 caddy app
    exit 1
  fi
  sleep 3
done

cat <<EOF

DeseoCerca free-VM bootstrap completed.

Application directory: $REMOTE_DIR
Generated DB secrets: $SECRETS_FILE
Architecture: $(uname -m)
Site binding: $STAGING_SITE_ADDRESS

Next:
1. Ensure your cloud network/security list allows inbound TCP 80 and 443.
2. Open the VM public IP in a browser and complete the first pH7 installation.
3. Use database host 'db', database 'deseocerca', user 'deseocerca', and the
   generated password from $SECRETS_FILE. Keep the table prefix exactly 'ph7_'.
4. After installation run:
   cd $REMOTE_DIR && bash deploy/deseocerca/apply-bootstrap.sh
5. Then point staging.deseocerca.com to this VM and set STAGING_SITE_ADDRESS
   to staging.deseocerca.com for automatic HTTPS via Caddy.
EOF
