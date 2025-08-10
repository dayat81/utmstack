#!/bin/bash

# UTMStack Configuration Backup Script
# Backs up all configuration files, certificates, and important system settings
# Usage: ./backup-config.sh [backup_path]

set -euo pipefail

# Configuration
UTMSTACK_ROOT="${UTMSTACK_ROOT:-/home/ptsec/utmstack}"
BACKUP_BASE_PATH="${1:-/var/backups/utmstack/config}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-90}"
REMOTE_BACKUP_ENABLED="${REMOTE_BACKUP_ENABLED:-false}"
REMOTE_PATH="${REMOTE_BACKUP_PATH:-}"

# Logging
LOG_FILE="/var/log/utmstack/backup-config.log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="utmstack_config_${TIMESTAMP}.tar.gz"

# Ensure directories exist
mkdir -p "$BACKUP_BASE_PATH"
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Configuration files to backup
get_config_files() {
    local config_files=(
        # Main configuration
        "$UTMSTACK_ROOT/config/utmstack.yml"
        "$UTMSTACK_ROOT/docker-compose.production.yml"
        "$UTMSTACK_ROOT/version.yml"
        
        # Backend configuration
        "$UTMSTACK_ROOT/backend/src/main/resources/config/application.yml"
        "$UTMSTACK_ROOT/backend/src/main/resources/config/application-prod.yml"
        "$UTMSTACK_ROOT/backend/src/main/resources/config/application-dev.yml"
        
        # Frontend configuration
        "$UTMSTACK_ROOT/frontend/src/environments/environment.prod.ts"
        "$UTMSTACK_ROOT/frontend/src/environments/environment.ts"
        "$UTMSTACK_ROOT/frontend/angular.json"
        "$UTMSTACK_ROOT/frontend/package.json"
        
        # Correlation engine configuration
        "$UTMSTACK_ROOT/correlation/config.yml"
        "$UTMSTACK_ROOT/correlation/config.yml.prod"
        
        # Agent manager configuration
        "$UTMSTACK_ROOT/agent-manager/config.yml"
        
        # Service configurations
        "$UTMSTACK_ROOT/user-auditor/src/main/resources/application.properties"
        "$UTMSTACK_ROOT/soc-ai/config.yml"
        
        # Cloud connector configurations
        "$UTMSTACK_ROOT/aws/config.yml"
        "$UTMSTACK_ROOT/office365/config.yml"
        "$UTMSTACK_ROOT/sophos/config.yml"
        "$UTMSTACK_ROOT/bitdefender/config.yml"
        
        # Scripts and deployment files
        "$UTMSTACK_ROOT/scripts/production-deployment/"
        "$UTMSTACK_ROOT/installer/"
        "$UTMSTACK_ROOT/config/"
        
        # Important root files
        "$UTMSTACK_ROOT/start-utmstack.sh"
        "$UTMSTACK_ROOT/stop-utmstack.sh"
        "$UTMSTACK_ROOT/status-utmstack.sh"
        "$UTMSTACK_ROOT/utmstack-manager.sh"
        "$UTMSTACK_ROOT/AGENT.md"
        
        # SSL/TLS certificates
        "/etc/ssl/certs/utmstack*"
        "/etc/ssl/private/utmstack*"
        
        # System service files
        "/etc/systemd/system/utmstack*"
        
        # Nginx/Apache configuration (if exists)
        "/etc/nginx/sites-available/utmstack*"
        "/etc/apache2/sites-available/utmstack*"
        
        # Log configuration
        "/etc/logrotate.d/utmstack*"
        
        # Cron jobs
        "/etc/cron.d/utmstack*"
        "/var/spool/cron/crontabs/utmstack*"
    )
    
    printf '%s\n' "${config_files[@]}"
}

