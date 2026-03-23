#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.restore.yml"

usage() {
  cat <<'EOF'
Usage:
  ./run-restore.sh [--backup-dir <path>] [--full <timestamp>] [--port <port>] [--force]

Examples:
  ./run-restore.sh --backup-dir /path/to/mysql_backups
  ./run-restore.sh --backup-dir /path/to/mysql_backups --full 20250622_190001
  ./run-restore.sh --backup-dir /path/to/mysql_backups --force
EOF
}

BACKUP_DIR="${BACKUP_DIR:-${SCRIPT_DIR}/data/mysql_backups}"
MYSQL_RESTORE_PORT="${MYSQL_RESTORE_PORT:-3307}"
TARGET_FULL_BACKUP="${TARGET_FULL_BACKUP:-}"
RESET_DATA="${RESET_DATA:-false}"

while [ $# -gt 0 ]; do
  case "$1" in
    --backup-dir)
      BACKUP_DIR="$2"
      shift 2
      ;;
    --full)
      TARGET_FULL_BACKUP="$2"
      shift 2
      ;;
    --port)
      MYSQL_RESTORE_PORT="$2"
      shift 2
      ;;
    --force)
      RESET_DATA="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [ ! -d "${BACKUP_DIR}" ]; then
  echo "Backup directory does not exist: ${BACKUP_DIR}"
  exit 1
fi

echo "Using backup dir: ${BACKUP_DIR}"
[ -n "${TARGET_FULL_BACKUP}" ] && echo "Using full backup: ${TARGET_FULL_BACKUP}_full"
echo "MySQL restore port: ${MYSQL_RESTORE_PORT}"
[ "${RESET_DATA}" = "true" ] && echo "Force restore: enabled"

export BACKUP_DIR
export MYSQL_RESTORE_PORT
export TARGET_FULL_BACKUP
export RESET_DATA

docker compose -f "${COMPOSE_FILE}" down >/dev/null 2>&1 || true

docker compose -f "${COMPOSE_FILE}" up \
  --abort-on-container-exit \
  --exit-code-from mysql-restore-init \
  mysql-restore-init

docker compose -f "${COMPOSE_FILE}" up -d mysql-restore

cat <<EOF

Restore container is running.
Connect:
  mysql -h 127.0.0.1 -P ${MYSQL_RESTORE_PORT} -u root -p

Stop:
  docker compose -f ${COMPOSE_FILE} down
EOF
