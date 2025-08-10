#!/bin/bash

# UTMStack PostgreSQL Backup Script
# Production-ready backup solution with compression, rotation, and remote storage
# Usage: ./backup-postgresql.sh [database_name] [backup_path]

set -euo pipefail

# Configuration from UTMStack config
DB_HOST="${POSTGRES_HOST:-localhost}"
DB_PORT="${POSTGRES_PORT:-5432}"
DB_NAME="${POSTGRES_DB:-utmstack}"
DB_USER="${POSTGRES_USER:-postgres}"
DB_PASSWORD="${POSTGRES_PASSWORD:-admin}"

# Backup configuration
BACKUP_BASE_PATH="${1:-/var/backups/utmstack/postgresql}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-6}"
REMOTE_BACKUP_ENABLED="${REMOTE_BACKUP_ENABLED:-false}"
REMOTE_PATH="${REMOTE_BACKUP_PATH:-}"

# Logging
LOG_FILE="/var/log/utmstack/backup-postgresql.log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="utmstack_db_${TIMESTAMP}.sql"
COMPRESSED_FILE="${BACKUP_FILE}.gz"

# Ensure directories exist
mkdir -p "$BACKUP_BASE_PATH"
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
cleanup() {
    if [[ -f "${BACKUP_BASE_PATH}/${BACKUP_FILE}" ]]; then
        rm -f "${BACKUP_BASE_PATH}/${BACKUP_FILE}"
    fi
}
trap cleanup ERR

# Health check
check_database_connection() {
    log "Checking database connection..."
    export PGPASSWORD="$DB_PASSWORD"
    
    if ! pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" >/dev/null 2>&1; then
        log "ERROR: Cannot connect to PostgreSQL server"
        exit 1
    fi
    
    if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c '\q' >/dev/null 2>&1; then
        log "ERROR: Cannot connect to database $DB_NAME"
        exit 1
    fi
    
    log "Database connection successful"
}

# Create backup
create_backup() {
    log "Starting PostgreSQL backup for database: $DB_NAME"
    
    export PGPASSWORD="$DB_PASSWORD"
    
    # Get database size
    DB_SIZE=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT pg_size_pretty(pg_database_size('$DB_NAME'));" | xargs)
    log "Database size: $DB_SIZE"
    
    # Create backup with custom format for better compression and parallel restore
    pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        --format=custom \
        --no-password \
        --verbose \
        --compress=9 \
        --file="${BACKUP_BASE_PATH}/${BACKUP_FILE%.sql}.dump" \
        2>>"$LOG_FILE"
    
    # Also create plain SQL backup for human readability
    pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        --no-password \
        --verbose \
        --file="${BACKUP_BASE_PATH}/${BACKUP_FILE}" \
        2>>"$LOG_FILE"
    
    log "Database dump completed"
}

# Compress backup
compress_backup() {
    log "Compressing backup with level $COMPRESSION_LEVEL..."
    
    gzip -"$COMPRESSION_LEVEL" "${BACKUP_BASE_PATH}/${BACKUP_FILE}"
    
    # Get compressed file size
    COMPRESSED_SIZE=$(du -h "${BACKUP_BASE_PATH}/${COMPRESSED_FILE}" | cut -f1)
    log "Backup compressed to: $COMPRESSED_SIZE"
}

# Validate backup integrity
validate_backup() {
    log "Validating backup integrity..."
    
    # Test gzip file integrity
    if ! gzip -t "${BACKUP_BASE_PATH}/${COMPRESSED_FILE}"; then
        log "ERROR: Backup file is corrupted"
        exit 1
    fi
    
    # Test custom format backup integrity
    if ! pg_restore --list "${BACKUP_BASE_PATH}/${BACKUP_FILE%.sql}.dump" >/dev/null 2>&1; then
        log "ERROR: Custom format backup is corrupted"
        exit 1
    fi
    
    log "Backup validation successful"
}

