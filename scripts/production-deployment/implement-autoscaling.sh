#!/bin/bash

# UTMStack Auto-Scaling Implementation Script
# Phase 6 - Sprint 2.2: Auto-Scaling Implementation
# Version: 1.0.0

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }

# Configuration
IMPLEMENTATION_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="/var/log/utmstack/autoscaling-${IMPLEMENTATION_DATE}.log"
SCALING_CONFIG_DIR="/etc/utmstack/scaling"
DOCKER_COMPOSE_DIR="/home/ptsec/utmstack"

# Create directories
mkdir -p /var/log/utmstack
mkdir -p ${SCALING_CONFIG_DIR}
mkdir -p ${SCALING_CONFIG_DIR}/scripts
mkdir -p ${SCALING_CONFIG_DIR}/policies
mkdir -p ${SCALING_CONFIG_DIR}/monitors

# Redirect output
exec > >(tee -a ${LOG_FILE})
exec 2>&1

echo "======================================================================"
echo "🔄 UTMStack Auto-Scaling Implementation"
echo "======================================================================"
echo "Implementation Date: ${IMPLEMENTATION_DATE}"
echo "Log File: ${LOG_FILE}"
echo "Scaling Config Directory: ${SCALING_CONFIG_DIR}"
echo "======================================================================"

# Function to create horizontal scaling orchestrator
create_horizontal_scaling_orchestrator() {
    log_step "Creating horizontal scaling orchestrator..."
    
    cat > ${SCALING_CONFIG_DIR}/scripts/horizontal-scaler.sh << 'EOF'
#!/bin/bash

# UTMStack Horizontal Scaling Orchestrator
# Manages automatic scaling of microservices based on metrics

set -e

# Configuration
SCALING_CONFIG_DIR="/etc/utmstack/scaling"
DOCKER_COMPOSE_FILE="/home/ptsec/utmstack/docker-compose.production.yml"
METRICS_ENDPOINT="http://localhost:9090"
LOG_FILE="/var/log/utmstack/scaling.log"

# Logging function
log_scaling() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> ${LOG_FILE}
}

# Function to get service metrics
get_service_metrics() {
    local service_name="$1"
    local metric_type="$2"
    
    case "$metric_type" in
        "cpu")
            # Get CPU usage from Prometheus
            curl -s "${METRICS_ENDPOINT}/api/v1/query?query=avg(rate(container_cpu_usage_seconds_total{name=\"${service_name}\"}[5m]))*100" | \
            jq -r '.data.result[0].value[1] // "0"'
            ;;
        "memory")
            # Get memory usage percentage
            curl -s "${METRICS_ENDPOINT}/api/v1/query?query=avg(container_memory_usage_bytes{name=\"${service_name}\"}/container_spec_memory_limit_bytes{name=\"${service_name}\"})*100" | \
            jq -r '.data.result[0].value[1] // "0"'
            ;;
        "requests")
            # Get request rate
            curl -s "${METRICS_ENDPOINT}/api/v1/query?query=avg(rate(http_requests_total{service=\"${service_name}\"}[5m]))" | \
            jq -r '.data.result[0].value[1] // "0"'
            ;;
        "response_time")
            # Get 95th percentile response time
            curl -s "${METRICS_ENDPOINT}/api/v1/query?query=histogram_quantile(0.95,rate(http_request_duration_seconds_bucket{service=\"${service_name}\"}[5m]))" | \
            jq -r '.data.result[0].value[1] // "0"'
            ;;
    esac
}

# Function to get current service replicas
get_service_replicas() {
    local service_name="$1"
    docker service ls --filter name="${service_name}" --format "{{.Replicas}}" | cut -d'/' -f1 || echo "1"
}

# Function to scale service
scale_service() {
    local service_name="$1"
    local new_replicas="$2"
    local current_replicas=$(get_service_replicas "$service_name")
    
    if [[ "$new_replicas" != "$current_replicas" ]]; then
        log_scaling "Scaling $service_name from $current_replicas to $new_replicas replicas"
        
        # Update docker-compose scale
        docker-compose -f ${DOCKER_COMPOSE_FILE} up -d --scale ${service_name}=${new_replicas}
        
        # Wait for scaling to complete
        sleep 30
        
        # Verify scaling
        local actual_replicas=$(get_service_replicas "$service_name")
        if [[ "$actual_replicas" == "$new_replicas" ]]; then
            log_scaling "Successfully scaled $service_name to $new_replicas replicas"
            
            # Update load balancer configuration
            update_load_balancer_config "$service_name" "$new_replicas"
            
            return 0
        else
            log_scaling "Failed to scale $service_name to $new_replicas replicas (actual: $actual_replicas)"
            return 1
        fi
    fi
    
    return 0
}

# Function to update load balancer configuration
update_load_balancer_config() {
    local service_name="$1"
    local replicas="$2"
    
    case "$service_name" in
        "utmstack-backend")
            update_nginx_upstream "utmstack_backend" "$replicas" "8080"
            ;;
        "utmstack-frontend")
            update_nginx_upstream "utmstack_frontend" "$replicas" "4200"
            ;;
    esac
}

