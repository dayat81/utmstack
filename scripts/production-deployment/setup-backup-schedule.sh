#!/bin/bash

# UTMStack Backup Scheduling Setup Script
# Sets up automated backup scheduling using cron and systemd timers
# Usage: ./setup-backup-schedule.sh

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTMSTACK_ROOT="${UTMSTACK_ROOT:-/home/ptsec/utmstack}"
BACKUP_USER="${BACKUP_USER:-root}"
USE_SYSTEMD="${USE_SYSTEMD:-true}"

# Logging
LOG_FILE="/var/log/utmstack/backup-schedule-setup.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if running as root or with sudo
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR: This script must be run as root or with sudo"
        exit 1
    fi
}

# Setup systemd timer-based scheduling
setup_systemd_timers() {
    log "Setting up systemd timers for backup scheduling..."
    
    # Create systemd service files
    cat > /etc/systemd/system/utmstack-backup-full.service <<EOF
[Unit]
Description=UTMStack Full Backup
Wants=utmstack-backup-full.timer

[Service]
Type=oneshot
User=$BACKUP_USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/backup-master.sh full
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/utmstack-backup-incremental.service <<EOF
[Unit]
Description=UTMStack Incremental Backup
Wants=utmstack-backup-incremental.timer

[Service]
Type=oneshot
User=$BACKUP_USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/backup-master.sh incremental
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/utmstack-backup-config.service <<EOF
[Unit]
Description=UTMStack Configuration Backup
Wants=utmstack-backup-config.timer

[Service]
Type=oneshot
User=$BACKUP_USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/backup-master.sh config-only
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Create systemd timer files
    cat > /etc/systemd/system/utmstack-backup-full.timer <<EOF
[Unit]
Description=UTMStack Full Backup Timer
Requires=utmstack-backup-full.service

[Timer]
# Run daily at 2:00 AM
OnCalendar=*-*-* 02:00:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

    cat > /etc/systemd/system/utmstack-backup-incremental.timer <<EOF
[Unit]
Description=UTMStack Incremental Backup Timer
Requires=utmstack-backup-incremental.service

[Timer]
# Run every 6 hours
OnCalendar=*-*-* 00,06,12,18:30:00
Persistent=true
RandomizedDelaySec=600

[Install]
WantedBy=timers.target
EOF

    cat > /etc/systemd/system/utmstack-backup-config.timer <<EOF
[Unit]
Description=UTMStack Configuration Backup Timer
Requires=utmstack-backup-config.service

[Timer]
# Run every 4 hours
OnCalendar=*-*-* 00,04,08,12,16,20:15:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

    # Reload systemd and enable timers
    systemctl daemon-reload
    
    systemctl enable utmstack-backup-full.timer
    systemctl enable utmstack-backup-incremental.timer
    systemctl enable utmstack-backup-config.timer
    
    systemctl start utmstack-backup-full.timer
    systemctl start utmstack-backup-incremental.timer
    systemctl start utmstack-backup-config.timer
    
    log "Systemd timers configured and started"
}

# Setup cron-based scheduling
setup_cron_jobs() {
    log "Setting up cron jobs for backup scheduling..."
    
    # Create cron job file
    cat > /etc/cron.d/utmstack-backup <<EOF
# UTMStack Automated Backup Schedule
# Full backup daily at 2:00 AM
0 2 * * * $BACKUP_USER $SCRIPT_DIR/backup-master.sh full >/dev/null 2>&1

# Incremental backup every 6 hours
30 */6 * * * $BACKUP_USER $SCRIPT_DIR/backup-master.sh incremental >/dev/null 2>&1

# Configuration backup every 4 hours
15 */4 * * * $BACKUP_USER $SCRIPT_DIR/backup-master.sh config-only >/dev/null 2>&1

# Log cleanup weekly on Sunday at 3:00 AM
0 3 * * 0 $BACKUP_USER $SCRIPT_DIR/backup-logs.sh >/dev/null 2>&1
EOF

    # Set proper permissions
    chmod 644 /etc/cron.d/utmstack-backup
    
    # Restart cron service
    systemctl restart cron || systemctl restart crond || true
    
    log "Cron jobs configured"
}

