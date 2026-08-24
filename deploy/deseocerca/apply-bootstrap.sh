#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="deploy/deseocerca/compose.staging.yml"
ENV_FILE="${DESEOCERCA_ENV_FILE:-.env}"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Run this script from the repository root." >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing environment file: ${ENV_FILE}" >&2
  exit 1
fi

compose=(docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")

"${compose[@]}" exec -T app test -s /var/www/html/_constants.php || {
  echo "DeseoCerca is not installed yet. Complete the browser installer first." >&2
  exit 1
}

db_prefix="$(
  "${compose[@]}" exec -T app php -r \
    '$c=parse_ini_file("/var/www/html/_protected/app/configs/config.ini", true); echo $c["database"]["prefix"] ?? "";'
)"

if [[ "${db_prefix}" != "ph7_" ]]; then
  echo "Refusing bootstrap: deploy/deseocerca/bootstrap.sql expects database prefix ph7_, found '${db_prefix}'." >&2
  exit 1
fi

"${compose[@]}" exec -T db sh -lc \
  'exec mysql --default-character-set=utf8mb4 -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' \
  < deploy/deseocerca/bootstrap.sql

"${compose[@]}" exec -T app php deploy/deseocerca/verify-runtime.php

echo "DeseoCerca bootstrap applied and runtime verification passed."
