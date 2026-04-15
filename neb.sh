#!/bin/sh
#
# neb.sh — Backup and restore the Nextcloud Enclave instance
#
# Usage:
#   ./neb.sh backup                        Run while the stack is UP
#   ./neb.sh restore <backup_directory>    Run while the stack is DOWN
#
# Each backup creates a directory under ./backups/ containing:
#   dump.sql.gz            — PostgreSQL roles + database
#   config.php             — Nextcloud configuration (DB creds, instance ID, etc.)
#   custom.config.php      — Nextcloud Enclave custom configuration (see documentation)
#   custom_apps.tar        — Apps installed from the Nextcloud app store
#
# Backup files contain secrets (DB password, Nextcloud instance secret,
# session signing key). The script enforces restrictive permissions:
#   ./backups/             0700
#   ./backups/<ts>/        0700
#   dump.sql.gz            0600
#   config.php             0600
#   custom_apps.tar        0600
#
set -eu

# Restrict default file creation mode for the duration of this script.
# 077 -> new files are 0600, new directories are 0700.
umask 077

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"

# If you use a custom COMPOSE_PROJECT_NAME, change this to match.
PROJECT_NAME="$(basename "${SCRIPT_DIR}")"
DB_VOLUME="${PROJECT_NAME}_nextcloud_postgres_data"
CONFIG_VOLUME="${PROJECT_NAME}_nextcloud_config"
DATA_VOLUME="${PROJECT_NAME}_nextcloud_data"
# ------------------------------------

. "${SCRIPT_DIR}/envs/nextcloud-postgres.env"

do_backup() {
    if ! podman exec nextcloud-postgres pg_isready -U "${POSTGRES_USER}" > /dev/null 2>&1; then
        echo "Error: PostgreSQL container is not running or not ready."
        exit 1
    fi

    # Make sure the parent backups dir exists and is locked down.
    # chmod runs unconditionally so an existing world-readable dir
    # from a previous version of this script gets corrected.
    mkdir -p "${BACKUP_DIR}"
    chmod 700 "${BACKUP_DIR}"

    TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"
    mkdir -p "${BACKUP_PATH}"
    chmod 700 "${BACKUP_PATH}"

    echo "Backing up database '${POSTGRES_DB}'..."
    {
        podman exec nextcloud-postgres pg_dumpall -U "${POSTGRES_USER}" --roles-only
        podman exec nextcloud-postgres pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}"
    } | gzip > "${BACKUP_PATH}/dump.sql.gz"
    chmod 600 "${BACKUP_PATH}/dump.sql.gz"

    echo "Backing up config.php..."
    podman cp nextcloud:/var/www/html/config/config.php "${BACKUP_PATH}/config.php"
    # podman cp preserves the in-container mode but we re-assert it
    # in case the source file ever changes.
    chmod 600 "${BACKUP_PATH}/config.php"

    echo "Backing up custom.config.php..."
    podman cp nextcloud:/var/www/html/config/custom.config.php "${BACKUP_PATH}/custom.config.php"
    # podman cp preserves the in-container mode but we re-assert it
    # in case the source file ever changes.
    chmod 600 "${BACKUP_PATH}/custom.config.php"

    echo "Backing up installed apps..."
    podman exec nextcloud tar cf - -C /var/www/html custom_apps > "${BACKUP_PATH}/custom_apps.tar"
    chmod 600 "${BACKUP_PATH}/custom_apps.tar"

    echo "Done: ${BACKUP_PATH}"
}

do_restore() {
    BACKUP_PATH="${1:-}"

    if [ -z "${BACKUP_PATH}" ]; then
        echo "Usage: $0 restore <backup_directory>"
        echo ""
        echo "Available backups:"
        ls -1td "${BACKUP_DIR}/"*/ 2>/dev/null | while read -r d; do
            echo "  ${d}"
        done || echo "  (none)"
        exit 1
    fi

    BACKUP_PATH="$(cd "${BACKUP_PATH%/}" && pwd)"

    if [ ! -f "${BACKUP_PATH}/dump.sql.gz" ]; then
        echo "Error: ${BACKUP_PATH}/dump.sql.gz not found."
        exit 1
    fi

    if [ ! -f "${BACKUP_PATH}/config.php" ]; then
        echo "Error: ${BACKUP_PATH}/config.php not found."
        exit 1
    fi

    if [ ! -f "${BACKUP_PATH}/custom.config.php" ]; then
        echo "Error: ${BACKUP_PATH}/custom.config.php not found."
        exit 1
    fi

    if podman ps --format '{{.Names}}' | grep -q '^nextcloud$'; then
        echo "Error: the stack is still running. Bring it down first:"
        echo "  podman-compose down"
        exit 1
    fi

    echo "This will restore the Nextcloud instance from:"
    echo "  ${BACKUP_PATH}"
    echo ""
    printf "Type 'yes' to continue: "
    read CONFIRM
    if [ "${CONFIRM}" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi

    echo ""
    echo "Starting database..."
    podman-compose -f "${SCRIPT_DIR}/docker-compose.yaml" up -d nextcloud-postgres

    echo "Waiting for PostgreSQL to be ready..."
    until podman exec nextcloud-postgres pg_isready -U "${POSTGRES_USER}" > /dev/null 2>&1; do
        sleep 1
    done
    sleep 2

    echo "Preparing database..."
    podman exec nextcloud-postgres psql -U "${POSTGRES_USER}" -d template1 --quiet \
        -c "DROP DATABASE IF EXISTS \"${POSTGRES_DB}\";" \
        -c "CREATE DATABASE \"${POSTGRES_DB}\" OWNER \"${POSTGRES_USER}\";" > /dev/null 2>&1

    echo "Restoring database from backup..."
    gunzip -c "${BACKUP_PATH}/dump.sql.gz" \
        | podman exec -i nextcloud-postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" --quiet > /dev/null 2>&1

    echo "Stopping database..."
    podman-compose -f "${SCRIPT_DIR}/docker-compose.yaml" down 2>/dev/null

    echo "Restoring config.php..."
    podman run --rm \
        -v "${CONFIG_VOLUME}:/config" \
        -v "${BACKUP_PATH}:/backup:ro" \
        docker.io/library/postgres:16-alpine \
        sh -c "cp /backup/config.php /config/config.php && chown 33:33 /config/config.php && chmod 640 /config/config.php"

    echo "Restoring data directory and installed apps..."
    podman run --rm \
        -v "${DATA_VOLUME}:/data" \
        -v "${BACKUP_PATH}:/backup:ro" \
        docker.io/library/postgres:16-alpine \
        sh -c "
            mkdir -p /data/data
            echo '# Nextcloud data directory' > /data/data/.ncdata
            tar xf /backup/custom_apps.tar -C /data 2>/dev/null || true
            chown -R 33:33 /data/data /data/custom_apps
        "

    echo ""
    echo "Restore complete."
    echo "Start the full stack with:  podman-compose up -d"
    echo ""
    echo "If the backup was outdated, run this after the stack is up:"
    echo "podman exec -u www-data nextcloud php occ maintenance:data-fingerprint"
}

case "${1:-}" in
    backup)
        do_backup
        ;;
    restore)
        shift
        do_restore "$@"
        ;;
    *)
        echo "Usage: $0 {backup|restore <backup_directory>}"
        exit 1
        ;;
esac
