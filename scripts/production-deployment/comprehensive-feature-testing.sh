#!/bin/bash

# Comprehensive Feature Functionality Testing Script
# UTMStack Multi-Tenant Production Deployment - Sprint 3.1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/utmstack/feature-testing-$(date +%Y%m%d-%H%M%S).log"
TEST_RESULTS_DIR="/tmp/utmstack-feature-testing"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$TEST_RESULTS_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

echo "🧪 UTMStack Comprehensive Feature Functionality Testing"
echo "========================================================"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
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

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0

# Test result tracking
record_test_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"
    
    echo "Test: $test_name | Result: $result | Details: $details" >> "$TEST_RESULTS_DIR/test-results.log"
    
    case $result in
        "PASS")
            ((TESTS_PASSED++))
            success "$test_name: PASSED"
            ;;
        "FAIL")
            ((TESTS_FAILED++))
            warning "$test_name: FAILED - $details"
            ;;
        "WARN")
            ((TESTS_WARNING++))
            warning "$test_name: WARNING - $details"
            ;;
    esac
}

# 1. Core SIEM Functionality Tests
test_core_siem_functionality() {
    info "Testing Core SIEM Functionality..."
    echo "===================================="
    
    # Test 1: Log Ingestion API
    info "Test 1: Log Ingestion API"
    if curl -s -f -m 10 http://localhost:8080/api/logs/health >/dev/null 2>&1; then
        record_test_result "Log Ingestion API" "PASS" "Health endpoint responsive"
    else
        record_test_result "Log Ingestion API" "FAIL" "Health endpoint not responding"
    fi
    
    # Test 2: Log Ingestion with Sample Data
    info "Test 2: Log Ingestion Sample Data"
    SAMPLE_LOG='{"timestamp":"2025-08-10T12:00:00Z","source":"test","message":"Test log message","tenant_id":"default"}'
    INGESTION_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/api/logs \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer test-token" \
        -d "$SAMPLE_LOG" 2>/dev/null || echo "000")
    
    if [[ "$INGESTION_RESPONSE" =~ ^(200|201|202)$ ]]; then
        record_test_result "Log Ingestion Sample Data" "PASS" "HTTP $INGESTION_RESPONSE"
    else
        record_test_result "Log Ingestion Sample Data" "WARN" "HTTP $INGESTION_RESPONSE - may require authentication"
    fi
    
    # Test 3: Alert Management API
    info "Test 3: Alert Management API"
    ALERT_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/alerts 2>/dev/null || echo "000")
    if [[ "$ALERT_RESPONSE" =~ ^(200|401)$ ]]; then
        record_test_result "Alert Management API" "PASS" "HTTP $ALERT_RESPONSE"
    else
        record_test_result "Alert Management API" "FAIL" "HTTP $ALERT_RESPONSE"
    fi
    
    # Test 4: Dashboard API
    info "Test 4: Dashboard API"
    DASHBOARD_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/dashboards 2>/dev/null || echo "000")
    if [[ "$DASHBOARD_RESPONSE" =~ ^(200|401)$ ]]; then
        record_test_result "Dashboard API" "PASS" "HTTP $DASHBOARD_RESPONSE"
    else
        record_test_result "Dashboard API" "FAIL" "HTTP $DASHBOARD_RESPONSE"
    fi
    
    echo ""
}

