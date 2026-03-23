#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '>>> [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/backups}"
RESTORE_DATA_DIR="${RESTORE_DATA_DIR:-/var/lib/mysql}"
WORK_DIR="${WORK_DIR:-/tmp/xtrabackup-restore}"
TARGET_FULL_BACKUP="${TARGET_FULL_BACKUP:-}"
RESET_DATA="${RESET_DATA:-false}"
MYSQL_UID="${MYSQL_UID:-999}"
MYSQL_GID="${MYSQL_GID:-999}"

if [ ! -d "${BACKUP_BASE_DIR}" ]; then
  log "Backup directory not found: ${BACKUP_BASE_DIR}"
  exit 1
fi

if [ -d "${RESTORE_DATA_DIR}/mysql" ] && [ "${RESET_DATA}" != "true" ]; then
  log "Detected existing MySQL data in ${RESTORE_DATA_DIR}, skipping restore."
  log "Set RESET_DATA=true to force re-restore."
  exit 0
fi

if [ "${RESET_DATA}" = "true" ]; then
  log "RESET_DATA=true, cleaning existing data dir: ${RESTORE_DATA_DIR}"
  find "${RESTORE_DATA_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

if [ -n "${TARGET_FULL_BACKUP}" ]; then
  if [ -d "${BACKUP_BASE_DIR}/${TARGET_FULL_BACKUP}_full" ]; then
    LATEST_FULL="${BACKUP_BASE_DIR}/${TARGET_FULL_BACKUP}_full"
  elif [ -d "${TARGET_FULL_BACKUP}" ]; then
    LATEST_FULL="${TARGET_FULL_BACKUP}"
  else
    log "TARGET_FULL_BACKUP not found: ${TARGET_FULL_BACKUP}"
    exit 1
  fi
else
  LATEST_FULL="$(find "${BACKUP_BASE_DIR}" -mindepth 1 -maxdepth 1 -type d -name '*_full' | sort | tail -n 1)"
fi

if [ -z "${LATEST_FULL:-}" ]; then
  log "No full backup found in ${BACKUP_BASE_DIR}"
  exit 1
fi

ALL_FULLS="$(find "${BACKUP_BASE_DIR}" -mindepth 1 -maxdepth 1 -type d -name '*_full' | sort)"
NEXT_FULL="$(printf '%s\n' "${ALL_FULLS}" | awk -v cur="${LATEST_FULL}" '$0 > cur { print; exit }')"

log "Selected full backup: ${LATEST_FULL}"
[ -n "${NEXT_FULL}" ] && log "Next full backup boundary: ${NEXT_FULL}"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}/base"
cp -a "${LATEST_FULL}/." "${WORK_DIR}/base/"
chmod -R u+rwX "${WORK_DIR}/base" || true
[ -f "${WORK_DIR}/base/backup-my.cnf" ] && chmod 600 "${WORK_DIR}/base/backup-my.cnf" || true

log "Preparing base full backup..."
xtrabackup --prepare --apply-log-only --target-dir="${WORK_DIR}/base"

mapfile -t INCREMENTALS < <(
  find "${BACKUP_BASE_DIR}" -mindepth 1 -maxdepth 1 -type d | sort | while read -r dir; do
    if [[ "${dir}" > "${LATEST_FULL}" ]] && { [ -z "${NEXT_FULL}" ] || [[ "${dir}" < "${NEXT_FULL}" ]]; }; then
      if [ -f "${dir}/xtrabackup_checkpoints" ] && grep -q 'backup_type.*incremental' "${dir}/xtrabackup_checkpoints"; then
        printf '%s\n' "${dir}"
      fi
    fi
  done
)

if [ "${#INCREMENTALS[@]}" -eq 0 ]; then
  log "No incremental backups found in this cycle."
else
  mkdir -p "${WORK_DIR}/incrementals"
  for inc in "${INCREMENTALS[@]}"; do
    inc_name="$(basename "${inc}")"
    inc_local="${WORK_DIR}/incrementals/${inc_name}"
    log "Staging incremental backup to writable workspace: ${inc_name}"
    rm -rf "${inc_local}"
    mkdir -p "${inc_local}"
    cp -a "${inc}/." "${inc_local}/"
    chmod -R u+rwX "${inc_local}" || true
    [ -f "${inc_local}/backup-my.cnf" ] && chmod 600 "${inc_local}/backup-my.cnf" || true

    if [ ! -f "${inc_local}/xtrabackup_checkpoints" ]; then
      log "Invalid incremental backup (missing xtrabackup_checkpoints): ${inc}"
      exit 1
    fi

    log "Applying incremental backup: ${inc}"
    xtrabackup --prepare --apply-log-only \
      --target-dir="${WORK_DIR}/base" \
      --incremental-dir="${inc_local}"
  done
fi

log "Final prepare..."
xtrabackup --prepare --target-dir="${WORK_DIR}/base"

log "Copying prepared data to ${RESTORE_DATA_DIR}..."
find "${RESTORE_DATA_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
xtrabackup --copy-back --target-dir="${WORK_DIR}/base" --datadir="${RESTORE_DATA_DIR}"
chown -R "${MYSQL_UID}:${MYSQL_GID}" "${RESTORE_DATA_DIR}"

log "Restore finished successfully."
