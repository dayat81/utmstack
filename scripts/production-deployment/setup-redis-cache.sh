#!/bin/bash

# Redis Cache Setup Script
# UTMStack Production Deployment - Critical Infrastructure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/utmstack-logs/redis-setup-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$(dirname "$LOG_FILE")"

echo "🔴 UTMStack Redis Cache Setup"
echo "============================="

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

# Check if Redis is already running
check_existing_redis() {
    info "Checking for existing Redis installation..."
    
    if docker ps | grep -q redis; then
        warning "Redis container already running"
        docker ps | grep redis
        return 0
    fi
    
    if ss -tlnp | grep -q :6379; then
        warning "Something is already running on Redis port 6379"
        ss -tlnp | grep :6379
        return 0
    fi
    
    info "No existing Redis installation found"
    return 1
}

# Deploy Redis container
deploy_redis_container() {
    info "Deploying Redis container..."
    
    # Create Redis configuration
    mkdir -p /tmp/redis-config
    
    cat > /tmp/redis-config/redis.conf << 'EOF'
# UTMStack Redis Configuration
port 6379
bind 0.0.0.0
protected-mode yes
requirepass utmstack_redis_pass
timeout 300
tcp-keepalive 300

# Memory management
maxmemory 512mb
maxmemory-policy allkeys-lru

# Persistence
save 900 1
save 300 10
save 60 10000

# Logging
loglevel notice

# Security
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command SHUTDOWN SHUTDOWN_UTM

# Performance
timeout 0
tcp-keepalive 60
databases 16
EOF

    # Deploy Redis container
    info "Starting Redis container with UTMStack configuration..."
    
    docker run -d \
        --name utmstack-redis \
        --restart unless-stopped \
        -p 6379:6379 \
        -v /tmp/redis-config/redis.conf:/usr/local/etc/redis/redis.conf \
        redis:7-alpine \
        redis-server /usr/local/etc/redis/redis.conf || error_exit "Failed to start Redis container"
    
    success "Redis container deployed successfully"
    
    # Wait for Redis to start
    info "Waiting for Redis to start..."
    sleep 5
    
    # Test Redis connection
    if docker exec utmstack-redis redis-cli -a utmstack_redis_pass ping | grep -q PONG; then
        success "Redis is responding to ping"
    else
        error_exit "Redis is not responding"
    fi
}

# Configure Redis for UTMStack
configure_redis_utmstack() {
    info "Configuring Redis for UTMStack integration..."
    
    # Create Redis databases for different UTMStack components
    docker exec utmstack-redis redis-cli -a utmstack_redis_pass << 'EOF'
SELECT 0
SET utmstack:setup:redis "configured"
SET utmstack:setup:timestamp "$(date)"

SELECT 1
SET utmstack:sessions:config "enabled"

SELECT 2  
SET utmstack:cache:config "enabled"

SELECT 3
SET utmstack:correlation:config "enabled"

SELECT 0
BGSAVE
EOF

    success "Redis configured for UTMStack components"
}

# Create Redis monitoring script
create_redis_monitoring() {
    info "Creating Redis monitoring script..."
    
    cat > /tmp/utmstack-redis-monitor.sh << 'EOF'
#!/bin/bash
# UTMStack Redis Monitoring Script

echo "🔴 Redis Health Check - $(date)"
echo "================================="

# Container status
echo "Container Status:"
docker ps | grep utmstack-redis || echo "❌ Redis container not running"

# Redis ping test
echo ""
echo "Redis Connectivity:"
if docker exec utmstack-redis redis-cli -a utmstack_redis_pass ping 2>/dev/null | grep -q PONG; then
    echo "✅ Redis responding to ping"
else
    echo "❌ Redis not responding"
fi

# Memory usage
echo ""
echo "Redis Memory Usage:"
docker exec utmstack-redis redis-cli -a utmstack_redis_pass INFO memory 2>/dev/null | grep -E "used_memory_human|maxmemory_human" || echo "Memory info unavailable"

# Key statistics
echo ""
echo "Redis Key Statistics:"  
docker exec utmstack-redis redis-cli -a utmstack_redis_pass INFO keyspace 2>/dev/null || echo "Keyspace info unavailable"

# Connection info
echo ""
echo "Redis Connections:"
docker exec utmstack-redis redis-cli -a utmstack_redis_pass INFO clients 2>/dev/null | grep connected_clients || echo "Connection info unavailable"

echo ""
echo "Redis Health Check Complete"
EOF

    chmod +x /tmp/utmstack-redis-monitor.sh
    success "Redis monitoring script created: /tmp/utmstack-redis-monitor.sh"
}