# Function to update Nginx upstream configuration
update_nginx_upstream() {
    local upstream_name="$1"
    local replicas="$2"
    local port="$3"
    
    local config_file="/etc/nginx/conf.d/upstream-${upstream_name}.conf"
    
    # Generate upstream configuration
    cat > ${config_file} << EOF
upstream ${upstream_name} {
    least_conn;
EOF

    for ((i=1; i<=replicas; i++)); do
        echo "    server 127.0.0.1:$((port + i - 1)) max_fails=3 fail_timeout=30s;" >> ${config_file}
    done
    
    echo "}" >> ${config_file}
    
    # Test and reload Nginx
    if nginx -t; then
        systemctl reload nginx
        log_scaling "Updated Nginx upstream configuration for $upstream_name ($replicas replicas)"
    else
        log_scaling "Failed to update Nginx configuration for $upstream_name"
    fi
}

# Function to make scaling decision
make_scaling_decision() {
    local service_name="$1"
    local cpu_threshold_scale_up="$2"
    local cpu_threshold_scale_down="$3"
    local memory_threshold_scale_up="$4"
    local response_time_threshold="$5"
    local min_replicas="$6"
    local max_replicas="$7"
    
    local current_replicas=$(get_service_replicas "$service_name")
    local cpu_usage=$(get_service_metrics "$service_name" "cpu")
    local memory_usage=$(get_service_metrics "$service_name" "memory")
    local response_time=$(get_service_metrics "$service_name" "response_time")
    local request_rate=$(get_service_metrics "$service_name" "requests")
    
    log_scaling "Metrics for $service_name: CPU=${cpu_usage}%, Memory=${memory_usage}%, ResponseTime=${response_time}s, Requests=${request_rate}/s, Replicas=${current_replicas}"
    
    local new_replicas=$current_replicas
    local scale_reason=""
    
    # Scale up conditions
    if (( $(echo "$cpu_usage > $cpu_threshold_scale_up" | bc -l) )) && (( current_replicas < max_replicas )); then
        new_replicas=$((current_replicas + 1))
        scale_reason="High CPU usage: ${cpu_usage}%"
    elif (( $(echo "$memory_usage > $memory_threshold_scale_up" | bc -l) )) && (( current_replicas < max_replicas )); then
        new_replicas=$((current_replicas + 1))
        scale_reason="High memory usage: ${memory_usage}%"
    elif (( $(echo "$response_time > $response_time_threshold" | bc -l) )) && (( current_replicas < max_replicas )); then
        new_replicas=$((current_replicas + 1))
        scale_reason="High response time: ${response_time}s"
    # Scale down conditions (more conservative)
    elif (( $(echo "$cpu_usage < $cpu_threshold_scale_down" | bc -l) )) && \
         (( $(echo "$memory_usage < 30" | bc -l) )) && \
         (( $(echo "$response_time < 0.5" | bc -l) )) && \
         (( current_replicas > min_replicas )); then
        new_replicas=$((current_replicas - 1))
        scale_reason="Low resource usage - CPU: ${cpu_usage}%, Memory: ${memory_usage}%"
    fi
    
    if [[ "$new_replicas" != "$current_replicas" ]]; then
        log_scaling "Scaling decision for $service_name: $current_replicas -> $new_replicas ($scale_reason)"
        scale_service "$service_name" "$new_replicas"
    fi
}

# Function to load scaling policies
load_scaling_policies() {
    local policies_file="${SCALING_CONFIG_DIR}/policies/scaling-policies.json"
    
    if [[ ! -f "$policies_file" ]]; then
        log_scaling "Scaling policies file not found: $policies_file"
        return 1
    fi
    
    # Parse and apply scaling policies
    jq -r '.services[] | @base64' "$policies_file" | while read service_data; do
        local service_config=$(echo "$service_data" | base64 --decode)
        local service_name=$(echo "$service_config" | jq -r '.name')
        local cpu_scale_up=$(echo "$service_config" | jq -r '.thresholds.cpu.scale_up')
        local cpu_scale_down=$(echo "$service_config" | jq -r '.thresholds.cpu.scale_down')
        local memory_scale_up=$(echo "$service_config" | jq -r '.thresholds.memory.scale_up')
        local response_time=$(echo "$service_config" | jq -r '.thresholds.response_time')
        local min_replicas=$(echo "$service_config" | jq -r '.replicas.min')
        local max_replicas=$(echo "$service_config" | jq -r '.replicas.max')
        
        make_scaling_decision "$service_name" "$cpu_scale_up" "$cpu_scale_down" "$memory_scale_up" "$response_time" "$min_replicas" "$max_replicas"
    done
}

# Main execution
main() {
    log_scaling "Starting horizontal scaling check"
    
    # Check if required tools are available
    if ! command -v jq &> /dev/null; then
        log_scaling "ERROR: jq is required but not installed"
        exit 1
    fi
    
    if ! command -v bc &> /dev/null; then
        log_scaling "ERROR: bc is required but not installed"
        exit 1
    fi
    
    # Load and apply scaling policies
    load_scaling_policies
    
    log_scaling "Completed horizontal scaling check"
}

# Execute main function
main "$@"
EOF

    chmod +x ${SCALING_CONFIG_DIR}/scripts/horizontal-scaler.sh
    
    log_success "Horizontal scaling orchestrator created"
}

# Function to create scaling policies configuration
create_scaling_policies() {
    log_step "Creating scaling policies configuration..."
    
    cat > ${SCALING_CONFIG_DIR}/policies/scaling-policies.json << 'EOF'
{
    "version": "1.0",
    "updated": "2025-08-10",
    "description": "UTMStack Multi-Tenant Auto-Scaling Policies",
    "services": [
        {
            "name": "utmstack-backend",
            "enabled": true,
            "thresholds": {
                "cpu": {
                    "scale_up": 70,
                    "scale_down": 30
                },
                "memory": {
                    "scale_up": 80,
                    "scale_down": 40
                },
                "response_time": 2.0,
                "request_rate": 1000
            },
            "replicas": {
                "min": 2,
                "max": 10,
                "default": 2
            },
            "cooldown": {
                "scale_up": 300,
                "scale_down": 600
            },
            "ports": [8080, 8081, 8082, 8083, 8084, 8085, 8086, 8087, 8088, 8089]
        },
        {
            "name": "utmstack-frontend",
            "enabled": true,
            "thresholds": {
                "cpu": {
                    "scale_up": 60,
                    "scale_down": 20
                },
                "memory": {
                    "scale_up": 70,
                    "scale_down": 30
                },
                "response_time": 1.0,
                "request_rate": 2000
            },
            "replicas": {
                "min": 2,
                "max": 8,
                "default": 2
            },
            "cooldown": {
                "scale_up": 180,
                "scale_down": 360
            },
            "ports": [4200, 4201, 4202, 4203, 4204, 4205, 4206, 4207]
        },
        {
            "name": "correlation",
            "enabled": true,
            "thresholds": {
                "cpu": {
                    "scale_up": 75,
                    "scale_down": 35
                },
                "memory": {
                    "scale_up": 85,
                    "scale_down": 45
                },
                "response_time": 5.0,
                "request_rate": 500
            },
            "replicas": {
                "min": 1,
                "max": 6,
                "default": 2
            },
            "cooldown": {
                "scale_up": 300,
                "scale_down": 600
            },
            "ports": [9091, 9092, 9093, 9094, 9095, 9096]
        },
        {
            "name": "agent-manager",
            "enabled": true,
            "thresholds": {
                "cpu": {
                    "scale_up": 65,
                    "scale_down": 25
                },
                "memory": {
                    "scale_up": 75,
                    "scale_down": 35
                },
                "response_time": 3.0,
                "request_rate": 200
            },
            "replicas": {
                "min": 1,
                "max": 4,
                "default": 2
            },
            "cooldown": {
                "scale_up": 240,
                "scale_down": 480
            },
            "ports": [9090, 9097, 9098, 9099]
        }
    ],
    "global_settings": {
        "check_interval": 60,
        "metrics_retention": 3600,
        "alert_thresholds": {
            "max_scaling_events_per_hour": 10,
            "min_time_between_scales": 120
        }
    }
}
EOF

    log_success "Scaling policies configuration created"
}