# System information to backup
backup_system_info() {
    local info_dir="$1/system_info"
    mkdir -p "$info_dir"
    
    log "Collecting system information..."
    
    # Operating system info
    cat /etc/os-release > "$info_dir/os-release" 2>/dev/null || true
    uname -a > "$info_dir/uname" 2>/dev/null || true
    
    # Network configuration
    ip addr show > "$info_dir/ip-addr" 2>/dev/null || true
    cat /etc/hosts > "$info_dir/hosts" 2>/dev/null || true
    cat /etc/resolv.conf > "$info_dir/resolv.conf" 2>/dev/null || true
    
    # System services
    systemctl list-units --type=service --state=running > "$info_dir/running-services" 2>/dev/null || true
    systemctl list-units --type=service --state=enabled > "$info_dir/enabled-services" 2>/dev/null || true
    
    # Installed packages
    if command -v dpkg >/dev/null 2>&1; then
        dpkg -l > "$info_dir/installed-packages" 2>/dev/null || true
    elif command -v rpm >/dev/null 2>&1; then
        rpm -qa > "$info_dir/installed-packages" 2>/dev/null || true
    fi
    
    # Docker info (if available)
    if command -v docker >/dev/null 2>&1; then
        docker version > "$info_dir/docker-version" 2>/dev/null || true
        docker images > "$info_dir/docker-images" 2>/dev/null || true
        docker ps -a > "$info_dir/docker-containers" 2>/dev/null || true
    fi
    
    # Java info (if available)
    if command -v java >/dev/null 2>&1; then
        java -version > "$info_dir/java-version" 2>&1 || true
    fi
    
    # Node.js info (if available)
    if command -v node >/dev/null 2>&1; then
        node --version > "$info_dir/node-version" 2>/dev/null || true
        npm --version > "$info_dir/npm-version" 2>/dev/null || true
    fi
    
    # Go info (if available)
    if command -v go >/dev/null 2>&1; then
        go version > "$info_dir/go-version" 2>/dev/null || true
    fi
    
    # Python info (if available)
    if command -v python3 >/dev/null 2>&1; then
        python3 --version > "$info_dir/python-version" 2>/dev/null || true
        pip3 list > "$info_dir/pip-packages" 2>/dev/null || true
    fi
    
    # Disk usage
    df -h > "$info_dir/disk-usage" 2>/dev/null || true
    
    # Memory usage
    free -h > "$info_dir/memory-usage" 2>/dev/null || true
    
    # UTMStack specific info
    if [[ -f "$UTMSTACK_ROOT/version.yml" ]]; then
        cp "$UTMSTACK_ROOT/version.yml" "$info_dir/" 2>/dev/null || true
    fi
    
    # Git information (if in git repository)
    if [[ -d "$UTMSTACK_ROOT/.git" ]]; then
        cd "$UTMSTACK_ROOT"
        git log --oneline -10 > "$info_dir/git-log" 2>/dev/null || true
        git status > "$info_dir/git-status" 2>/dev/null || true
        git branch -a > "$info_dir/git-branches" 2>/dev/null || true
        git remote -v > "$info_dir/git-remotes" 2>/dev/null || true
    fi
}

# Database schema backup
backup_database_schema() {
    local schema_dir="$1/database_schema"
    mkdir -p "$schema_dir"
    
    log "Backing up database schema..."
    
    # PostgreSQL connection details from config
    local db_host="${POSTGRES_HOST:-localhost}"
    local db_port="${POSTGRES_PORT:-5432}"
    local db_name="${POSTGRES_DB:-utmstack}"
    local db_user="${POSTGRES_USER:-postgres}"
    local db_password="${POSTGRES_PASSWORD:-admin}"
    
    export PGPASSWORD="$db_password"
    
    # Check if PostgreSQL is available
    if pg_isready -h "$db_host" -p "$db_port" -U "$db_user" >/dev/null 2>&1; then
        # Export schema only (no data)
        pg_dump -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_name" \
            --schema-only \
            --no-password \
            --file="$schema_dir/utmstack_schema.sql" \
            2>/dev/null || log "WARNING: Could not backup database schema"
        
        # Export table list
        psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_name" \
            -c "\dt" > "$schema_dir/table_list.txt" 2>/dev/null || true
        
        # Export user permissions
        psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_name" \
            -c "\dp" > "$schema_dir/permissions.txt" 2>/dev/null || true
    else
        log "WARNING: PostgreSQL not available, skipping schema backup"
    fi
}

# Elasticsearch mappings backup
backup_elasticsearch_mappings() {
    local es_dir="$1/elasticsearch_mappings"
    mkdir -p "$es_dir"
    
    log "Backing up Elasticsearch mappings..."
    
    local es_host="${ELASTICSEARCH_HOST:-localhost}"
    local es_port="${ELASTICSEARCH_PORT:-9200}"
    local es_url="http://${es_host}:${es_port}"
    
    # Check if Elasticsearch is available
    if curl -s "$es_url/_cluster/health" >/dev/null 2>&1; then
        # Export cluster settings
        curl -s "$es_url/_cluster/settings" > "$es_dir/cluster_settings.json" 2>/dev/null || true
        
        # Export index templates
        curl -s "$es_url/_template" > "$es_dir/index_templates.json" 2>/dev/null || true
        
        # Export index mappings
        curl -s "$es_url/utmstack-*/_mapping" > "$es_dir/index_mappings.json" 2>/dev/null || true
        
        # Export index list
        curl -s "$es_url/_cat/indices?format=json" > "$es_dir/indices_list.json" 2>/dev/null || true
    else
        log "WARNING: Elasticsearch not available, skipping mappings backup"
    fi
}