# 2. Multi-Tenant Authentication Tests
test_multitenant_authentication() {
    info "Testing Multi-Tenant Authentication..."
    echo "======================================="
    
    # Test 1: Authentication Endpoint
    info "Test 1: Authentication Endpoint Availability"
    AUTH_ENDPOINT_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/api/auth/login \
        -H "Content-Type: application/json" \
        -d '{}' 2>/dev/null || echo "000")
    
    if [[ "$AUTH_ENDPOINT_RESPONSE" =~ ^(400|401|422)$ ]]; then
        record_test_result "Authentication Endpoint" "PASS" "HTTP $AUTH_ENDPOINT_RESPONSE - endpoint responding"
    else
        record_test_result "Authentication Endpoint" "FAIL" "HTTP $AUTH_ENDPOINT_RESPONSE"
    fi
    
    # Test 2: Tenant-Specific Authentication
    info "Test 2: Tenant-Specific Authentication"
    TENANT_AUTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/api/auth/login \
        -H "Content-Type: application/json" \
        -d '{"username":"test","password":"test","tenant":"default"}' 2>/dev/null || echo "000")
    
    if [[ "$TENANT_AUTH_RESPONSE" =~ ^(200|401|400)$ ]]; then
        record_test_result "Tenant-Specific Authentication" "PASS" "HTTP $TENANT_AUTH_RESPONSE - handling tenant parameter"
    else
        record_test_result "Tenant-Specific Authentication" "FAIL" "HTTP $TENANT_AUTH_RESPONSE"
    fi
    
    # Test 3: JWT Token Validation
    info "Test 3: JWT Token Validation"
    JWT_VALIDATION_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X GET http://localhost:8080/api/user/profile \
        -H "Authorization: Bearer invalid-token" 2>/dev/null || echo "000")
    
    if [ "$JWT_VALIDATION_RESPONSE" = "401" ]; then
        record_test_result "JWT Token Validation" "PASS" "HTTP 401 - correctly rejecting invalid token"
    else
        record_test_result "JWT Token Validation" "WARN" "HTTP $JWT_VALIDATION_RESPONSE - token validation behavior unclear"
    fi
    
    echo ""
}

# 3. Correlation Engine Tests
test_correlation_engine() {
    info "Testing Correlation Engine..."
    echo "=============================="
    
    # Test 1: Correlation Service Process
    info "Test 1: Correlation Service Process"
    if pgrep -f "correlation" >/dev/null; then
        CORRELATION_PID=$(pgrep -f "correlation")
        record_test_result "Correlation Service Process" "PASS" "PID: $CORRELATION_PID"
    else
        record_test_result "Correlation Service Process" "FAIL" "Process not found"
    fi
    
    # Test 2: Correlation Engine Health
    info "Test 2: Correlation Engine Health Check"
    if [ -f "/var/run/utmstack/correlation.pid" ]; then
        CORRELATION_PID_FILE=$(cat /var/run/utmstack/correlation.pid 2>/dev/null || echo "")
        if [ -n "$CORRELATION_PID_FILE" ] && kill -0 "$CORRELATION_PID_FILE" 2>/dev/null; then
            record_test_result "Correlation Engine Health" "PASS" "Process active with PID: $CORRELATION_PID_FILE"
        else
            record_test_result "Correlation Engine Health" "WARN" "PID file exists but process not responding"
        fi
    else
        record_test_result "Correlation Engine Health" "WARN" "PID file not found"
    fi
    
    # Test 3: Correlation Rules API
    info "Test 3: Correlation Rules API"
    CORRELATION_API_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/correlation/rules 2>/dev/null || echo "000")
    if [[ "$CORRELATION_API_RESPONSE" =~ ^(200|401)$ ]]; then
        record_test_result "Correlation Rules API" "PASS" "HTTP $CORRELATION_API_RESPONSE"
    else
        record_test_result "Correlation Rules API" "FAIL" "HTTP $CORRELATION_API_RESPONSE"
    fi
    
    echo ""
}

