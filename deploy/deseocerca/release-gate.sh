#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
ENV_FILE="${DESEOCERCA_ENV_FILE:-$REMOTE_DIR/.env}"
COMPOSE_FILE="$REMOTE_DIR/deploy/deseocerca/compose.staging.yml"
BACKUP_DIR="${DESEOCERCA_BACKUP_DIR:-/var/backups/deseocerca}"
MODE="${DESEOCERCA_GATE_MODE:-staging}"
EXPECTED_HOST="${1:-}"
MAX_BACKUP_AGE_SECONDS="${DESEOCERCA_MAX_BACKUP_AGE_SECONDS:-129600}"
LEGAL_NOTICE="$REMOTE_DIR/_protected/app/system/modules/page/views/base/tpl/main/legalnotice.tpl"

failures=0
warnings=0

pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; failures=$((failures + 1)); }

if [ "$MODE" != "staging" ] && [ "$MODE" != "production" ]; then
  echo "DESEOCERCA_GATE_MODE must be staging or production." >&2
  exit 2
fi
if [[ ! "$EXPECTED_HOST" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "Usage: DESEOCERCA_GATE_MODE=staging|production $0 <hostname>" >&2
  exit 2
fi
if [ ! -f "$ENV_FILE" ] || [ ! -f "$COMPOSE_FILE" ]; then
  echo "Missing DeseoCerca environment or Compose file." >&2
  exit 2
fi

printf 'DeseoCerca release gate (%s)\n==============================\n' "$MODE"

if DESEOCERCA_DIR="$REMOTE_DIR" DESEOCERCA_ENV_FILE="$ENV_FILE" \
    bash "$REMOTE_DIR/deploy/deseocerca/host-preflight.sh" "$EXPECTED_HOST"; then
  pass "host preflight has no hard failures"
else
  fail "host preflight reported hard failures"
fi

compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
for service in db app caddy lifecycle; do
  if "${compose[@]}" ps --status running --services 2>/dev/null | grep -qx "$service"; then
    pass "container running: $service"
  else
    fail "required container is not running: $service"
  fi
done

if "${compose[@]}" exec -T app test -s /var/www/html/_constants.php; then
  pass "pH7 installation constants exist"
else
  fail "pH7 installation is incomplete (_constants.php missing)"
fi
if "${compose[@]}" exec -T app test ! -d /var/www/html/_install; then
  pass "installer directory is removed from installed runtime"
else
  fail "installer directory still exists in installed runtime"
fi

if "${compose[@]}" exec -T app php deploy/deseocerca/verify-runtime.php; then
  pass "DeseoCerca runtime verifier passed"
else
  fail "DeseoCerca runtime verifier failed"
fi

site_address="$(grep -m1 '^STAGING_SITE_ADDRESS=' "$ENV_FILE" | cut -d= -f2- || true)"
if [ "$site_address" = "$EXPECTED_HOST" ]; then
  pass "configured site address matches release-gate host"
else
  fail "STAGING_SITE_ADDRESS='$site_address' does not match '$EXPECTED_HOST'"
fi

if ENV_FILE="$ENV_FILE" python3 - <<'PY'
import os
import socket
import sys
from urllib.parse import urlsplit

env_path = os.environ["ENV_FILE"]
dsn = ""
with open(env_path, "r", encoding="utf-8") as handle:
    for raw in handle:
        if raw.startswith("PH7_MAILER_DSN="):
            dsn = raw.rstrip("\r\n").split("=", 1)[1]
            break
if not dsn:
    print("PH7_MAILER_DSN is empty", file=sys.stderr)
    raise SystemExit(1)
parsed = urlsplit(dsn)
if parsed.scheme not in {"smtp", "smtps"} or not parsed.hostname:
    print("PH7_MAILER_DSN is not a valid smtp/smtps DSN", file=sys.stderr)
    raise SystemExit(1)
port = parsed.port or (465 if parsed.scheme == "smtps" else 25)
try:
    with socket.create_connection((parsed.hostname, port), timeout=8):
        pass
except OSError as exc:
    print(f"SMTP endpoint is unreachable: {exc}", file=sys.stderr)
    raise SystemExit(1)
print(f"SMTP endpoint reachable: {parsed.hostname}:{port}")
PY
then
  pass "transactional mail transport is configured and reachable"
else
  fail "transactional mail transport is not release-ready"
fi

if systemctl is-enabled --quiet deseocerca-backup.timer 2>/dev/null && \
   systemctl is-active --quiet deseocerca-backup.timer 2>/dev/null; then
  pass "encrypted backup timer is enabled and active"
else
  fail "encrypted backup timer is not both enabled and active"
fi

latest_backup="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'deseocerca-*.tar.gz.enc' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {$1=""; sub(/^ /, ""); print; exit}')"
if [ -z "$latest_backup" ] || [ ! -f "$latest_backup" ]; then
  fail "no encrypted backup archive exists"
else
  now="$(date +%s)"
  modified="$(stat -c '%Y' "$latest_backup")"
  age=$((now - modified))
  if [ "$age" -le "$MAX_BACKUP_AGE_SECONDS" ]; then
    pass "latest encrypted backup is fresh (${age}s old)"
  else
    fail "latest encrypted backup is stale (${age}s old)"
  fi
  if [ -f "$latest_backup.sha256" ] && sha256sum -c "$latest_backup.sha256" >/dev/null 2>&1; then
    pass "latest encrypted backup checksum is valid"
  else
    fail "latest encrypted backup checksum is missing or invalid"
  fi
fi

if python3 "$REMOTE_DIR/deploy/deseocerca/public-smoke.py" "$EXPECTED_HOST"; then
  pass "public HTTPS/legal-page smoke checks passed"
else
  fail "public HTTPS/legal-page smoke checks failed"
fi

placeholder='deben publicarse antes del lanzamiento comercial de producción'
if grep -Fq "$placeholder" "$LEGAL_NOTICE" 2>/dev/null; then
  if [ "$MODE" = "production" ]; then
    fail "Legal Notice still contains the pre-production operator placeholder"
  else
    warn "Legal Notice still contains the pre-production operator placeholder"
  fi
else
  pass "Legal Notice operator placeholder has been removed"
fi

if [ "$MODE" = "production" ]; then
  for marker in \
    /root/deseocerca-legal-approved \
    /root/deseocerca-e2e-approved \
    /root/deseocerca-restore-drill-approved \
    /root/deseocerca-offsite-backup-approved; do
    if [ -s "$marker" ]; then
      pass "production approval marker exists: $marker"
    else
      fail "missing production approval marker: $marker"
    fi
  done
else
  for marker in \
    /root/deseocerca-legal-approved \
    /root/deseocerca-e2e-approved \
    /root/deseocerca-restore-drill-approved \
    /root/deseocerca-offsite-backup-approved; do
    [ -s "$marker" ] || warn "production approval marker not present yet: $marker"
  done
fi

printf '\nRelease gate summary: mode=%s failures=%d warnings=%d\n' "$MODE" "$failures" "$warnings"
exit "$failures"