# Create backup monitoring script
create_monitoring_script() {
    log "Creating backup monitoring script..."
    
    cat > "$SCRIPT_DIR/monitor-backups.sh" <<'EOF'
#!/bin/bash

# UTMStack Backup Monitoring Script
# Checks backup status and sends alerts if backups are failing or missing

set -euo pipefail

BACKUP_BASE_PATH="${BACKUP_BASE_PATH:-/var/backups/utmstack}"
LOG_FILE="/var/log/utmstack/backup-monitor.log"
ALERT_THRESHOLD_HOURS="${ALERT_THRESHOLD_HOURS:-26}"  # Alert if no backup in 26 hours
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-}"
NOTIFICATION_WEBHOOK="${NOTIFICATION_WEBHOOK:-}"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Send alert
send_alert() {
    local message="$1"
    local subject="UTMStack Backup Alert - $(hostname)"
    
    log "ALERT: $message"
    
    # Email alert
    if [[ -n "$NOTIFICATION_EMAIL" ]] && command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "$subject" "$NOTIFICATION_EMAIL"
    fi
    
    # Webhook alert
    if [[ -n "$NOTIFICATION_WEBHOOK" ]] && command -v curl >/dev/null 2>&1; then
        local payload='{
            "alert": true,
            "message": "'$message'",
            "timestamp": "'$(date -Iseconds)'",
            "hostname": "'$(hostname)'"
        }'
        curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$NOTIFICATION_WEBHOOK"
    fi
}

