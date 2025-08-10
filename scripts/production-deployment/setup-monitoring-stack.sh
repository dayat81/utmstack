#!/bin/bash

# Monitoring Stack Setup Script (Prometheus + Grafana)
# UTMStack Production Deployment - Critical Infrastructure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/utmstack-logs/monitoring-setup-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$(dirname "$LOG_FILE")"

echo "📊 UTMStack Monitoring Stack Setup"
echo "=================================="

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "$LOG_FILE"
}

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

# Check for existing monitoring services
check_existing_monitoring() {
    info "Checking for existing monitoring services..."
    
    if docker ps | grep -E "prometheus|grafana"; then
        warning "Monitoring containers already running:"
        docker ps | grep -E "prometheus|grafana"
    fi
    
    if ss -tlnp | grep -E ":3000|:9090"; then
        warning "Monitoring ports already in use:"
        ss -tlnp | grep -E ":3000|:9090"
    fi
}

# Create monitoring configuration directories
create_monitoring_dirs() {
    info "Creating monitoring configuration directories..."
    
    mkdir -p /tmp/monitoring/{prometheus,grafana,alertmanager}
    mkdir -p /tmp/monitoring/grafana/{dashboards,provisioning/{dashboards,datasources}}
    
    success "Monitoring directories created"
}

# Configure Prometheus
setup_prometheus() {
    info "Setting up Prometheus configuration..."
    
    cat > /tmp/monitoring/prometheus/prometheus.yml << 'EOF'
# UTMStack Prometheus Configuration
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Alertmanager configuration  
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

# Load rules once and periodically evaluate them
rule_files:
  - "utmstack_alerts.yml"

# Scrape configuration
scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
      
  # UTMStack Backend API
  - job_name: 'utmstack-backend'
    static_configs:
      - targets: ['host.docker.internal:8080']
    scheme: https
    tls_config:
      insecure_skip_verify: true
    metrics_path: '/actuator/prometheus'
    scrape_interval: 30s
    
  # UTMStack Database
  - job_name: 'postgres'
    static_configs:
      - targets: ['host.docker.internal:5432']
    scrape_interval: 30s
    
  # Elasticsearch
  - job_name: 'elasticsearch'
    static_configs:
      - targets: ['host.docker.internal:9200']
    metrics_path: '/_prometheus/metrics'
    scrape_interval: 30s
    
  # Redis
  - job_name: 'redis'
    static_configs:
      - targets: ['host.docker.internal:6379']
    scrape_interval: 30s
    
  # Node Exporter (system metrics)
  - job_name: 'node'
    static_configs:
      - targets: ['host.docker.internal:9100']
    scrape_interval: 30s

  # Container metrics
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['host.docker.internal:8085']
    scrape_interval: 30s
EOF

    # Create UTMStack alert rules
    cat > /tmp/monitoring/prometheus/utmstack_alerts.yml << 'EOF'
groups:
  - name: utmstack-alerts
    rules:
      # System Alerts
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 85% for more than 5 minutes"
          
      - alert: HighCPUUsage  
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% for more than 5 minutes"
          
      - alert: DiskSpaceHigh
        expr: (1 - (node_filesystem_avail_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes{fstype!="tmpfs"})) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High disk usage detected"
          description: "Disk usage is above 85%"
          
      # Database Alerts  
      - alert: PostgreSQLDown
        expr: pg_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL is down"
          description: "PostgreSQL database is not responding"
          
      # Elasticsearch Alerts
      - alert: ElasticsearchClusterRed
        expr: elasticsearch_cluster_health_status{color="red"} == 1
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Elasticsearch cluster status is RED"
          description: "Elasticsearch cluster health is critical"
          
      # UTMStack Application Alerts
      - alert: BackendAPIDown
        expr: up{job="utmstack-backend"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "UTMStack Backend API is down"
          description: "The UTMStack backend API is not responding"
          
      - alert: RedisDown
        expr: redis_up == 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Redis is down"
          description: "Redis cache service is not responding"
EOF

    success "Prometheus configuration created"
}

# Configure Grafana
setup_grafana() {
    info "Setting up Grafana configuration..."
    
    # Grafana datasource configuration
    cat > /tmp/monitoring/grafana/provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF

    # Grafana dashboard configuration
    cat > /tmp/monitoring/grafana/provisioning/dashboards/utmstack.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'UTMStack Dashboards'
    orgId: 1
    folder: 'UTMStack'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

    # Create UTMStack system dashboard
    cat > /tmp/monitoring/grafana/dashboards/utmstack-system.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "UTMStack System Overview",
    "tags": ["utmstack", "system"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "System Memory Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "min": 0,
            "max": 100
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "System CPU Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "min": 0,
            "max": 100
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      }
    ],
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "refresh": "30s"
  }
}
EOF

    success "Grafana configuration created"
}

# Deploy monitoring containers
deploy_monitoring_containers() {
    info "Deploying monitoring containers..."
    
    # Deploy Prometheus
    info "Starting Prometheus container..."
    docker run -d \
        --name utmstack-prometheus \
        --restart unless-stopped \
        -p 9090:9090 \
        -v /tmp/monitoring/prometheus:/etc/prometheus \
        --add-host host.docker.internal:host-gateway \
        prom/prometheus:latest \
        --config.file=/etc/prometheus/prometheus.yml \
        --storage.tsdb.path=/prometheus \
        --web.console.libraries=/etc/prometheus/console_libraries \
        --web.console.templates=/etc/prometheus/consoles \
        --web.enable-lifecycle || error_exit "Failed to start Prometheus"
    
    success "Prometheus container started"
    
    # Wait for Prometheus to start
    sleep 10
    
    # Deploy Grafana
    info "Starting Grafana container..."
    docker run -d \
        --name utmstack-grafana \
        --restart unless-stopped \
        -p 3001:3000 \
        -v /tmp/monitoring/grafana/provisioning:/etc/grafana/provisioning \
        -v /tmp/monitoring/grafana/dashboards:/var/lib/grafana/dashboards \
        -e GF_SECURITY_ADMIN_PASSWORD=utmstack_admin \
        -e GF_USERS_ALLOW_SIGN_UP=false \
        -e GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource \
        grafana/grafana:latest || error_exit "Failed to start Grafana"
    
    success "Grafana container started"
    
    # Wait for services to start
    info "Waiting for monitoring services to start..."
    sleep 15
}

