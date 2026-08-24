#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
ENV_FILE="${DESEOCERCA_ENV_FILE:-$REMOTE_DIR/.env}"
COMPOSE_FILE="$REMOTE_DIR/deploy/deseocerca/compose.staging.yml"
EXPECTED_HOST="${1:-}"

failures=0
warnings=0

pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; failures=$((failures + 1)); }

printf 'DeseoCerca host preflight\n=========================\n'

arch="$(uname -m)"
case "$arch" in
  x86_64|aarch64|arm64) pass "supported architecture: $arch" ;;
  *) fail "untested architecture: $arch" ;;
esac

mem_mb="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)"
if [ "$mem_mb" -ge 3500 ]; then
  pass "memory: ${mem_mb} MB"
elif [ "$mem_mb" -ge 900 ]; then
  warn "low memory: ${mem_mb} MB; swap and reduced concurrency are required"
else
  fail "insufficient memory: ${mem_mb} MB"
fi

root_free_mb="$(df -Pm / | awk 'NR==2 {print $4}')"
if [ "$root_free_mb" -ge 12000 ]; then
  pass "free disk: ${root_free_mb} MB"
elif [ "$root_free_mb" -ge 6000 ]; then
  warn "limited free disk: ${root_free_mb} MB; Docker builds/backups may exhaust it"
else
  fail "insufficient free disk: ${root_free_mb} MB"
fi

if command -v docker >/dev/null 2>&1; then
  pass "Docker installed: $(docker --version)"
else
  fail "Docker is not installed"
fi

if docker compose version >/dev/null 2>&1; then
  pass "Docker Compose plugin installed"
else
  fail "Docker Compose plugin is unavailable"
fi

if systemctl is-active --quiet docker 2>/dev/null; then
  pass "Docker service active"
else
  fail "Docker service is not active"
fi

if [ -f "$ENV_FILE" ]; then
  if [ "$(stat -c '%a' "$ENV_FILE")" = "600" ]; then
    pass ".env permissions are 600"
  else
    warn ".env permissions are $(stat -c '%a' "$ENV_FILE"); expected 600"
  fi
else
  fail "missing environment file: $ENV_FILE"
fi

if [ -f "$COMPOSE_FILE" ]; then
  pass "staging Compose file exists"
else
  fail "missing staging Compose file"
fi

if [ -f "$ENV_FILE" ] && [ -f "$COMPOSE_FILE" ] && docker compose version >/dev/null 2>&1; then
  compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
  if "${compose[@]}" config --quiet >/dev/null 2>&1; then
    pass "staging Compose configuration parses"
  else
    fail "staging Compose configuration is invalid"
  fi

  for service in db app caddy lifecycle; do
    if "${compose[@]}" ps --status running --services 2>/dev/null | grep -qx "$service"; then
      pass "container running: $service"
    else
      warn "container not running: $service"
    fi
  done
fi

if systemctl is-enabled --quiet deseocerca-backup.timer 2>/dev/null; then
  pass "encrypted backup timer enabled"
else
  warn "encrypted backup timer is not enabled"
fi

if systemctl is-active --quiet deseocerca-backup.timer 2>/dev/null; then
  pass "encrypted backup timer active"
else
  warn "encrypted backup timer is not active"
fi

if [ -s /root/deseocerca-backup-passphrase ]; then
  pass "backup encryption key exists"
else
  warn "backup encryption key is missing"
fi

if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)80$'; then
  pass "TCP 80 is listening"
else
  warn "TCP 80 is not listening"
fi
if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)443$'; then
  pass "TCP 443 is listening"
else
  warn "TCP 443 is not listening yet"
fi
if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)3306$'; then
  fail "MySQL 3306 is listening on the host; it should remain Docker-internal only"
else
  pass "MySQL 3306 is not exposed on the host"
fi

if [ -n "$EXPECTED_HOST" ]; then
  if command -v getent >/dev/null 2>&1 && getent ahostsv4 "$EXPECTED_HOST" >/dev/null 2>&1; then
    resolved_ip="$(getent ahostsv4 "$EXPECTED_HOST" | awk 'NR==1 {print $1}')"
    pass "DNS resolves: $EXPECTED_HOST -> $resolved_ip"
  else
    fail "DNS does not resolve: $EXPECTED_HOST"
  fi

  if curl -fsSI --max-time 10 "https://$EXPECTED_HOST/" >/dev/null 2>&1; then
    pass "HTTPS responds: https://$EXPECTED_HOST/"
  else
    warn "HTTPS not ready for $EXPECTED_HOST"
  fi
fi

printf '\nSummary: failures=%d warnings=%d\n' "$failures" "$warnings"
exit "$failures"
