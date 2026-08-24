#!/bin/sh
set -eu

APP_ROOT="/var/www/html"
RUNTIME_DIR="/var/lib/deseocerca/runtime"
CONSTANTS_FILE="${APP_ROOT}/_constants.php"
PERSISTED_CONSTANTS="${RUNTIME_DIR}/_constants.php"
INSTALL_DIR="${APP_ROOT}/_install"
INSTALL_TOKEN_FILE="${INSTALL_DIR}/data/caches/install-token.hash"
PERSISTED_INSTALL_TOKEN="${RUNTIME_DIR}/install-token.hash"

mkdir -p "${RUNTIME_DIR}"

secure_installed_runtime() {
    if [ -s "${CONSTANTS_FILE}" ]; then
        rm -f "${PERSISTED_INSTALL_TOKEN}"
        if [ -d "${INSTALL_DIR}" ]; then
            rm -rf "${INSTALL_DIR}"
        fi
    fi
}

restore_runtime_constants() {
    if [ ! -s "${CONSTANTS_FILE}" ] && [ -s "${PERSISTED_CONSTANTS}" ]; then
        cp "${PERSISTED_CONSTANTS}" "${CONSTANTS_FILE}"
        chmod 0600 "${CONSTANTS_FILE}"
        chown www-data:www-data "${CONSTANTS_FILE}"
    fi
}

restore_installer_token() {
    if [ ! -s "${CONSTANTS_FILE}" ] && [ -d "${INSTALL_DIR}" ] && [ ! -s "${INSTALL_TOKEN_FILE}" ] && [ -s "${PERSISTED_INSTALL_TOKEN}" ]; then
        mkdir -p "$(dirname "${INSTALL_TOKEN_FILE}")"
        cp "${PERSISTED_INSTALL_TOKEN}" "${INSTALL_TOKEN_FILE}"
        chmod 0640 "${INSTALL_TOKEN_FILE}"
        chown www-data:www-data "${INSTALL_TOKEN_FILE}"
    fi
}

restore_runtime_constants
restore_installer_token
secure_installed_runtime

sync_runtime_state() {
    while :; do
        # This lets sidecar/replacement containers discover an installation
        # completed later by the web container without requiring a restart.
        restore_runtime_constants
        restore_installer_token

        if [ -s "${CONSTANTS_FILE}" ]; then
            secure_installed_runtime
            if [ ! -s "${PERSISTED_CONSTANTS}" ] || ! cmp -s "${CONSTANTS_FILE}" "${PERSISTED_CONSTANTS}"; then
                cp "${CONSTANTS_FILE}" "${PERSISTED_CONSTANTS}.tmp"
                chmod 0600 "${PERSISTED_CONSTANTS}.tmp"
                chown www-data:www-data "${PERSISTED_CONSTANTS}.tmp"
                mv -f "${PERSISTED_CONSTANTS}.tmp" "${PERSISTED_CONSTANTS}"
            fi
        elif [ -s "${INSTALL_TOKEN_FILE}" ]; then
            if [ ! -s "${PERSISTED_INSTALL_TOKEN}" ] || ! cmp -s "${INSTALL_TOKEN_FILE}" "${PERSISTED_INSTALL_TOKEN}"; then
                cp "${INSTALL_TOKEN_FILE}" "${PERSISTED_INSTALL_TOKEN}.tmp"
                chmod 0640 "${PERSISTED_INSTALL_TOKEN}.tmp"
                chown www-data:www-data "${PERSISTED_INSTALL_TOKEN}.tmp"
                mv -f "${PERSISTED_INSTALL_TOKEN}.tmp" "${PERSISTED_INSTALL_TOKEN}"
            fi
        fi
        sleep 5
    done
}

# The installer writes _constants.php and the access-token hash after the
# container is already running. Mirror both to the named runtime volume until
# installation completes. Once installed, delete the token and installer tree.
sync_runtime_state &

exec docker-php-entrypoint "$@"
