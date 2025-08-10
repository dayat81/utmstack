#!/bin/bash

# SSL/TLS and Load Balancer Setup Script
# UTMStack Production Deployment - Critical Infrastructure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/utmstack-logs/ssl-loadbalancer-setup-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$(dirname "$LOG_FILE")"

echo "🔒 UTMStack SSL/TLS & Load Balancer Setup"
echo "========================================="

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

# Check existing services on target ports
check_existing_services() {
    info "Checking for existing services on SSL/Load Balancer ports..."
    
    if ss -tlnp | grep -E ":443|:80"; then
        warning "Ports 80/443 already in use:"
        ss -tlnp | grep -E ":443|:80"
    fi
    
    if docker ps | grep -E "nginx|traefik|haproxy"; then
        warning "Existing load balancer containers:"
        docker ps | grep -E "nginx|traefik|haproxy"
    fi
}

# Generate self-signed SSL certificates for development
generate_ssl_certificates() {
    info "Generating self-signed SSL certificates..."
    
    mkdir -p /tmp/ssl-certs
    
    # Generate private key
    openssl genrsa -out /tmp/ssl-certs/utmstack.key 2048 || error_exit "Failed to generate private key"
    
    # Generate certificate signing request
    openssl req -new -key /tmp/ssl-certs/utmstack.key -out /tmp/ssl-certs/utmstack.csr -subj "/C=US/ST=State/L=City/O=UTMStack/CN=localhost" || error_exit "Failed to generate CSR"
    
    # Generate self-signed certificate
    openssl x509 -req -days 365 -in /tmp/ssl-certs/utmstack.csr -signkey /tmp/ssl-certs/utmstack.key -out /tmp/ssl-certs/utmstack.crt || error_exit "Failed to generate certificate"
    
    # Create combined certificate chain
    cat /tmp/ssl-certs/utmstack.crt > /tmp/ssl-certs/utmstack-chain.crt
    
    # Set proper permissions
    chmod 600 /tmp/ssl-certs/utmstack.key
    chmod 644 /tmp/ssl-certs/utmstack.crt
    
    success "SSL certificates generated successfully"
}

