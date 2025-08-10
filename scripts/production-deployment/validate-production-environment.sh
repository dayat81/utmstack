#!/bin/bash

# UTMStack Production Environment Validation Script
# Phase 6 - Sprint 1.3: Security & Compliance Validation
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
VALIDATION_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="/var/log/utmstack/validation-${VALIDATION_DATE}.log"
REPORT_FILE="/var/log/utmstack/validation-report-${VALIDATION_DATE}.html"

# Create log directory
mkdir -p /var/log/utmstack

# Redirect output to log file
exec > >(tee -a ${LOG_FILE})
exec 2>&1

echo "======================================================================"
echo "🔍 UTMStack Production Environment Validation"
echo "======================================================================"
echo "Validation Date: ${VALIDATION_DATE}"
echo "Log File: ${LOG_FILE}"
echo "Report File: ${REPORT_FILE}"
echo "======================================================================"

# Validation counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Function to track check results
track_check() {
    local status="$1"
    local message="$2"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    case "$status" in
        "PASS")
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            log_success "$message"
            ;;
        "FAIL")
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            log_error "$message"
            ;;
        "WARN")
            WARNING_CHECKS=$((WARNING_CHECKS + 1))
            log_warning "$message"
            ;;
    esac
}

# System Requirements Validation
validate_system_requirements() {
    log_info "Validating system requirements..."
    
    # Check available memory (minimum 16GB)
    total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    total_mem_gb=$((total_mem / 1024 / 1024))
    
    if [[ $total_mem_gb -ge 16 ]]; then
        track_check "PASS" "System memory: ${total_mem_gb}GB (minimum 16GB required)"
    else
        track_check "FAIL" "System memory: ${total_mem_gb}GB (minimum 16GB required)"
    fi
    
    # Check available disk space (minimum 500GB)
    available_space=$(df / | awk 'NR==2 {print $4}')
    available_space_gb=$((available_space / 1024 / 1024))
    
    if [[ $available_space_gb -ge 500 ]]; then
        track_check "PASS" "Available disk space: ${available_space_gb}GB (minimum 500GB required)"
    else
        track_check "FAIL" "Available disk space: ${available_space_gb}GB (minimum 500GB required)"
    fi
    
    # Check CPU cores (minimum 8 cores)
    cpu_cores=$(nproc)
    if [[ $cpu_cores -ge 8 ]]; then
        track_check "PASS" "CPU cores: ${cpu_cores} (minimum 8 required)"
    else
        track_check "FAIL" "CPU cores: ${cpu_cores} (minimum 8 required)"
    fi
}

