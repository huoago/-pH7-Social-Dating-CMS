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
BACKUP_PASSPHRASE_FILE="/root/deseocerca-backup-passphrase"
FIRST_INSTALL_FILE="/root/deseocerca-first-install.txt"
STAGING_SITE_ADDRESS="${STAGING_SITE_ADDRESS:-:80}"
MAILER_DSN="${PH7_MAILER_DSN:-}"
DEPLOY_USER="${DESEOCERCA_DEPLOY_USER:-ubuntu}"

if [ "${EUID}" -ne 0 ]; then
  echo "Run this script with sudo or as root." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This bootstrap currently supports Debian/Ubuntu apt-based systems." >&2
  exit 1
fi

# Compose .env is line-oriented. Reject control characters rather than allowing a
# malformed DSN/site value to inject additional environment entries.
for value_name in STAGING_SITE_ADDRESS MAILER_DSN; do
  value="${!value_name}"
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo "$value_name must not contain CR/LF characters." >&2
    exit 1
  fi
done

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git gnupg openssl ufw jq python3-minimal iproute2

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

# OCI Ubuntu uses the 'ubuntu' user by default. Give the selected deployment user
# ownership of the Git working tree and Docker access so subsequent GitHub Actions
# SSH deployments do not fail on root-owned /opt files. Root-only generated secret
# files remain outside the application directory.
if id "$DEPLOY_USER" >/dev/null 2>&1; then
  usermod -aG docker "$DEPLOY_USER"
  DEPLOY_GROUP="$(id -gn "$DEPLOY_USER")"
else
  echo "Deployment user '$DEPLOY_USER' does not exist; keeping application tree root-owned." >&2
  DEPLOY_USER=""
  DEPLOY_GROUP=""
fi

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
# A rerun may encounter a repository that is intentionally owned by DEPLOY_USER.
git config --global --add safe.directory "$REMOTE_DIR" || true
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
DESEOCERCA_STAGING_USER=${DEPLOY_USER:-root}

Keep this root-only file private. Database values are not required in GitHub
Actions when the remote .env created by this bootstrap is preserved.
EOF
  chmod 600 "$SECRETS_FILE"
fi

# Allow the deployment user to update the Git working tree and protected .env.
if [ -n "$DEPLOY_USER" ]; then
  chown -R "$DEPLOY_USER:$DEPLOY_GROUP" "$REMOTE_DIR"
  chmod 600 "$ENV_FILE"
fi

# Generate a dedicated backup encryption key only once. It is intentionally
# separate from the MySQL and SSH credentials.
if [ ! -s "$BACKUP_PASSPHRASE_FILE" ]; then
  umask 077
  openssl rand -base64 48 > "$BACKUP_PASSPHRASE_FILE"
  chmod 600 "$BACKUP_PASSPHRASE_FILE"
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

# Prepare a root-only first-install sheet and persist the installer token hash so
# rebuilding the app container before installation does not invalidate access.
bash "$REMOTE_DIR/deploy/deseocerca/prepare-first-install.sh"

# Install an encrypted daily local-backup timer. Production should additionally
# replicate these encrypted files to private off-VM storage.
cat > /etc/systemd/system/deseocerca-backup.service <<EOF
[Unit]
Description=DeseoCerca encrypted backup
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/bin/bash $REMOTE_DIR/deploy/deseocerca/backup.sh
User=root
Group=root
Nice=10
EOF

cat > /etc/systemd/system/deseocerca-backup.timer <<'EOF'
[Unit]
Description=Run DeseoCerca encrypted backup daily

[Timer]
OnCalendar=*-*-* 03:20:00 America/Lima
Persistent=true
RandomizedDelaySec=10m
Unit=deseocerca-backup.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now deseocerca-backup.timer

cat <<EOF

DeseoCerca free-VM bootstrap completed.

Application directory: $REMOTE_DIR
Generated DB secrets: $SECRETS_FILE
Protected first-install sheet: $FIRST_INSTALL_FILE
Backup encryption key: $BACKUP_PASSPHRASE_FILE
Deployment user: ${DEPLOY_USER:-root}
Architecture: $(uname -m)
Site binding: $STAGING_SITE_ADDRESS

Next:
1. Ensure your cloud network/security list allows inbound TCP 80 and 443.
2. Open the VM public IP in a browser and follow the root-only first-install sheet.
3. Keep the database table prefix exactly 'ph7_'.
4. After installation run:
   cd $REMOTE_DIR && bash deploy/deseocerca/apply-bootstrap.sh
5. Then point staging.deseocerca.com to this VM and set STAGING_SITE_ADDRESS
   to staging.deseocerca.com for automatic HTTPS via Caddy.
6. Delete $FIRST_INSTALL_FILE after installation and copy any credentials you still
   need to a separate password manager.
7. Copy the backup encryption key to a separate secure location. Losing the key
   makes encrypted backups unrecoverable.
EOF
