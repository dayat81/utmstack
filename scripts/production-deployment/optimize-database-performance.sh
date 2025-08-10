#!/bin/bash

# UTMStack Database Performance Optimization Script
# Phase 6 - Sprint 2.1: Performance Optimization
# Version: 1.0.0

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
OPTIMIZATION_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="/var/log/utmstack/db-optimization-${OPTIMIZATION_DATE}.log"
BACKUP_DIR="/var/backups/utmstack/db-optimization-${OPTIMIZATION_DATE}"

# Create directories
mkdir -p /var/log/utmstack
mkdir -p ${BACKUP_DIR}

# Redirect output
exec > >(tee -a ${LOG_FILE})
exec 2>&1

echo "======================================================================"
echo "⚡ UTMStack Database Performance Optimization"
echo "======================================================================"
echo "Optimization Date: ${OPTIMIZATION_DATE}"
echo "Log File: ${LOG_FILE}"
echo "Backup Directory: ${BACKUP_DIR}"
echo "======================================================================"

# Function to analyze current database performance
analyze_current_performance() {
    log_info "Analyzing current database performance..."
    
    # Create performance analysis script
    cat > /tmp/performance_analysis.sql << 'EOF'
-- Database Performance Analysis

-- 1. Check current database size and statistics
SELECT 
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation,
    most_common_vals,
    most_common_freqs
FROM pg_stats 
WHERE schemaname = 'public' 
AND tablename IN ('jhi_user', 'utm_dashboard', 'utm_alert_log', 'utm_visualization')
ORDER BY tablename, attname;

-- 2. Analyze slow queries
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    rows,
    100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0) AS hit_percent
FROM pg_stat_statements 
WHERE total_time > 1000 -- queries taking more than 1 second total
ORDER BY total_time DESC
LIMIT 20;

-- 3. Check index usage
SELECT 
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation
FROM pg_stats 
WHERE schemaname = 'public'
AND tablename IN ('jhi_user', 'utm_dashboard', 'utm_alert_log')
ORDER BY tablename;

-- 4. Check table sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
    pg_total_relation_size(schemaname||'.'||tablename) as size_bytes
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- 5. Check unused indexes
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_tup_read,
    idx_tup_fetch,
    pg_size_pretty(pg_relation_size(indexname::regclass)) as size
FROM pg_stat_user_indexes 
WHERE idx_tup_read = 0 
AND idx_tup_fetch = 0
ORDER BY pg_relation_size(indexname::regclass) DESC;
EOF

    # Execute analysis
    psql -h localhost -U utmstack_prod -d utmstack_production -f /tmp/performance_analysis.sql > ${BACKUP_DIR}/performance_analysis_before.txt
    
    log_success "Performance analysis completed"
}

# Function to optimize database configuration
optimize_database_config() {
    log_info "Optimizing PostgreSQL configuration..."
    
    # Backup current configuration
    cp /var/lib/postgresql/data/postgresql.conf ${BACKUP_DIR}/postgresql.conf.backup
    
    # Calculate optimal settings based on system resources
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_mb=$((total_mem_kb / 1024))
    local shared_buffers_mb=$((total_mem_mb / 4))  # 25% of total memory
    local effective_cache_size_mb=$((total_mem_mb * 3 / 4))  # 75% of total memory
    local work_mem_mb=$((total_mem_mb / 32))  # Conservative work_mem
    local maintenance_work_mem_mb=$((total_mem_mb / 16))  # Maintenance work mem
    
    # Create optimized PostgreSQL configuration
    cat > /tmp/postgresql_optimizations.conf << EOF
# UTMStack Production PostgreSQL Optimizations
# Generated: ${OPTIMIZATION_DATE}

# Memory Configuration
shared_buffers = ${shared_buffers_mb}MB
effective_cache_size = ${effective_cache_size_mb}MB
work_mem = ${work_mem_mb}MB
maintenance_work_mem = ${maintenance_work_mem_mb}MB

# Connection Configuration
max_connections = 500
shared_preload_libraries = 'pg_stat_statements'

# Checkpoint Configuration
checkpoint_completion_target = 0.9
checkpoint_timeout = 10min
max_wal_size = 4GB
min_wal_size = 1GB
wal_buffers = 16MB

# Query Planner Configuration
random_page_cost = 1.1
effective_io_concurrency = 200
default_statistics_target = 100

# Logging Configuration
log_min_duration_statement = 1000  # Log queries taking more than 1 second
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0

# Auto-vacuum Configuration
autovacuum = on
autovacuum_max_workers = 4
autovacuum_naptime = 30s
autovacuum_vacuum_threshold = 50
autovacuum_analyze_threshold = 50
autovacuum_vacuum_scale_factor = 0.1
autovacuum_analyze_scale_factor = 0.05

# Multi-tenant specific optimizations
track_activities = on
track_counts = on
track_io_timing = on
track_functions = all

# Performance monitoring
pg_stat_statements.max = 10000
pg_stat_statements.track = all
pg_stat_statements.track_utility = on
pg_stat_statements.save = on
EOF

    # Apply configuration
    cat /tmp/postgresql_optimizations.conf >> /var/lib/postgresql/data/postgresql.conf
    
    log_success "Database configuration optimized"
}

