#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
ENV_FILE="${DESEOCERCA_ENV_FILE:-$REMOTE_DIR/.env}"
COMPOSE_FILE="${DESEOCERCA_COMPOSE_FILE:-}"
BACKUP_DIR="${DESEOCERCA_BACKUP_DIR:-/var/backups/deseocerca}"
EXPECTED_HOST="${1:-}"
MODE="${2:-${DESEOCERCA_GATE_MODE:-staging}}"
MAX_BACKUP_AGE_SECONDS="${DESEOCERCA_MAX_BACKUP_AGE_SECONDS:-129600}"
SITE_ENV_KEY="${DESEOCERCA_SITE_ENV_KEY:-STAGING_SITE_ADDRESS}"
LEGAL_NOTICE="$REMOTE_DIR/_protected/app/system/modules/page/views/base/tpl/main/legalnotice.tpl"

if [ -z "$COMPOSE_FILE" ]; then
  if [ -f "$ENV_FILE" ] && grep -Eq '^TIDB_HOST=.+$' "$ENV_FILE"; then
    COMPOSE_FILE="$REMOTE_DIR/deploy/deseocerca/compose.free.yml"
  else
    COMPOSE_FILE="$REMOTE_DIR/deploy/deseocerca/compose.staging.yml"
  fi
fi

failures=0
warnings=0

pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; failures=$((failures + 1)); }

if [ "$MODE" != "staging" ] && [ "$MODE" != "production" ]; then
  echo "Gate mode must be staging or production." >&2
  exit 2
fi
if [[ ! "$EXPECTED_HOST" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "Usage: $0 <hostname> [staging|production]" >&2
  exit 2
fi
if [[ ! "$SITE_ENV_KEY" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "DESEOCERCA_SITE_ENV_KEY is invalid." >&2
  exit 2
fi
if [ ! -f "$ENV_FILE" ] || [ ! -f "$COMPOSE_FILE" ]; then
  echo "Missing DeseoCerca environment or Compose file." >&2
  exit 2
fi

printf 'DeseoCerca release gate (%s)\n==============================\n' "$MODE"

if DESEOCERCA_DIR="$REMOTE_DIR" DESEOCERCA_ENV_FILE="$ENV_FILE" DESEOCERCA_COMPOSE_FILE="$COMPOSE_FILE" \
    bash "$REMOTE_DIR/deploy/deseocerca/host-preflight.sh" "$EXPECTED_HOST"; then
  pass "host preflight has no hard failures"
else
  fail "host preflight reported hard failures"
fi

compose=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
database_service="db"
if "${compose[@]}" config --services | grep -qx 'db-tls'; then
  database_service="db-tls"
fi
for service in "$database_service" app caddy lifecycle; do
  if "${compose[@]}" ps --status running --services 2>/dev/null | grep -qx "$service"; then
    pass "container running: $service"
  else
    fail "required container is not running: $service"
  fi
done

if [ "$database_service" = "db-tls" ]; then
  tidb_user="$(grep -m1 '^TIDB_USERNAME=' "$ENV_FILE" | cut -d= -f2- || true)"
  tidb_database="$(grep -m1 '^TIDB_DATABASE=' "$ENV_FILE" | cut -d= -f2- || true)"
  if [ -n "$tidb_user" ] && [ -n "$tidb_database" ] && \
     "${compose[@]}" run --rm --no-deps -T --entrypoint mysql db-client \
       --host=db-tls --port=3306 --user="$tidb_user" --database="$tidb_database" \
       --connect-timeout=10 --execute='SELECT 1' >/dev/null 2>&1; then
    pass "TiDB Cloud connection succeeds through verified TLS proxy"
  else
    fail "TiDB Cloud database connectivity check failed"
  fi
fi

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

site_address="$(grep -m1 -E "^${SITE_ENV_KEY}=" "$ENV_FILE" | cut -d= -f2- || true)"
site_matches=false
while IFS= read -r token; do
  [ -n "$token" ] || continue
  token="${token#http://}"
  token="${token#https://}"
  token="${token%%/*}"
  token="${token%%:*}"
  if [ "$token" = "$EXPECTED_HOST" ]; then
    site_matches=true
    break
  fi
done < <(printf '%s' "$site_address" | tr ',' ' ' | tr -s '[:space:]' '\n')

if [ "$site_matches" = true ]; then
  pass "configured site addresses include release-gate host"
else
  fail "$SITE_ENV_KEY='$site_address' does not include '$EXPECTED_HOST'"
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

current_sha="$(git -C "$REMOTE_DIR" rev-parse HEAD 2>/dev/null || true)"
if [[ "$current_sha" =~ ^[a-f0-9]{40}$ ]]; then
  pass "release revision resolved: $current_sha"
else
  fail "could not resolve the deployed Git revision"
fi

approval_markers=(
  /root/deseocerca-legal-approved
  /root/deseocerca-e2e-approved
  /root/deseocerca-restore-drill-approved
  /root/deseocerca-offsite-backup-approved
)

if [ "$MODE" = "production" ]; then
  for marker in "${approval_markers[@]}"; do
    if [ -s "$marker" ] && grep -Fxq "release_sha=$current_sha" "$marker"; then
      pass "production approval matches release: $marker"
    else
      fail "missing or stale production approval for release $current_sha: $marker"
    fi
  done
else
  for marker in "${approval_markers[@]}"; do
    if [ -s "$marker" ] && grep -Fxq "release_sha=$current_sha" "$marker"; then
      pass "production approval already matches current release: $marker"
    else
      warn "production approval not recorded for current release: $marker"
    fi
  done
fi

printf '\nRelease gate summary: mode=%s failures=%d warnings=%d\n' "$MODE" "$failures" "$warnings"
exit "$failures"
