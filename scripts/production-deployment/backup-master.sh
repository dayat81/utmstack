#!/bin/bash

# UTMStack Master Backup Script
# Orchestrates all backup operations with error handling and notifications
# Usage: ./backup-master.sh [full|incremental|config-only]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTMSTACK_ROOT="${UTMSTACK_ROOT:-/home/ptsec/utmstack}"
BACKUP_TYPE="${1:-full}"
BACKUP_BASE_PATH="${BACKUP_BASE_PATH:-/var/backups/utmstack}"
CONFIG_FILE="${CONFIG_FILE:-$UTMSTACK_ROOT/config/utmstack.yml}"

# Load configuration from utmstack.yml if available
if [[ -f "$CONFIG_FILE" ]]; then
    source <(grep -E '^\s*(BACKUP_|REMOTE_|POSTGRES_|ELASTICSEARCH_)' "$CONFIG_FILE" | sed 's/^\s*/export /' || true)
fi

# Environment variables with defaults
export BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
export REMOTE_BACKUP_ENABLED="${REMOTE_BACKUP_ENABLED:-false}"
export REMOTE_BACKUP_PATH="${REMOTE_BACKUP_PATH:-}"
export NOTIFICATION_ENABLED="${NOTIFICATION_ENABLED:-false}"
export NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-}"
export NOTIFICATION_WEBHOOK="${NOTIFICATION_WEBHOOK:-}"
export POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
export POSTGRES_DB="${POSTGRES_DB:-utmstack}"
export POSTGRES_USER="${POSTGRES_USER:-postgres}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-admin}"
export ELASTICSEARCH_HOST="${ELASTICSEARCH_HOST:-localhost}"
export ELASTICSEARCH_PORT="${ELASTICSEARCH_PORT:-9200}"

# Logging
LOG_FILE="/var/log/utmstack/backup-master.log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Ensure directories exist
mkdir -p "$BACKUP_BASE_PATH"
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR: Backup process failed with exit code $exit_code"
        send_notification "FAILED" "Backup process failed" "$exit_code"
    fi
}
trap cleanup EXIT

# Send notification
send_notification() {
    local status="$1"
    local message="$2"
    local details="${3:-}"
    
    if [[ "$NOTIFICATION_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local subject="UTMStack Backup $status - $(hostname)"
    local body="Backup Status: $status
Message: $message
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)
Backup Type: $BACKUP_TYPE"
    
    if [[ -n "$details" ]]; then
        body="$body
Details: $details"
    fi
    
    # Email notification
    if [[ -n "$NOTIFICATION_EMAIL" ]] && command -v mail >/dev/null 2>&1; then
        echo "$body" | mail -s "$subject" "$NOTIFICATION_EMAIL" || log "WARNING: Failed to send email notification"
    fi
    
    # Webhook notification
    if [[ -n "$NOTIFICATION_WEBHOOK" ]] && command -v curl >/dev/null 2>&1; then
        local webhook_payload='{
            "status": "'$status'",
            "message": "'$message'",
            "timestamp": "'$(date -Iseconds)'",
            "hostname": "'$(hostname)'",
            "backup_type": "'$BACKUP_TYPE'",
            "details": "'$details'"
        }'
        
        curl -s -X POST -H "Content-Type: application/json" \
            -d "$webhook_payload" "$NOTIFICATION_WEBHOOK" || log "WARNING: Failed to send webhook notification"
    fi
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."
    
    local missing_tools=()
    
    # Required tools
    local required_tools=(
        "tar"
        "gzip"
        "find"
        "pg_dump"
        "pg_isready"
        "curl"
        "jq"
    )
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log "ERROR: Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check disk space (require at least 5GB free)
    local available_space=$(df "$BACKUP_BASE_PATH" | awk 'NR==2 {print $4}')
    local required_space=5242880  # 5GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        log "ERROR: Insufficient disk space. Available: $(numfmt --to=iec --from-unit=1024 $available_space)B, Required: 5GB"
        exit 1
    fi
    
    log "System requirements check passed"
}

# Health check services
health_check() {
    log "Performing health check..."
    
    local services_status=()
    
    # Check PostgreSQL
    if pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" >/dev/null 2>&1; then
        services_status+=("PostgreSQL: OK")
    else
        services_status+=("PostgreSQL: FAILED")
        log "WARNING: PostgreSQL health check failed"
    fi
    
    # Check Elasticsearch
    if curl -s "http://$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT/_cluster/health" >/dev/null 2>&1; then
        services_status+=("Elasticsearch: OK")
    else
        services_status+=("Elasticsearch: FAILED")
        log "WARNING: Elasticsearch health check failed"
    fi
    
    # Check disk space on data directories
    local data_dirs=(
        "/var/lib/postgresql"
        "/var/lib/elasticsearch"
        "$UTMSTACK_ROOT"
    )
    
    for data_dir in "${data_dirs[@]}"; do
        if [[ -d "$data_dir" ]]; then
            local usage=$(df "$data_dir" | awk 'NR==2 {print $5}' | sed 's/%//')
            if [[ $usage -gt 90 ]]; then
                services_status+=("$data_dir: HIGH USAGE ($usage%)")
                log "WARNING: High disk usage on $data_dir: $usage%"
            else
                services_status+=("$data_dir: OK ($usage%)")
            fi
        fi
    done
    
    log "Health check results: ${services_status[*]}"
}