# Function to create optimized indexes
create_optimized_indexes() {
    log_info "Creating optimized indexes for multi-tenant performance..."
    
    cat > /tmp/index_optimizations.sql << 'EOF'
-- UTMStack Multi-Tenant Index Optimizations

-- Enable timing for performance measurement
\timing on

-- 1. Composite indexes for common tenant-scoped queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_jhi_user_tenant_email 
ON jhi_user(tenant_id, email) 
WHERE tenant_id IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_jhi_user_tenant_created 
ON jhi_user(tenant_id, created_date) 
WHERE tenant_id IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_utm_dashboard_tenant_created 
ON utm_dashboard(tenant_id, created_date) 
WHERE tenant_id IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_utm_dashboard_tenant_name 
ON utm_dashboard(tenant_id, name) 
WHERE tenant_id IS NOT NULL;

-- 2. Alert log performance indexes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_utm_alert_log_tenant_timestamp 
ON utm_alert_log(tenant_id, log_date) 
WHERE tenant_id IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_utm_alert_log_tenant_severity 
ON utm_alert_log(tenant_id, severity) 
WHERE tenant_id IS NOT NULL AND severity IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_utm_alert_log_tenant_status 
ON utm_alert_log(tenant_id, status) 
WHERE tenant_id IS NOT NULL AND status IS NOT NULL;

-- 3. Visualization performance indexes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_utm_visualization_tenant_dashboard 
ON utm_visualization(tenant_id, utm_dashboard_id) 
WHERE tenant_id IS NOT NULL;

-- 4. Filter performance indexes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_utm_logstash_filter_tenant_enabled 
ON utm_logstash_filter(tenant_id, is_enabled) 
WHERE tenant_id IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_utm_logstash_filter_group_tenant 
ON utm_logstash_filter_group(tenant_id, group_name) 
WHERE tenant_id IS NOT NULL;

-- 5. Index pattern performance
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_utm_index_pattern_tenant_active 
ON utm_index_pattern(tenant_id, is_active) 
WHERE tenant_id IS NOT NULL;

-- 6. Partial indexes for active records only
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_jhi_user_active_tenant 
ON jhi_user(tenant_id, login) 
WHERE tenant_id IS NOT NULL AND activated = true;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_utm_dashboard_active_tenant 
ON utm_dashboard(tenant_id) 
WHERE tenant_id IS NOT NULL AND is_active = true;

-- 7. JSON/JSONB indexes for configuration data
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_utm_tenant_settings_gin 
ON utm_tenant USING gin(settings) 
WHERE settings IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_utm_tenant_config_key_value 
ON utm_tenant_config(tenant_id, config_key, config_value) 
WHERE tenant_id IS NOT NULL;

-- 8. Text search indexes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_utm_alert_log_message_gin 
ON utm_alert_log USING gin(to_tsvector('english', message)) 
WHERE tenant_id IS NOT NULL AND message IS NOT NULL;

-- Analyze tables after index creation
ANALYZE jhi_user;
ANALYZE utm_dashboard;
ANALYZE utm_alert_log;
ANALYZE utm_visualization;
ANALYZE utm_logstash_filter;
ANALYZE utm_logstash_filter_group;
ANALYZE utm_index_pattern;
ANALYZE utm_tenant;
ANALYZE utm_tenant_config;
EOF

    # Execute index creation
    psql -h localhost -U utmstack_prod -d utmstack_production -f /tmp/index_optimizations.sql
    
    log_success "Optimized indexes created"
}

