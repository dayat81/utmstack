#!/bin/bash

# UTMStack Log Backup and Retention Script
# Manages log archival, compression, and retention policies
# Usage: ./backup-logs.sh [log_paths] [backup_path]

set -euo pipefail

# Configuration
UTMSTACK_ROOT="${UTMSTACK_ROOT:-/home/ptsec/utmstack}"
LOG_PATHS="${1:-/var/log/utmstack,${UTMSTACK_ROOT}/logs,/var/log/postgresql,/var/log/elasticsearch}"
BACKUP_BASE_PATH="${2:-/var/backups/utmstack/logs}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
ARCHIVE_RETENTION_DAYS="${ARCHIVE_RETENTION_DAYS:-365}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-6}"
REMOTE_BACKUP_ENABLED="${REMOTE_BACKUP_ENABLED:-false}"
REMOTE_PATH="${REMOTE_BACKUP_PATH:-}"

# Size thresholds for log rotation
MIN_LOG_SIZE_BYTES="${MIN_LOG_SIZE_BYTES:-1048576}"  # 1MB
MAX_LOG_SIZE_BYTES="${MAX_LOG_SIZE_BYTES:-104857600}"  # 100MB

# Logging
LOG_FILE="/var/log/utmstack/backup-logs.log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
DATE_DIR=$(date '+%Y/%m/%d')

# Ensure directories exist
mkdir -p "$BACKUP_BASE_PATH"
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Convert bytes to human readable
human_readable_size() {
    numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1}B"
}

# Get log file age in days
get_file_age_days() {
    local file="$1"
    local file_time=$(stat -c %Y "$file" 2>/dev/null || echo 0)
    local current_time=$(date +%s)
    echo $(( (current_time - file_time) / 86400 ))
}

# Compress log file
compress_log() {
    local source_file="$1"
    local dest_file="$2"
    
    if [[ ! -f "$source_file" ]]; then
        return 1
    fi
    
    local source_size=$(stat -c %s "$source_file" 2>/dev/null || echo 0)
    
    if [[ $source_size -lt $MIN_LOG_SIZE_BYTES ]]; then
        log "Skipping compression of $source_file (too small: $(human_readable_size $source_size))"
        return 1
    fi
    
    log "Compressing $source_file to $dest_file"
    
    if gzip -c -"$COMPRESSION_LEVEL" "$source_file" > "$dest_file.tmp"; then
        mv "$dest_file.tmp" "$dest_file"
        local compressed_size=$(stat -c %s "$dest_file" 2>/dev/null || echo 0)
        local compression_ratio=$(( (source_size - compressed_size) * 100 / source_size ))
        log "Compressed $(human_readable_size $source_size) to $(human_readable_size $compressed_size) (${compression_ratio}% reduction)"
        return 0
    else
        rm -f "$dest_file.tmp"
        log "ERROR: Failed to compress $source_file"
        return 1
    fi
}

# Process log files in a directory
process_log_directory() {
    local log_dir="$1"
    local backup_subdir="$2"
    
    if [[ ! -d "$log_dir" ]]; then
        log "WARNING: Log directory not found: $log_dir"
        return 0
    fi
    
    log "Processing log directory: $log_dir"
    
    local backup_dest="$BACKUP_BASE_PATH/$backup_subdir/$DATE_DIR"
    mkdir -p "$backup_dest"
    
    local files_processed=0
    local total_original_size=0
    local total_compressed_size=0
    
    # Find log files to archive
    while IFS= read -r -d '' log_file; do
        local file_age=$(get_file_age_days "$log_file")
        local file_size=$(stat -c %s "$log_file" 2>/dev/null || echo 0)
        
        # Skip if file is too new or too small
        if [[ $file_age -lt 1 || $file_size -lt $MIN_LOG_SIZE_BYTES ]]; then
            continue
        fi
        
        # Skip already compressed files
        if [[ "$log_file" =~ \.(gz|bz2|xz)$ ]]; then
            continue
        fi
        
        # Skip currently active log files (being written to)
        if lsof "$log_file" >/dev/null 2>&1; then
            log "Skipping active log file: $log_file"
            continue
        fi
        
        local relative_path="${log_file#$log_dir/}"
        local backup_file="$backup_dest/$relative_path.gz"
        local backup_file_dir=$(dirname "$backup_file")
        
        mkdir -p "$backup_file_dir"
        
        if compress_log "$log_file" "$backup_file"; then
            # Archive successful, remove or truncate original based on file type
            if [[ "$log_file" =~ \.(log|out)$ ]]; then
                # For .log and .out files, truncate instead of delete to preserve file handles
                > "$log_file"
                log "Truncated original log file: $log_file"
            else
                # For other files, move to backup to avoid deletion
                mv "$log_file" "${log_file}.archived_${TIMESTAMP}"
                log "Archived original log file: $log_file"
            fi
            
            ((files_processed++))
            total_original_size=$((total_original_size + file_size))
            local compressed_size=$(stat -c %s "$backup_file" 2>/dev/null || echo 0)
            total_compressed_size=$((total_compressed_size + compressed_size))
        fi
        
    done < <(find "$log_dir" -type f \( -name "*.log" -o -name "*.out" -o -name "*.txt" -o -name "*.err" \) -print0 2>/dev/null || true)
    
    if [[ $files_processed -gt 0 ]]; then
        local compression_ratio=$(( (total_original_size - total_compressed_size) * 100 / total_original_size ))
        log "Processed $files_processed files in $log_dir"
        log "Total compression: $(human_readable_size $total_original_size) -> $(human_readable_size $total_compressed_size) (${compression_ratio}% reduction)"
    else
        log "No files to process in $log_dir"
    fi
}