# Run PostgreSQL backup
backup_postgresql() {
    log "Starting PostgreSQL backup..."
    
    if [[ ! -x "$SCRIPT_DIR/backup-postgresql.sh" ]]; then
        log "ERROR: PostgreSQL backup script not found or not executable"
        return 1
    fi
    
    if "$SCRIPT_DIR/backup-postgresql.sh" "$BACKUP_BASE_PATH/postgresql"; then
        log "PostgreSQL backup completed successfully"
        return 0
    else
        log "ERROR: PostgreSQL backup failed"
        return 1
    fi
}

# Run Elasticsearch backup
backup_elasticsearch() {
    log "Starting Elasticsearch backup..."
    
    if [[ ! -x "$SCRIPT_DIR/backup-elasticsearch.sh" ]]; then
        log "ERROR: Elasticsearch backup script not found or not executable"
        return 1
    fi
    
    if "$SCRIPT_DIR/backup-elasticsearch.sh" "utmstack-*" "$BACKUP_BASE_PATH/elasticsearch"; then
        log "Elasticsearch backup completed successfully"
        return 0
    else
        log "ERROR: Elasticsearch backup failed"
        return 1
    fi
}

# Run configuration backup
backup_configuration() {
    log "Starting configuration backup..."
    
    if [[ ! -x "$SCRIPT_DIR/backup-config.sh" ]]; then
        log "ERROR: Configuration backup script not found or not executable"
        return 1
    fi
    
    if "$SCRIPT_DIR/backup-config.sh" "$BACKUP_BASE_PATH/config"; then
        log "Configuration backup completed successfully"
        return 0
    else
        log "ERROR: Configuration backup failed"
        return 1
    fi
}

# Run log backup
backup_logs() {
    log "Starting log backup..."
    
    if [[ ! -x "$SCRIPT_DIR/backup-logs.sh" ]]; then
        log "ERROR: Log backup script not found or not executable"
        return 1
    fi
    
    if "$SCRIPT_DIR/backup-logs.sh" "" "$BACKUP_BASE_PATH/logs"; then
        log "Log backup completed successfully"
        return 0
    else
        log "ERROR: Log backup failed"
        return 1
    fi
}

# Create master backup report
create_master_report() {
    local backup_duration=$((SECONDS))
    local total_size=$(du -sh "$BACKUP_BASE_PATH" 2>/dev/null | cut -f1 || echo "0B")
    
    local postgres_size="N/A"
    local elasticsearch_size="N/A"
    local config_size="N/A"
    local logs_size="N/A"
    
    if [[ -d "$BACKUP_BASE_PATH/postgresql" ]]; then
        postgres_size=$(du -sh "$BACKUP_BASE_PATH/postgresql" 2>/dev/null | cut -f1 || echo "0B")
    fi
    
    if [[ -d "$BACKUP_BASE_PATH/elasticsearch" ]]; then
        elasticsearch_size=$(du -sh "$BACKUP_BASE_PATH/elasticsearch" 2>/dev/null | cut -f1 || echo "0B")
    fi
    
    if [[ -d "$BACKUP_BASE_PATH/config" ]]; then
        config_size=$(du -sh "$BACKUP_BASE_PATH/config" 2>/dev/null | cut -f1 || echo "0B")
    fi
    
    if [[ -d "$BACKUP_BASE_PATH/logs" ]]; then
        logs_size=$(du -sh "$BACKUP_BASE_PATH/logs" 2>/dev/null | cut -f1 || echo "0B")
    fi
    
    cat > "${BACKUP_BASE_PATH}/master_backup_report_${TIMESTAMP}.txt" <<EOF
UTMStack Master Backup Report
============================
Date: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)
Backup Type: $BACKUP_TYPE
Duration: ${backup_duration}s
Total Size: $total_size

Component Breakdown:
- PostgreSQL: $postgres_size
- Elasticsearch: $elasticsearch_size
- Configuration: $config_size
- Logs: $logs_size

