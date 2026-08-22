#!/usr/bin/env bash
set -euo pipefail

# Installs the upstream pH7 Spanish language pack at a pinned revision.
# Run from the pH7Builder application root after deployment.
# Upstream: https://github.com/pH7Software/pH7-Internationalization

REVISION="af674a4b41515145a8a85551a8ac69e42aec44d7"
BASE_URL="https://raw.githubusercontent.com/pH7Software/pH7-Internationalization/${REVISION}/_protected/app/langs/es_ES"
TARGET="_protected/app/langs/es_ES"

mkdir -p "${TARGET}/LC_MESSAGES" "${TARGET}/config"

curl --fail --location --silent --show-error \
    "${BASE_URL}/language.php" \
    --output "${TARGET}/language.php"

curl --fail --location --silent --show-error \
    "${BASE_URL}/config/config.ini" \
    --output "${TARGET}/config/config.ini"

curl --fail --location --silent --show-error \
    "${BASE_URL}/LC_MESSAGES/global.po" \
    --output "${TARGET}/LC_MESSAGES/global.po"

curl --fail --location --silent --show-error \
    "${BASE_URL}/LC_MESSAGES/global.mo" \
    --output "${TARGET}/LC_MESSAGES/global.mo"

# Peru-specific runtime defaults while retaining the upstream es_ES locale ID.
sed -i 's#timezone = "Europe/Madrid"#timezone = "America/Lima"#' "${TARGET}/config/config.ini"
sed -i 's#date_time_format = "d-m-Y H:i:s"#date_time_format = "d/m/Y H:i:s"#' "${TARGET}/config/config.ini"
sed -i 's#date_format = "d-m-Y"#date_format = "d/m/Y"#' "${TARGET}/config/config.ini"

printf '%s\n' "Spanish language pack installed at ${TARGET}."
printf '%s\n' "Review the translations for Peruvian Spanish before making es_ES the production default."
