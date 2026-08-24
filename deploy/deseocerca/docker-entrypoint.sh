#!/bin/sh
set -eu

APP_ROOT="/var/www/html"
RUNTIME_DIR="/var/lib/deseocerca/runtime"
CONSTANTS_FILE="${APP_ROOT}/_constants.php"
PERSISTED_CONSTANTS="${RUNTIME_DIR}/_constants.php"
INSTALL_DIR="${APP_ROOT}/_install"

mkdir -p "${RUNTIME_DIR}"

# Restore the installer-generated runtime constants before PHP/Apache or any
# maintenance command starts after a container replacement.
if [ ! -f "${CONSTANTS_FILE}" ] && [ -s "${PERSISTED_CONSTANTS}" ]; then
    cp "${PERSISTED_CONSTANTS}" "${CONSTANTS_FILE}"
    chmod 0600 "${CONSTANTS_FILE}"
    chown www-data:www-data "${CONSTANTS_FILE}"
fi

# A rebuilt image contains the browser installer again. Once a persisted
# _constants.php proves installation has completed, remove the installer on
# every container start so deployment cannot accidentally reopen setup.
if [ -s "${CONSTANTS_FILE}" ] && [ -d "${INSTALL_DIR}" ]; then
    rm -rf "${INSTALL_DIR}"
fi

sync_runtime_constants() {
    while :; do
        if [ -s "${CONSTANTS_FILE}" ]; then
            if [ ! -s "${PERSISTED_CONSTANTS}" ] || ! cmp -s "${CONSTANTS_FILE}" "${PERSISTED_CONSTANTS}"; then
                cp "${CONSTANTS_FILE}" "${PERSISTED_CONSTANTS}.tmp"
                chmod 0600 "${PERSISTED_CONSTANTS}.tmp"
                chown www-data:www-data "${PERSISTED_CONSTANTS}.tmp"
                mv -f "${PERSISTED_CONSTANTS}.tmp" "${PERSISTED_CONSTANTS}"
            fi
        fi
        sleep 5
    done
}

# The installer writes _constants.php atomically after the container is already
# running. Mirror it to the named runtime volume so future containers can restore it.
sync_runtime_constants &

exec docker-php-entrypoint "$@"