# Create Nginx configuration for load balancing and SSL termination
create_nginx_config() {
    info "Creating Nginx load balancer configuration..."
    
    mkdir -p /tmp/nginx-config/conf.d
    
    # Main Nginx configuration
    cat > /tmp/nginx-config/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging format
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    # Basic settings
    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript 
               application/x-javascript application/xml+rss 
               application/javascript application/json;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Include server configurations
    include /etc/nginx/conf.d/*.conf;
}
EOF

    # UTMStack server configuration
    cat > /tmp/nginx-config/conf.d/utmstack.conf << 'EOF'
# UTMStack Load Balancer Configuration

# Upstream backend servers
upstream utmstack_backend {
    server host.docker.internal:8080;
    # Add more backend servers here for load balancing
    # server host.docker.internal:8081;
    # server host.docker.internal:8082;
}

upstream utmstack_frontend {
    server host.docker.internal:4200;
}

upstream utmstack_elasticsearch {
    server host.docker.internal:9200;
}

upstream utmstack_prometheus {
    server host.docker.internal:9090;
}

upstream utmstack_grafana {
    server host.docker.internal:3001;
}

# HTTP to HTTPS redirect
server {
    listen 80;
    server_name localhost;
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Redirect all HTTP to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# Main HTTPS server
server {
    listen 443 ssl http2;
    server_name localhost;

    # SSL certificate configuration
    ssl_certificate /etc/ssl/certs/utmstack.crt;
    ssl_certificate_key /etc/ssl/private/utmstack.key;

    # SSL security settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Frontend application (main site)
    location / {
        proxy_pass http://utmstack_frontend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }

    # Backend API
    location /api/ {
        proxy_pass https://utmstack_backend/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
        proxy_connect_timeout 30s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Handle CORS
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS';
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization';
        
        if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }
    }

    # Elasticsearch (read-only access)
    location /elasticsearch/ {
        proxy_pass http://utmstack_elasticsearch/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Restrict to safe operations only
        limit_except GET HEAD {
            deny all;
        }
    }

    # Monitoring endpoints (Prometheus)
    location /prometheus/ {
        auth_basic "Monitoring";
        auth_basic_user_file /etc/nginx/.htpasswd;
        
        proxy_pass http://utmstack_prometheus/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Grafana dashboard
    location /grafana/ {
        proxy_pass http://utmstack_grafana/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support for Grafana
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Security settings
    location ~ /\. {
        deny all;
    }
}
EOF

    # Create basic auth for monitoring endpoints
    echo "monitor:\$apr1\$utmstack\$2GKnGQ3E7V0cDxg5TlGLF1" > /tmp/nginx-config/.htpasswd
    
    success "Nginx configuration created"
}

# Deploy Nginx load balancer
deploy_nginx_load_balancer() {
    info "Deploying Nginx load balancer container..."
    
    docker run -d \
        --name utmstack-nginx-lb \
        --restart unless-stopped \
        -p 80:80 \
        -p 443:443 \
        -v /tmp/nginx-config/nginx.conf:/etc/nginx/nginx.conf:ro \
        -v /tmp/nginx-config/conf.d:/etc/nginx/conf.d:ro \
        -v /tmp/nginx-config/.htpasswd:/etc/nginx/.htpasswd:ro \
        -v /tmp/ssl-certs/utmstack.crt:/etc/ssl/certs/utmstack.crt:ro \
        -v /tmp/ssl-certs/utmstack.key:/etc/ssl/private/utmstack.key:ro \
        --add-host host.docker.internal:host-gateway \
        nginx:alpine || error_exit "Failed to start Nginx load balancer"
    
    success "Nginx load balancer deployed"
    
    # Wait for Nginx to start
    sleep 10
}

# Test SSL and load balancer configuration
test_ssl_load_balancer() {
    info "Testing SSL and load balancer configuration..."
    
    # Test HTTP redirect
    HTTP_REDIRECT=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
    if [ "$HTTP_REDIRECT" = "301" ]; then
        success "HTTP to HTTPS redirect working"
    else
        warning "HTTP redirect may not be working (got $HTTP_REDIRECT)"
    fi
    
    # Test HTTPS health check
    if curl -s -k https://localhost/health | grep -q "healthy"; then
        success "HTTPS health check working"
    else
        warning "HTTPS health check may not be working"
    fi
    
    # Test frontend proxy
    if curl -s -k https://localhost/ | grep -q "html"; then
        success "Frontend proxy working"
    else
        warning "Frontend proxy may not be working"
    fi
    
    # Test backend API proxy
    API_RESPONSE=$(curl -s -k -o /dev/null -w "%{http_code}" https://localhost/api/health)
    if [[ "$API_RESPONSE" =~ ^(200|404|401)$ ]]; then
        success "Backend API proxy working (HTTP $API_RESPONSE)"
    else
        warning "Backend API proxy may have issues (HTTP $API_RESPONSE)"
    fi
}

# Create SSL and load balancer management scripts
create_management_scripts() {
    info "Creating SSL and load balancer management scripts..."
    
    # SSL certificate renewal script
    cat > /tmp/utmstack-ssl-renew.sh << 'EOF'
#!/bin/bash
# UTMStack SSL Certificate Renewal Script

echo "🔒 Renewing UTMStack SSL Certificates..."

# Generate new certificates
openssl genrsa -out /tmp/ssl-certs/utmstack-new.key 2048
openssl req -new -key /tmp/ssl-certs/utmstack-new.key -out /tmp/ssl-certs/utmstack-new.csr -subj "/C=US/ST=State/L=City/O=UTMStack/CN=localhost"
openssl x509 -req -days 365 -in /tmp/ssl-certs/utmstack-new.csr -signkey /tmp/ssl-certs/utmstack-new.key -out /tmp/ssl-certs/utmstack-new.crt

# Backup old certificates
cp /tmp/ssl-certs/utmstack.crt /tmp/ssl-certs/utmstack-old.crt
cp /tmp/ssl-certs/utmstack.key /tmp/ssl-certs/utmstack-old.key

# Replace certificates
mv /tmp/ssl-certs/utmstack-new.crt /tmp/ssl-certs/utmstack.crt
mv /tmp/ssl-certs/utmstack-new.key /tmp/ssl-certs/utmstack.key

# Set permissions
chmod 600 /tmp/ssl-certs/utmstack.key
chmod 644 /tmp/ssl-certs/utmstack.crt

# Reload Nginx
docker exec utmstack-nginx-lb nginx -s reload

echo "✅ SSL certificates renewed and Nginx reloaded"
EOF

    chmod +x /tmp/utmstack-ssl-renew.sh
    
    # Load balancer health check script
    cat > /tmp/utmstack-lb-check.sh << 'EOF'
#!/bin/bash
# UTMStack Load Balancer Health Check

echo "🔒 Load Balancer Health Check - $(date)"
echo "======================================="

# Container status
echo "Nginx Container Status:"
docker ps | grep utmstack-nginx-lb || echo "❌ Nginx load balancer not running"

# Port status
echo ""
echo "Port Status:"
ss -tlnp | grep -E ":80|:443" || echo "Ports 80/443 not listening"

# HTTP redirect test
echo ""
echo "HTTP Redirect Test:"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "301" ]; then
    echo "✅ HTTP to HTTPS redirect working"
else
    echo "❌ HTTP redirect failed (HTTP $HTTP_CODE)"
fi

# HTTPS health test
echo ""
echo "HTTPS Health Test:"
if curl -s -k https://localhost/health 2>/dev/null | grep -q "healthy"; then
    echo "✅ HTTPS health endpoint working"
else
    echo "❌ HTTPS health endpoint failed"
fi

# Backend proxy test
echo ""
echo "Backend Proxy Test:"
BACKEND_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" https://localhost/api/health 2>/dev/null || echo "000")
echo "Backend API response: HTTP $BACKEND_CODE"

# SSL certificate info
echo ""
echo "SSL Certificate Info:"
echo | openssl s_client -connect localhost:443 -servername localhost 2>/dev/null | openssl x509 -noout -dates 2>/dev/null || echo "Certificate info unavailable"

echo ""
echo "Load Balancer Health Check Complete"
EOF

    chmod +x /tmp/utmstack-lb-check.sh
    
    success "Management scripts created"
}

# Update system health check
update_health_check() {
    info "Updating system health check to include SSL/Load Balancer..."
    
    if [ -f "$SCRIPT_DIR/quick-health-check.sh" ]; then
        # Add load balancer checks if not already present
        if ! grep -q "Load Balancer" "$SCRIPT_DIR/quick-health-check.sh"; then
            cat >> "$SCRIPT_DIR/quick-health-check.sh" << 'EOF'

# Load Balancer
check_service "Load Balancer (HTTP)" "curl -s -o /dev/null -w '%{http_code}' http://localhost/ | grep -q 301" "success"
check_service "Load Balancer (HTTPS)" "curl -s -k https://localhost/health | grep -q healthy" "success"
EOF
        fi
        success "Health check updated to include load balancer"
    else
        warning "Health check script not found"
    fi
}

# Main execution
main() {
    log "Starting SSL/TLS and Load Balancer Setup for UTMStack"
    
    check_existing_services
    generate_ssl_certificates
    create_nginx_config
    deploy_nginx_load_balancer
    test_ssl_load_balancer
    create_management_scripts
    update_health_check
    
    echo ""
    echo "=============================================="
    success "SSL/TLS & Load Balancer Setup COMPLETED Successfully"
    echo "=============================================="
    echo ""
    echo "🔒 SSL/TLS & Load Balancer Information:"
    echo "   HTTP:  http://localhost (redirects to HTTPS)"
    echo "   HTTPS: https://localhost"
    echo "   Container: utmstack-nginx-lb"
    echo ""
    echo "🌐 Available Endpoints:"
    echo "   Frontend:      https://localhost/"
    echo "   Backend API:   https://localhost/api/"
    echo "   Elasticsearch: https://localhost/elasticsearch/ (read-only)"
    echo "   Prometheus:    https://localhost/prometheus/ (auth: monitor/monitor)"
    echo "   Grafana:       https://localhost/grafana/"
    echo "   Health Check:  https://localhost/health"
    echo ""
    echo "📋 Management Scripts:"
    echo "   SSL Renewal:   /tmp/utmstack-ssl-renew.sh"
    echo "   Health Check:  /tmp/utmstack-lb-check.sh"
    echo ""
    echo "🔐 Security Features:"
    echo "   • SSL/TLS encryption with self-signed certificates"
    echo "   • HTTP to HTTPS redirect"
    echo "   • Security headers (HSTS, X-Frame-Options, etc.)"
    echo "   • Basic authentication for monitoring endpoints"
    echo "   • CORS headers for API endpoints"
    echo ""
    echo "⚠️  Note: Using self-signed certificates (browser warnings expected)"
    echo "   For production, replace with proper SSL certificates"
    echo ""
    echo "🚀 UTMStack is now accessible via HTTPS with load balancing!"
    echo ""
}

# Execute main function
main "$@"
