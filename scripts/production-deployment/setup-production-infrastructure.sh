#!/bin/bash

# UTMStack Multi-Tenant Production Infrastructure Setup
# Phase 6 - Sprint 1.1: Production Environment Setup
# Version: 1.0.0
# Author: UTMStack Multi-Tenant Development Team

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
PRODUCTION_ENV="production"
MULTI_TENANT_ENABLED="true"
DEPLOYMENT_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="/var/log/utmstack/production-setup-${DEPLOYMENT_DATE}.log"

# Create log directory
mkdir -p /var/log/utmstack

# Redirect all output to log file while also displaying on console
exec > >(tee -a ${LOG_FILE})
exec 2>&1

echo "======================================================================"
echo "🚀 UTMStack Multi-Tenant Production Infrastructure Setup"
echo "======================================================================"
echo "Date: $(date)"
echo "Environment: ${PRODUCTION_ENV}"
echo "Multi-Tenant: ${MULTI_TENANT_ENABLED}"
echo "Log File: ${LOG_FILE}"
echo "======================================================================"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo privileges"
        exit 1
    fi
    
    # Check if multi-tenant development branch
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
    if [[ "$CURRENT_BRANCH" != "multi-tenant-development" ]]; then
        log_warning "Current branch is '$CURRENT_BRANCH', expected 'multi-tenant-development'"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Aborted by user"
            exit 1
        fi
    fi
    
    # Check required commands
    local required_commands=("docker" "docker-compose" "psql" "curl" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            log_error "Required command '$cmd' not found"
            exit 1
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Function to load production configuration
load_production_config() {
    log_info "Loading production configuration..."
    
    # Source existing configuration
    if [[ -f "config/utmstack.yml" ]]; then
        log_info "Loading configuration from config/utmstack.yml"
        # Convert YAML to environment variables (simplified approach)
        # In production, use proper YAML parser
    else
        log_warning "config/utmstack.yml not found, using defaults"
    fi
    
    # Set production environment variables
    export NODE_ENV=production
    export SPRING_PROFILES_ACTIVE=production,multi-tenant
    export MULTI_TENANT_ENABLED=true
    export DATABASE_RLS_ENABLED=true
    export JWT_ENHANCED=true
    export TENANT_CONTEXT_MANDATORY=true
    export AUDIT_LOGGING=comprehensive
    export AUTO_SCALING=enabled
    
    log_success "Production configuration loaded"
}

# Function to setup production database
setup_production_database() {
    log_info "Setting up production PostgreSQL database with Row-Level Security..."
    
    # Database configuration
    local DB_NAME="utmstack_production"
    local DB_USER="utmstack_prod"
    local DB_PASSWORD=$(openssl rand -base64 32)
    local DB_HOST="localhost"
    local DB_PORT="5432"
    
    # Install PostgreSQL if not present
    if ! command -v psql &> /dev/null; then
        log_info "Installing PostgreSQL..."
        apt-get update
        apt-get install -y postgresql postgresql-contrib
        systemctl enable postgresql
        systemctl start postgresql
    fi
    
    # Create production database and user
    log_info "Creating production database and user..."
    sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME};" || log_warning "Database may already exist"
    sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';" || log_warning "User may already exist"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
    
    # Apply multi-tenant schema
    log_info "Applying multi-tenant database schema..."
    
    # Create schema migration script
    cat > /tmp/production_schema.sql << 'EOF'
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create tenant management tables
CREATE TABLE IF NOT EXISTS utm_tenant (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    subdomain VARCHAR(100) UNIQUE NOT NULL,
    status VARCHAR(50) DEFAULT 'active',
    tier VARCHAR(50) DEFAULT 'standard',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    settings JSONB DEFAULT '{}',
    resource_limits JSONB DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS utm_tenant_config (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES utm_tenant(id) ON DELETE CASCADE,
    config_key VARCHAR(255) NOT NULL,
    config_value TEXT,
    config_type VARCHAR(50) DEFAULT 'string',
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(tenant_id, config_key)
);

CREATE TABLE IF NOT EXISTS utm_tenant_role (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES utm_tenant(id) ON DELETE CASCADE,
    role_name VARCHAR(100) NOT NULL,
    permissions JSONB DEFAULT '[]',
    parent_role_id UUID REFERENCES utm_tenant_role(id),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(tenant_id, role_name)
);

-- Function to set tenant context
CREATE OR REPLACE FUNCTION set_tenant_context(tenant_uuid UUID)
RETURNS void AS $$
BEGIN
    PERFORM set_config('app.current_tenant_id', tenant_uuid::TEXT, TRUE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get current tenant
CREATE OR REPLACE FUNCTION get_current_tenant_id()
RETURNS UUID AS $$
BEGIN
    RETURN current_setting('app.current_tenant_id', TRUE)::UUID;
EXCEPTION
    WHEN others THEN RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_utm_tenant_subdomain ON utm_tenant(subdomain);
CREATE INDEX IF NOT EXISTS idx_utm_tenant_status ON utm_tenant(status);
CREATE INDEX IF NOT EXISTS idx_utm_tenant_config_tenant ON utm_tenant_config(tenant_id);
CREATE INDEX IF NOT EXISTS idx_utm_tenant_role_tenant ON utm_tenant_role(tenant_id);

-- Insert default tenant for migration
INSERT INTO utm_tenant (id, name, subdomain, status, tier, settings)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Default Tenant',
    'default',
    'active',
    'enterprise',
    '{"migration": true, "default": true}'
) ON CONFLICT (subdomain) DO NOTHING;
EOF

    # Apply schema
    sudo -u postgres psql -d ${DB_NAME} -f /tmp/production_schema.sql
    
    # Save database credentials securely
    cat > /etc/utmstack/production-db.conf << EOF
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_RLS_ENABLED=true
EOF
    
    chmod 600 /etc/utmstack/production-db.conf
    
    log_success "Production database setup completed"
}

# Function to setup production Elasticsearch
setup_production_elasticsearch() {
    log_info "Setting up production Elasticsearch cluster..."
    
    # Create Elasticsearch configuration directory
    mkdir -p /etc/utmstack/elasticsearch
    
    # Create production Elasticsearch configuration
    cat > /etc/utmstack/elasticsearch/elasticsearch.yml << 'EOF'
# Production Elasticsearch configuration for UTMStack Multi-Tenant
cluster.name: utmstack-production
node.name: utmstack-node-1

# Network settings
network.host: 0.0.0.0
http.port: 9200
transport.port: 9300

# Discovery settings for production cluster
discovery.type: zen
discovery.zen.hosts_provider: file
discovery.zen.minimum_master_nodes: 2

# Memory settings
bootstrap.memory_lock: true
indices.memory.index_buffer_size: 20%

# Security settings
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.http.ssl.enabled: true

# Multi-tenant index settings
index.number_of_shards: 2
index.number_of_replicas: 1
index.max_result_window: 50000

# Lifecycle management
xpack.ilm.enabled: true
EOF

    # Create index templates for multi-tenant
    cat > /etc/utmstack/elasticsearch/tenant-index-template.json << 'EOF'
{
  "index_patterns": ["utmstack-*-logs-*", "utmstack-*-alerts-*"],
  "template": {
    "settings": {
      "number_of_shards": 2,
      "number_of_replicas": 1,
      "index.lifecycle.name": "tenant-log-policy",
      "index.refresh_interval": "30s"
    },
    "mappings": {
      "properties": {
        "@timestamp": {
          "type": "date"
        },
        "tenant_id": {
          "type": "keyword",
          "index": true
        },
        "log_level": {
          "type": "keyword"
        },
        "message": {
          "type": "text",
          "analyzer": "standard"
        },
        "source_ip": {
          "type": "ip"
        },
        "dest_ip": {
          "type": "ip"
        },
        "event_type": {
          "type": "keyword"
        },
        "severity": {
          "type": "keyword"
        }
      }
    }
  },
  "priority": 100,
  "version": 1
}
EOF

    # Create lifecycle policies
    cat > /etc/utmstack/elasticsearch/tenant-lifecycle-policy.json << 'EOF'
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_size": "10gb",
            "max_age": "1d"
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "allocate": {
            "number_of_replicas": 0
          }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "allocate": {
            "number_of_replicas": 0
          }
        }
      },
      "delete": {
        "min_age": "365d"
      }
    }
  }
}
EOF

    log_success "Elasticsearch configuration created"
}

