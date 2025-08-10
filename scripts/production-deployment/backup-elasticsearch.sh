#!/bin/bash

# UTMStack Elasticsearch Backup Script
# Production-ready backup solution with snapshots, compression, and remote storage
# Usage: ./backup-elasticsearch.sh [indices] [backup_path]

set -euo pipefail

# Configuration from UTMStack config
ES_HOST="${ELASTICSEARCH_HOST:-localhost}"
ES_PORT="${ELASTICSEARCH_PORT:-9200}"
ES_PROTOCOL="${ELASTICSEARCH_PROTOCOL:-http}"
ES_URL="${ES_PROTOCOL}://${ES_HOST}:${ES_PORT}"
ES_USER="${ELASTICSEARCH_USER:-}"
ES_PASSWORD="${ELASTICSEARCH_PASSWORD:-}"

# Backup configuration
BACKUP_BASE_PATH="${1:-/var/backups/utmstack/elasticsearch}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
INDICES="${2:-utmstack-*}"
SNAPSHOT_REPOSITORY="utmstack_backup_repo"
REMOTE_BACKUP_ENABLED="${REMOTE_BACKUP_ENABLED:-false}"
REMOTE_PATH="${REMOTE_BACKUP_PATH:-}"

# Logging
LOG_FILE="/var/log/utmstack/backup-elasticsearch.log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
SNAPSHOT_NAME="utmstack_snapshot_${TIMESTAMP}"

# Ensure directories exist
mkdir -p "$BACKUP_BASE_PATH"
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Elasticsearch API helper
es_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local auth_header=""
    if [[ -n "$ES_USER" && -n "$ES_PASSWORD" ]]; then
        auth_header="-u ${ES_USER}:${ES_PASSWORD}"
    fi
    
    if [[ -n "$data" ]]; then
        curl -s -X "$method" $auth_header -H "Content-Type: application/json" \
            "${ES_URL}${endpoint}" -d "$data"
    else
        curl -s -X "$method" $auth_header "${ES_URL}${endpoint}"
    fi
}

# Health check
check_elasticsearch_connection() {
    log "Checking Elasticsearch connection..."
    
    if ! es_api "GET" "/_cluster/health" >/dev/null 2>&1; then
        log "ERROR: Cannot connect to Elasticsearch at $ES_URL"
        exit 1
    fi
    
    local cluster_health=$(es_api "GET" "/_cluster/health" | jq -r '.status // "unknown"')
    log "Cluster health: $cluster_health"
    
    if [[ "$cluster_health" == "red" ]]; then
        log "WARNING: Cluster health is RED - backup may be incomplete"
    fi
}

# Setup snapshot repository
setup_snapshot_repository() {
    log "Setting up snapshot repository: $SNAPSHOT_REPOSITORY"
    
    local repo_settings='{
        "type": "fs",
        "settings": {
            "location": "'$BACKUP_BASE_PATH'/snapshots",
            "compress": true,
            "chunk_size": "1gb",
            "max_restore_bytes_per_sec": "40mb",
            "max_snapshot_bytes_per_sec": "40mb"
        }
    }'
    
    # Create backup directory for snapshots
    mkdir -p "$BACKUP_BASE_PATH/snapshots"
    
    # Register repository
    local response=$(es_api "PUT" "/_snapshot/$SNAPSHOT_REPOSITORY" "$repo_settings")
    
    if echo "$response" | jq -e '.acknowledged == true' >/dev/null 2>&1; then
        log "Snapshot repository configured successfully"
    else
        log "ERROR: Failed to configure snapshot repository: $response"
        exit 1
    fi
}

# Get index information
get_index_info() {
    log "Getting index information for pattern: $INDICES"
    
    local indices_info=$(es_api "GET" "/${INDICES}/_stats/store,docs")
    local total_size=$(echo "$indices_info" | jq -r '.indices | to_entries | map(.value.total.store.size_in_bytes // 0) | add')
    local total_docs=$(echo "$indices_info" | jq -r '.indices | to_entries | map(.value.total.docs.count // 0) | add')
    
    # Convert bytes to human readable
    local size_human=$(numfmt --to=iec --suffix=B "$total_size" 2>/dev/null || echo "${total_size}B")
    
    log "Total indices size: $size_human"
    log "Total document count: $total_docs"
    
    # List matching indices
    local matching_indices=$(es_api "GET" "/_cat/indices/${INDICES}?format=json" | jq -r '.[].index' | tr '\n' ' ')
    log "Matching indices: $matching_indices"
}