# Function to optimize queries and create materialized views
optimize_queries() {
    log_info "Creating optimized views and query optimizations..."
    
    cat > /tmp/query_optimizations.sql << 'EOF'
-- UTMStack Query Optimizations

-- 1. Materialized view for tenant dashboard statistics
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_tenant_dashboard_stats AS
SELECT 
    t.id as tenant_id,
    t.name as tenant_name,
    COUNT(d.id) as dashboard_count,
    COUNT(v.id) as visualization_count,
    MAX(d.last_modified_date) as last_activity
FROM utm_tenant t
LEFT JOIN utm_dashboard d ON t.id = d.tenant_id
LEFT JOIN utm_visualization v ON d.id = v.utm_dashboard_id
GROUP BY t.id, t.name;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_tenant_dashboard_stats_tenant 
ON mv_tenant_dashboard_stats(tenant_id);

-- 2. Materialized view for tenant alert statistics
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_tenant_alert_stats AS
SELECT 
    tenant_id,
    DATE(log_date) as alert_date,
    COUNT(*) as total_alerts,
    COUNT(CASE WHEN severity = 'HIGH' THEN 1 END) as high_severity_alerts,
    COUNT(CASE WHEN severity = 'MEDIUM' THEN 1 END) as medium_severity_alerts,
    COUNT(CASE WHEN severity = 'LOW' THEN 1 END) as low_severity_alerts,
    COUNT(CASE WHEN status = 'OPEN' THEN 1 END) as open_alerts
FROM utm_alert_log 
WHERE tenant_id IS NOT NULL 
AND log_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY tenant_id, DATE(log_date);

CREATE INDEX IF NOT EXISTS idx_mv_tenant_alert_stats_tenant_date 
ON mv_tenant_alert_stats(tenant_id, alert_date);

-- 3. Function to refresh materialized views
CREATE OR REPLACE FUNCTION refresh_tenant_statistics()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_tenant_dashboard_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_tenant_alert_stats;
END;
$$ LANGUAGE plpgsql;

-- 4. Create optimized tenant context functions
CREATE OR REPLACE FUNCTION get_tenant_dashboard_count(tenant_uuid UUID)
RETURNS integer AS $$
DECLARE
    dashboard_count integer;
BEGIN
    SELECT COUNT(*) INTO dashboard_count
    FROM utm_dashboard 
    WHERE tenant_id = tenant_uuid;
    
    RETURN dashboard_count;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION get_tenant_alert_summary(tenant_uuid UUID, days_back integer DEFAULT 7)
RETURNS TABLE(
    total_alerts bigint,
    high_severity bigint,
    medium_severity bigint,
    low_severity bigint,
    open_alerts bigint
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*) as total_alerts,
        COUNT(CASE WHEN severity = 'HIGH' THEN 1 END) as high_severity,
        COUNT(CASE WHEN severity = 'MEDIUM' THEN 1 END) as medium_severity,
        COUNT(CASE WHEN severity = 'LOW' THEN 1 END) as low_severity,
        COUNT(CASE WHEN status = 'OPEN' THEN 1 END) as open_alerts
    FROM utm_alert_log
    WHERE tenant_id = tenant_uuid
    AND log_date >= CURRENT_DATE - INTERVAL '1 day' * days_back;
END;
$$ LANGUAGE plpgsql STABLE;

-- 5. Optimize frequent queries with prepared statements
PREPARE get_user_dashboards(UUID) AS
SELECT d.id, d.name, d.description, d.created_date, d.last_modified_date
FROM utm_dashboard d
WHERE d.tenant_id = $1
AND d.is_active = true
ORDER BY d.last_modified_date DESC;

PREPARE get_recent_alerts(UUID, integer) AS
SELECT id, message, severity, status, log_date
FROM utm_alert_log
WHERE tenant_id = $1
AND log_date >= CURRENT_DATE - INTERVAL '1 day' * $2
ORDER BY log_date DESC
LIMIT 100;

-- 6. Create partition maintenance function
CREATE OR REPLACE FUNCTION maintain_alert_log_partitions()
RETURNS void AS $$
DECLARE
    partition_date date;
    partition_name text;
BEGIN
    -- Create partitions for the next 3 months
    FOR i IN 0..2 LOOP
        partition_date := date_trunc('month', CURRENT_DATE + INTERVAL '1 month' * i);
        partition_name := 'utm_alert_log_' || to_char(partition_date, 'YYYY_MM');
        
        -- Create partition if it doesn't exist
        EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF utm_alert_log
                       FOR VALUES FROM (%L) TO (%L)',
                       partition_name,
                       partition_date,
                       partition_date + INTERVAL '1 month');
    END LOOP;
    
    -- Drop old partitions (older than 2 years)
    FOR partition_name IN 
        SELECT tablename FROM pg_tables 
        WHERE tablename LIKE 'utm_alert_log_%' 
        AND tablename < 'utm_alert_log_' || to_char(CURRENT_DATE - INTERVAL '2 years', 'YYYY_MM')
    LOOP
        EXECUTE format('DROP TABLE IF EXISTS %I', partition_name);
    END LOOP;