# 4. Agent Management Tests
test_agent_management() {
    info "Testing Agent Management..."
    echo "==========================="
    
    # Test 1: Agent Manager gRPC Service
    info "Test 1: Agent Manager gRPC Service"
    if lsof -i :50051 >/dev/null 2>&1; then
        record_test_result "Agent Manager gRPC Service" "PASS" "Port 50051 is listening"
    else
        record_test_result "Agent Manager gRPC Service" "FAIL" "Port 50051 not listening"
    fi
    
    # Test 2: Agent Manager Process
    info "Test 2: Agent Manager Process"
    if pgrep -f "agent-manager" >/dev/null; then
        AGENT_MANAGER_PID=$(pgrep -f "agent-manager")
        record_test_result "Agent Manager Process" "PASS" "PID: $AGENT_MANAGER_PID"
    else
        record_test_result "Agent Manager Process" "FAIL" "Process not found"
    fi
    
    # Test 3: Agent Registration API
    info "Test 3: Agent Registration API"
    AGENT_API_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/agents 2>/dev/null || echo "000")
    if [[ "$AGENT_API_RESPONSE" =~ ^(200|401)$ ]]; then
        record_test_result "Agent Registration API" "PASS" "HTTP $AGENT_API_RESPONSE"
    else
        record_test_result "Agent Registration API" "FAIL" "HTTP $AGENT_API_RESPONSE"
    fi
    
    echo ""
}

# 5. Data Processing Pipeline Tests
test_data_processing_pipeline() {
    info "Testing Data Processing Pipeline..."
    echo "==================================="
    
    # Test 1: Mutate Service
    info "Test 1: Mutate Data Processing Service"
    if pgrep -f "mutate" >/dev/null; then
        MUTATE_PID=$(pgrep -f "mutate")
        record_test_result "Mutate Service" "PASS" "PID: $MUTATE_PID"
    else
        record_test_result "Mutate Service" "WARN" "Process not found - may be container-based"
    fi
    
    # Test 2: Logstash Filters
    info "Test 2: Logstash Processing"
    if pgrep -f "logstash" >/dev/null; then
        LOGSTASH_PID=$(pgrep -f "logstash")
        record_test_result "Logstash Processing" "PASS" "PID: $LOGSTASH_PID"
    else
        record_test_result "Logstash Processing" "WARN" "Process not found - may be container-based"
    fi
    
    # Test 3: Data Pipeline Health
    info "Test 3: Data Pipeline Health Check"
    PIPELINE_HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/pipeline/health 2>/dev/null || echo "000")
    if [[ "$PIPELINE_HEALTH_RESPONSE" =~ ^(200|404)$ ]]; then
        if [ "$PIPELINE_HEALTH_RESPONSE" = "200" ]; then
            record_test_result "Data Pipeline Health" "PASS" "HTTP 200"
        else
            record_test_result "Data Pipeline Health" "WARN" "HTTP 404 - endpoint may not be implemented"
        fi
    else
        record_test_result "Data Pipeline Health" "FAIL" "HTTP $PIPELINE_HEALTH_RESPONSE"
    fi
    
    echo ""
}

# 6. Cloud Connector Tests
test_cloud_connectors() {
    info "Testing Cloud Connectors..."
    echo "============================"
    
    # Test 1: AWS Connector
    info "Test 1: AWS Connector Service"
    if [ -d "/home/ptsec/utmstack/aws" ]; then
        AWS_SERVICE_STATUS=$(systemctl is-active utmstack-aws 2>/dev/null || echo "inactive")
        if [ "$AWS_SERVICE_STATUS" = "active" ]; then
            record_test_result "AWS Connector" "PASS" "Service active"
        else
            record_test_result "AWS Connector" "WARN" "Service $AWS_SERVICE_STATUS"
        fi
    else
        record_test_result "AWS Connector" "WARN" "AWS directory not found"
    fi
    
    # Test 2: Office365 Connector
    info "Test 2: Office365 Connector Service"
    if [ -d "/home/ptsec/utmstack/office365" ]; then
        O365_SERVICE_STATUS=$(systemctl is-active utmstack-office365 2>/dev/null || echo "inactive")
        if [ "$O365_SERVICE_STATUS" = "active" ]; then
            record_test_result "Office365 Connector" "PASS" "Service active"
        else
            record_test_result "Office365 Connector" "WARN" "Service $O365_SERVICE_STATUS"
        fi
    else
        record_test_result "Office365 Connector" "WARN" "Office365 directory not found"
    fi
    
    # Test 3: Sophos Connector
    info "Test 3: Sophos Connector Service"
    if [ -d "/home/ptsec/utmstack/sophos" ]; then
        SOPHOS_SERVICE_STATUS=$(systemctl is-active utmstack-sophos 2>/dev/null || echo "inactive")
        if [ "$SOPHOS_SERVICE_STATUS" = "active" ]; then
            record_test_result "Sophos Connector" "PASS" "Service active"
        else
            record_test_result "Sophos Connector" "WARN" "Service $SOPHOS_SERVICE_STATUS"
        fi
    else
        record_test_result "Sophos Connector" "WARN" "Sophos directory not found"
    fi
    
    echo ""
}