# Create Redis backup script
create_redis_backup() {
    info "Creating Redis backup script..."
    
    cat > /tmp/utmstack-redis-backup.sh << 'EOF'
#!/bin/bash
# UTMStack Redis Backup Script

BACKUP_DIR="/tmp/redis-backups"
mkdir -p "$BACKUP_DIR"

BACKUP_FILE="$BACKUP_DIR/redis-backup-$(date +%Y%m%d-%H%M%S).rdb"

echo "🔴 Creating Redis backup..."
echo "Backup file: $BACKUP_FILE"

# Force a save
docker exec utmstack-redis redis-cli -a utmstack_redis_pass BGSAVE

# Wait for background save to complete
sleep 3

# Copy the RDB file
docker cp utmstack-redis:/data/dump.rdb "$BACKUP_FILE"

if [ -f "$BACKUP_FILE" ]; then
    echo "✅ Backup created successfully: $BACKUP_FILE"
    echo "Backup size: $(ls -lh "$BACKUP_FILE" | awk '{print $5}')"
else
    echo "❌ Backup failed"
    exit 1
fi

# Keep only last 5 backups
cd "$BACKUP_DIR"
ls -t redis-backup-*.rdb | tail -n +6 | xargs -r rm

echo "Backup retention: Keeping last 5 backups"
echo "Available backups:"
ls -la redis-backup-*.rdb 2>/dev/null || echo "No backups found"
EOF

    chmod +x /tmp/utmstack-redis-backup.sh
    success "Redis backup script created: /tmp/utmstack-redis-backup.sh"
}

# Integrate Redis with UTMStack services
integrate_with_utmstack() {
    info "Creating UTMStack Redis integration configuration..."
    
    # Create Redis connection configuration for UTMStack services
    cat > /tmp/utmstack-redis-config.env << 'EOF'
# UTMStack Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=utmstack_redis_pass

# Database assignments
REDIS_SESSION_DB=1
REDIS_CACHE_DB=2
REDIS_CORRELATION_DB=3

# Connection settings
REDIS_TIMEOUT=30
REDIS_MAX_CONNECTIONS=100
REDIS_POOL_SIZE=20

# UTMStack specific settings
REDIS_KEY_PREFIX=utmstack:
REDIS_SESSION_TIMEOUT=3600
REDIS_CACHE_TTL=1800
EOF

    success "Redis integration configuration created: /tmp/utmstack-redis-config.env"
    
    # Test Redis integration
    info "Testing Redis integration..."
    
    # Test all assigned databases
    for db in 0 1 2 3; do
        if docker exec utmstack-redis redis-cli -a utmstack_redis_pass -n $db SET "test:db:$db" "working" | grep -q OK; then
            success "Database $db: Working"
            docker exec utmstack-redis redis-cli -a utmstack_redis_pass -n $db DEL "test:db:$db" >/dev/null
        else
            warning "Database $db: Issue detected"
        fi
    done
}

# Update system health check
update_health_check() {
    info "Updating system health check to include Redis..."
    
    # Add Redis check to quick health check script
    if [ -f "$SCRIPT_DIR/quick-health-check.sh" ]; then
        # Add Redis line if not already present
        if ! grep -q "utmstack-redis" "$SCRIPT_DIR/quick-health-check.sh"; then
            sed -i '/# Redis/a check_service "Redis Cache" "docker exec utmstack-redis redis-cli -a utmstack_redis_pass ping | grep -q PONG" "success"' "$SCRIPT_DIR/quick-health-check.sh"
        fi
        success "Health check updated to include Redis"
    else
        warning "Health check script not found"
    fi
}

# Main execution
main() {
    log "Starting Redis Cache Setup for UTMStack"
    
    if check_existing_redis; then
        warning "Redis may already be configured. Proceeding with verification..."
    fi
    
    deploy_redis_container
    configure_redis_utmstack
    create_redis_monitoring
    create_redis_backup
    integrate_with_utmstack
    update_health_check
    
    echo ""
    echo "=============================================="
    success "Redis Cache Setup COMPLETED Successfully"
    echo "=============================================="
    echo ""
    echo "🔴 Redis Service Information:"
    echo "   Host: localhost:6379"
    echo "   Password: utmstack_redis_pass"
    echo "   Container: utmstack-redis"
    echo "   Databases: 0=general, 1=sessions, 2=cache, 3=correlation"
    echo ""
    echo "📋 Management Scripts:"
    echo "   Monitor: /tmp/utmstack-redis-monitor.sh"
    echo "   Backup:  /tmp/utmstack-redis-backup.sh"
    echo "   Config:  /tmp/utmstack-redis-config.env"
    echo ""
    echo "🧪 Test Redis:"
    echo "   docker exec utmstack-redis redis-cli -a utmstack_redis_pass ping"
    echo ""
    echo "📊 Redis is now ready for UTMStack integration!"
    echo ""
}

# Execute main function
main "$@"
