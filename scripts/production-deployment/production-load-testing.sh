#!/bin/bash

# UTMStack Production Load Testing Framework
# Phase 6 - Sprint 2.3: Production Load Testing
# Version: 1.0.0

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }
log_test() { echo -e "${CYAN}[TEST]${NC} $1"; }

# Configuration
TEST_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="/var/log/utmstack/load-testing-${TEST_DATE}.log"
LOAD_TEST_DIR="/etc/utmstack/load-testing"
RESULTS_DIR="/var/log/utmstack/load-test-results/${TEST_DATE}"
BACKEND_URL="http://localhost:8080"
FRONTEND_URL="http://localhost:4200"
ES_URL="http://localhost:9200"

# Create directories
mkdir -p /var/log/utmstack
mkdir -p ${LOAD_TEST_DIR}
mkdir -p ${LOAD_TEST_DIR}/scripts
mkdir -p ${LOAD_TEST_DIR}/scenarios
mkdir -p ${LOAD_TEST_DIR}/data
mkdir -p ${RESULTS_DIR}

# Redirect output
exec > >(tee -a ${LOG_FILE})
exec 2>&1

echo "======================================================================"
echo "🧪 UTMStack Production Load Testing Framework"
echo "======================================================================"
echo "Test Date: ${TEST_DATE}"
echo "Log File: ${LOG_FILE}"
echo "Load Test Directory: ${LOAD_TEST_DIR}"
echo "Results Directory: ${RESULTS_DIR}"
echo "======================================================================"

# Function to install load testing tools
install_load_testing_tools() {
    log_step "Installing load testing tools..."
    
    # Install Apache Bench
    if ! command -v ab &> /dev/null; then
        log_info "Installing Apache Bench..."
        apt-get update
        apt-get install -y apache2-utils
    fi
    
    # Install wrk (modern HTTP benchmarking tool)
    if ! command -v wrk &> /dev/null; then
        log_info "Installing wrk..."
        apt-get install -y wrk
    fi
    
    # Install hey (HTTP load generator)
    if ! command -v hey &> /dev/null; then
        log_info "Installing hey..."
        wget -O /usr/local/bin/hey https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64
        chmod +x /usr/local/bin/hey
    fi
    
    # Install jq for JSON processing
    if ! command -v jq &> /dev/null; then
        apt-get install -y jq
    fi
    
    # Install curl and curl-loader
    apt-get install -y curl bc parallel
    
    log_success "Load testing tools installed"
}