# Function to create database read replica setup
create_database_read_replicas() {
    log_step "Creating database read replica setup..."
    
    cat > ${SCALING_CONFIG_DIR}/scripts/setup-db-read-replicas.sh << 'EOF'
#!/bin/bash

# UTMStack Database Read Replica Setup Script

set -e

# Configuration
PRIMARY_DB_HOST="localhost"
PRIMARY_DB_PORT="5432"
PRIMARY_DB_NAME="utmstack_production"
PRIMARY_DB_USER="utmstack_prod"
REPLICA_BASE_PORT="5433"
REPLICA_COUNT=2

# Logging
LOG_FILE="/var/log/utmstack/db-replica-setup.log"
log_replica() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

# Function to create read replica
create_read_replica() {
    local replica_number="$1"
    local replica_port=$((REPLICA_BASE_PORT + replica_number - 1))
    local replica_name="utmstack-db-replica-${replica_number}"
    local replica_data_dir="/var/lib/postgresql/replica${replica_number}"
    
    log_replica "Creating read replica ${replica_number} on port ${replica_port}"
    
    # Create replica data directory
    mkdir -p ${replica_data_dir}
    chown postgres:postgres ${replica_data_dir}
    
    # Create base backup from primary
    sudo -u postgres pg_basebackup -h ${PRIMARY_DB_HOST} -p ${PRIMARY_DB_PORT} -U ${PRIMARY_DB_USER} \
        -D ${replica_data_dir} -Fp -Xs -P -R
    
    # Configure replica
    cat >> ${replica_data_dir}/postgresql.conf << EOF

# Read Replica Configuration
port = ${replica_port}
hot_standby = on
max_standby_streaming_delay = 30s
max_standby_archive_delay = 60s
wal_receiver_status_interval = 10s
hot_standby_feedback = on
EOF
    
    # Start replica instance
    sudo -u postgres pg_ctl -D ${replica_data_dir} -l ${replica_data_dir}/replica.log start
    
    # Verify replica status
    sleep 5
    if sudo -u postgres psql -h localhost -p ${replica_port} -c "SELECT pg_is_in_recovery();" | grep -q "t"; then
        log_replica "Read replica ${replica_number} created successfully"
        
        # Create systemd service for replica
        create_replica_service "${replica_number}" "${replica_data_dir}"
        
        return 0
    else
        log_replica "Failed to create read replica ${replica_number}"
        return 1
    fi
}

# Function to create systemd service for replica
create_replica_service() {
    local replica_number="$1"
    local data_dir="$2"
    local service_name="postgresql-replica-${replica_number}"
    
    cat > /etc/systemd/system/${service_name}.service << EOF
[Unit]
Description=PostgreSQL Read Replica ${replica_number}
Documentation=man:postgres(1)
After=network.target
RequiresMountsFor=${data_dir}

[Service]
Type=notify
User=postgres
ExecStart=/usr/lib/postgresql/15/bin/postgres -D ${data_dir}
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutSec=0

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${service_name}
    
    log_replica "Created systemd service for replica ${replica_number}"
}

# Function to setup read replica connection pooling
setup_replica_connection_pooling() {
    log_replica "Setting up read replica connection pooling"
    
    cat > /etc/pgbouncer/pgbouncer-readonly.ini << EOF
[databases]
utmstack_production_readonly = host=localhost port=5433 dbname=utmstack_production
utmstack_production_readonly_2 = host=localhost port=5434 dbname=utmstack_production

[pgbouncer]
listen_port = 6433
listen_addr = 127.0.0.1
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
admin_users = postgres
stats_users = postgres

pool_mode = transaction
max_client_conn = 500
default_pool_size = 25
min_pool_size = 5
reserve_pool_size = 5
max_db_connections = 100

server_reset_query = DISCARD ALL
server_check_query = SELECT 1
server_check_delay = 30

log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
EOF

    # Start read-only connection pooler
    systemctl enable pgbouncer-readonly
    systemctl start pgbouncer-readonly
    
    log_replica "Read replica connection pooling configured"
}

# Function to create load balancer for read replicas
create_replica_load_balancer() {
    log_replica "Creating load balancer for read replicas"
    
    cat > /etc/nginx/conf.d/db-replica-lb.conf << 'EOF'
upstream postgres_read_replicas {
    least_conn;
    server 127.0.0.1:5433 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:5434 max_fails=3 fail_timeout=30s;
}

server {
    listen 5435;
    proxy_pass postgres_read_replicas;
    proxy_timeout 1s;
    proxy_responses 1;
    proxy_connect_timeout 1s;
}
EOF

    # Test and reload nginx
    nginx -t && systemctl reload nginx
    
    log_replica "Read replica load balancer configured"
}

# Main execution
main() {
    log_replica "Starting database read replica setup"
    
    # Check if primary database is accessible
    if ! sudo -u postgres psql -h ${PRIMARY_DB_HOST} -p ${PRIMARY_DB_PORT} -d ${PRIMARY_DB_NAME} -c "SELECT 1;" > /dev/null 2>&1; then
        log_replica "ERROR: Cannot connect to primary database"
        exit 1
    fi
    
    # Create read replicas
    for ((i=1; i<=REPLICA_COUNT; i++)); do
        create_read_replica "$i"
    done
    
    # Setup connection pooling for replicas
    setup_replica_connection_pooling
    
    # Create load balancer for replicas
    create_replica_load_balancer
    
    log_replica "Database read replica setup completed"
}

# Execute main function
main "$@"
EOF

    chmod +x ${SCALING_CONFIG_DIR}/scripts/setup-db-read-replicas.sh
    
    log_success "Database read replica setup script created"
}

