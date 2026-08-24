#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
DEPLOY_USER="${DESEOCERCA_DEPLOY_USER:-${SUDO_USER:-}}"
BRANCH="${DESEOCERCA_BRANCH:-deseocerca-v1}"
SITE_ADDRESS="${STAGING_SITE_ADDRESS:-:80}"
REPO_URL="${DESEOCERCA_REPO_URL:-https://github.com/huoago/-pH7-Social-Dating-CMS.git}"
BACKUP_KEY="/root/deseocerca-backup-passphrase"

if [ "${EUID}" -ne 0 ]; then
  echo "Run as root or through sudo." >&2
  exit 1
fi
if [ -z "$DEPLOY_USER" ] || ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  echo "DESEOCERCA_DEPLOY_USER must name the existing SSH user." >&2
  exit 2
fi
case "$BRANCH" in
  deseocerca-v1|18.x) ;;
  *) echo "Unsupported deployment branch: $BRANCH" >&2; exit 2 ;;
esac

. /etc/os-release
if [ "${ID:-}" != "ubuntu" ]; then
  echo "Google Free Tier bootstrap currently supports Ubuntu only." >&2
  exit 2
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl git gnupg openssl ufw

if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  printf '%s\n' \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

systemctl enable --now docker
usermod -aG docker "$DEPLOY_USER"

if [ "$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)" -lt 1800 ] && ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
  if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
  fi
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

if [ ! -d "$REMOTE_DIR/.git" ]; then
  rm -rf "$REMOTE_DIR"
  git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$REMOTE_DIR"
else
  git -C "$REMOTE_DIR" fetch --prune origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
  git -C "$REMOTE_DIR" checkout -B "$BRANCH" "origin/$BRANCH"
  git -C "$REMOTE_DIR" reset --hard "origin/$BRANCH"
fi

cat > "$REMOTE_DIR/.env" <<EOF
DESEOCERCA_APP_IMAGE=deseocerca-free:current
STAGING_SITE_ADDRESS=$SITE_ADDRESS
PH7_CANONICAL_HOST=
PH7_CANONICAL_SCHEME=https
TIDB_HOST=
TIDB_USERNAME=
TIDB_PASSWORD=
TIDB_DATABASE=deseocerca
PH7_MAILER_DSN=
EOF
chmod 600 "$REMOTE_DIR/.env"
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$REMOTE_DIR"

if [ ! -s "$BACKUP_KEY" ]; then
  umask 077
  openssl rand -hex 32 > "$BACKUP_KEY"
fi
chmod 600 "$BACKUP_KEY"

cat > /etc/systemd/system/deseocerca-backup.service <<EOF
[Unit]
Description=DeseoCerca encrypted backup (Google Free Tier + TiDB)
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
Environment=DESEOCERCA_DIR=$REMOTE_DIR
ExecStart=/bin/bash $REMOTE_DIR/deploy/deseocerca/backup-free.sh
EOF

cat > /etc/systemd/system/deseocerca-backup.timer <<'EOF'
[Unit]
Description=Daily DeseoCerca encrypted backup

[Timer]
OnCalendar=*-*-* 03:20:00 America/Lima
Persistent=true
RandomizedDelaySec=20m

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now deseocerca-backup.timer

cat > /etc/sudoers.d/deseocerca-deploy <<EOF
$DEPLOY_USER ALL=(root) NOPASSWD: /bin/bash $REMOTE_DIR/deploy/deseocerca/root-ops.sh *
$DEPLOY_USER ALL=(root) NOPASSWD: /bin/bash $REMOTE_DIR/deploy/deseocerca/prepare-first-install-free.sh
$DEPLOY_USER ALL=(root) NOPASSWD: /bin/bash $REMOTE_DIR/deploy/deseocerca/restore-free.sh *
EOF
chmod 440 /etc/sudoers.d/deseocerca-deploy
visudo -cf /etc/sudoers.d/deseocerca-deploy >/dev/null

echo "Google Free Tier host prepared at $REMOTE_DIR."
echo "No local MySQL server was installed; TiDB Cloud Starter will be used through a TLS proxy."