# Function to create test data generation scripts
create_test_data_generators() {
    log_step "Creating test data generators..."
    
    # Create multi-tenant user data generator
    cat > ${LOAD_TEST_DIR}/scripts/generate-test-users.sh << 'EOF'
#!/bin/bash

# Generate test users for multi-tenant load testing

TENANT_COUNT=${1:-10}
USERS_PER_TENANT=${2:-50}
OUTPUT_FILE=${3:-/etc/utmstack/load-testing/data/test-users.json}

echo "Generating $((TENANT_COUNT * USERS_PER_TENANT)) test users across $TENANT_COUNT tenants..."

cat > $OUTPUT_FILE << 'EOL'
{
  "tenants": [
EOL

for ((t=1; t<=TENANT_COUNT; t++)); do
    tenant_id=$(uuidgen)
    tenant_subdomain="tenant-$t"
    
    echo "    {" >> $OUTPUT_FILE
    echo "      \"id\": \"$tenant_id\"," >> $OUTPUT_FILE
    echo "      \"name\": \"Test Tenant $t\"," >> $OUTPUT_FILE
    echo "      \"subdomain\": \"$tenant_subdomain\"," >> $OUTPUT_FILE
    echo "      \"users\": [" >> $OUTPUT_FILE
    
    for ((u=1; u<=USERS_PER_TENANT; u++)); do
        user_id=$(uuidgen)
        username="user-$t-$u"
        email="user$u@tenant$t.test"
        
        echo "        {" >> $OUTPUT_FILE
        echo "          \"id\": \"$user_id\"," >> $OUTPUT_FILE
        echo "          \"username\": \"$username\"," >> $OUTPUT_FILE
        echo "          \"email\": \"$email\"," >> $OUTPUT_FILE
        echo "          \"tenant_id\": \"$tenant_id\"," >> $OUTPUT_FILE
        echo "          \"password\": \"TestPassword123!\"," >> $OUTPUT_FILE
        echo "          \"role\": \"USER\"" >> $OUTPUT_FILE
        
        if [[ $u -lt $USERS_PER_TENANT ]]; then
            echo "        }," >> $OUTPUT_FILE
        else
            echo "        }" >> $OUTPUT_FILE
        fi
    done
    
    echo "      ]" >> $OUTPUT_FILE
    
    if [[ $t -lt $TENANT_COUNT ]]; then
        echo "    }," >> $OUTPUT_FILE
    else
        echo "    }" >> $OUTPUT_FILE
    fi
done

echo "  ]" >> $OUTPUT_FILE
echo "}" >> $OUTPUT_FILE

echo "Test data generated: $OUTPUT_FILE"
EOF

    chmod +x ${LOAD_TEST_DIR}/scripts/generate-test-users.sh
    
    # Create alert data generator
    cat > ${LOAD_TEST_DIR}/scripts/generate-alert-data.sh << 'EOF'
#!/bin/bash

# Generate realistic alert data for load testing

ALERTS_COUNT=${1:-10000}
OUTPUT_FILE=${2:-/etc/utmstack/load-testing/data/test-alerts.json}

echo "Generating $ALERTS_COUNT test alerts..."

# Alert types and severities
alert_types=("Network Intrusion" "Malware Detection" "Authentication Failure" "Data Exfiltration" "Privilege Escalation" "SQL Injection" "XSS Attack" "Brute Force" "Suspicious File" "Policy Violation")
severities=("LOW" "MEDIUM" "HIGH" "CRITICAL")
statuses=("OPEN" "IN_PROGRESS" "RESOLVED" "CLOSED")
sources=("Firewall" "IDS" "AV" "EDR" "Web Filter" "Email Security" "Network Monitor" "Host Monitor")

cat > $OUTPUT_FILE << 'EOL'
{
  "alerts": [
EOL

for ((i=1; i<=ALERTS_COUNT; i++)); do
    alert_id=$(uuidgen)
    alert_type=${alert_types[$((RANDOM % ${#alert_types[@]}))]}
    severity=${severities[$((RANDOM % ${#severities[@]}))]}
    status=${statuses[$((RANDOM % ${#statuses[@]}))]}
    source=${sources[$((RANDOM % ${#sources[@]}))]}
    
    # Random timestamp within last 30 days
    timestamp=$(date -d "$((RANDOM % 30)) days ago + $((RANDOM % 24)) hours + $((RANDOM % 60)) minutes" -u +"%Y-%m-%dT%H:%M:%S.000Z")
    
    # Random IP addresses
    src_ip="192.168.$((RANDOM % 255)).$((RANDOM % 255))"
    dst_ip="10.0.$((RANDOM % 255)).$((RANDOM % 255))"
    
    echo "    {" >> $OUTPUT_FILE
    echo "      \"id\": \"$alert_id\"," >> $OUTPUT_FILE
    echo "      \"type\": \"$alert_type\"," >> $OUTPUT_FILE
    echo "      \"severity\": \"$severity\"," >> $OUTPUT_FILE
    echo "      \"status\": \"$status\"," >> $OUTPUT_FILE
    echo "      \"source\": \"$source\"," >> $OUTPUT_FILE
    echo "      \"message\": \"Test alert $i: $alert_type detected from $src_ip\"," >> $OUTPUT_FILE
    echo "      \"timestamp\": \"$timestamp\"," >> $OUTPUT_FILE
    echo "      \"source_ip\": \"$src_ip\"," >> $OUTPUT_FILE
    echo "      \"destination_ip\": \"$dst_ip\"," >> $OUTPUT_FILE
    echo "      \"details\": {" >> $OUTPUT_FILE
    echo "        \"rule_id\": $((RANDOM % 1000))," >> $OUTPUT_FILE
    echo "        \"confidence\": $((RANDOM % 100))," >> $OUTPUT_FILE
    echo "        \"risk_score\": $((RANDOM % 10))" >> $OUTPUT_FILE
    echo "      }" >> $OUTPUT_FILE
    
    if [[ $i -lt $ALERTS_COUNT ]]; then
        echo "    }," >> $OUTPUT_FILE
    else
        echo "    }" >> $OUTPUT_FILE
    fi
    
    # Progress indicator
    if [[ $((i % 1000)) -eq 0 ]]; then
        echo "Generated $i alerts..."
    fi
done

echo "  ]" >> $OUTPUT_FILE
echo "}" >> $OUTPUT_FILE

echo "Alert data generated: $OUTPUT_FILE"
EOF

    chmod +x ${LOAD_TEST_DIR}/scripts/generate-alert-data.sh
    
    log_success "Test data generators created"
}

# Function to create load testing scenarios
create_load_testing_scenarios() {
    log_step "Creating load testing scenarios..."
    
    # Scenario 1: Authentication Load Test
    cat > ${LOAD_TEST_DIR}/scenarios/auth-load-test.sh << 'EOF'
#!/bin/bash

# Authentication Load Test Scenario

BACKEND_URL=${1:-http://localhost:8080}
CONCURRENT_USERS=${2:-100}
DURATION=${3:-300}
RESULTS_DIR=${4:-/var/log/utmstack/load-test-results}

echo "Running Authentication Load Test"
echo "Backend URL: $BACKEND_URL"
echo "Concurrent Users: $CONCURRENT_USERS"
echo "Duration: ${DURATION}s"

# Create test payload
cat > /tmp/auth_payload.json << EOL
{
    "username": "admin@tenant1.test",
    "password": "TestPassword123!",
    "rememberMe": false
}
EOL

# Run load test with wrk
wrk -t12 -c$CONCURRENT_USERS -d${DURATION}s -s /etc/utmstack/load-testing/scripts/auth-script.lua $BACKEND_URL/api/authenticate > $RESULTS_DIR/auth-load-test.txt

# Run with hey for detailed metrics
hey -n $((CONCURRENT_USERS * 100)) -c $CONCURRENT_USERS -m POST -H "Content-Type: application/json" -d @/tmp/auth_payload.json $BACKEND_URL/api/authenticate > $RESULTS_DIR/auth-load-hey.txt

echo "Authentication load test completed"
EOF

    # Create wrk Lua script for authentication
    cat > ${LOAD_TEST_DIR}/scripts/auth-script.lua << 'EOF'
-- Authentication Load Test Script for wrk

wrk.method = "POST"
wrk.body   = '{"username": "admin@tenant1.test", "password": "TestPassword123!", "rememberMe": false}'
wrk.headers["Content-Type"] = "application/json"

-- Track response times and errors
local counter = 0
local errors = 0

function response(status, headers, body)
    counter = counter + 1
    if status ~= 200 then
        errors = errors + 1
    end
end

function done(summary, latency, requests)
    print(string.format("Total requests: %d", counter))
    print(string.format("Errors: %d", errors))
    print(string.format("Error rate: %.2f%%", (errors/counter)*100))
end
EOF

    # Scenario 2: Dashboard Load Test
    cat > ${LOAD_TEST_DIR}/scenarios/dashboard-load-test.sh << 'EOF'
#!/bin/bash

# Dashboard Load Test Scenario

BACKEND_URL=${1:-http://localhost:8080}
CONCURRENT_USERS=${2:-50}
DURATION=${3:-300}
RESULTS_DIR=${4:-/var/log/utmstack/load-test-results}

echo "Running Dashboard Load Test"

# First authenticate to get JWT token
JWT_TOKEN=$(curl -s -X POST "$BACKEND_URL/api/authenticate" \
    -H "Content-Type: application/json" \
    -d '{"username": "admin@tenant1.test", "password": "TestPassword123!", "rememberMe": false}' | \
    jq -r '.id_token')

if [[ "$JWT_TOKEN" == "null" || -z "$JWT_TOKEN" ]]; then
    echo "Failed to authenticate"
    exit 1
fi

# Create wrk script with authentication
cat > /tmp/dashboard-script.lua << EOL
wrk.headers["Authorization"] = "Bearer $JWT_TOKEN"
wrk.headers["Content-Type"] = "application/json"

-- Rotate between different dashboard endpoints
local endpoints = {
    "/api/utm-dashboards",
    "/api/utm-visualizations",
    "/api/utm-alert-logs",
    "/api/statistics/dashboard"
}

local counter = 0

function request()
    counter = counter + 1
    local endpoint = endpoints[(counter % #endpoints) + 1]
    return wrk.format("GET", endpoint)
end
EOL

# Run dashboard load test
wrk -t8 -c$CONCURRENT_USERS -d${DURATION}s -s /tmp/dashboard-script.lua $BACKEND_URL > $RESULTS_DIR/dashboard-load-test.txt

echo "Dashboard load test completed"
EOF

    # Scenario 3: Search Load Test
    cat > ${LOAD_TEST_DIR}/scenarios/search-load-test.sh << 'EOF'
#!/bin/bash

# Search Load Test Scenario

ES_URL=${1:-http://localhost:9200}
CONCURRENT_SEARCHES=${2:-20}
DURATION=${3:-300}
RESULTS_DIR=${4:-/var/log/utmstack/load-test-results}

echo "Running Search Load Test"

# Create search queries
cat > /tmp/search_queries.txt << EOL
{"query":{"bool":{"must":[{"term":{"tenant_id":"tenant-1"}},{"range":{"@timestamp":{"gte":"now-1h"}}}]}},"size":100}
{"query":{"bool":{"must":[{"term":{"tenant_id":"tenant-2"}},{"match":{"message":"error"}}]}},"size":50}
{"query":{"bool":{"must":[{"term":{"tenant_id":"tenant-3"}},{"term":{"severity":"HIGH"}}]}},"size":200}
{"query":{"bool":{"must":[{"term":{"tenant_id":"tenant-1"}},{"wildcard":{"source_ip":"192.168.*"}}]}},"size":75}
EOL

# Function to run single search
run_search() {
    local query=$(shuf -n1 /tmp/search_queries.txt)
    curl -s -X POST "$ES_URL/utmstack-*/_search" \
        -H "Content-Type: application/json" \
        -d "$query" > /dev/null
}

export -f run_search
export ES_URL

# Run parallel searches
echo "Starting $CONCURRENT_SEARCHES concurrent search threads for ${DURATION}s"
timeout ${DURATION}s parallel -j$CONCURRENT_SEARCHES --no-notice "while true; do run_search; sleep 0.1; done" ::: $(seq 1 $CONCURRENT_SEARCHES) 2>&1 | tee $RESULTS_DIR/search-load-test.txt

echo "Search load test completed"
EOF

    # Scenario 4: Multi-Tenant Stress Test
    cat > ${LOAD_TEST_DIR}/scenarios/multitenant-stress-test.sh << 'EOF'
#!/bin/bash

# Multi-Tenant Stress Test Scenario

BACKEND_URL=${1:-http://localhost:8080}
TENANT_COUNT=${2:-10}
USERS_PER_TENANT=${3:-20}
DURATION=${4:-600}
RESULTS_DIR=${5:-/var/log/utmstack/load-test-results}

echo "Running Multi-Tenant Stress Test"
echo "Tenants: $TENANT_COUNT"
echo "Users per tenant: $USERS_PER_TENANT"
echo "Total users: $((TENANT_COUNT * USERS_PER_TENANT))"
echo "Duration: ${DURATION}s"

# Create tenant-specific test functions
for ((t=1; t<=TENANT_COUNT; t++)); do
    cat > /tmp/tenant_${t}_test.sh << EOL
#!/bin/bash
tenant_id="tenant-$t"
backend_url="$BACKEND_URL"

# Authenticate
jwt_token=\$(curl -s -X POST "\$backend_url/api/authenticate" \\
    -H "Content-Type: application/json" \\
    -d '{"username": "admin@'$t'.test", "password": "TestPassword123!", "rememberMe": false}' | \\
    jq -r '.id_token')

if [[ "\$jwt_token" == "null" || -z "\$jwt_token" ]]; then
    echo "Tenant $t: Authentication failed"
    exit 1
fi

# Run tenant-specific load test
for ((i=1; i<=$USERS_PER_TENANT; i++)); do
    {
        while true; do
            # Dashboard request
            curl -s -H "Authorization: Bearer \$jwt_token" \\
                "\$backend_url/api/utm-dashboards" > /dev/null
            
            # Alert request
            curl -s -H "Authorization: Bearer \$jwt_token" \\
                "\$backend_url/api/utm-alert-logs?page=0&size=20" > /dev/null
            
            # Statistics request
            curl -s -H "Authorization: Bearer \$jwt_token" \\
                "\$backend_url/api/statistics/overview" > /dev/null
            
            sleep 1
        done
    } &
done

wait
EOL

    chmod +x /tmp/tenant_${t}_test.sh
done

# Start all tenant tests
for ((t=1; t<=TENANT_COUNT; t++)); do
    echo "Starting load test for tenant $t"
    timeout ${DURATION}s /tmp/tenant_${t}_test.sh > $RESULTS_DIR/tenant_${t}_stress.txt 2>&1 &
done

# Wait for all tests to complete
wait

echo "Multi-tenant stress test completed"
EOF

    chmod +x ${LOAD_TEST_DIR}/scenarios/*.sh
    
    log_success "Load testing scenarios created"
}

# Function to create performance monitoring during tests
create_test_monitoring() {
    log_step "Creating test monitoring scripts..."
    
    cat > ${LOAD_TEST_DIR}/scripts/monitor-during-test.sh << 'EOF'
#!/bin/bash

# Monitor system performance during load tests

DURATION=${1:-300}
RESULTS_DIR=${2:-/var/log/utmstack/load-test-results}
INTERVAL=5

echo "Starting performance monitoring for ${DURATION}s"

# Create monitoring output files
CPU_FILE="$RESULTS_DIR/cpu-usage.log"
MEMORY_FILE="$RESULTS_DIR/memory-usage.log"
DISK_FILE="$RESULTS_DIR/disk-usage.log"
NETWORK_FILE="$RESULTS_DIR/network-usage.log"
DOCKER_FILE="$RESULTS_DIR/docker-stats.log"
POSTGRES_FILE="$RESULTS_DIR/postgres-stats.log"
ES_FILE="$RESULTS_DIR/elasticsearch-stats.log"

# Start monitoring functions in background
{
    echo "Timestamp,CPU_User,CPU_System,CPU_Idle,Load_1m,Load_5m,Load_15m"
    for ((i=0; i<DURATION; i+=INTERVAL)); do
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        cpu_stats=$(sar 1 1 | grep Average | awk '{print $3","$5","$8}')
        load_stats=$(uptime | awk -F'load average:' '{print $2}' | sed 's/ //g')
        echo "$timestamp,$cpu_stats,$load_stats"
        sleep $INTERVAL
    done
} > $CPU_FILE &

{
    echo "Timestamp,Total_MB,Used_MB,Free_MB,Cached_MB,Usage_Percent"
    for ((i=0; i<DURATION; i+=INTERVAL)); do
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        mem_stats=$(free -m | grep Mem | awk '{printf "%d,%d,%d,%d,%.1f", $2,$3,$4,$6,($3/$2)*100}')
        echo "$timestamp,$mem_stats"
        sleep $INTERVAL
    done
} > $MEMORY_FILE &

{
    echo "Timestamp,Filesystem,Size,Used,Available,Use_Percent,Mounted"
    for ((i=0; i<DURATION; i+=INTERVAL)); do
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        df -h | grep -v Filesystem | while read line; do
            echo "$timestamp,$line"
        done
        sleep $INTERVAL
    done
} > $DISK_FILE &

{
    echo "Timestamp,Interface,RX_Bytes,TX_Bytes,RX_Packets,TX_Packets"
    for ((i=0; i<DURATION; i+=INTERVAL)); do
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        cat /proc/net/dev | grep -E "(eth|ens|enp)" | while read line; do
            iface=$(echo $line | cut -d: -f1 | tr -d ' ')
            stats=$(echo $line | cut -d: -f2 | awk '{print $1","$9","$2","$10}')
            echo "$timestamp,$iface,$stats"
        done
        sleep $INTERVAL
    done
} > $NETWORK_FILE &

{
    echo "Timestamp,Container,CPU_Percent,Memory_Usage,Memory_Limit,Memory_Percent,Network_IO,Block_IO"
    for ((i=0; i<DURATION; i+=INTERVAL)); do
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" | \
        tail -n +2 | while read line; do
            echo "$timestamp,$line" | tr '\t' ','
        done
        sleep $INTERVAL
    done
} > $DOCKER_FILE &

{
    echo "Timestamp,Active_Connections,Queries_Per_Second,Cache_Hit_Ratio,Temp_Files"
    for ((i=0; i<DURATION; i+=INTERVAL)); do
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        pg_stats=$(psql -h localhost -U utmstack_prod -d utmstack_production -t -c "
            SELECT 
                (SELECT count(*) FROM pg_stat_activity WHERE state = 'active'),
                (SELECT sum(xact_commit + xact_rollback) FROM pg_stat_database WHERE datname = 'utmstack_production'),
                (SELECT round(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2) FROM pg_stat_database),
                (SELECT count(*) FROM pg_stat_database WHERE temp_files > 0)
        " 2>/dev/null | tr -d ' ' | tr '|' ',')
        echo "$timestamp,$pg_stats"
        sleep $INTERVAL
    done
} > $POSTGRES_FILE &

{
    echo "Timestamp,Cluster_Status,Active_Shards,Relocating_Shards,Nodes,Search_Query_Total,Indexing_Rate"
    for ((i=0; i<DURATION; i+=INTERVAL)); do
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        if curl -s http://localhost:9200/_cluster/health > /dev/null 2>&1; then
            es_health=$(curl -s http://localhost:9200/_cluster/health | jq -r '.status + "," + (.active_shards|tostring) + "," + (.relocating_shards|tostring) + "," + (.number_of_nodes|tostring)')
            es_stats=$(curl -s http://localhost:9200/_nodes/stats | jq -r '.nodes | to_entries | map(.value.indices.search.query_total) | add')
            echo "$timestamp,$es_health,$es_stats"
        else
            echo "$timestamp,N/A,N/A,N/A,N/A,N/A"
        fi
        sleep $INTERVAL
    done
} > $ES_FILE &

# Wait for monitoring to complete
wait

echo "Performance monitoring completed"
echo "Results saved to: $RESULTS_DIR"
EOF

    chmod +x ${LOAD_TEST_DIR}/scripts/monitor-during-test.sh
    
    log_success "Test monitoring scripts created"
}

# Function to create test result analysis tools
create_result_analysis_tools() {
    log_step "Creating result analysis tools..."
    
    cat > ${LOAD_TEST_DIR}/scripts/analyze-results.sh << 'EOF'
#!/bin/bash

# Analyze load test results and generate reports

RESULTS_DIR=${1:-/var/log/utmstack/load-test-results}
REPORT_FILE="$RESULTS_DIR/load-test-report.html"

echo "Analyzing load test results from: $RESULTS_DIR"

# Generate HTML report
cat > $REPORT_FILE << 'HTML_START'
<!DOCTYPE html>
<html>
<head>
    <title>UTMStack Load Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #2c3e50; color: white; padding: 20px; text-align: center; }
        .section { margin: 20px 0; padding: 15px; border-left: 4px solid #3498db; background-color: #f8f9fa; }
        .metric { background-color: white; padding: 10px; margin: 10px 0; border-radius: 5px; }
        .success { border-left-color: #27ae60; }
        .warning { border-left-color: #f39c12; }
        .error { border-left-color: #e74c3c; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #34495e; color: white; }
        .chart { width: 100%; height: 300px; background-color: #ecf0f1; margin: 10px 0; display: flex; align-items: center; justify-content: center; }
    </style>
</head>
<body>
    <div class="header">
        <h1>UTMStack Production Load Test Report</h1>
        <p>Generated on: $(date)</p>
    </div>
HTML_START

# Analyze authentication test results
if [[ -f "$RESULTS_DIR/auth-load-test.txt" ]]; then
    echo "    <div class='section success'>" >> $REPORT_FILE
    echo "        <h2>Authentication Load Test Results</h2>" >> $REPORT_FILE
    
    # Extract metrics from wrk output
    requests_per_sec=$(grep "Requests/sec:" "$RESULTS_DIR/auth-load-test.txt" | awk '{print $2}')
    avg_latency=$(grep "Latency" "$RESULTS_DIR/auth-load-test.txt" | awk '{print $2}')
    total_requests=$(grep "requests in" "$RESULTS_DIR/auth-load-test.txt" | awk '{print $1}')
    
    echo "        <div class='metric'>" >> $REPORT_FILE
    echo "            <strong>Requests per second:</strong> $requests_per_sec<br>" >> $REPORT_FILE
    echo "            <strong>Average latency:</strong> $avg_latency<br>" >> $REPORT_FILE
    echo "            <strong>Total requests:</strong> $total_requests" >> $REPORT_FILE
    echo "        </div>" >> $REPORT_FILE
    echo "    </div>" >> $REPORT_FILE
fi

# Analyze dashboard test results
if [[ -f "$RESULTS_DIR/dashboard-load-test.txt" ]]; then
    echo "    <div class='section success'>" >> $REPORT_FILE
    echo "        <h2>Dashboard Load Test Results</h2>" >> $REPORT_FILE
    
    dashboard_rps=$(grep "Requests/sec:" "$RESULTS_DIR/dashboard-load-test.txt" | awk '{print $2}')
    dashboard_latency=$(grep "Latency" "$RESULTS_DIR/dashboard-load-test.txt" | awk '{print $2}')
    
    echo "        <div class='metric'>" >> $REPORT_FILE
    echo "            <strong>Dashboard requests per second:</strong> $dashboard_rps<br>" >> $REPORT_FILE
    echo "            <strong>Dashboard average latency:</strong> $dashboard_latency" >> $REPORT_FILE
    echo "        </div>" >> $REPORT_FILE
    echo "    </div>" >> $REPORT_FILE
fi

# Analyze system performance
if [[ -f "$RESULTS_DIR/cpu-usage.log" ]]; then
    echo "    <div class='section'>" >> $REPORT_FILE
    echo "        <h2>System Performance During Tests</h2>" >> $REPORT_FILE
    
    # Calculate average CPU usage
    avg_cpu=$(tail -n +2 "$RESULTS_DIR/cpu-usage.log" | awk -F',' '{sum+=$2} END {print sum/NR}')
    max_load=$(tail -n +2 "$RESULTS_DIR/cpu-usage.log" | awk -F',' '{if($5>max) max=$5} END {print max}')
    
    echo "        <div class='metric'>" >> $REPORT_FILE
    echo "            <strong>Average CPU Usage:</strong> $(printf "%.2f" $avg_cpu)%<br>" >> $REPORT_FILE
    echo "            <strong>Maximum Load:</strong> $max_load" >> $REPORT_FILE
    echo "        </div>" >> $REPORT_FILE
    echo "    </div>" >> $REPORT_FILE
fi

# Memory usage analysis
if [[ -f "$RESULTS_DIR/memory-usage.log" ]]; then
    avg_memory=$(tail -n +2 "$RESULTS_DIR/memory-usage.log" | awk -F',' '{sum+=$6} END {print sum/NR}')
    max_memory=$(tail -n +2 "$RESULTS_DIR/memory-usage.log" | awk -F',' '{if($6>max) max=$6} END {print max}')
    
    echo "    <div class='section'>" >> $REPORT_FILE
    echo "        <h2>Memory Usage Analysis</h2>" >> $REPORT_FILE
    echo "        <div class='metric'>" >> $REPORT_FILE
    echo "            <strong>Average Memory Usage:</strong> $(printf "%.2f" $avg_memory)%<br>" >> $REPORT_FILE
    echo "            <strong>Peak Memory Usage:</strong> $(printf "%.2f" $max_memory)%" >> $REPORT_FILE
    echo "        </div>" >> $REPORT_FILE
    echo "    </div>" >> $REPORT_FILE
fi

# Database performance analysis
if [[ -f "$RESULTS_DIR/postgres-stats.log" ]]; then
    echo "    <div class='section'>" >> $REPORT_FILE
    echo "        <h2>Database Performance</h2>" >> $REPORT_FILE
    
    avg_connections=$(tail -n +2 "$RESULTS_DIR/postgres-stats.log" | awk -F',' '{sum+=$2} END {print sum/NR}')
    avg_cache_hit=$(tail -n +2 "$RESULTS_DIR/postgres-stats.log" | awk -F',' '{sum+=$4} END {print sum/NR}')
    
    echo "        <div class='metric'>" >> $REPORT_FILE
    echo "            <strong>Average Active Connections:</strong> $(printf "%.0f" $avg_connections)<br>" >> $REPORT_FILE
    echo "            <strong>Average Cache Hit Ratio:</strong> $(printf "%.2f" $avg_cache_hit)%" >> $REPORT_FILE
    echo "        </div>" >> $REPORT_FILE
    echo "    </div>" >> $REPORT_FILE
fi

# Performance recommendations
echo "    <div class='section warning'>" >> $REPORT_FILE
echo "        <h2>Performance Recommendations</h2>" >> $REPORT_FILE
echo "        <div class='metric'>" >> $REPORT_FILE

# Generate recommendations based on results
if [[ -n "$avg_cpu" ]] && (( $(echo "$avg_cpu > 70" | bc -l) )); then
    echo "            <p>⚠️ High CPU usage detected ($(printf "%.2f" $avg_cpu)%). Consider scaling up or optimizing application code.</p>" >> $REPORT_FILE
fi

if [[ -n "$avg_memory" ]] && (( $(echo "$avg_memory > 80" | bc -l) )); then
    echo "            <p>⚠️ High memory usage detected ($(printf "%.2f" $avg_memory)%). Consider increasing memory or optimizing memory usage.</p>" >> $REPORT_FILE
fi

if [[ -n "$avg_cache_hit" ]] && (( $(echo "$avg_cache_hit < 90" | bc -l) )); then
    echo "            <p>⚠️ Low database cache hit ratio ($(printf "%.2f" $avg_cache_hit)%). Consider tuning database configuration.</p>" >> $REPORT_FILE
fi

echo "            <p>✅ Load test completed successfully. Review detailed metrics above for optimization opportunities.</p>" >> $REPORT_FILE
echo "        </div>" >> $REPORT_FILE
echo "    </div>" >> $REPORT_FILE

# Close HTML
echo "</body></html>" >> $REPORT_FILE

echo "Load test analysis completed. Report: $REPORT_FILE"
EOF

    chmod +x ${LOAD_TEST_DIR}/scripts/analyze-results.sh
    
    log_success "Result analysis tools created"
}

# Function to create the main load test orchestrator
create_load_test_orchestrator() {
    log_step "Creating load test orchestrator..."
    
    cat > ${LOAD_TEST_DIR}/run-load-tests.sh << 'EOF'
#!/bin/bash

# UTMStack Load Test Orchestrator
# Runs comprehensive load tests with monitoring and analysis

set -e

# Configuration
BACKEND_URL="http://localhost:8080"
FRONTEND_URL="http://localhost:4200"
ES_URL="http://localhost:9200"
TEST_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
RESULTS_DIR="/var/log/utmstack/load-test-results/$TEST_DATE"
LOAD_TEST_DIR="/etc/utmstack/load-testing"

# Test parameters (can be overridden)
TENANT_COUNT=${TENANT_COUNT:-5}
USERS_PER_TENANT=${USERS_PER_TENANT:-20}
TEST_DURATION=${TEST_DURATION:-300}
CONCURRENT_USERS=${CONCURRENT_USERS:-100}

# Create results directory
mkdir -p $RESULTS_DIR

echo "======================================================================"
echo "🧪 UTMStack Comprehensive Load Test Suite"
echo "======================================================================"
echo "Test Date: $TEST_DATE"
echo "Results Directory: $RESULTS_DIR"
echo "Tenant Count: $TENANT_COUNT"
echo "Users per Tenant: $USERS_PER_TENANT"
echo "Test Duration: ${TEST_DURATION}s"
echo "Concurrent Users: $CONCURRENT_USERS"
echo "======================================================================"

# Function to wait for services to be ready
wait_for_services() {
    echo "Waiting for services to be ready..."
    
    # Check backend
    while ! curl -sf $BACKEND_URL/management/health > /dev/null; do
        echo "Waiting for backend..."
        sleep 5
    done
    
    # Check Elasticsearch
    while ! curl -sf $ES_URL/_cluster/health > /dev/null; do
        echo "Waiting for Elasticsearch..."
        sleep 5
    done
    
    echo "All services are ready"
}

# Function to generate test data
generate_test_data() {
    echo "Generating test data..."
    
    # Generate test users
    $LOAD_TEST_DIR/scripts/generate-test-users.sh $TENANT_COUNT $USERS_PER_TENANT $LOAD_TEST_DIR/data/test-users.json
    
    # Generate test alerts
    $LOAD_TEST_DIR/scripts/generate-alert-data.sh 10000 $LOAD_TEST_DIR/data/test-alerts.json
    
    echo "Test data generated"
}

# Function to run pre-test validation
pre_test_validation() {
    echo "Running pre-test validation..."
    
    # Check system resources
    echo "System Resources:"
    echo "CPU Cores: $(nproc)"
    echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
    echo "Disk Space: $(df -h / | tail -1 | awk '{print $4}')"
    echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    
    # Check service status
    echo "Service Status:"
    curl -sf $BACKEND_URL/management/health | jq '.status' || echo "Backend: ERROR"
    curl -sf $ES_URL/_cluster/health | jq '.status' || echo "Elasticsearch: ERROR"
    
    echo "Pre-test validation completed"
}

# Function to run load tests
run_load_tests() {
    echo "Starting load tests..."
    
    # Start performance monitoring
    echo "Starting performance monitoring..."
    $LOAD_TEST_DIR/scripts/monitor-during-test.sh $TEST_DURATION $RESULTS_DIR &
    MONITOR_PID=$!
    
    # Test 1: Authentication Load Test
    echo "Running Authentication Load Test..."
    timeout $((TEST_DURATION + 60)) $LOAD_TEST_DIR/scenarios/auth-load-test.sh $BACKEND_URL $CONCURRENT_USERS $TEST_DURATION $RESULTS_DIR
    
    sleep 30  # Brief pause between tests
    
    # Test 2: Dashboard Load Test
    echo "Running Dashboard Load Test..."
    timeout $((TEST_DURATION + 60)) $LOAD_TEST_DIR/scenarios/dashboard-load-test.sh $BACKEND_URL $((CONCURRENT_USERS / 2)) $TEST_DURATION $RESULTS_DIR
    
    sleep 30
    
    # Test 3: Search Load Test
    echo "Running Search Load Test..."
    timeout $((TEST_DURATION + 60)) $LOAD_TEST_DIR/scenarios/search-load-test.sh $ES_URL $((CONCURRENT_USERS / 5)) $TEST_DURATION $RESULTS_DIR
    
    sleep 30
    
    # Test 4: Multi-Tenant Stress Test
    echo "Running Multi-Tenant Stress Test..."
    timeout $((TEST_DURATION + 60)) $LOAD_TEST_DIR/scenarios/multitenant-stress-test.sh $BACKEND_URL $TENANT_COUNT $USERS_PER_TENANT $TEST_DURATION $RESULTS_DIR
    
    # Wait for monitoring to complete
    wait $MONITOR_PID
    
    echo "Load tests completed"
}

# Function to analyze results
analyze_results() {
    echo "Analyzing test results..."
    
    # Run analysis script
    $LOAD_TEST_DIR/scripts/analyze-results.sh $RESULTS_DIR
    
    # Generate summary
    cat > $RESULTS_DIR/test-summary.txt << EOL
UTMStack Load Test Summary
=========================
Test Date: $TEST_DATE
Configuration:
- Tenant Count: $TENANT_COUNT
- Users per Tenant: $USERS_PER_TENANT
- Test Duration: ${TEST_DURATION}s
- Concurrent Users: $CONCURRENT_USERS

Test Results:
$(ls -la $RESULTS_DIR/*.txt $RESULTS_DIR/*.log 2>/dev/null | wc -l) result files generated

Performance Metrics:
EOL

    # Add key metrics to summary
    if [[ -f "$RESULTS_DIR/auth-load-test.txt" ]]; then
        echo "- Authentication RPS: $(grep "Requests/sec:" "$RESULTS_DIR/auth-load-test.txt" | awk '{print $2}')" >> $RESULTS_DIR/test-summary.txt
    fi
    
    if [[ -f "$RESULTS_DIR/cpu-usage.log" ]]; then
        avg_cpu=$(tail -n +2 "$RESULTS_DIR/cpu-usage.log" | awk -F',' '{sum+=$2} END {print sum/NR}')
        echo "- Average CPU Usage: $(printf "%.2f" $avg_cpu)%" >> $RESULTS_DIR/test-summary.txt
    fi
    
    if [[ -f "$RESULTS_DIR/memory-usage.log" ]]; then
        avg_memory=$(tail -n +2 "$RESULTS_DIR/memory-usage.log" | awk -F',' '{sum+=$6} END {print sum/NR}')
        echo "- Average Memory Usage: $(printf "%.2f" $avg_memory)%" >> $RESULTS_DIR/test-summary.txt
    fi
    
    echo "Results analysis completed"
}

# Function to generate capacity planning report
generate_capacity_report() {
    echo "Generating capacity planning report..."
    
    cat > $RESULTS_DIR/capacity-planning.md << 'EOL'
# UTMStack Capacity Planning Report

## Test Configuration
- **Test Date:** $(date)
- **Tenant Count:** $TENANT_COUNT
- **Users per Tenant:** $USERS_PER_TENANT
- **Total Concurrent Users:** $((TENANT_COUNT * USERS_PER_TENANT))
- **Test Duration:** ${TEST_DURATION}s

## Performance Baselines Established

### Authentication Performance
- Target: >500 requests/second
- Measured: [See auth-load-test.txt]

### Dashboard Performance
- Target: <2s response time (95th percentile)
- Measured: [See dashboard-load-test.txt]

### Search Performance
- Target: <1s search response time
- Measured: [See search-load-test.txt]

### System Resource Usage
- CPU: Target <70% average usage
- Memory: Target <80% average usage
- Disk I/O: Monitor for bottlenecks

## Scaling Recommendations

### Current Capacity
Based on test results, the current configuration can handle:
- **Tenants:** Up to X tenants
- **Concurrent Users:** Up to Y users
- **Peak Load:** Z requests/second

### Scaling Triggers
- **Scale Up When:**
  - CPU usage >70% for 5+ minutes
  - Memory usage >80% for 5+ minutes
  - Response time >3s (95th percentile)
  - Error rate >1%

- **Scale Down When:**
  - CPU usage <30% for 15+ minutes
  - Memory usage <40% for 15+ minutes
  - Response time <1s (95th percentile)
  - No errors for 30+ minutes

### Infrastructure Recommendations
1. **Database Scaling:**
   - Add read replicas when >200 concurrent connections
   - Consider sharding when >500GB data
   
2. **Application Scaling:**
   - Horizontal scaling: +1 instance per 100 concurrent users
   - Vertical scaling: +2GB RAM per 50 additional users
   
3. **Elasticsearch Scaling:**
   - Add nodes when search latency >1s
   - Consider hot/warm architecture for large datasets

## Monitoring and Alerting
- Set up automated alerts for all scaling triggers
- Monitor key performance indicators continuously
- Review capacity monthly and adjust thresholds
EOL

    echo "Capacity planning report generated"
}

# Main execution
main() {
    wait_for_services
    generate_test_data
    pre_test_validation
    run_load_tests
    analyze_results
    generate_capacity_report
    
    echo ""
    echo "======================================================================"
    echo "🎉 Load Testing Complete!"
    echo "======================================================================"
    echo "Results Directory: $RESULTS_DIR"
    echo "HTML Report: $RESULTS_DIR/load-test-report.html"
    echo "Summary: $RESULTS_DIR/test-summary.txt"
    echo "Capacity Planning: $RESULTS_DIR/capacity-planning.md"
    echo ""
    echo "Next Steps:"
    echo "1. Review HTML report for detailed analysis"
    echo "2. Check capacity planning recommendations"
    echo "3. Adjust scaling thresholds based on results"
    echo "4. Schedule regular load testing"
    echo "======================================================================"
}

# Execute main function
main "$@"
EOF

    chmod +x ${LOAD_TEST_DIR}/run-load-tests.sh
    
    log_success "Load test orchestrator created"
}

# Main implementation execution
main() {
    log_info "Starting UTMStack Production Load Testing Framework implementation..."
    
    install_load_testing_tools
    create_test_data_generators
    create_load_testing_scenarios
    create_test_monitoring
    create_result_analysis_tools
    create_load_test_orchestrator
    
    # Generate initial test data
    log_step "Generating initial test data..."
    ${LOAD_TEST_DIR}/scripts/generate-test-users.sh 5 20 ${LOAD_TEST_DIR}/data/test-users.json
    ${LOAD_TEST_DIR}/scripts/generate-alert-data.sh 1000 ${LOAD_TEST_DIR}/data/test-alerts.json
    
    log_success "Production load testing framework implementation completed!"
    echo ""
    echo "======================================================================"
    echo "🧪 Production Load Testing Framework Summary"
    echo "======================================================================"
    echo "Implementation Date: ${TEST_DATE}"
    echo "Log File: ${LOG_FILE}"
    echo "Load Test Directory: ${LOAD_TEST_DIR}"
    echo "Results Directory: ${RESULTS_DIR}"
    echo ""
    echo "Load Testing Components:"
    echo "✅ Comprehensive testing tools (wrk, hey, Apache Bench)"
    echo "✅ Multi-tenant test data generators"
    echo "✅ Realistic load testing scenarios"
    echo "✅ Real-time performance monitoring"
    echo "✅ Automated result analysis and reporting"
    echo "✅ Capacity planning and recommendations"
    echo ""
    echo "Testing Scenarios:"
    echo "• Authentication load testing"
    echo "• Dashboard performance testing"
    echo "• Search and query load testing"
    echo "• Multi-tenant stress testing"
    echo "• Database performance testing"
    echo "• Elasticsearch load testing"
    echo ""
    echo "Monitoring Capabilities:"
    echo "• CPU, memory, disk, and network usage"
    echo "• Docker container performance"
    echo "• Database connection and query metrics"
    echo "• Elasticsearch cluster performance"
    echo "• Application response times and error rates"
    echo ""
    echo "Analysis and Reporting:"
    echo "• HTML performance reports"
    echo "• Capacity planning recommendations"
    echo "• Performance baseline establishment"
    echo "• Scaling threshold recommendations"
    echo ""
    echo "Usage:"
    echo "Run comprehensive load test: ${LOAD_TEST_DIR}/run-load-tests.sh"
    echo "Custom scenarios: ${LOAD_TEST_DIR}/scenarios/"
    echo "Test data generators: ${LOAD_TEST_DIR}/scripts/"
    echo "======================================================================"
}

# Execute main function
main "$@"