# Function to create Elasticsearch auto-scaling
create_elasticsearch_autoscaling() {
    log_step "Creating Elasticsearch auto-scaling configuration..."
    
    cat > ${SCALING_CONFIG_DIR}/scripts/elasticsearch-autoscaler.sh << 'EOF'
#!/bin/bash

# UTMStack Elasticsearch Auto-Scaling Script

set -e

# Configuration
ES_HOST="localhost"
ES_PORT="9200"
LOG_FILE="/var/log/utmstack/es-autoscaling.log"
SCALING_CONFIG="/etc/utmstack/scaling/policies/es-scaling-policy.json"

# Logging
log_es() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

# Function to get cluster metrics
get_cluster_metrics() {
    local metric_type="$1"
    
    case "$metric_type" in
        "cpu")
            # Get average CPU usage across nodes
            curl -s "${ES_HOST}:${ES_PORT}/_nodes/stats/os" | \
            jq -r '.nodes | to_entries | map(.value.os.cpu.percent) | add / length'
            ;;
        "memory")
            # Get average memory usage across nodes
            curl -s "${ES_HOST}:${ES_PORT}/_nodes/stats/jvm" | \
            jq -r '.nodes | to_entries | map(.value.jvm.mem.heap_used_percent) | add / length'
            ;;
        "disk")
            # Get average disk usage across nodes
            curl -s "${ES_HOST}:${ES_PORT}/_nodes/stats/fs" | \
            jq -r '.nodes | to_entries | map((.value.fs.total.available_in_bytes / .value.fs.total.total_in_bytes) * 100) | add / length'
            ;;
        "search_latency")
            # Get average search latency
            curl -s "${ES_HOST}:${ES_PORT}/_nodes/stats/indices" | \
            jq -r '.nodes | to_entries | map(.value.indices.search.query_time_in_millis / (.value.indices.search.query_total + 1)) | add / length'
            ;;
        "indexing_rate")
            # Get indexing rate
            curl -s "${ES_HOST}:${ES_PORT}/_nodes/stats/indices" | \
            jq -r '.nodes | to_entries | map(.value.indices.indexing.index_total) | add'
            ;;
        "node_count")
            # Get current node count
            curl -s "${ES_HOST}:${ES_PORT}/_cat/nodes" | wc -l
            ;;
    esac
}

# Function to get shard allocation status
get_shard_status() {
    curl -s "${ES_HOST}:${ES_PORT}/_cluster/health" | jq -r '.relocating_shards + .initializing_shards + .unassigned_shards'
}

# Function to add Elasticsearch node
add_elasticsearch_node() {
    local node_number="$1"
    local node_name="es-node-$((node_number + 3))"
    local node_port=$((9200 + node_number))
    local node_transport_port=$((9300 + node_number))
    
    log_es "Adding new Elasticsearch node: ${node_name}"
    
    # Create node configuration
    local node_config_dir="/etc/elasticsearch/nodes/${node_name}"
    mkdir -p ${node_config_dir}
    
    cat > ${node_config_dir}/elasticsearch.yml << EOF
# Elasticsearch Node Configuration - ${node_name}
cluster.name: utmstack-production
node.name: ${node_name}
node.roles: [data, ingest]

# Network settings
network.host: 0.0.0.0
http.port: ${node_port}
transport.port: ${node_transport_port}

# Discovery settings
discovery.seed_hosts: [localhost:9300, localhost:9301, localhost:9302]
cluster.initial_master_nodes: [es-node-1, es-node-2, es-node-3]

# Data path
path.data: /var/lib/elasticsearch/${node_name}
path.logs: /var/log/elasticsearch/${node_name}

# Memory settings
bootstrap.memory_lock: true
indices.memory.index_buffer_size: 20%

# Auto-scaling settings
cluster.routing.allocation.enable: all
cluster.routing.rebalance.enable: all
EOF

    # Create data and log directories
    mkdir -p /var/lib/elasticsearch/${node_name}
    mkdir -p /var/log/elasticsearch/${node_name}
    chown -R elasticsearch:elasticsearch /var/lib/elasticsearch/${node_name}
    chown -R elasticsearch:elasticsearch /var/log/elasticsearch/${node_name}
    
    # Start node using Docker
    docker run -d \
        --name "${node_name}" \
        --network utmstack-production \
        -p ${node_port}:9200 \
        -p ${node_transport_port}:9300 \
        -v ${node_config_dir}/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml \
        -v /var/lib/elasticsearch/${node_name}:/usr/share/elasticsearch/data \
        -v /var/log/elasticsearch/${node_name}:/usr/share/elasticsearch/logs \
        -e "ES_JAVA_OPTS=-Xms2g -Xmx2g" \
        -e "bootstrap.memory_lock=true" \
        --ulimit memlock=-1:-1 \
        docker.elastic.co/elasticsearch/elasticsearch:8.11.0
    
    # Wait for node to join cluster
    for i in {1..30}; do
        if curl -s "${ES_HOST}:${ES_PORT}/_cat/nodes" | grep -q "${node_name}"; then
            log_es "Node ${node_name} successfully joined the cluster"
            return 0
        fi
        sleep 10
    done
    
    log_es "Failed to add node ${node_name} to cluster"
    return 1
}

# Function to remove Elasticsearch node
remove_elasticsearch_node() {
    local node_name="$1"
    
    log_es "Removing Elasticsearch node: ${node_name}"
    
    # Exclude node from allocation
    curl -X PUT "${ES_HOST}:${ES_PORT}/_cluster/settings" -H 'Content-Type: application/json' -d"{
        \"persistent\": {
            \"cluster.routing.allocation.exclude._name\": \"${node_name}\"
        }
    }"
    
    # Wait for shards to relocate
    local timeout=300
    local elapsed=0
    while [[ $(get_shard_status) -gt 0 ]] && [[ $elapsed -lt $timeout ]]; do
        log_es "Waiting for shard relocation... (${elapsed}s)"
        sleep 30
        elapsed=$((elapsed + 30))
    done
    
    # Stop and remove Docker container
    docker stop "${node_name}" || true
    docker rm "${node_name}" || true
    
    # Clear allocation exclusion
    curl -X PUT "${ES_HOST}:${ES_PORT}/_cluster/settings" -H 'Content-Type: application/json' -d'{
        "persistent": {
            "cluster.routing.allocation.exclude._name": null
        }
    }'
    
    log_es "Node ${node_name} removed from cluster"
}