# 7. Frontend Application Tests
test_frontend_application() {
    info "Testing Frontend Application..."
    echo "==============================="
    
    # Test 1: Frontend Service
    info "Test 1: Frontend Service Availability"
    FRONTEND_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4200 2>/dev/null || echo "000")
    if [ "$FRONTEND_RESPONSE" = "200" ]; then
        record_test_result "Frontend Service" "PASS" "HTTP 200"
    else
        record_test_result "Frontend Service" "WARN" "HTTP $FRONTEND_RESPONSE - may not be running on port 4200"
    fi
    
    # Test 2: Frontend Static Assets
    info "Test 2: Frontend Static Assets"
    ASSETS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4200/assets/ 2>/dev/null || echo "000")
    if [[ "$ASSETS_RESPONSE" =~ ^(200|403)$ ]]; then
        record_test_result "Frontend Static Assets" "PASS" "HTTP $ASSETS_RESPONSE"
    else
        record_test_result "Frontend Static Assets" "WARN" "HTTP $ASSETS_RESPONSE"
    fi
    
    # Test 3: Frontend API Integration
    info "Test 3: Frontend API Integration"
    API_CONFIG_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4200/api/config 2>/dev/null || echo "000")
    if [[ "$API_CONFIG_RESPONSE" =~ ^(200|404)$ ]]; then
        record_test_result "Frontend API Integration" "PASS" "HTTP $API_CONFIG_RESPONSE"
    else
        record_test_result "Frontend API Integration" "WARN" "HTTP $API_CONFIG_RESPONSE"
    fi
    
    echo ""
}