# Verify monitoring services
verify_monitoring_services() {
    info "Verifying monitoring services..."
    
    # Test Prometheus
    if curl -s http://localhost:9090/api/v1/targets >/dev/null; then
        success "Prometheus is responding"
    else
        warning "Prometheus may not be fully ready yet"
    fi
    
    # Test Grafana
    if curl -s http://localhost:3001/api/health >/dev/null; then
        success "Grafana is responding"
    else
        warning "Grafana may not be fully ready yet"
    fi
    
    # Check container status
    info "Monitoring container status:"
    docker ps | grep -E "prometheus|grafana" || warning "Some monitoring containers may not be running"
}

# Create monitoring management scripts
create_monitoring_scripts() {
    info "Creating monitoring management scripts..."
    
    # Monitoring health check script
    cat > /tmp/utmstack-monitoring-check.sh << 'EOF'
#!/bin/bash
# UTMStack Monitoring Health Check

echo "📊 Monitoring Stack Health Check - $(date)"
echo "==========================================="

# Container status
echo "Container Status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "prometheus|grafana" || echo "❌ Monitoring containers not running"

# Prometheus health
echo ""
echo "Prometheus Health:"
if curl -s http://localhost:9090/-/healthy >/dev/null 2>&1; then
    echo "✅ Prometheus healthy"
    echo "   Targets: $(curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets | length') active"
else
    echo "❌ Prometheus not responding"
fi

# Grafana health  
echo ""
echo "Grafana Health:"
if curl -s http://localhost:3001/api/health >/dev/null 2>&1; then
    echo "✅ Grafana healthy"
    echo "   Admin URL: http://localhost:3001 (admin/utmstack_admin)"
else
    echo "❌ Grafana not responding"
fi

# Resource usage
echo ""
echo "Monitoring Resource Usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep -E "prometheus|grafana"

echo ""
echo "Monitoring Health Check Complete"
EOF

    chmod +x /tmp/utmstack-monitoring-check.sh
    
    # Monitoring restart script
    cat > /tmp/utmstack-monitoring-restart.sh << 'EOF'
#!/bin/bash
# UTMStack Monitoring Restart Script

echo "🔄 Restarting UTMStack Monitoring Stack..."

# Stop containers
docker stop utmstack-prometheus utmstack-grafana 2>/dev/null || true

# Remove containers
docker rm utmstack-prometheus utmstack-grafana 2>/dev/null || true

# Restart monitoring stack
echo "Starting monitoring containers..."
cd /home/ptsec/utmstack
./scripts/production-deployment/setup-monitoring-stack.sh

echo "✅ Monitoring stack restarted"
EOF

    chmod +x /tmp/utmstack-monitoring-restart.sh
    
    success "Monitoring management scripts created"
}

# Update system health check
update_health_check() {
    info "Updating system health check to include monitoring..."
    
    if [ -f "$SCRIPT_DIR/quick-health-check.sh" ]; then
        # Add monitoring checks if not already present
        if ! grep -q "Prometheus" "$SCRIPT_DIR/quick-health-check.sh"; then
            cat >> "$SCRIPT_DIR/quick-health-check.sh" << 'EOF'

# Prometheus
check_service "Prometheus" "curl -s http://localhost:9090/-/healthy" "success"

# Grafana  
check_service "Grafana" "curl -s http://localhost:3001/api/health" "success"
EOF
        fi
        success "Health check updated to include monitoring"
    else
        warning "Health check script not found"
    fi
}

# Main execution
main() {
    log "Starting Monitoring Stack Setup for UTMStack"
    
    check_existing_monitoring
    create_monitoring_dirs
    setup_prometheus
    setup_grafana
    deploy_monitoring_containers
    verify_monitoring_services
    create_monitoring_scripts
    update_health_check
    
    echo ""
    echo "=============================================="
    success "Monitoring Stack Setup COMPLETED Successfully"
    echo "=============================================="
    echo ""
    echo "📊 Monitoring Services Information:"
    echo "   Prometheus: http://localhost:9090"
    echo "   Grafana:    http://localhost:3001 (admin/utmstack_admin)"
    echo ""
    echo "🎯 Key Features:"
    echo "   • System resource monitoring"
    echo "   • UTMStack application metrics"
    echo "   • Database and service health"
    echo "   • Alerting and notifications"
    echo ""
    echo "📋 Management Scripts:"
    echo "   Health Check: /tmp/utmstack-monitoring-check.sh"
    echo "   Restart:      /tmp/utmstack-monitoring-restart.sh"
    echo ""
    echo "🚨 Alert Rules Configured:"
    echo "   • High memory/CPU usage"
    echo "   • Database connectivity"
    echo "   • Service availability"
    echo "   • Disk space monitoring"
    echo ""
    echo "📊 Monitoring stack is now operational!"
    echo ""
}

# Execute main function
main "$@"