# Create snapshot
create_snapshot() {
    log "Creating snapshot: $SNAPSHOT_NAME"
    
    local snapshot_settings='{
        "indices": "'$INDICES'",
        "ignore_unavailable": true,
        "include_global_state": true,
        "metadata": {
            "taken_by": "utmstack-backup",
            "taken_because": "scheduled_backup",
            "timestamp": "'$TIMESTAMP'"
        }
    }'
    
    # Initiate snapshot
    local response=$(es_api "PUT" "/_snapshot/$SNAPSHOT_REPOSITORY/$SNAPSHOT_NAME?wait_for_completion=false" "$snapshot_settings")
    
    if echo "$response" | jq -e '.accepted == true' >/dev/null 2>&1; then
        log "Snapshot creation initiated"
    else
        log "ERROR: Failed to initiate snapshot: $response"
        exit 1
    fi
    
    # Wait for completion with progress monitoring
    wait_for_snapshot_completion
}

# Wait for snapshot completion
wait_for_snapshot_completion() {
    log "Waiting for snapshot completion..."
    
    local max_wait=3600  # 1 hour max wait
    local wait_interval=30
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        local status=$(es_api "GET" "/_snapshot/$SNAPSHOT_REPOSITORY/$SNAPSHOT_NAME" | jq -r '.snapshots[0].state // "unknown"')
        
        case "$status" in
            "SUCCESS")
                log "Snapshot completed successfully"
                get_snapshot_details
                return 0
                ;;
            "IN_PROGRESS")
                local progress=$(es_api "GET" "/_snapshot/$SNAPSHOT_REPOSITORY/$SNAPSHOT_NAME" | jq -r '.snapshots[0] | "\(.stats.incremental.file_count // 0) files, \(.stats.incremental.size_in_bytes // 0 | . / 1024 / 1024 | floor)MB"')
                log "Snapshot in progress: $progress"
                ;;
            "FAILED"|"PARTIAL")
                log "ERROR: Snapshot failed with status: $status"
                get_snapshot_details
                exit 1
                ;;
            *)
                log "Unknown snapshot status: $status"
                ;;
        esac
        
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    log "ERROR: Snapshot did not complete within ${max_wait}s"
    exit 1
}

# Get snapshot details
get_snapshot_details() {
    local snapshot_info=$(es_api "GET" "/_snapshot/$SNAPSHOT_REPOSITORY/$SNAPSHOT_NAME")
    local snapshot_details=$(echo "$snapshot_info" | jq -r '.snapshots[0]')
    
    local state=$(echo "$snapshot_details" | jq -r '.state')
    local start_time=$(echo "$snapshot_details" | jq -r '.start_time')
    local end_time=$(echo "$snapshot_details" | jq -r '.end_time')
    local duration=$(echo "$snapshot_details" | jq -r '.duration_in_millis // 0 | . / 1000')
    local indices_count=$(echo "$snapshot_details" | jq -r '.indices | length')
    local total_shards=$(echo "$snapshot_details" | jq -r '.shards.total // 0')
    local failed_shards=$(echo "$snapshot_details" | jq -r '.shards.failed // 0')
    
    log "Snapshot details:"
    log "  State: $state"
    log "  Duration: ${duration}s"
    log "  Indices: $indices_count"
    log "  Total shards: $total_shards"
    log "  Failed shards: $failed_shards"
    
    if [[ "$failed_shards" -gt 0 ]]; then
        log "WARNING: $failed_shards shards failed during backup"
    fi
}