# Check backup freshness
check_backup_freshness() {
    local component="$1"
    local backup_dir="$BACKUP_BASE_PATH/$component"
    
    if [[ ! -d "$backup_dir" ]]; then
        send_alert "No backup directory found for $component"
        return 1
    fi
    
    # Find the most recent backup file
    local latest_backup=$(find "$backup_dir" -type f \( -name "*.gz" -o -name "*.sql" -o -name "*.dump" -o -name "*.tar.gz" \) -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [[ -z "$latest_backup" ]]; then
        send_alert "No backup files found for $component"
        return 1
    fi
    
    # Check age of latest backup
    local backup_age_hours=$(( ($(date +%s) - $(stat -c %Y "$latest_backup")) / 3600 ))
    
    if [[ $backup_age_hours -gt $ALERT_THRESHOLD_HOURS ]]; then
        send_alert "Latest $component backup is $backup_age_hours hours old (threshold: $ALERT_THRESHOLD_HOURS hours)"
        return 1
    fi
    
    log "$component backup is current (${backup_age_hours}h old)"
    return 0
}

# Check disk space
check_disk_space() {
    local usage=$(df "$BACKUP_BASE_PATH" | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [[ $usage -gt 90 ]]; then
        send_alert "Backup disk usage is high: ${usage}%"
        return 1
    elif [[ $usage -gt 80 ]]; then
        log "WARNING: Backup disk usage: ${usage}%"
    fi
    
    return 0
}

# Check service health
check_service_health() {
    local failed_services=()
    
    # Check backup timers (if using systemd)
    if command -v systemctl >/dev/null 2>&1; then
        local timers=(
            "utmstack-backup-full.timer"
            "utmstack-backup-incremental.timer"
            "utmstack-backup-config.timer"
        )
        
        for timer in "${timers[@]}"; do
            if ! systemctl is-active "$timer" >/dev/null 2>&1; then
                failed_services+=("$timer")
            fi
        done
    fi
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        send_alert "Backup timers not running: ${failed_services[*]}"
        return 1
    fi
    
    return 0
}

# Main monitoring function
main() {
    log "Starting backup monitoring check"
    
    local issues=0
    
    # Check backup freshness for each component
    check_backup_freshness "postgresql" || ((issues++))
    check_backup_freshness "elasticsearch" || ((issues++))
    check_backup_freshness "config" || ((issues++))
    
    # Check disk space
    check_disk_space || ((issues++))
    
    # Check service health
    check_service_health || ((issues++))
    
    if [[ $issues -eq 0 ]]; then
        log "All backup checks passed"
    else
        log "Found $issues backup issues"
    fi
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF

    chmod +x "$SCRIPT_DIR/monitor-backups.sh"
    
    # Add monitoring to cron (every hour)
    if [[ "$USE_SYSTEMD" == "true" ]]; then
        cat > /etc/systemd/system/utmstack-backup-monitor.service <<EOF
[Unit]
Description=UTMStack Backup Monitor
Wants=utmstack-backup-monitor.timer

[Service]
Type=oneshot
User=$BACKUP_USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/monitor-backups.sh
StandardOutput=journal
StandardError=journal
EOF

        cat > /etc/systemd/system/utmstack-backup-monitor.timer <<EOF
[Unit]
Description=UTMStack Backup Monitor Timer
Requires=utmstack-backup-monitor.service

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

        systemctl daemon-reload
        systemctl enable utmstack-backup-monitor.timer
        systemctl start utmstack-backup-monitor.timer
    else
        echo "0 * * * * $BACKUP_USER $SCRIPT_DIR/monitor-backups.sh >/dev/null 2>&1" >> /etc/cron.d/utmstack-backup
    fi
    
    log "Backup monitoring configured"
}

# Create backup restoration script
create_restoration_script() {
    log "Creating backup restoration script..."
    
    cat > "$SCRIPT_DIR/restore-backup.sh" <<'EOF'
#!/bin/bash

# UTMStack Backup Restoration Script
# Restores UTMStack from backup files
# Usage: ./restore-backup.sh [component] [backup_file]

set -euo pipefail

COMPONENT="${1:-}"
BACKUP_FILE="${2:-}"
BACKUP_BASE_PATH="${BACKUP_BASE_PATH:-/var/backups/utmstack}"

# Logging
LOG_FILE="/var/log/utmstack/backup-restore.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

usage() {
    cat <<EOF
UTMStack Backup Restoration Script

Usage: $0 [component] [backup_file]

Components:
  postgresql     - Restore PostgreSQL database
  elasticsearch  - Restore Elasticsearch indices
  config         - Restore configuration files
  all           - Restore all components from latest backups

Examples:
  $0 postgresql /var/backups/utmstack/postgresql/utmstack_db_20250810_020000.sql.gz
  $0 config /var/backups/utmstack/config/utmstack_config_20250810_020000.tar.gz
  $0 all        # Restore from latest backups

EOF
}

restore_postgresql() {
    local backup_file="$1"
    
    log "Restoring PostgreSQL from: $backup_file"
    
    if [[ ! -f "$backup_file" ]]; then
        log "ERROR: Backup file not found: $backup_file"
        return 1
    fi
    
    # Determine file type and restore accordingly
    if [[ "$backup_file" =~ \.dump$ ]]; then
        # Custom format backup
        pg_restore -h localhost -p 5432 -U postgres -d utmstack --clean --if-exists "$backup_file"
    elif [[ "$backup_file" =~ \.sql\.gz$ ]]; then
        # Compressed SQL backup
        gunzip -c "$backup_file" | psql -h localhost -p 5432 -U postgres -d utmstack
    elif [[ "$backup_file" =~ \.sql$ ]]; then
        # Plain SQL backup
        psql -h localhost -p 5432 -U postgres -d utmstack < "$backup_file"
    else
        log "ERROR: Unknown backup file format: $backup_file"
        return 1
    fi
    
    log "PostgreSQL restoration completed"
}

restore_elasticsearch() {
    local snapshot_name="$1"
    
    log "Restoring Elasticsearch snapshot: $snapshot_name"
    
    # Close indices before restore
    curl -X POST "localhost:9200/utmstack-*/_close"
    
    # Restore snapshot
    curl -X POST "localhost:9200/_snapshot/utmstack_backup_repo/$snapshot_name/_restore" \
        -H "Content-Type: application/json" \
        -d '{"include_global_state": true}'
    
    log "Elasticsearch restoration initiated"
}

restore_config() {
    local backup_file="$1"
    
    log "Restoring configuration from: $backup_file"
    
    if [[ ! -f "$backup_file" ]]; then
        log "ERROR: Backup file not found: $backup_file"
        return 1
    fi
    
    # Extract to temporary directory
    local temp_dir=$(mktemp -d)
    tar -xzf "$backup_file" -C "$temp_dir"
    
    # Find the extracted directory
    local extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "utmstack_config_*" | head -1)
    
    if [[ -z "$extracted_dir" ]]; then
        log "ERROR: Invalid configuration backup format"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Restore files (be careful with this in production!)
    log "WARNING: This will overwrite existing configuration files"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ -d "$extracted_dir/files" ]]; then
            cp -r "$extracted_dir/files"/* / 2>/dev/null || true
            log "Configuration files restored"
        fi
    else
        log "Configuration restoration cancelled"
    fi
    
    rm -rf "$temp_dir"
}

find_latest_backup() {
    local component="$1"
    local backup_dir="$BACKUP_BASE_PATH/$component"
    
    if [[ ! -d "$backup_dir" ]]; then
        log "ERROR: Backup directory not found: $backup_dir"
        return 1
    fi
    
    case "$component" in
        "postgresql")
            find "$backup_dir" -name "*.sql.gz" -o -name "*.dump" | sort | tail -1
            ;;
        "elasticsearch")
            # Return the latest snapshot name
            curl -s "localhost:9200/_snapshot/utmstack_backup_repo/_all" | jq -r '.snapshots[-1].snapshot'
            ;;
        "config")
            find "$backup_dir" -name "*.tar.gz" | sort | tail -1
            ;;
        *)
            log "ERROR: Unknown component: $component"
            return 1
            ;;
    esac
}

main() {
    if [[ -z "$COMPONENT" ]]; then
        usage
        exit 1
    fi
    
    case "$COMPONENT" in
        "postgresql")
            if [[ -z "$BACKUP_FILE" ]]; then
                BACKUP_FILE=$(find_latest_backup "postgresql")
            fi
            restore_postgresql "$BACKUP_FILE"
            ;;
        "elasticsearch")
            if [[ -z "$BACKUP_FILE" ]]; then
                BACKUP_FILE=$(find_latest_backup "elasticsearch")
            fi
            restore_elasticsearch "$BACKUP_FILE"
            ;;
        "config")
            if [[ -z "$BACKUP_FILE" ]]; then
                BACKUP_FILE=$(find_latest_backup "config")
            fi
            restore_config "$BACKUP_FILE"
            ;;
        "all")
            log "Restoring all components from latest backups"
            restore_postgresql "$(find_latest_backup "postgresql")"
            restore_elasticsearch "$(find_latest_backup "elasticsearch")"
            restore_config "$(find_latest_backup "config")"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
    
    log "Restoration process completed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF

    chmod +x "$SCRIPT_DIR/restore-backup.sh"
    log "Backup restoration script created"
}

# Create environment configuration
create_environment_config() {
    log "Creating backup environment configuration..."
    
    cat > "$SCRIPT_DIR/backup.env" <<EOF
# UTMStack Backup Environment Configuration
# Source this file to set up backup environment variables

# Basic configuration
export BACKUP_BASE_PATH="/var/backups/utmstack"
export BACKUP_RETENTION_DAYS="30"
export COMPRESSION_LEVEL="6"

# Remote backup configuration
export REMOTE_BACKUP_ENABLED="false"
export REMOTE_BACKUP_PATH=""

# Database configuration
export POSTGRES_HOST="localhost"
export POSTGRES_PORT="5432"
export POSTGRES_DB="utmstack"
export POSTGRES_USER="postgres"
export POSTGRES_PASSWORD="admin"

# Elasticsearch configuration
export ELASTICSEARCH_HOST="localhost"
export ELASTICSEARCH_PORT="9200"
export ELASTICSEARCH_PROTOCOL="http"

# Notification configuration
export NOTIFICATION_ENABLED="false"
export NOTIFICATION_EMAIL=""
export NOTIFICATION_WEBHOOK=""

# Monitoring configuration
export ALERT_THRESHOLD_HOURS="26"

# Log configuration
export LOG_RETENTION_DAYS="30"
export ARCHIVE_RETENTION_DAYS="365"
export MIN_LOG_SIZE_BYTES="1048576"
export MAX_LOG_SIZE_BYTES="104857600"
EOF

    log "Environment configuration created: backup.env"
}

# Main setup function
main() {
    log "Setting up UTMStack backup scheduling..."
    
    check_privileges
    
    # Make all scripts executable
    chmod +x "$SCRIPT_DIR"/*.sh
    
    # Create environment configuration
    create_environment_config
    
    # Setup scheduling based on preference
    if [[ "$USE_SYSTEMD" == "true" ]] && command -v systemctl >/dev/null 2>&1; then
        setup_systemd_timers
    else
        setup_cron_jobs
    fi
    
    # Create additional scripts
    create_monitoring_script
    create_restoration_script
    
    log "Backup scheduling setup completed successfully"
    
    # Display status
    echo
    echo "UTMStack Backup Scheduling Setup Complete"
    echo "========================================"
    echo
    echo "Backup Schedule:"
    echo "- Full backup: Daily at 2:00 AM"
    echo "- Incremental backup: Every 6 hours"
    echo "- Configuration backup: Every 4 hours"
    echo "- Log cleanup: Weekly on Sunday at 3:00 AM"
    echo "- Monitoring: Hourly"
    echo
    echo "Configuration file: $SCRIPT_DIR/backup.env"
    echo "Log files: /var/log/utmstack/backup-*.log"
    echo "Backup location: /var/backups/utmstack/"
    echo
    echo "Management commands:"
    echo "- Manual backup: $SCRIPT_DIR/backup-master.sh [full|incremental|config-only]"
    echo "- Monitor status: $SCRIPT_DIR/monitor-backups.sh"
    echo "- Restore backup: $SCRIPT_DIR/restore-backup.sh [component] [backup_file]"
    echo
    
    if [[ "$USE_SYSTEMD" == "true" ]]; then
        echo "Systemd timer status:"
        systemctl list-timers | grep utmstack-backup || true
    else
        echo "Cron jobs:"
        cat /etc/cron.d/utmstack-backup
    fi
}

# Show usage
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<EOF
UTMStack Backup Scheduling Setup

This script sets up automated backup scheduling for UTMStack using either
systemd timers (preferred) or cron jobs.

Usage: $0

Environment Variables:
  BACKUP_USER      - User to run backups as (default: root)
  USE_SYSTEMD      - Use systemd timers instead of cron (default: true)

The script will create:
- Backup service/cron configuration
- Monitoring and alerting
- Restoration scripts
- Environment configuration

EOF
    exit 0
fi

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
