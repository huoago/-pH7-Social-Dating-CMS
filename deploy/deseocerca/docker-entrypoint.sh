#!/bin/sh
set -eu

APP_ROOT="/var/www/html"
RUNTIME_DIR="/var/lib/deseocerca/runtime"
CONSTANTS_FILE="${APP_ROOT}/_constants.php"
PERSISTED_CONSTANTS="${RUNTIME_DIR}/_constants.php"
INSTALL_DIR="${APP_ROOT}/_install"

mkdir -p "${RUNTIME_DIR}"

secure_installed_runtime() {
    if [ -s "${CONSTANTS_FILE}" ] && [ -d "${INSTALL_DIR}" ]; then
        rm -rf "${INSTALL_DIR}"
    fi
}

restore_runtime_constants() {
    if [ ! -s "${CONSTANTS_FILE}" ] && [ -s "${PERSISTED_CONSTANTS}" ]; then
        cp "${PERSISTED_CONSTANTS}" "${CONSTANTS_FILE}"
        chmod 0600 "${CONSTANTS_FILE}"
        chown www-data:www-data "${CONSTANTS_FILE}"
        secure_installed_runtime
    fi
}

restore_runtime_constants
secure_installed_runtime

sync_runtime_constants() {
    while :; do
        # This also lets sidecar containers discover an installation completed
        # later by the web container without requiring a restart.
        restore_runtime_constants

        if [ -s "${CONSTANTS_FILE}" ]; then
            secure_installed_runtime
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
# running. Mirror it to the named runtime volume and restore it into sidecars or
# replacement containers as soon as it becomes available.
sync_runtime_constants &

exec docker-php-entrypoint "$@"