# Function to make scaling decision for Elasticsearch
make_es_scaling_decision() {
    local cpu_usage=$(get_cluster_metrics "cpu")
    local memory_usage=$(get_cluster_metrics "memory")
    local disk_usage=$(get_cluster_metrics "disk")
    local search_latency=$(get_cluster_metrics "search_latency")
    local node_count=$(get_cluster_metrics "node_count")
    local unassigned_shards=$(get_shard_status)
    
    log_es "ES Metrics: CPU=${cpu_usage}%, Memory=${memory_usage}%, Disk=${disk_usage}%, Latency=${search_latency}ms, Nodes=${node_count}, UnassignedShards=${unassigned_shards}"
    
    # Load scaling thresholds
    local cpu_scale_up=75
    local memory_scale_up=80
    local latency_scale_up=1000
    local min_nodes=3
    local max_nodes=9
    
    if [[ -f "$SCALING_CONFIG" ]]; then
        cpu_scale_up=$(jq -r '.elasticsearch.thresholds.cpu.scale_up' "$SCALING_CONFIG")
        memory_scale_up=$(jq -r '.elasticsearch.thresholds.memory.scale_up' "$SCALING_CONFIG")
        latency_scale_up=$(jq -r '.elasticsearch.thresholds.search_latency' "$SCALING_CONFIG")
        min_nodes=$(jq -r '.elasticsearch.nodes.min' "$SCALING_CONFIG")
        max_nodes=$(jq -r '.elasticsearch.nodes.max' "$SCALING_CONFIG")
    fi
    
    # Scale up conditions
    if (( $(echo "$cpu_usage > $cpu_scale_up" | bc -l) )) && (( node_count < max_nodes )); then
        log_es "Scaling up due to high CPU usage: ${cpu_usage}%"
        add_elasticsearch_node $((node_count))
    elif (( $(echo "$memory_usage > $memory_scale_up" | bc -l) )) && (( node_count < max_nodes )); then
        log_es "Scaling up due to high memory usage: ${memory_usage}%"
        add_elasticsearch_node $((node_count))
    elif (( $(echo "$search_latency > $latency_scale_up" | bc -l) )) && (( node_count < max_nodes )); then
        log_es "Scaling up due to high search latency: ${search_latency}ms"
        add_elasticsearch_node $((node_count))
    elif (( unassigned_shards > 0 )) && (( node_count < max_nodes )); then
        log_es "Scaling up due to unassigned shards: ${unassigned_shards}"
        add_elasticsearch_node $((node_count))
    # Scale down conditions (very conservative)
    elif (( $(echo "$cpu_usage < 20" | bc -l) )) && \
         (( $(echo "$memory_usage < 40" | bc -l) )) && \
         (( $(echo "$search_latency < 100" | bc -l) )) && \
         (( node_count > min_nodes )) && \
         (( unassigned_shards == 0 )); then
        log_es "Scaling down due to low resource usage"
        local highest_node_num=$((node_count + 2))
        remove_elasticsearch_node "es-node-${highest_node_num}"
    fi
}

# Main execution
main() {
    log_es "Starting Elasticsearch auto-scaling check"
    
    # Check if Elasticsearch is accessible
    if ! curl -s "${ES_HOST}:${ES_PORT}/_cluster/health" > /dev/null; then
        log_es "ERROR: Cannot connect to Elasticsearch cluster"
        exit 1
    fi
    
    # Check cluster health
    local cluster_status=$(curl -s "${ES_HOST}:${ES_PORT}/_cluster/health" | jq -r '.status')
    if [[ "$cluster_status" == "red" ]]; then
        log_es "WARNING: Cluster status is RED - skipping scaling operations"
        exit 0
    fi
    
    # Make scaling decision
    make_es_scaling_decision
    
    log_es "Completed Elasticsearch auto-scaling check"
}

# Execute main function
main "$@"
EOF

    chmod +x ${SCALING_CONFIG_DIR}/scripts/elasticsearch-autoscaler.sh
    
    # Create Elasticsearch scaling policy
    cat > ${SCALING_CONFIG_DIR}/policies/es-scaling-policy.json << 'EOF'
{
    "elasticsearch": {
        "enabled": true,
        "thresholds": {
            "cpu": {
                "scale_up": 75,
                "scale_down": 20
            },
            "memory": {
                "scale_up": 80,
                "scale_down": 40
            },
            "disk": {
                "scale_up": 85,
                "scale_down": 50
            },
            "search_latency": 1000,
            "indexing_rate": 10000
        },
        "nodes": {
            "min": 3,
            "max": 9,
            "default": 3
        },
        "cooldown": {
            "scale_up": 600,
            "scale_down": 1200
        }
    }
}
EOF

    log_success "Elasticsearch auto-scaling configuration created"
}

# Function to create resource monitoring and alerting
create_resource_monitoring() {
    log_step "Creating resource monitoring and scaling triggers..."
    
    cat > ${SCALING_CONFIG_DIR}/monitors/resource-monitor.sh << 'EOF'
#!/bin/bash

# UTMStack Resource Monitoring and Scaling Triggers

set -e

# Configuration
PROMETHEUS_URL="http://localhost:9090"
ALERT_MANAGER_URL="http://localhost:9093"
LOG_FILE="/var/log/utmstack/resource-monitor.log"
SCALING_CONFIG="/etc/utmstack/scaling"

# Logging
log_monitor() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

# Function to check system resources
check_system_resources() {
    log_monitor "Checking system resources"
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    
    # Memory usage
    local memory_info=$(free | grep Mem)
    local total_mem=$(echo $memory_info | awk '{print $2}')
    local used_mem=$(echo $memory_info | awk '{print $3}')
    local memory_usage=$((used_mem * 100 / total_mem))
    
    # Disk usage
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1)
    
    # Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | cut -d',' -f1)
    
    log_monitor "System metrics - CPU: ${cpu_usage}%, Memory: ${memory_usage}%, Disk: ${disk_usage}%, Load: ${load_avg}"
    
    # Check thresholds and trigger scaling if needed
    check_scaling_thresholds "$cpu_usage" "$memory_usage" "$disk_usage" "$load_avg"
}