END;
$$ LANGUAGE plpgsql;
EOF

    # Execute query optimizations
    psql -h localhost -U utmstack_prod -d utmstack_production -f /tmp/query_optimizations.sql
    
    log_success "Query optimizations applied"
}

# Function to setup connection pooling optimization
optimize_connection_pooling() {
    log_info "Optimizing connection pooling configuration..."
    
    # Create PgBouncer configuration for connection pooling
    cat > /etc/pgbouncer/pgbouncer.ini << 'EOF'
[databases]
utmstack_production = host=localhost port=5432 dbname=utmstack_production

[pgbouncer]
listen_port = 6432
listen_addr = 127.0.0.1
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
admin_users = postgres
stats_users = postgres

pool_mode = transaction
max_client_conn = 1000
default_pool_size = 50
min_pool_size = 10
reserve_pool_size = 10
reserve_pool_timeout = 3
max_db_connections = 200
max_user_connections = 100

server_reset_query = DISCARD ALL
server_check_query = SELECT 1
server_check_delay = 30
max_packet_size = 2147483647

log_connections = 1
log_disconnections = 1
log_pooler_errors = 1

tcp_keepalive = 1
tcp_keepcnt = 9
tcp_keepidle = 7200
tcp_keepintvl = 75
EOF

    # Create user authentication file
    echo '"utmstack_prod" "md5d41d8cd98f00b204e9800998ecf8427e"' > /etc/pgbouncer/userlist.txt
    
    # Set proper permissions
    chmod 600 /etc/pgbouncer/pgbouncer.ini
    chmod 600 /etc/pgbouncer/userlist.txt
    
    log_success "Connection pooling optimization completed"
}