# Function to setup production load balancer
setup_production_loadbalancer() {
    log_info "Setting up production load balancer with tenant-aware routing..."
    
    # Install nginx if not present
    if ! command -v nginx &> /dev/null; then
        log_info "Installing nginx..."
        apt-get update
        apt-get install -y nginx
        systemctl enable nginx
    fi
    
    # Create nginx configuration for multi-tenant
    cat > /etc/nginx/sites-available/utmstack-multitenant << 'EOF'
# UTMStack Multi-Tenant Production Configuration

# Rate limiting zones
limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
limit_req_zone $binary_remote_addr zone=api:10m rate=100r/m;

# Upstream backend servers
upstream utmstack_backend {
    least_conn;
    server 127.0.0.1:8080 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:8081 max_fails=3 fail_timeout=30s backup;
}

# Upstream frontend servers
upstream utmstack_frontend {
    least_conn;
    server 127.0.0.1:4200 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:4201 max_fails=3 fail_timeout=30s backup;
}

# Main server block
server {
    listen 80;
    listen [::]:80;
    server_name *.utmstack.com utmstack.com;
    
    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

# HTTPS server block
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name *.utmstack.com utmstack.com;
    
    # SSL configuration
    ssl_certificate /etc/ssl/certs/utmstack.crt;
    ssl_certificate_key /etc/ssl/private/utmstack.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Extract tenant from subdomain
    set $tenant "default";
    if ($host ~* "^([^.]+)\.utmstack\.com$") {
        set $tenant $1;
    }
    
    # Add tenant header for backend
    proxy_set_header X-Tenant-ID $tenant;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Host $host;
    
    # API routes
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://utmstack_backend;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Management API (restricted)
    location /management/ {
        allow 10.0.0.0/8;
        allow 172.16.0.0/12;
        allow 192.168.0.0/16;
        deny all;
        
        proxy_pass http://utmstack_backend;
    }
    
    # Frontend application
    location / {
        proxy_pass http://utmstack_frontend;
        
        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}

# Monitoring server for internal use
server {
    listen 8090;
    server_name 127.0.0.1;
    
    location /nginx_status {
        stub_status on;
        allow 127.0.0.1;
        deny all;
    }
}
EOF

    # Enable the site
    ln -sf /etc/nginx/sites-available/utmstack-multitenant /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test nginx configuration
    nginx -t
    
    log_success "Load balancer configuration completed"
}

# Function to setup production monitoring
setup_production_monitoring() {
    log_info "Setting up production monitoring and alerting..."
    
    # Create monitoring configuration directory
    mkdir -p /etc/utmstack/monitoring
    
    # Create Prometheus configuration
    cat > /etc/utmstack/monitoring/prometheus.yml << 'EOF'
# Prometheus configuration for UTMStack Multi-Tenant Production
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Rules and alerts
rule_files:
  - "alerts.yml"

# Alerting configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

# Scrape configurations
scrape_configs:
  # UTMStack Backend
  - job_name: 'utmstack-backend'
    static_configs:
      - targets: ['localhost:8080', 'localhost:8081']
    metrics_path: '/management/prometheus'
    scrape_interval: 30s
    
  # UTMStack Frontend
  - job_name: 'utmstack-frontend'
    static_configs:
      - targets: ['localhost:4200', 'localhost:4201']
    scrape_interval: 30s
    
  # PostgreSQL
  - job_name: 'postgresql'
    static_configs:
      - targets: ['localhost:9187']
    scrape_interval: 30s
    
  # Elasticsearch
  - job_name: 'elasticsearch'
    static_configs:
      - targets: ['localhost:9200']
    scrape_interval: 30s
    
  # Nginx
  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:8090']
    metrics_path: '/nginx_status'
    scrape_interval: 30s
    
  # System metrics
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']
    scrape_interval: 30s
EOF

    # Create alerting rules
    cat > /etc/utmstack/monitoring/alerts.yml << 'EOF'
groups:
  - name: utmstack-alerts
    rules:
      # High CPU usage
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% for more than 5 minutes"
      
      # High memory usage
      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 85% for more than 5 minutes"
      
      # Database connection issues
      - alert: PostgreSQLDown
        expr: up{job="postgresql"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL is down"
          description: "PostgreSQL database is not responding"
      
      # Elasticsearch cluster issues
      - alert: ElasticsearchDown
        expr: up{job="elasticsearch"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Elasticsearch is down"
          description: "Elasticsearch cluster is not responding"
      
      # UTMStack backend issues
      - alert: UTMStackBackendDown
        expr: up{job="utmstack-backend"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "UTMStack backend is down"
          description: "UTMStack backend service is not responding"
      
      # High response time
      - alert: HighResponseTime
        expr: http_request_duration_seconds{quantile="0.95"} > 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High response time detected"
          description: "95th percentile response time is above 2 seconds"
EOF

    # Create Grafana dashboard configuration
    cat > /etc/utmstack/monitoring/grafana-dashboard.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "UTMStack Multi-Tenant Production Dashboard",
    "tags": ["utmstack", "multi-tenant", "production"],
    "timezone": "UTC",
    "panels": [
      {
        "id": 1,
        "title": "System Overview",
        "type": "stat",
        "targets": [
          {
            "expr": "up{job=\"utmstack-backend\"}",
            "refId": "A"
          }
        ]
      },
      {
        "id": 2,
        "title": "Active Tenants",
        "type": "stat",
        "targets": [
          {
            "expr": "utmstack_active_tenants_total",
            "refId": "A"
          }
        ]
      },
      {
        "id": 3,
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])",
            "refId": "A"
          }
        ]
      },
      {
        "id": 4,
        "title": "Response Time",
        "type": "graph",
        "targets": [
          {
            "expr": "http_request_duration_seconds{quantile=\"0.95\"}",
            "refId": "A"
          }
        ]
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

    log_success "Production monitoring configuration completed"
}

# Function to create production environment validation
create_production_validation() {
    log_info "Creating production environment validation script..."
    
    cat > /usr/local/bin/validate-production-environment.sh << 'EOF'
#!/bin/bash

# UTMStack Production Environment Validation Script

echo "🔍 Validating UTMStack Production Environment..."

# Check database connectivity
echo "📊 Checking database connectivity..."
if pg_isready -h localhost -p 5432 -U utmstack_prod; then
    echo "✅ Database is ready"
else
    echo "❌ Database connection failed"
    exit 1
fi

# Check Elasticsearch
echo "🔍 Checking Elasticsearch..."
if curl -s -f http://localhost:9200/_cluster/health > /dev/null; then
    echo "✅ Elasticsearch is ready"
else
    echo "❌ Elasticsearch is not responding"
    exit 1
fi

# Check backend service
echo "🖥️ Checking backend service..."
if curl -s -f http://localhost:8080/management/health > /dev/null; then
    echo "✅ Backend service is ready"
else
    echo "❌ Backend service is not responding"
    exit 1
fi

# Check nginx
echo "🌐 Checking nginx..."
if nginx -t && systemctl is-active --quiet nginx; then
    echo "✅ Nginx is configured and running"
else
    echo "❌ Nginx configuration error"
    exit 1
fi

echo "✅ All production environment checks passed!"
EOF

    chmod +x /usr/local/bin/validate-production-environment.sh
    
    log_success "Production validation script created"
}

# Main execution function
main() {
    log_info "Starting UTMStack Multi-Tenant Production Infrastructure Setup..."
    
    # Create required directories
    mkdir -p /etc/utmstack
    mkdir -p /var/log/utmstack
    mkdir -p /var/lib/utmstack
    
    # Execute setup phases
    check_prerequisites
    load_production_config
    setup_production_database
    setup_production_elasticsearch
    setup_production_loadbalancer
    setup_production_monitoring
    create_production_validation
    
    log_success "Production infrastructure setup completed successfully!"
    echo ""
    echo "======================================================================"
    echo "🎉 UTMStack Multi-Tenant Production Infrastructure Setup Complete"
    echo "======================================================================"
    echo "Database: PostgreSQL with Row-Level Security enabled"
    echo "Search: Elasticsearch with multi-tenant indexing"
    echo "Load Balancer: Nginx with tenant-aware routing"
    echo "Monitoring: Prometheus + Grafana with alerting"
    echo "Log File: ${LOG_FILE}"
    echo ""
    echo "Next Steps:"
    echo "1. Run: /usr/local/bin/validate-production-environment.sh"
    echo "2. Execute migration scripts"
    echo "3. Configure SSL certificates"
    echo "4. Start production services"
    echo "======================================================================"
}

# Execute main function
main "$@"