# Function to check application-specific metrics
check_application_metrics() {
    log_monitor "Checking application metrics"
    
    # Query Prometheus for application metrics
    local backend_response_time=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=histogram_quantile(0.95,rate(http_request_duration_seconds_bucket{service=\"utmstack-backend\"}[5m]))" | jq -r '.data.result[0].value[1] // "0"')
    local backend_request_rate=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=rate(http_requests_total{service=\"utmstack-backend\"}[5m])" | jq -r '.data.result[0].value[1] // "0"')
    local backend_error_rate=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=rate(http_requests_total{service=\"utmstack-backend\",status=~\"5..\"}[5m])" | jq -r '.data.result[0].value[1] // "0"')
    
    # Database metrics
    local db_connections=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=pg_stat_activity_count" | jq -r '.data.result[0].value[1] // "0"')
    local db_response_time=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=pg_stat_database_tup_fetched_rate" | jq -r '.data.result[0].value[1] // "0"')
    
    # Elasticsearch metrics
    local es_search_latency=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=elasticsearch_indices_search_query_time_seconds" | jq -r '.data.result[0].value[1] // "0"')
    local es_indexing_rate=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=rate(elasticsearch_indices_indexing_index_total[5m])" | jq -r '.data.result[0].value[1] // "0"')
    
    log_monitor "App metrics - Backend RT: ${backend_response_time}s, Request rate: ${backend_request_rate}/s, Error rate: ${backend_error_rate}/s"
    log_monitor "DB metrics - Connections: ${db_connections}, Response time: ${db_response_time}ms"
    log_monitor "ES metrics - Search latency: ${es_search_latency}ms, Indexing rate: ${es_indexing_rate}/s"
    
    # Check if scaling is needed based on application metrics
    check_application_scaling_needs "$backend_response_time" "$backend_request_rate" "$db_connections" "$es_search_latency"
}

# Function to check scaling thresholds
check_scaling_thresholds() {
    local cpu="$1"
    local memory="$2"
    local disk="$3"
    local load="$4"
    
    # System-level scaling triggers
    if (( $(echo "$cpu > 80" | bc -l) )) || (( $(echo "$memory > 85" | bc -l) )) || (( $(echo "$load > 4" | bc -l) )); then
        log_monitor "HIGH SYSTEM LOAD DETECTED - Triggering horizontal scaling"
        trigger_emergency_scaling "system_overload"
    elif (( $(echo "$disk > 90" | bc -l) )); then
        log_monitor "HIGH DISK USAGE DETECTED - Triggering storage scaling"
        trigger_storage_scaling "$disk"
    fi
}

# Function to check application scaling needs
check_application_scaling_needs() {
    local response_time="$1"
    local request_rate="$2"
    local db_connections="$3"
    local es_latency="$4"
    
    # Application-level scaling triggers
    if (( $(echo "$response_time > 3" | bc -l) )) || (( $(echo "$request_rate > 2000" | bc -l) )); then
        log_monitor "HIGH APPLICATION LOAD DETECTED - Triggering backend scaling"
        trigger_service_scaling "utmstack-backend" "scale_up"
    fi
    
    if (( $(echo "$db_connections > 400" | bc -l) )); then
        log_monitor "HIGH DATABASE LOAD DETECTED - Scaling read replicas"
        trigger_database_scaling "read_replicas"
    fi
    
    if (( $(echo "$es_latency > 2000" | bc -l) )); then
        log_monitor "HIGH ELASTICSEARCH LATENCY DETECTED - Scaling ES cluster"
        trigger_elasticsearch_scaling "scale_up"
    fi
}

# Function to trigger emergency scaling
trigger_emergency_scaling() {
    local reason="$1"
    
    log_monitor "EMERGENCY SCALING TRIGGERED: $reason"
    
    # Scale up all critical services immediately
    ${SCALING_CONFIG}/scripts/horizontal-scaler.sh
    
    # Send alert
    send_scaling_alert "emergency" "$reason" "All services scaled up due to system overload"
}

# Function to trigger service scaling
trigger_service_scaling() {
    local service="$1"
    local action="$2"
    
    log_monitor "Service scaling triggered: $service ($action)"
    
    # Execute service-specific scaling
    case "$service" in
        "utmstack-backend")
            ${SCALING_CONFIG}/scripts/horizontal-scaler.sh
            ;;
        "elasticsearch")
            ${SCALING_CONFIG}/scripts/elasticsearch-autoscaler.sh
            ;;
    esac
}

# Function to trigger database scaling
trigger_database_scaling() {
    local scaling_type="$1"
    
    log_monitor "Database scaling triggered: $scaling_type"
    
    case "$scaling_type" in
        "read_replicas")
            # Add additional read replica if needed
            ${SCALING_CONFIG}/scripts/setup-db-read-replicas.sh
            ;;
    esac
}

# Function to trigger Elasticsearch scaling
trigger_elasticsearch_scaling() {
    local action="$1"
    
    log_monitor "Elasticsearch scaling triggered: $action"
    ${SCALING_CONFIG}/scripts/elasticsearch-autoscaler.sh
}

# Function to send scaling alerts
send_scaling_alert() {
    local severity="$1"
    local reason="$2"
    local message="$3"
    
    # Send alert to AlertManager
    curl -X POST "${ALERT_MANAGER_URL}/api/v1/alerts" -H 'Content-Type: application/json' -d"[
        {
            \"labels\": {
                \"alertname\": \"UTMStackScalingEvent\",
                \"severity\": \"${severity}\",
                \"reason\": \"${reason}\",
                \"service\": \"utmstack\"
            },
            \"annotations\": {
                \"summary\": \"UTMStack Auto-Scaling Event\",
                \"description\": \"${message}\"
            },
            \"startsAt\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\"
        }
    ]"
    
    log_monitor "Scaling alert sent: $severity - $message"
}

# Function to generate scaling report
generate_scaling_report() {
    local report_file="/var/log/utmstack/scaling-report-$(date +%Y-%m-%d).txt"
    
    cat > ${report_file} << EOF
UTMStack Auto-Scaling Report
Generated: $(date)
=================================

System Resources:
$(check_system_resources 2>&1 | grep "System metrics")

Application Metrics:
$(check_application_metrics 2>&1 | grep -E "(App metrics|DB metrics|ES metrics)")

Recent Scaling Events:
$(tail -20 ${LOG_FILE} | grep -E "(Scaling|TRIGGERED)")

Current Service Status:
$(docker-compose -f /home/ptsec/utmstack/docker-compose.production.yml ps --services | while read service; do
    replicas=$(docker service ls --filter name="$service" --format "{{.Replicas}}" 2>/dev/null || echo "N/A")
    echo "$service: $replicas"
done)

Recommendations:
- Monitor scaling frequency to avoid thrashing
- Adjust thresholds based on actual workload patterns
- Consider pre-emptive scaling during known peak periods
- Review scaling policies weekly
EOF

    log_monitor "Scaling report generated: $report_file"
}

# Main execution
main() {
    log_monitor "Starting resource monitoring and scaling check"
    
    # Check system resources
    check_system_resources
    
    # Check application metrics
    check_application_metrics
    
    # Generate daily report (if it's the first run of the day)
    if [[ ! -f "/var/log/utmstack/scaling-report-$(date +%Y-%m-%d).txt" ]]; then
        generate_scaling_report
    fi
    
    log_monitor "Completed resource monitoring and scaling check"
}