# Function to create database maintenance procedures
create_maintenance_procedures() {
    log_info "Creating automated database maintenance procedures..."
    
    cat > /tmp/maintenance_procedures.sql << 'EOF'
-- UTMStack Database Maintenance Procedures

-- 1. Comprehensive maintenance function
CREATE OR REPLACE FUNCTION perform_database_maintenance()
RETURNS text AS $$
DECLARE
    maintenance_log text := '';
    table_name text;
    start_time timestamp;
    end_time timestamp;
BEGIN
    start_time := clock_timestamp();
    maintenance_log := 'Database maintenance started at ' || start_time || E'\n';
    
    -- Update statistics for all tables
    FOR table_name IN 
        SELECT tablename FROM pg_tables 
        WHERE schemaname = 'public' 
        AND tablename LIKE 'utm_%' OR tablename = 'jhi_user'
    LOOP
        EXECUTE 'ANALYZE ' || quote_ident(table_name);
        maintenance_log := maintenance_log || 'Analyzed table: ' || table_name || E'\n';
    END LOOP;
    
    -- Refresh materialized views
    PERFORM refresh_tenant_statistics();
    maintenance_log := maintenance_log || 'Refreshed materialized views' || E'\n';
    
    -- Maintain partitions
    PERFORM maintain_alert_log_partitions();
    maintenance_log := maintenance_log || 'Maintained alert log partitions' || E'\n';
    
    -- Vacuum and reindex if needed (during low usage periods)
    IF EXTRACT(hour FROM now()) BETWEEN 2 AND 4 THEN
        VACUUM ANALYZE;
        maintenance_log := maintenance_log || 'Performed VACUUM ANALYZE' || E'\n';
    END IF;
    
    end_time := clock_timestamp();
    maintenance_log := maintenance_log || 'Maintenance completed at ' || end_time;
    maintenance_log := maintenance_log || E'\nTotal duration: ' || (end_time - start_time);
    
    RETURN maintenance_log;
END;
$$ LANGUAGE plpgsql;

-- 2. Performance monitoring function
CREATE OR REPLACE FUNCTION get_performance_metrics()
RETURNS TABLE(
    metric_name text,
    metric_value text,
    metric_unit text,
    severity text
) AS $$
BEGIN
    RETURN QUERY
    -- Database size
    SELECT 
        'Database Size'::text,
        pg_size_pretty(pg_database_size('utmstack_production'))::text,
        'bytes'::text,
        CASE 
            WHEN pg_database_size('utmstack_production') > 100*1024*1024*1024 THEN 'warning'
            WHEN pg_database_size('utmstack_production') > 500*1024*1024*1024 THEN 'critical'
            ELSE 'normal'
        END::text
    
    UNION ALL
    
    -- Active connections
    SELECT 
        'Active Connections'::text,
        COUNT(*)::text,
        'connections'::text,
        CASE 
            WHEN COUNT(*) > 400 THEN 'critical'
            WHEN COUNT(*) > 200 THEN 'warning'
            ELSE 'normal'
        END::text
    FROM pg_stat_activity 
    WHERE state = 'active'
    
    UNION ALL
    
    -- Cache hit ratio
    SELECT 
        'Cache Hit Ratio'::text,
        ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2)::text,
        'percent'::text,
        CASE 
            WHEN ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2) < 90 THEN 'warning'
            WHEN ROUND(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2) < 80 THEN 'critical'
            ELSE 'normal'
        END::text
    FROM pg_stat_database
    WHERE datname = 'utmstack_production';
END;
$$ LANGUAGE plpgsql;

-- 3. Tenant performance analysis
CREATE OR REPLACE FUNCTION analyze_tenant_performance(tenant_uuid UUID)
RETURNS TABLE(
    metric text,
    value text,
    recommendation text
) AS $$
DECLARE
    user_count integer;
    dashboard_count integer;
    alert_count integer;
    avg_response_time numeric;
BEGIN
    -- Get tenant metrics
    SELECT COUNT(*) INTO user_count FROM jhi_user WHERE tenant_id = tenant_uuid;
    SELECT COUNT(*) INTO dashboard_count FROM utm_dashboard WHERE tenant_id = tenant_uuid;
    SELECT COUNT(*) INTO alert_count 
    FROM utm_alert_log 
    WHERE tenant_id = tenant_uuid 
    AND log_date >= CURRENT_DATE - INTERVAL '24 hours';
    
    RETURN QUERY
    SELECT 
        'User Count'::text,
        user_count::text,
        CASE 
            WHEN user_count > 1000 THEN 'Consider user archiving for inactive users'
            ELSE 'User count within normal range'
        END::text
    
    UNION ALL
    
    SELECT 
        'Dashboard Count'::text,
        dashboard_count::text,
        CASE 
            WHEN dashboard_count > 100 THEN 'Consider dashboard optimization or archiving'
            ELSE 'Dashboard count within normal range'
        END::text
    
    UNION ALL
    
    SELECT 
        'Daily Alert Volume'::text,
        alert_count::text,
        CASE 
            WHEN alert_count > 50000 THEN 'High alert volume - consider rule tuning'
            WHEN alert_count > 10000 THEN 'Moderate alert volume - monitor trends'
            ELSE 'Alert volume within normal range'
        END::text;