# Export index mappings and settings
export_metadata() {
    log "Exporting index mappings and settings..."
    
    local metadata_dir="$BACKUP_BASE_PATH/metadata/$TIMESTAMP"
    mkdir -p "$metadata_dir"
    
    # Export cluster settings
    es_api "GET" "/_cluster/settings" > "$metadata_dir/cluster_settings.json"
    
    # Export index templates
    es_api "GET" "/_template" > "$metadata_dir/index_templates.json"
    
    # Export index settings and mappings for each matching index
    local indices=$(es_api "GET" "/_cat/indices/${INDICES}?format=json" | jq -r '.[].index')
    
    while IFS= read -r index; do
        if [[ -n "$index" ]]; then
            es_api "GET" "/${index}/_settings" > "$metadata_dir/${index}_settings.json"
            es_api "GET" "/${index}/_mapping" > "$metadata_dir/${index}_mapping.json"
        fi
    done <<< "$indices"
    
    # Compress metadata
    tar -czf "$metadata_dir.tar.gz" -C "$BACKUP_BASE_PATH/metadata" "$TIMESTAMP"
    rm -rf "$metadata_dir"
    
    log "Metadata exported to: ${TIMESTAMP}.tar.gz"
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
            # Upload snapshot files
            aws s3 sync "$BACKUP_BASE_PATH/snapshots" "$REMOTE_PATH/snapshots/" --storage-class STANDARD_IA
            # Upload metadata
            aws s3 cp "$BACKUP_BASE_PATH/metadata/${TIMESTAMP}.tar.gz" "$REMOTE_PATH/metadata/"
            ;;
        rsync://*)
            rsync -avz "$BACKUP_BASE_PATH/" "${REMOTE_PATH}/"
            ;;
        scp://*)
            REMOTE_DEST="${REMOTE_PATH#scp://}"
            scp -r "$BACKUP_BASE_PATH/" "$REMOTE_DEST/"
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
    
    # Get list of snapshots
    local snapshots=$(es_api "GET" "/_snapshot/$SNAPSHOT_REPOSITORY/_all" | jq -r '.snapshots[].snapshot')
    local cutoff_date=$(date -d "$BACKUP_RETENTION_DAYS days ago" '+%Y%m%d')
    
    while IFS= read -r snapshot; do
        if [[ "$snapshot" =~ ^utmstack_snapshot_([0-9]{8})_ ]]; then
            local snapshot_date="${BASH_REMATCH[1]}"
            if [[ "$snapshot_date" < "$cutoff_date" ]]; then
                log "Deleting old snapshot: $snapshot"
                es_api "DELETE" "/_snapshot/$SNAPSHOT_REPOSITORY/$snapshot"
            fi
        fi
    done <<< "$snapshots"
    
    # Clean local metadata files
    find "$BACKUP_BASE_PATH/metadata" -name "*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null || true
    
    # Count remaining snapshots
    local remaining_snapshots=$(es_api "GET" "/_snapshot/$SNAPSHOT_REPOSITORY/_all" | jq -r '.snapshots | length')
    log "Snapshots retained: $remaining_snapshots"
}

# Generate backup report
generate_report() {
    local backup_duration=$((SECONDS))
    
    cat > "${BACKUP_BASE_PATH}/backup_report_${TIMESTAMP}.txt" <<EOF
UTMStack Elasticsearch Backup Report
===================================
Date: $(date '+%Y-%m-%d %H:%M:%S')
Cluster: $ES_URL
Indices: $INDICES
Duration: ${backup_duration}s

Snapshot Details:
- Name: $SNAPSHOT_NAME
- Repository: $SNAPSHOT_REPOSITORY
- Location: $BACKUP_BASE_PATH/snapshots

Remote Backup: $([ "$REMOTE_BACKUP_ENABLED" = "true" ] && echo "Enabled" || echo "Disabled")
Retention: $BACKUP_RETENTION_DAYS days
Status: SUCCESS
EOF

    log "Backup report generated: backup_report_${TIMESTAMP}.txt"
}

# Main execution
main() {
    log "Starting UTMStack Elasticsearch backup process"
    
    check_elasticsearch_connection
    setup_snapshot_repository
    get_index_info
    create_snapshot
    export_metadata
    upload_remote
    cleanup_old_backups
    generate_report
    
    log "Backup process completed successfully"
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