Configuration:
- Retention Days: $BACKUP_RETENTION_DAYS
- Remote Backup: $([ "$REMOTE_BACKUP_ENABLED" = "true" ] && echo "Enabled" || echo "Disabled")
- Remote Path: $REMOTE_BACKUP_PATH
- Notifications: $([ "$NOTIFICATION_ENABLED" = "true" ] && echo "Enabled" || echo "Disabled")

System Information:
- OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
- Kernel: $(uname -r)
- Architecture: $(uname -m)
- Load Average: $(uptime | grep -o 'load average.*' | cut -d':' -f2)
- Memory Usage: $(free -h | grep Mem: | awk '{print $3"/"$2}')

Status: SUCCESS
EOF

    log "Master backup report generated: master_backup_report_${TIMESTAMP}.txt"
}

# Perform full backup
perform_full_backup() {
    log "Performing full backup..."
    
    local failed_components=()
    
    # Run all backup components
    backup_postgresql || failed_components+=("PostgreSQL")
    backup_elasticsearch || failed_components+=("Elasticsearch")
    backup_configuration || failed_components+=("Configuration")
    backup_logs || failed_components+=("Logs")
    
    if [[ ${#failed_components[@]} -gt 0 ]]; then
        log "WARNING: Some backup components failed: ${failed_components[*]}"
        send_notification "PARTIAL" "Some backup components failed" "${failed_components[*]}"
        return 1
    else
        log "Full backup completed successfully"
        return 0
    fi
}

# Perform incremental backup
perform_incremental_backup() {
    log "Performing incremental backup..."
    
    # For incremental, only backup logs and configuration (data changes frequently)
    local failed_components=()
    
    backup_configuration || failed_components+=("Configuration")
    backup_logs || failed_components+=("Logs")
    
    # Only backup data if it's been more than 1 day since last backup
    local last_postgres_backup=$(find "$BACKUP_BASE_PATH/postgresql" -name "*.sql.gz" -mtime -1 2>/dev/null | wc -l)
    local last_es_backup=$(find "$BACKUP_BASE_PATH/elasticsearch" -name "*snapshot*" -mtime -1 2>/dev/null | wc -l)
    
    if [[ $last_postgres_backup -eq 0 ]]; then
        backup_postgresql || failed_components+=("PostgreSQL")
    fi
    
    if [[ $last_es_backup -eq 0 ]]; then
        backup_elasticsearch || failed_components+=("Elasticsearch")
    fi
    
    if [[ ${#failed_components[@]} -gt 0 ]]; then
        log "WARNING: Some backup components failed: ${failed_components[*]}"
        send_notification "PARTIAL" "Some incremental backup components failed" "${failed_components[*]}"
        return 1
    else
        log "Incremental backup completed successfully"
        return 0
    fi
}

# Perform config-only backup
perform_config_backup() {
    log "Performing configuration-only backup..."
    
    if backup_configuration; then
        log "Configuration backup completed successfully"
        return 0
    else
        log "ERROR: Configuration backup failed"
        return 1
    fi
}

# Main execution
main() {
    log "Starting UTMStack master backup process (type: $BACKUP_TYPE)"
    
    # Pre-flight checks
    check_requirements
    health_check
    
    # Make backup scripts executable
    chmod +x "$SCRIPT_DIR"/*.sh
    
    # Perform backup based on type
    case "$BACKUP_TYPE" in
        "full")
            perform_full_backup
            ;;
        "incremental")
            perform_incremental_backup
            ;;
        "config-only")
            perform_config_backup
            ;;
        *)
            log "ERROR: Unknown backup type: $BACKUP_TYPE"
            log "Valid types: full, incremental, config-only"
            exit 1
            ;;
    esac
    
    # Generate master report
    create_master_report
    
    # Send success notification
    send_notification "SUCCESS" "Backup completed successfully" "Type: $BACKUP_TYPE, Duration: ${SECONDS}s"
    
    log "Master backup process completed successfully"
}

# Show usage information
usage() {
    cat <<EOF
UTMStack Master Backup Script

Usage: $0 [backup_type]

Backup Types:
  full         - Complete backup of all components (default)
  incremental  - Backup only changed data and configurations
  config-only  - Backup only configuration files

Environment Variables:
  BACKUP_RETENTION_DAYS   - How long to keep backups (default: 30)
  REMOTE_BACKUP_ENABLED   - Enable remote backup (default: false)
  REMOTE_BACKUP_PATH      - Remote backup destination
  NOTIFICATION_ENABLED    - Enable notifications (default: false)
  NOTIFICATION_EMAIL      - Email for notifications
  NOTIFICATION_WEBHOOK    - Webhook URL for notifications

Examples:
  $0                      # Full backup
  $0 full                 # Full backup
  $0 incremental         # Incremental backup
  $0 config-only         # Configuration only

EOF
}

# Handle command line arguments
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