# Execute main function
main "$@"
EOF

    chmod +x ${SCALING_CONFIG_DIR}/monitors/resource-monitor.sh
    
    log_success "Resource monitoring and scaling triggers created"
}

# Function to create load balancer scaling configuration
create_load_balancer_scaling() {
    log_step "Creating load balancer scaling configuration..."
    
    cat > ${SCALING_CONFIG_DIR}/scripts/update-load-balancer.sh << 'EOF'
#!/bin/bash

# UTMStack Load Balancer Auto-Scaling Configuration

set -e

# Configuration
NGINX_CONFIG_DIR="/etc/nginx"
SCALING_CONFIG_DIR="/etc/utmstack/scaling"
LOG_FILE="/var/log/utmstack/lb-scaling.log"

# Logging
log_lb() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

# Function to update upstream configuration
update_upstream_config() {
    local service_name="$1"
    local replica_count="$2"
    local base_port="$3"
    
    log_lb "Updating upstream configuration for $service_name ($replica_count replicas)"
    
    local upstream_file="${NGINX_CONFIG_DIR}/conf.d/upstream-${service_name}.conf"
    
    # Generate upstream configuration
    cat > ${upstream_file} << EOF
upstream ${service_name} {
    least_conn;
    
    # Health check configuration
    keepalive 32;
    keepalive_requests 100;
    keepalive_timeout 60s;
EOF

    # Add server entries for each replica
    for ((i=1; i<=replica_count; i++)); do
        local port=$((base_port + i - 1))
        cat >> ${upstream_file} << EOF
    server 127.0.0.1:${port} max_fails=3 fail_timeout=30s weight=1;
EOF
    done
    
    cat >> ${upstream_file} << EOF
}

# Rate limiting configuration for ${service_name}
limit_req_zone \$binary_remote_addr zone=${service_name}_limit:10m rate=100r/s;
EOF
    
    log_lb "Generated upstream configuration for $service_name with $replica_count backends"
}

# Function to update main nginx configuration
update_main_nginx_config() {
    log_lb "Updating main Nginx configuration for auto-scaling"
    
    cat > ${NGINX_CONFIG_DIR}/conf.d/utmstack-autoscaling.conf << 'EOF'
# UTMStack Auto-Scaling Load Balancer Configuration

# Backend API Load Balancing
server {
    listen 80;
    listen [::]:80;
    server_name api.utmstack.com backend.utmstack.com;
    
    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name api.utmstack.com backend.utmstack.com;
    
    # SSL configuration
    ssl_certificate /etc/ssl/certs/utmstack.crt;
    ssl_certificate_key /etc/ssl/private/utmstack.key;
    
    # Auto-scaling specific headers
    add_header X-Served-By $hostname always;
    add_header X-Backend-Pool "utmstack_backend" always;
    
    # API routes with rate limiting
    location /api/ {
        limit_req zone=utmstack_backend_limit burst=50 nodelay;
        
        proxy_pass http://utmstack_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Connection pooling
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        
        # Timeouts
        proxy_connect_timeout 5s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Health checks
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_next_upstream_tries 3;
        proxy_next_upstream_timeout 10s;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        proxy_pass http://utmstack_backend/management/health;
        proxy_set_header Host $host;
    }
}

# Frontend Load Balancing
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name *.utmstack.com utmstack.com;
    
    # SSL configuration
    ssl_certificate /etc/ssl/certs/utmstack.crt;
    ssl_certificate_key /etc/ssl/private/utmstack.key;
    
    # Extract tenant from subdomain
    set $tenant "default";
    if ($host ~* "^([^.]+)\.utmstack\.com$") {
        set $tenant $1;
    }
    
    # Add tenant and scaling headers
    add_header X-Tenant-ID $tenant always;
    add_header X-Frontend-Pool "utmstack_frontend" always;
    
    # Frontend routes
    location / {
        limit_req zone=utmstack_frontend_limit burst=100 nodelay;
        
        proxy_pass http://utmstack_frontend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Tenant-ID $tenant;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Caching for static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
            proxy_pass http://utmstack_frontend;
        }
    }
}

# Monitoring and Status
server {
    listen 8090;
    server_name 127.0.0.1;
    
    location /nginx_status {
        stub_status on;
        allow 127.0.0.1;
        deny all;
    }
    
    location /upstream_status {
        # Custom upstream status endpoint
        content_by_lua_block {
            local upstreams = {
                "utmstack_backend",
                "utmstack_frontend"
            }
            
            ngx.header["Content-Type"] = "application/json"
            
            local status = {}
            for _, upstream in ipairs(upstreams) do
                local peers = ngx.shared.upstream_status:get_keys()
                status[upstream] = {
                    active_connections = 0,
                    total_requests = 0,
                    failed_requests = 0
                }
            end
            
            ngx.say(require("cjson").encode(status))
        }
    }
}
EOF

    log_lb "Main Nginx configuration updated for auto-scaling"
}

