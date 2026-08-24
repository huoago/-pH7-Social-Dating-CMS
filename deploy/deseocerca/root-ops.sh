#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${DESEOCERCA_DIR:-/opt/deseocerca-staging}"
ENV_FILE="${DESEOCERCA_ENV_FILE:-$REMOTE_DIR/.env}"
ACTION="${1:-}"

[ "${EUID}" -eq 0 ] || { echo "root-ops.sh must run as root." >&2; exit 1; }
[ -d "$REMOTE_DIR/.git" ] || { echo "DeseoCerca repository is missing." >&2; exit 2; }
[ -f "$ENV_FILE" ] || { echo "DeseoCerca environment is missing." >&2; exit 2; }

is_free_tier() {
  grep -Eq '^TIDB_HOST=.+$' "$ENV_FILE"
}

validate_sha() {
  [[ "$1" =~ ^[a-f0-9]{40}$ ]]
}

validate_host() {
  [[ "$1" =~ ^[A-Za-z0-9.-]+$ ]]
}

case "$ACTION" in
  auto-install)
    [ "$#" -eq 1 ] || { echo "Usage: root-ops.sh auto-install" >&2; exit 64; }
    is_free_tier || { echo "Automatic first install is configured for the TiDB free-tier stack." >&2; exit 2; }
    compose=(docker compose --env-file "$ENV_FILE" -f "$REMOTE_DIR/deploy/deseocerca/compose.free.yml")
    if "${compose[@]}" exec -T app test -s /var/www/html/_constants.php; then
      echo "DeseoCerca is already installed; automatic installer skipped."
      exit 0
    fi
    exec /usr/bin/python3 "$REMOTE_DIR/deploy/deseocerca/automate-first-install.py"
    ;;

  backup)
    [ "$#" -eq 1 ] || { echo "Usage: root-ops.sh backup" >&2; exit 64; }
    if is_free_tier; then
      exec /bin/bash "$REMOTE_DIR/deploy/deseocerca/backup-free.sh"
    fi
    exec /bin/bash "$REMOTE_DIR/deploy/deseocerca/backup.sh"
    ;;

  gate)
    [ "$#" -eq 3 ] || { echo "Usage: root-ops.sh gate HOST staging|production" >&2; exit 64; }
    host="$2"
    mode="$3"
    validate_host "$host" || { echo "Invalid release-gate host." >&2; exit 64; }
    case "$mode" in staging|production) ;; *) echo "Invalid release-gate mode." >&2; exit 64 ;; esac
    exec /bin/bash "$REMOTE_DIR/deploy/deseocerca/release-gate.sh" "$host" "$mode"
    ;;

  promote)
    [ "$#" -eq 2 ] || { echo "Usage: root-ops.sh promote RELEASE_SHA" >&2; exit 64; }
    release_sha="$2"
    validate_sha "$release_sha" || { echo "Invalid release SHA." >&2; exit 64; }
    export DESEOCERCA_RELEASE_SHA="$release_sha"
    export DESEOCERCA_PRODUCTION_SITES="deseocerca.com www.deseocerca.com"
    exec /bin/bash "$REMOTE_DIR/deploy/deseocerca/promote-production.sh"
    ;;

  rollback)
    if [ "$#" -eq 1 ]; then
      exec /bin/bash "$REMOTE_DIR/deploy/deseocerca/rollback-production.sh"
    elif [ "$#" -eq 2 ] && [ "$2" = "--restore-site" ]; then
      exec /bin/bash "$REMOTE_DIR/deploy/deseocerca/rollback-production.sh" --restore-site
    fi
    echo "Usage: root-ops.sh rollback [--restore-site]" >&2
    exit 64
    ;;

  record-approval)
    [ "$#" -eq 1 ] || { echo "Usage: root-ops.sh record-approval" >&2; exit 64; }
    exec /usr/bin/python3 "$REMOTE_DIR/deploy/deseocerca/record-production-approval.py"
    ;;

  prepared-check)
    [ "$#" -eq 2 ] || { echo "Usage: root-ops.sh prepared-check RELEASE_SHA" >&2; exit 64; }
    release_sha="$2"
    validate_sha "$release_sha" || { echo "Invalid release SHA." >&2; exit 64; }
    grep -Fxq "release_sha=$release_sha" /root/deseocerca-production-prepared
    echo "Production prepared marker matches $release_sha."
    ;;

  mark-verified)
    [ "$#" -eq 2 ] || { echo "Usage: root-ops.sh mark-verified RELEASE_SHA" >&2; exit 64; }
    release_sha="$2"
    validate_sha "$release_sha" || { echo "Invalid release SHA." >&2; exit 64; }
    umask 077
    tmp="$(mktemp /root/.deseocerca-production-verified.XXXXXX)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<EOF
service=DeseoCerca
release_sha=$release_sha
verified_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    chmod 600 "$tmp"
    mv -f "$tmp" /root/deseocerca-production-verified
    trap - EXIT
    echo "Production verification marker recorded for $release_sha."
    ;;

  *)
    echo "Allowed actions: auto-install, backup, gate, promote, rollback, record-approval, prepared-check, mark-verified" >&2
    exit 64
    ;;
esac