END;
$$ LANGUAGE plpgsql;
EOF

    # Execute maintenance procedures
    psql -h localhost -U utmstack_prod -d utmstack_production -f /tmp/maintenance_procedures.sql
    
    # Create cron job for maintenance
    cat > /etc/cron.d/utmstack-db-maintenance << 'EOF'
# UTMStack Database Maintenance
0 3 * * * postgres psql -h localhost -U utmstack_prod -d utmstack_production -c "SELECT perform_database_maintenance();" >> /var/log/utmstack/db-maintenance.log 2>&1
EOF

    log_success "Database maintenance procedures created"
}

# Function to benchmark performance improvements
benchmark_performance() {
    log_info "Benchmarking performance improvements..."
    
    cat > /tmp/performance_benchmark.sql << 'EOF'
-- Performance Benchmark Tests

-- 1. Test tenant-scoped queries
\timing on

-- Test 1: User lookup by tenant
EXPLAIN ANALYZE
SELECT * FROM jhi_user 
WHERE tenant_id = '00000000-0000-0000-0000-000000000001' 
AND email = 'admin@example.com';

-- Test 2: Dashboard listing for tenant
EXPLAIN ANALYZE
SELECT id, name, description, created_date 
FROM utm_dashboard 
WHERE tenant_id = '00000000-0000-0000-0000-000000000001' 
ORDER BY last_modified_date DESC 
LIMIT 20;

-- Test 3: Recent alerts for tenant
EXPLAIN ANALYZE
SELECT id, message, severity, status, log_date 
FROM utm_alert_log 
WHERE tenant_id = '00000000-0000-0000-0000-000000000001' 
AND log_date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY log_date DESC 
LIMIT 100;

-- Test 4: Tenant statistics
EXPLAIN ANALYZE
SELECT 
    COUNT(*) as total_users,
    (SELECT COUNT(*) FROM utm_dashboard WHERE tenant_id = '00000000-0000-0000-0000-000000000001') as total_dashboards,
    (SELECT COUNT(*) FROM utm_alert_log WHERE tenant_id = '00000000-0000-0000-0000-000000000001' AND log_date >= CURRENT_DATE - INTERVAL '24 hours') as daily_alerts
FROM jhi_user 
WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

-- Test 5: Complex join with tenant context
EXPLAIN ANALYZE
SELECT 
    d.name as dashboard_name,
    COUNT(v.id) as visualization_count,
    MAX(v.created_date) as last_visualization_date
FROM utm_dashboard d
LEFT JOIN utm_visualization v ON d.id = v.utm_dashboard_id
WHERE d.tenant_id = '00000000-0000-0000-0000-000000000001'
GROUP BY d.id, d.name
ORDER BY COUNT(v.id) DESC;

\timing off
EOF

    # Execute benchmark
    psql -h localhost -U utmstack_prod -d utmstack_production -f /tmp/performance_benchmark.sql > ${BACKUP_DIR}/performance_benchmark_after.txt
    
    log_success "Performance benchmark completed"
}

# Main optimization execution
main() {
    log_info "Starting UTMStack Database Performance Optimization..."
    
    analyze_current_performance
    optimize_database_config
    create_optimized_indexes
    optimize_queries
    optimize_connection_pooling
    create_maintenance_procedures
    benchmark_performance
    
    log_success "Database performance optimization completed!"
    echo ""
    echo "======================================================================"
    echo "⚡ Database Performance Optimization Summary"
    echo "======================================================================"
    echo "Optimization Date: ${OPTIMIZATION_DATE}"
    echo "Log File: ${LOG_FILE}"
    echo "Backup Directory: ${BACKUP_DIR}"
    echo ""
    echo "Optimizations Applied:"
    echo "✅ PostgreSQL configuration tuning"
    echo "✅ Multi-tenant optimized indexes"
    echo "✅ Query optimization and materialized views"
    echo "✅ Connection pooling with PgBouncer"
    echo "✅ Automated maintenance procedures"
    echo "✅ Performance monitoring functions"
    echo ""
    echo "Next Steps:"
    echo "1. Restart PostgreSQL to apply configuration changes"
    echo "2. Monitor performance metrics"
    echo "3. Run load tests to validate improvements"
    echo "4. Schedule regular maintenance tasks"
    echo "======================================================================"
}

# Execute main function
main "$@"