# Upload to remote storage (if configured)
upload_remote() {
    if [[ "$REMOTE_BACKUP_ENABLED" != "true" ]]; then
        return 0
    fi
    
    if [[ -z "$REMOTE_PATH" ]]; then
        log "WARNING: Remote backup enabled but no remote path configured"
        return 1
    fi
    
    log "Uploading backup to remote storage..."
    
    # Support different remote storage types
    case "$REMOTE_PATH" in
        s3://*)
            aws s3 cp "${BACKUP_BASE_PATH}/${COMPRESSED_FILE}" "$REMOTE_PATH/" --storage-class STANDARD_IA
            aws s3 cp "${BACKUP_BASE_PATH}/${BACKUP_FILE%.sql}.dump" "$REMOTE_PATH/"
            ;;
        rsync://*)
            rsync -avz "${BACKUP_BASE_PATH}/${COMPRESSED_FILE}" "${REMOTE_PATH}/"
            rsync -avz "${BACKUP_BASE_PATH}/${BACKUP_FILE%.sql}.dump" "${REMOTE_PATH}/"
            ;;
        scp://*)
            REMOTE_DEST="${REMOTE_PATH#scp://}"
            scp "${BACKUP_BASE_PATH}/${COMPRESSED_FILE}" "$REMOTE_DEST/"
            scp "${BACKUP_BASE_PATH}/${BACKUP_FILE%.sql}.dump" "$REMOTE_DEST/"
            ;;
        *)
            log "ERROR: Unsupported remote storage type: $REMOTE_PATH"
            return 1
            ;;
    esac
    
    log "Remote upload completed"
}

# Clean old backups
cleanup_old_backups() {
    log "Cleaning up backups older than $BACKUP_RETENTION_DAYS days..."
    
    # Remove local backups older than retention period
    find "$BACKUP_BASE_PATH" -name "utmstack_db_*.sql.gz" -mtime +$BACKUP_RETENTION_DAYS -delete
    find "$BACKUP_BASE_PATH" -name "utmstack_db_*.dump" -mtime +$BACKUP_RETENTION_DAYS -delete
    
    # Count remaining backups
    LOCAL_BACKUP_COUNT=$(find "$BACKUP_BASE_PATH" -name "utmstack_db_*.sql.gz" | wc -l)
    log "Local backups retained: $LOCAL_BACKUP_COUNT"
    
    if [[ "$REMOTE_BACKUP_ENABLED" == "true" && "$REMOTE_PATH" =~ ^s3:// ]]; then
        # Clean old S3 backups
        aws s3 ls "$REMOTE_PATH/" --recursive | awk '$1 < "'$(date -d "$BACKUP_RETENTION_DAYS days ago" '+%Y-%m-%d')'" {print $4}' | while read -r file; do
            if [[ "$file" =~ utmstack_db_.*\.(sql\.gz|dump)$ ]]; then
                aws s3 rm "s3://${REMOTE_PATH#s3://}/$file"
                log "Removed remote backup: $file"
            fi
        done
    fi
}

# Generate backup report
generate_report() {
    local backup_duration=$((SECONDS))
    
    cat > "${BACKUP_BASE_PATH}/backup_report_${TIMESTAMP}.txt" <<EOF
UTMStack PostgreSQL Backup Report
================================
Date: $(date '+%Y-%m-%d %H:%M:%S')
Database: $DB_NAME
Host: $DB_HOST:$DB_PORT
Duration: ${backup_duration}s

Files Created:
- ${COMPRESSED_FILE} ($(du -h "${BACKUP_BASE_PATH}/${COMPRESSED_FILE}" | cut -f1))
- ${BACKUP_FILE%.sql}.dump ($(du -h "${BACKUP_BASE_PATH}/${BACKUP_FILE%.sql}.dump" | cut -f1))

Remote Backup: $([ "$REMOTE_BACKUP_ENABLED" = "true" ] && echo "Enabled" || echo "Disabled")
Retention: $BACKUP_RETENTION_DAYS days
Status: SUCCESS
EOF

    log "Backup report generated: backup_report_${TIMESTAMP}.txt"
}

# Main execution
main() {
    log "Starting UTMStack PostgreSQL backup process"
    
    check_database_connection
    create_backup
    compress_backup
    validate_backup
    upload_remote
    cleanup_old_backups
    generate_report
    
    log "Backup process completed successfully"
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