# Create configuration backup
create_backup() {
    log "Starting configuration backup..."
    
    local temp_dir=$(mktemp -d)
    local backup_dir="$temp_dir/utmstack_config_$TIMESTAMP"
    mkdir -p "$backup_dir"
    
    # Backup system information
    backup_system_info "$backup_dir"
    
    # Backup database schema
    backup_database_schema "$backup_dir"
    
    # Backup Elasticsearch mappings
    backup_elasticsearch_mappings "$backup_dir"
    
    # Copy configuration files
    log "Copying configuration files..."
    local files_copied=0
    local files_total=0
    
    while IFS= read -r file_pattern; do
        ((files_total++))
        if [[ -e "$file_pattern" ]]; then
            local relative_path="${file_pattern#/}"
            local target_dir="$backup_dir/files/$(dirname "$relative_path")"
            mkdir -p "$target_dir"
            
            if [[ -d "$file_pattern" ]]; then
                cp -r "$file_pattern" "$target_dir/" 2>/dev/null && ((files_copied++)) || true
            else
                cp "$file_pattern" "$target_dir/" 2>/dev/null && ((files_copied++)) || true
            fi
        fi
    done < <(get_config_files)
    
    log "Copied $files_copied of $files_total configuration items"
    
    # Create manifest file
    cat > "$backup_dir/manifest.txt" <<EOF
UTMStack Configuration Backup Manifest
=====================================
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)
UTMStack Root: $UTMSTACK_ROOT
Files Copied: $files_copied/$files_total
Backup Size: $(du -sh "$backup_dir" | cut -f1)

Contents:
- system_info/: System configuration and information
- database_schema/: PostgreSQL schema and metadata
- elasticsearch_mappings/: Elasticsearch cluster configuration
- files/: UTMStack configuration files and scripts
EOF
    
    # Create compressed archive
    log "Creating compressed archive..."
    tar -czf "$BACKUP_BASE_PATH/$BACKUP_FILE" -C "$temp_dir" "utmstack_config_$TIMESTAMP"
    
    # Cleanup temp directory
    rm -rf "$temp_dir"
    
    local final_size=$(du -h "$BACKUP_BASE_PATH/$BACKUP_FILE" | cut -f1)
    log "Configuration backup created: $BACKUP_FILE ($final_size)"
}

# Validate backup
validate_backup() {
    log "Validating backup integrity..."
    
    if ! tar -tzf "$BACKUP_BASE_PATH/$BACKUP_FILE" >/dev/null 2>&1; then
        log "ERROR: Backup archive is corrupted"
        exit 1
    fi
    
    # Check if manifest exists in archive
    if ! tar -tzf "$BACKUP_BASE_PATH/$BACKUP_FILE" | grep -q "manifest.txt"; then
        log "ERROR: Backup manifest missing"
        exit 1
    fi
    
    log "Backup validation successful"
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
    
    log "Uploading backup to remote storage..."
    
    case "$REMOTE_PATH" in
        s3://*)
            aws s3 cp "$BACKUP_BASE_PATH/$BACKUP_FILE" "$REMOTE_PATH/" --storage-class STANDARD_IA
            ;;
        rsync://*)
            rsync -avz "$BACKUP_BASE_PATH/$BACKUP_FILE" "${REMOTE_PATH}/"
            ;;
        scp://*)
            REMOTE_DEST="${REMOTE_PATH#scp://}"
            scp "$BACKUP_BASE_PATH/$BACKUP_FILE" "$REMOTE_DEST/"
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
    
    find "$BACKUP_BASE_PATH" -name "utmstack_config_*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS -delete
    
    local remaining_backups=$(find "$BACKUP_BASE_PATH" -name "utmstack_config_*.tar.gz" | wc -l)
    log "Configuration backups retained: $remaining_backups"
}

# Generate backup report
generate_report() {
    local backup_duration=$((SECONDS))
    
    cat > "${BACKUP_BASE_PATH}/backup_report_${TIMESTAMP}.txt" <<EOF
UTMStack Configuration Backup Report
===================================
Date: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)
UTMStack Root: $UTMSTACK_ROOT
Duration: ${backup_duration}s

Backup File: $BACKUP_FILE
Size: $(du -h "$BACKUP_BASE_PATH/$BACKUP_FILE" | cut -f1)

Remote Backup: $([ "$REMOTE_BACKUP_ENABLED" = "true" ] && echo "Enabled" || echo "Disabled")
Retention: $BACKUP_RETENTION_DAYS days
Status: SUCCESS
EOF

    log "Backup report generated: backup_report_${TIMESTAMP}.txt"
}

# Main execution
main() {
    log "Starting UTMStack configuration backup process"
    
    create_backup
    validate_backup
    upload_remote
    cleanup_old_backups
    generate_report
    
    log "Configuration backup process completed successfully"
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