# Database Validation
validate_database() {
    log_info "Validating PostgreSQL database..."
    
    # Check if PostgreSQL is running
    if systemctl is-active --quiet postgresql; then
        track_check "PASS" "PostgreSQL service is running"
    else
        track_check "FAIL" "PostgreSQL service is not running"
        return
    fi
    
    # Check database connectivity
    if pg_isready -h localhost -p 5432 -U utmstack_prod; then
        track_check "PASS" "Database connectivity successful"
    else
        track_check "FAIL" "Cannot connect to database"
        return
    fi
    
    # Check if multi-tenant schema exists
    if psql -h localhost -U utmstack_prod -d utmstack_production -c "SELECT 1 FROM utm_tenant LIMIT 1;" > /dev/null 2>&1; then
        track_check "PASS" "Multi-tenant schema is present"
    else
        track_check "FAIL" "Multi-tenant schema not found"
    fi
    
    # Check Row-Level Security status
    rls_enabled=$(psql -h localhost -U utmstack_prod -d utmstack_production -t -c "
        SELECT COUNT(*) FROM pg_class c 
        JOIN pg_namespace n ON c.relnamespace = n.oid 
        WHERE c.relrowsecurity = true 
        AND n.nspname = 'public' 
        AND c.relname IN ('jhi_user', 'utm_dashboard', 'utm_alert_log');
    " | tr -d ' ')
    
    if [[ "$rls_enabled" -eq 3 ]]; then
        track_check "PASS" "Row-Level Security is enabled on core tables"
    else
        track_check "FAIL" "Row-Level Security not properly enabled"
    fi
    
    # Check RLS policies
    policies_count=$(psql -h localhost -U utmstack_prod -d utmstack_production -t -c "
        SELECT COUNT(*) FROM pg_policies 
        WHERE tablename IN ('jhi_user', 'utm_dashboard', 'utm_alert_log')
        AND policyname = 'tenant_isolation_policy';
    " | tr -d ' ')
    
    if [[ "$policies_count" -eq 3 ]]; then
        track_check "PASS" "RLS policies are correctly configured"
    else
        track_check "FAIL" "RLS policies are missing or misconfigured"
    fi
}

# Elasticsearch Validation
validate_elasticsearch() {
    log_info "Validating Elasticsearch cluster..."
    
    # Check Elasticsearch connectivity
    if curl -s -f http://localhost:9200/_cluster/health > /dev/null; then
        track_check "PASS" "Elasticsearch cluster is accessible"
    else
        track_check "FAIL" "Elasticsearch cluster is not accessible"
        return
    fi
    
    # Check cluster health
    cluster_status=$(curl -s http://localhost:9200/_cluster/health | jq -r '.status')
    if [[ "$cluster_status" == "green" ]]; then
        track_check "PASS" "Elasticsearch cluster status: green"
    elif [[ "$cluster_status" == "yellow" ]]; then
        track_check "WARN" "Elasticsearch cluster status: yellow"
    else
        track_check "FAIL" "Elasticsearch cluster status: $cluster_status"
    fi
    
    # Check if multi-tenant index template exists
    if curl -s http://localhost:9200/_index_template/utmstack-multitenant-template > /dev/null; then
        track_check "PASS" "Multi-tenant index template is configured"
    else
        track_check "FAIL" "Multi-tenant index template not found"
    fi
    
    # Check node count
    node_count=$(curl -s http://localhost:9200/_cat/nodes | wc -l)
    if [[ $node_count -ge 3 ]]; then
        track_check "PASS" "Elasticsearch nodes: $node_count (minimum 3 for production)"
    else
        track_check "WARN" "Elasticsearch nodes: $node_count (recommended: minimum 3)"
    fi
}

# Security Validation
validate_security() {
    log_info "Validating security configuration..."
    
    # Check SSL certificates
    if [[ -f /etc/ssl/certs/utmstack.crt ]] && [[ -f /etc/ssl/private/utmstack.key ]]; then
        track_check "PASS" "SSL certificates are present"
        
        # Check certificate validity
        cert_expiry=$(openssl x509 -in /etc/ssl/certs/utmstack.crt -noout -enddate | cut -d= -f2)
        cert_expiry_epoch=$(date -d "$cert_expiry" +%s)
        current_epoch=$(date +%s)
        days_until_expiry=$(( (cert_expiry_epoch - current_epoch) / 86400 ))
        
        if [[ $days_until_expiry -gt 30 ]]; then
            track_check "PASS" "SSL certificate valid for $days_until_expiry days"
        else
            track_check "WARN" "SSL certificate expires in $days_until_expiry days"
        fi
    else
        track_check "FAIL" "SSL certificates not found"
    fi
    
    # Check firewall status
    if ufw status | grep -q "Status: active"; then
        track_check "PASS" "UFW firewall is active"
    else
        track_check "WARN" "UFW firewall is not active"
    fi
    
    # Check if fail2ban is running
    if systemctl is-active --quiet fail2ban; then
        track_check "PASS" "Fail2ban is running"
    else
        track_check "WARN" "Fail2ban is not running"
    fi
    
    # Check SSH configuration
    if grep -q "PermitRootLogin no" /etc/ssh/sshd_config; then
        track_check "PASS" "SSH root login is disabled"
    else
        track_check "WARN" "SSH root login should be disabled"
    fi
    
    # Check password authentication
    if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
        track_check "PASS" "SSH password authentication is disabled"
    else
        track_check "WARN" "SSH password authentication should be disabled"
    fi
}

# Application Services Validation
validate_application_services() {
    log_info "Validating application services..."
    
    # Check if Docker is running
    if systemctl is-active --quiet docker; then
        track_check "PASS" "Docker service is running"
    else
        track_check "FAIL" "Docker service is not running"
    fi
    
    # Check if docker-compose is available
    if command -v docker-compose > /dev/null; then
        track_check "PASS" "Docker Compose is available"
    else
        track_check "FAIL" "Docker Compose is not available"
    fi
    
    # Check nginx configuration
    if nginx -t 2>/dev/null; then
        track_check "PASS" "Nginx configuration is valid"
    else
        track_check "FAIL" "Nginx configuration has errors"
    fi
    
    # Check if nginx is running
    if systemctl is-active --quiet nginx; then
        track_check "PASS" "Nginx service is running"
    else
        track_check "FAIL" "Nginx service is not running"
    fi
}

# Network and Connectivity Validation
validate_network() {
    log_info "Validating network configuration..."
    
    # Check DNS resolution
    if nslookup google.com > /dev/null 2>&1; then
        track_check "PASS" "DNS resolution is working"
    else
        track_check "FAIL" "DNS resolution is not working"
    fi
    
    # Check internet connectivity
    if curl -s --max-time 10 https://www.google.com > /dev/null; then
        track_check "PASS" "Internet connectivity is working"
    else
        track_check "FAIL" "Internet connectivity is not working"
    fi
    
    # Check required ports
    required_ports=(80 443 5432 9200 8080 9090)
    for port in "${required_ports[@]}"; do
        if netstat -tuln | grep -q ":$port "; then
            track_check "PASS" "Port $port is listening"
        else
            track_check "WARN" "Port $port is not listening"
        fi
    done
}

# Multi-Tenant Validation
validate_multitenant() {
    log_info "Validating multi-tenant functionality..."
    
    # Check default tenant exists
    default_tenant_exists=$(psql -h localhost -U utmstack_prod -d utmstack_production -t -c "
        SELECT COUNT(*) FROM utm_tenant WHERE id = '00000000-0000-0000-0000-000000000001';
    " | tr -d ' ')
    
    if [[ "$default_tenant_exists" -eq 1 ]]; then
        track_check "PASS" "Default tenant exists in database"
    else
        track_check "FAIL" "Default tenant not found"
    fi
    
    # Test tenant context functionality
    if psql -h localhost -U utmstack_prod -d utmstack_production -c "SELECT set_tenant_context('00000000-0000-0000-0000-000000000001');" > /dev/null 2>&1; then
        track_check "PASS" "Tenant context function is working"
    else
        track_check "FAIL" "Tenant context function is not working"
    fi
    
    # Check tenant isolation (simulate cross-tenant access attempt)
    isolation_test=$(psql -h localhost -U utmstack_prod -d utmstack_production -t -c "
        SELECT set_tenant_context('99999999-9999-9999-9999-999999999999');
        SELECT COUNT(*) FROM jhi_user;
    " | tail -n 1 | tr -d ' ')
    
    if [[ "$isolation_test" -eq 0 ]]; then
        track_check "PASS" "Tenant isolation is working correctly"
    else
        track_check "FAIL" "Tenant isolation may be compromised"
    fi
}

# Performance Validation
validate_performance() {
    log_info "Validating system performance..."
    
    # Check system load
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    load_threshold=5.0
    
    if (( $(echo "$load_avg < $load_threshold" | bc -l) )); then
        track_check "PASS" "System load average: $load_avg (acceptable)"
    else
        track_check "WARN" "System load average: $load_avg (high)"
    fi
    
    # Check database response time
    db_response_time=$(time psql -h localhost -U utmstack_prod -d utmstack_production -c "SELECT 1;" 2>&1 | grep real | awk '{print $2}' | sed 's/m/\*60+/' | sed 's/s//' | bc)
    
    if (( $(echo "$db_response_time < 1" | bc -l) )); then
        track_check "PASS" "Database response time: ${db_response_time}s (acceptable)"
    else
        track_check "WARN" "Database response time: ${db_response_time}s (slow)"
    fi
    
    # Check Elasticsearch response time
    es_response_time=$(curl -w "%{time_total}" -s -o /dev/null http://localhost:9200/_cluster/health)
    
    if (( $(echo "$es_response_time < 1" | bc -l) )); then
        track_check "PASS" "Elasticsearch response time: ${es_response_time}s (acceptable)"
    else
        track_check "WARN" "Elasticsearch response time: ${es_response_time}s (slow)"
    fi
}

# Compliance Validation
validate_compliance() {
    log_info "Validating compliance requirements..."
    
    # Check audit logging configuration
    if [[ -d /var/log/utmstack ]] && [[ -w /var/log/utmstack ]]; then
        track_check "PASS" "Audit logging directory is accessible"
    else
        track_check "FAIL" "Audit logging directory is not accessible"
    fi
    
    # Check log rotation configuration
    if [[ -f /etc/logrotate.d/utmstack ]]; then
        track_check "PASS" "Log rotation is configured"
    else
        track_check "WARN" "Log rotation should be configured"
    fi
    
    # Check backup configuration
    if [[ -f /etc/cron.d/utmstack-backup ]]; then
        track_check "PASS" "Automated backup is configured"
    else
        track_check "WARN" "Automated backup should be configured"
    fi
    
    # Check data retention policies
    retention_policies=$(psql -h localhost -U utmstack_prod -d utmstack_production -t -c "
        SELECT COUNT(*) FROM utm_tenant_config WHERE config_key LIKE '%retention%';
    " | tr -d ' ')
    
    if [[ "$retention_policies" -gt 0 ]]; then
        track_check "PASS" "Data retention policies are configured"
    else
        track_check "WARN" "Data retention policies should be configured"
    fi
}

# Generate HTML Report
generate_html_report() {
    log_info "Generating validation report..."
    
    cat > ${REPORT_FILE} << EOF
<!DOCTYPE html>
<html>
<head>
    <title>UTMStack Production Validation Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #2c3e50; color: white; padding: 20px; text-align: center; }
        .summary { background-color: #ecf0f1; padding: 15px; margin: 20px 0; }
        .section { margin: 20px 0; }
        .pass { color: #27ae60; }
        .fail { color: #e74c3c; }
        .warn { color: #f39c12; }
        table { width: 100%; border-collapse: collapse; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #34495e; color: white; }
    </style>
</head>
<body>
    <div class="header">
        <h1>UTMStack Production Environment Validation Report</h1>
        <p>Generated on: ${VALIDATION_DATE}</p>
    </div>
    
    <div class="summary">
        <h2>Validation Summary</h2>
        <table>
            <tr><td><strong>Total Checks:</strong></td><td>${TOTAL_CHECKS}</td></tr>
            <tr><td><strong>Passed:</strong></td><td class="pass">${PASSED_CHECKS}</td></tr>
            <tr><td><strong>Failed:</strong></td><td class="fail">${FAILED_CHECKS}</td></tr>
            <tr><td><strong>Warnings:</strong></td><td class="warn">${WARNING_CHECKS}</td></tr>
            <tr><td><strong>Success Rate:</strong></td><td>$(( PASSED_CHECKS * 100 / TOTAL_CHECKS ))%</td></tr>
        </table>
    </div>
    
    <div class="section">
        <h2>Validation Details</h2>
        <p>For detailed validation results, please check the log file: <code>${LOG_FILE}</code></p>
    </div>
    
    <div class="section">
        <h2>Recommendations</h2>
EOF

    if [[ $FAILED_CHECKS -gt 0 ]]; then
        echo "        <p class=\"fail\"><strong>Critical Issues Found:</strong> $FAILED_CHECKS critical issues must be resolved before production deployment.</p>" >> ${REPORT_FILE}
    fi
    
    if [[ $WARNING_CHECKS -gt 0 ]]; then
        echo "        <p class=\"warn\"><strong>Warnings Found:</strong> $WARNING_CHECKS warnings should be addressed for optimal security and performance.</p>" >> ${REPORT_FILE}
    fi
    
    if [[ $FAILED_CHECKS -eq 0 ]] && [[ $WARNING_CHECKS -eq 0 ]]; then
        echo "        <p class=\"pass\"><strong>System Ready:</strong> All validation checks passed. The system is ready for production deployment.</p>" >> ${REPORT_FILE}
    fi
    
    cat >> ${REPORT_FILE} << EOF
    </div>
</body>
</html>
EOF
}

# Main validation execution
main() {
    log_info "Starting UTMStack Production Environment Validation..."
    
    validate_system_requirements
    validate_database
    validate_elasticsearch
    validate_security
    validate_application_services
    validate_network
    validate_multitenant
    validate_performance
    validate_compliance
    
    generate_html_report
    
    echo ""
    echo "======================================================================"
    echo "🎯 Validation Summary"
    echo "======================================================================"
    echo "Total Checks: $TOTAL_CHECKS"
    echo "Passed: $PASSED_CHECKS"
    echo "Failed: $FAILED_CHECKS"
    echo "Warnings: $WARNING_CHECKS"
    echo "Success Rate: $(( PASSED_CHECKS * 100 / TOTAL_CHECKS ))%"
    echo ""
    echo "Log File: $LOG_FILE"
    echo "Report File: $REPORT_FILE"
    echo "======================================================================"
    
    if [[ $FAILED_CHECKS -eq 0 ]]; then
        if [[ $WARNING_CHECKS -eq 0 ]]; then
            log_success "All validation checks passed! System is ready for production."
            exit 0
        else
            log_warning "$WARNING_CHECKS warnings found. Review recommendations before deployment."
            exit 0
        fi
    else
        log_error "$FAILED_CHECKS critical issues found. System is not ready for production."
        exit 1
    fi
}

# Execute main function
main "$@"