# Archive system logs
archive_system_logs() {
    log "Archiving system logs..."
    
    # UTMStack application logs
    if [[ -d "${UTMSTACK_ROOT}/logs" ]]; then
        process_log_directory "${UTMSTACK_ROOT}/logs" "application"
    fi
    
    # UTMStack service logs
    if [[ -d "/var/log/utmstack" ]]; then
        process_log_directory "/var/log/utmstack" "service"
    fi
    
    # PostgreSQL logs
    local pg_log_dirs=(
        "/var/log/postgresql"
        "/var/lib/postgresql/*/main/log"
        "/opt/postgresql/*/data/log"
    )
    
    for pg_dir_pattern in "${pg_log_dirs[@]}"; do
        for pg_dir in $pg_dir_pattern; do
            if [[ -d "$pg_dir" ]]; then
                process_log_directory "$pg_dir" "postgresql"
                break
            fi
        done
    done
    
    # Elasticsearch logs
    local es_log_dirs=(
        "/var/log/elasticsearch"
        "/opt/elasticsearch/logs"
        "/usr/share/elasticsearch/logs"
    )
    
    for es_dir in "${es_log_dirs[@]}"; do
        if [[ -d "$es_dir" ]]; then
            process_log_directory "$es_dir" "elasticsearch"
            break
        fi
    done
    
    # Web server logs
    local web_log_dirs=(
        "/var/log/nginx"
        "/var/log/apache2"
        "/var/log/httpd"
    )
    
    for web_dir in "${web_log_dirs[@]}"; do
        if [[ -d "$web_dir" ]]; then
            process_log_directory "$web_dir" "webserver"
        fi
    done
    
    # System logs that might be relevant
    if [[ -d "/var/log" ]]; then
        local system_logs=(
            "/var/log/syslog*"
            "/var/log/auth.log*"
            "/var/log/kern.log*"
            "/var/log/daemon.log*"
            "/var/log/messages*"
        )
        
        for log_pattern in "${system_logs[@]}"; do
            for log_file in $log_pattern; do
                if [[ -f "$log_file" && ! "$log_file" =~ \.gz$ ]]; then
                    local file_age=$(get_file_age_days "$log_file")
                    if [[ $file_age -ge 1 ]]; then
                        local backup_dest="$BACKUP_BASE_PATH/system/$DATE_DIR"
                        mkdir -p "$backup_dest"
                        local backup_file="$backup_dest/$(basename "$log_file").gz"
                        compress_log "$log_file" "$backup_file" || true
                    fi
                fi
            done
        done
    fi
}

# Rotate large active log files
rotate_large_logs() {
    log "Checking for large active log files..."
    
    local log_dirs=(
        "${UTMSTACK_ROOT}/logs"
        "/var/log/utmstack"
        "/var/log/postgresql"
        "/var/log/elasticsearch"
    )
    
    for log_dir in "${log_dirs[@]}"; do
        if [[ ! -d "$log_dir" ]]; then
            continue
        fi
        
        while IFS= read -r -d '' log_file; do
            local file_size=$(stat -c %s "$log_file" 2>/dev/null || echo 0)
            
            if [[ $file_size -gt $MAX_LOG_SIZE_BYTES ]]; then
                log "Rotating large log file: $log_file ($(human_readable_size $file_size))"
                
                # Create backup of current log
                local backup_dest="$BACKUP_BASE_PATH/rotated/$DATE_DIR"
                mkdir -p "$backup_dest"
                local backup_file="$backup_dest/$(basename "$log_file")_${TIMESTAMP}.gz"
                
                if compress_log "$log_file" "$backup_file"; then
                    # Truncate the original file
                    > "$log_file"
                    log "Rotated and truncated: $log_file"
                    
                    # Send SIGHUP to services that might need to reopen log files
                    if [[ "$log_file" =~ postgres ]]; then
                        systemctl reload postgresql >/dev/null 2>&1 || true
                    elif [[ "$log_file" =~ elasticsearch ]]; then
                        systemctl reload elasticsearch >/dev/null 2>&1 || true
                    fi
                fi
            fi
        done < <(find "$log_dir" -type f \( -name "*.log" -o -name "*.out" \) -print0 2>/dev/null || true)
    done
}