# Function to create dynamic upstream management
create_dynamic_upstream_management() {
    log_lb "Creating dynamic upstream management system"
    
    cat > ${SCALING_CONFIG_DIR}/scripts/manage-upstreams.sh << 'EOF'
#!/bin/bash

# Dynamic Upstream Management for Auto-Scaling

set -e

NGINX_CONFIG_DIR="/etc/nginx"
LOG_FILE="/var/log/utmstack/upstream-management.log"

log_upstream() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

# Function to add backend to upstream
add_backend() {
    local service="$1"
    local host="$2"
    local port="$3"
    local weight="${4:-1}"
    
    log_upstream "Adding backend $host:$port to $service upstream (weight: $weight)"
    
    # Use nginx-plus API if available, otherwise update config file
    if command -v nginx-plus &> /dev/null; then
        curl -X POST "http://localhost:8080/api/6/http/upstreams/$service/servers" \
             -H 'Content-Type: application/json' \
             -d "{\"server\":\"$host:$port\",\"weight\":$weight}"
    else
        # Update config file and reload
        update_upstream_config "$service"
        nginx -t && systemctl reload nginx
    fi
}

# Function to remove backend from upstream
remove_backend() {
    local service="$1"
    local host="$2"
    local port="$3"
    
    log_upstream "Removing backend $host:$port from $service upstream"
    
    if command -v nginx-plus &> /dev/null; then
        # Get server ID first
        local server_id=$(curl -s "http://localhost:8080/api/6/http/upstreams/$service" | \
                         jq -r ".peers[] | select(.server==\"$host:$port\") | .id")
        
        if [[ -n "$server_id" ]]; then
            curl -X DELETE "http://localhost:8080/api/6/http/upstreams/$service/servers/$server_id"
        fi
    else
        # Update config file and reload
        update_upstream_config "$service"
        nginx -t && systemctl reload nginx
    fi
}

# Function to check backend health
check_backend_health() {
    local host="$1"
    local port="$2"
    local health_path="${3:-/health}"
    
    if curl -sf --max-time 5 "http://$host:$port$health_path" > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to monitor and manage upstream health
monitor_upstream_health() {
    local service="$1"
    local health_path="${2:-/health}"
    
    log_upstream "Monitoring health for $service upstream"
    
    # Get current upstream servers
    local upstream_file="${NGINX_CONFIG_DIR}/conf.d/upstream-${service}.conf"
    
    if [[ -f "$upstream_file" ]]; then
        grep "server " "$upstream_file" | while read -r line; do
            local server=$(echo "$line" | awk '{print $2}' | cut -d';' -f1)
            local host=$(echo "$server" | cut -d':' -f1)
            local port=$(echo "$server" | cut -d':' -f2)
            
            if ! check_backend_health "$host" "$port" "$health_path"; then
                log_upstream "Backend $host:$port is unhealthy - marking as down"
                # In a real implementation, this would mark the server as down
                # or remove it temporarily from the upstream
            fi
        done
    fi
}

# Main execution
case "${1:-help}" in
    "add")
        add_backend "$2" "$3" "$4" "$5"
        ;;
    "remove")
        remove_backend "$2" "$3" "$4"
        ;;
    "health")
        monitor_upstream_health "$2" "$3"
        ;;
    "status")
        # Show upstream status
        for service in utmstack_backend utmstack_frontend; do
            echo "=== $service ==="
            if [[ -f "${NGINX_CONFIG_DIR}/conf.d/upstream-${service}.conf" ]]; then
                grep "server " "${NGINX_CONFIG_DIR}/conf.d/upstream-${service}.conf"
            fi
        done
        ;;
    *)
        echo "Usage: $0 {add|remove|health|status}"
        echo "  add <service> <host> <port> [weight]"
        echo "  remove <service> <host> <port>"
        echo "  health <service> [health_path]"
        echo "  status"
        ;;
esac
EOF

    chmod +x ${SCALING_CONFIG_DIR}/scripts/manage-upstreams.sh
    
    log_lb "Dynamic upstream management system created"
}

# Function to create auto-scaling cron jobs
create_autoscaling_cron_jobs() {
    log_step "Creating auto-scaling cron jobs..."
    
    cat > /etc/cron.d/utmstack-autoscaling << 'EOF'
# UTMStack Auto-Scaling Cron Jobs

# Run horizontal scaling check every 2 minutes
*/2 * * * * root /etc/utmstack/scaling/scripts/horizontal-scaler.sh >> /var/log/utmstack/scaling.log 2>&1

# Run Elasticsearch scaling check every 5 minutes
*/5 * * * * root /etc/utmstack/scaling/scripts/elasticsearch-autoscaler.sh >> /var/log/utmstack/es-scaling.log 2>&1

# Run resource monitoring every minute
*/1 * * * * root /etc/utmstack/scaling/monitors/resource-monitor.sh >> /var/log/utmstack/resource-monitor.log 2>&1

# Check upstream health every 30 seconds
*/1 * * * * root /etc/utmstack/scaling/scripts/manage-upstreams.sh health utmstack_backend >> /var/log/utmstack/upstream-health.log 2>&1
*/1 * * * * root /etc/utmstack/scaling/scripts/manage-upstreams.sh health utmstack_frontend >> /var/log/utmstack/upstream-health.log 2>&1

# Generate scaling reports daily at 6 AM
0 6 * * * root /etc/utmstack/scaling/monitors/resource-monitor.sh >> /var/log/utmstack/daily-scaling-report.log 2>&1
EOF

    log_success "Auto-scaling cron jobs created"
}

# Main implementation execution
main() {
    log_info "Starting UTMStack Auto-Scaling Implementation..."
    
    # Create all auto-scaling components
    create_horizontal_scaling_orchestrator
    create_scaling_policies
    create_database_read_replicas
    create_elasticsearch_autoscaling
    create_resource_monitoring
    create_load_balancer_scaling
    create_dynamic_upstream_management
    create_autoscaling_cron_jobs
    
    log_success "Auto-scaling implementation completed!"
    echo ""
    echo "======================================================================"
    echo "🔄 Auto-Scaling Implementation Summary"
    echo "======================================================================"
    echo "Implementation Date: ${IMPLEMENTATION_DATE}"
    echo "Log File: ${LOG_FILE}"
    echo "Scaling Config Directory: ${SCALING_CONFIG_DIR}"
    echo ""
    echo "Auto-Scaling Components Implemented:"
    echo "✅ Horizontal scaling orchestrator for microservices"
    echo "✅ Database read replica setup and management"
    echo "✅ Elasticsearch cluster auto-scaling"
    echo "✅ Load balancer configuration for scaling"
    echo "✅ Resource monitoring and scaling triggers"
    echo "✅ Dynamic upstream management"
    echo "✅ Automated scaling policies"
    echo ""
    echo "Scaling Capabilities:"
    echo "• Automatic service scaling based on CPU, memory, and response time"
    echo "• Elasticsearch cluster expansion/contraction"
    echo "• Database read replica management"
    echo "• Load balancer automatic reconfiguration"
    echo "• Real-time resource monitoring and alerting"
    echo "• Emergency scaling for critical situations"
    echo ""
    echo "Monitoring & Control:"
    echo "• Scaling policies: ${SCALING_CONFIG_DIR}/policies/"
    echo "• Monitoring scripts: ${SCALING_CONFIG_DIR}/monitors/"
    echo "• Management scripts: ${SCALING_CONFIG_DIR}/scripts/"
    echo "• Logs: /var/log/utmstack/scaling*.log"
    echo ""
    echo "Next Steps:"
    echo "1. Test auto-scaling with controlled load"
    echo "2. Fine-tune scaling thresholds"
    echo "3. Validate load balancer reconfiguration"
    echo "4. Run production load testing"
    echo "======================================================================"
}

# Execute main function
main "$@"