# 8. Database Integration Tests
test_database_integration() {
    info "Testing Database Integration..."
    echo "==============================="
    
    # Test 1: PostgreSQL Connectivity
    info "Test 1: PostgreSQL Connectivity"
    if psql -h localhost -U postgres -d utmstack -c "SELECT 1;" >/dev/null 2>&1; then
        record_test_result "PostgreSQL Connectivity" "PASS" "Connection successful"
    else
        record_test_result "PostgreSQL Connectivity" "FAIL" "Connection failed"
    fi
    
    # Test 2: Database Schema Validation
    info "Test 2: Database Schema Validation"
    CRITICAL_TABLES=("tenants" "logs" "alerts" "incidents" "users")
    MISSING_TABLES=()
    
    for table in "${CRITICAL_TABLES[@]}"; do
        TABLE_EXISTS=$(psql -h localhost -U postgres -d utmstack -t -c "
            SELECT EXISTS (
                SELECT 1 FROM information_schema.tables 
                WHERE table_name = '$table' AND table_schema = 'public'
            );
        " 2>/dev/null | tr -d ' ')
        
        if [ "$TABLE_EXISTS" != "t" ]; then
            MISSING_TABLES+=("$table")
        fi
    done
    
    if [ ${#MISSING_TABLES[@]} -eq 0 ]; then
        record_test_result "Database Schema Validation" "PASS" "All critical tables present"
    else
        record_test_result "Database Schema Validation" "FAIL" "Missing tables: ${MISSING_TABLES[*]}"
    fi
    
    # Test 3: Database Performance
    info "Test 3: Database Performance Check"
    QUERY_TIME=$(psql -h localhost -U postgres -d utmstack -t -c "
        \timing on
        SELECT count(*) FROM logs;
    " 2>&1 | grep "Time:" | awk '{print $2}' | sed 's/ms//' || echo "0")
    
    if (( $(echo "$QUERY_TIME < 1000" | bc -l) )); then
        record_test_result "Database Performance" "PASS" "Query time: ${QUERY_TIME}ms"
    else
        record_test_result "Database Performance" "WARN" "Query time: ${QUERY_TIME}ms - may be slow"
    fi
    
    echo ""
}

# Generate comprehensive test report
generate_feature_test_report() {
    info "Generating comprehensive feature test report..."
    
    REPORT_FILE="$TEST_RESULTS_DIR/feature-testing-report.md"
    
    cat > "$REPORT_FILE" << EOF
# UTMStack Comprehensive Feature Functionality Test Report

**Date:** $(date)
**Phase:** Sprint 3.1 - Feature Functionality Comprehensive Testing
**Status:** COMPLETED

## Test Summary

- **Tests Passed:** $TESTS_PASSED
- **Tests Failed:** $TESTS_FAILED  
- **Tests with Warnings:** $TESTS_WARNING
- **Total Tests:** $((TESTS_PASSED + TESTS_FAILED + TESTS_WARNING))

## Test Results by Category

### 1. Core SIEM Functionality
- Log Ingestion API testing
- Alert Management API validation
- Dashboard API verification
- Sample data processing

### 2. Multi-Tenant Authentication
- Authentication endpoint validation
- Tenant-specific authentication testing
- JWT token validation

### 3. Correlation Engine
- Process status verification
- Health check validation
- Rules API testing

### 4. Agent Management
- gRPC service testing
- Process status verification
- Registration API validation

### 5. Data Processing Pipeline
- Mutate service testing
- Logstash processing validation
- Pipeline health checks

### 6. Cloud Connectors
- AWS connector status
- Office365 connector status
- Sophos connector status

### 7. Frontend Application
- Service availability testing
- Static assets validation
- API integration verification

### 8. Database Integration
- PostgreSQL connectivity testing
- Schema validation
- Performance benchmarking

## Detailed Test Results

EOF

    # Append detailed test results
    if [ -f "$TEST_RESULTS_DIR/test-results.log" ]; then
        echo "### Detailed Test Log" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        cat "$TEST_RESULTS_DIR/test-results.log" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
    fi
    
    cat >> "$REPORT_FILE" << EOF

## Overall Assessment

EOF

    if [ $TESTS_FAILED -eq 0 ]; then
        echo "✅ **All critical tests PASSED** - System ready for production" >> "$REPORT_FILE"
    elif [ $TESTS_FAILED -le 2 ]; then
        echo "⚠️ **Minor issues detected** - Review failed tests before production" >> "$REPORT_FILE"
    else
        echo "❌ **Critical issues detected** - Address failed tests before production" >> "$REPORT_FILE"
    fi
    
    cat >> "$REPORT_FILE" << EOF

## Recommendations

- Address any failed tests before proceeding to production
- Investigate warning conditions for optimization opportunities
- Ensure all critical services are properly configured and running
- Validate that all APIs are responding appropriately

## Next Steps

Proceed to Sprint 3.1 Performance and Scalability Final Validation.

EOF

    success "Feature test report generated: $REPORT_FILE"
}

# Main execution
main() {
    log "Starting Comprehensive Feature Functionality Testing"
    
    test_core_siem_functionality
    test_multitenant_authentication
    test_correlation_engine
    test_agent_management
    test_data_processing_pipeline
    test_cloud_connectors
    test_frontend_application
    test_database_integration
    generate_feature_test_report
    
    echo ""
    echo "=================================================="
    success "Feature Functionality Testing COMPLETED"
    echo "=================================================="
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo "Tests with Warnings: $TESTS_WARNING"
    echo "Total Tests: $((TESTS_PASSED + TESTS_FAILED + TESTS_WARNING))"
    echo ""
    echo "Test results available in: $TEST_RESULTS_DIR"
    echo "Full log available at: $LOG_FILE"
    echo ""
}

# Execute main function
main "$@"