# Upload to remote storage
upload_remote() {
    if [[ "$REMOTE_BACKUP_ENABLED" != "true" ]]; then
        return 0
    fi
    
    if [[ -z "$REMOTE_PATH" ]]; then
        log "WARNING: Remote backup enabled but no remote path configured"
        return 1
    fi
    
    log "Uploading log archives to remote storage..."
    
    local today_dir="$BACKUP_BASE_PATH/$DATE_DIR"
    
    if [[ ! -d "$today_dir" ]]; then
        log "No log archives created today, skipping remote upload"
        return 0
    fi
    
    case "$REMOTE_PATH" in
        s3://*)
            aws s3 sync "$today_dir" "$REMOTE_PATH/logs/$DATE_DIR/" --storage-class STANDARD_IA
            ;;
        rsync://*)
            rsync -avz "$today_dir/" "${REMOTE_PATH}/logs/$DATE_DIR/"
            ;;
        scp://*)
            REMOTE_DEST="${REMOTE_PATH#scp://}"
            scp -r "$today_dir" "$REMOTE_DEST/logs/"
            ;;
        *)
            log "ERROR: Unsupported remote storage type: $REMOTE_PATH"
            return 1
            ;;
    esac
    
    log "Remote upload completed"
}

# Clean old archives
cleanup_old_archives() {
    log "Cleaning up old log archives..."
    
    # Remove local archives older than retention period
    find "$BACKUP_BASE_PATH" -name "*.gz" -mtime +$ARCHIVE_RETENTION_DAYS -delete 2>/dev/null || true
    find "$BACKUP_BASE_PATH" -type d -empty -delete 2>/dev/null || true
    
    # Clean archived log files
    find "${UTMSTACK_ROOT}/logs" -name "*.archived_*" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
    
    # Count remaining archives
    local remaining_archives=$(find "$BACKUP_BASE_PATH" -name "*.gz" | wc -l)
    log "Log archives retained: $remaining_archives"
}

# Setup log rotation configuration
setup_logrotate() {
    log "Setting up logrotate configuration..."
    
    local logrotate_config="/etc/logrotate.d/utmstack"
    
    cat > "$logrotate_config" <<EOF
# UTMStack log rotation configuration
${UTMSTACK_ROOT}/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        # Restart services if needed
        systemctl reload utmstack-backend >/dev/null 2>&1 || true
    endscript
}

/var/log/utmstack/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    sharedscripts
    copytruncate
}

/var/log/utmstack/*.out {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF

    log "Logrotate configuration created: $logrotate_config"
}

# Generate backup report
generate_report() {
    local backup_duration=$((SECONDS))
    local total_archives=$(find "$BACKUP_BASE_PATH" -name "*.gz" | wc -l)
    local total_size=$(du -sh "$BACKUP_BASE_PATH" 2>/dev/null | cut -f1 || echo "0B")
    
    cat > "${BACKUP_BASE_PATH}/backup_report_${TIMESTAMP}.txt" <<EOF
UTMStack Log Backup Report
=========================
Date: $(date '+%Y-%m-%d %H:%M:%S')
Duration: ${backup_duration}s

Configuration:
- Log Retention: $LOG_RETENTION_DAYS days
- Archive Retention: $ARCHIVE_RETENTION_DAYS days
- Compression Level: $COMPRESSION_LEVEL
- Min File Size: $(human_readable_size $MIN_LOG_SIZE_BYTES)
- Max File Size: $(human_readable_size $MAX_LOG_SIZE_BYTES)

Results:
- Total Archives: $total_archives
- Total Size: $total_size
- Backup Path: $BACKUP_BASE_PATH

Remote Backup: $([ "$REMOTE_BACKUP_ENABLED" = "true" ] && echo "Enabled" || echo "Disabled")
Status: SUCCESS
EOF

    log "Backup report generated: backup_report_${TIMESTAMP}.txt"
}

# Main execution
main() {
    log "Starting UTMStack log backup and retention process"
    
    setup_logrotate
    archive_system_logs
    rotate_large_logs
    upload_remote
    cleanup_old_archives
    generate_report
    
    log "Log backup and retention process completed successfully"
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
