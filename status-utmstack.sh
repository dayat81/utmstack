#!/bin/bash

# UTMStack Service Status Script
# Shows the current status of all UTMStack SIEM platform services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Base directory
BASE_DIR="/home/ptsec/utmstack"
LOG_DIR="$BASE_DIR/logs"

echo -e "${BLUE}UTMStack SIEM Platform - Service Status${NC}"
echo -e "${BLUE}=======================================${NC}"

# Function to check if port is in use  
port_in_use() {
    # Use lsof for more reliable port detection (supports IPv4/IPv6 and all states)
    if command -v lsof >/dev/null 2>&1; then
        lsof -iTCP:$1 -sTCP:LISTEN >/dev/null 2>&1
    else
        # Fallback to ss if lsof not available
        ss -tuln | grep ":$1 " > /dev/null 2>&1
    fi
}

# Function to check service status by PID
check_service_status() {
    local service_name=$1
    local expected_port=$2
    local pid_file="$LOG_DIR/${service_name}.pid"
    local log_file="$LOG_DIR/${service_name}.log"
    
    echo -e "\n${CYAN}━━━ $service_name ━━━${NC}"
    
    # Check PID file
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "Status: ${GREEN}✓ RUNNING${NC} (PID: $pid)"
            
            # Check if process is actually our service
            local cmd=$(ps -p "$pid" -o cmd= 2>/dev/null || echo "unknown")
            echo -e "Command: ${cmd:0:60}..."
            
            # Check port if specified
            if [ ! -z "$expected_port" ]; then
                if port_in_use "$expected_port"; then
                    echo -e "Port: ${GREEN}✓ $expected_port (listening)${NC}"
                else
                    echo -e "Port: ${YELLOW}⚠ $expected_port (not listening)${NC}"
                fi
            fi
            
            # Check log file for recent activity
            if [ -f "$log_file" ]; then
                local log_size=$(stat -c%s "$log_file" 2>/dev/null || echo "0")
                local log_modified=$(stat -c%Y "$log_file" 2>/dev/null || echo "0")
                local current_time=$(date +%s)
                local time_diff=$((current_time - log_modified))
                
                echo -e "Log: ${CYAN}$log_file${NC} (${log_size} bytes)"
                if [ $time_diff -lt 300 ]; then  # Less than 5 minutes
                    echo -e "Activity: ${GREEN}✓ Recent (${time_diff}s ago)${NC}"
                else
                    echo -e "Activity: ${YELLOW}⚠ Last update ${time_diff}s ago${NC}"
                fi
                
                # Show last few lines of log if there are errors
                if grep -i "error\|exception\|fail" "$log_file" >/dev/null 2>&1; then
                    echo -e "Issues: ${RED}⚠ Errors found in log${NC}"
                    echo -e "${YELLOW}Recent errors:${NC}"
                    grep -i "error\|exception\|fail" "$log_file" | tail -2 | sed 's/^/  /'
                else
                    echo -e "Issues: ${GREEN}✓ No errors detected${NC}"
                fi
            else
                echo -e "Log: ${RED}✗ No log file${NC}"
            fi
            
        else
            echo -e "Status: ${RED}✗ STOPPED${NC} (PID file exists but process not running)"
            rm -f "$pid_file"  # Clean up stale PID file
        fi
    else
        echo -e "Status: ${RED}✗ NOT STARTED${NC} (No PID file)"
        
        # Check if port is in use by another process
        if [ ! -z "$expected_port" ] && port_in_use "$expected_port"; then
            local port_pid=$(lsof -ti:$expected_port 2>/dev/null | head -1)
            if [ ! -z "$port_pid" ]; then
                local port_cmd=$(ps -p "$port_pid" -o cmd= 2>/dev/null || echo "unknown")
                echo -e "Port: ${YELLOW}⚠ $expected_port occupied by PID $port_pid${NC}"
                echo -e "Command: ${port_cmd:0:50}..."
            fi
        elif [ ! -z "$expected_port" ]; then
            echo -e "Port: ${GREEN}✓ $expected_port (available)${NC}"
        fi
    fi
}

# Function to check system resources
check_system_resources() {
    echo -e "\n${PURPLE}━━━ System Resources ━━━${NC}"
    
    # Memory usage
    local memory_info=$(free -h | grep "Mem:")
    local total_mem=$(echo $memory_info | awk '{print $2}')
    local used_mem=$(echo $memory_info | awk '{print $3}')
    local free_mem=$(echo $memory_info | awk '{print $4}')
    echo -e "Memory: ${total_mem} total, ${used_mem} used, ${GREEN}${free_mem} free${NC}"
    
    # Disk usage for UTMStack directory
    local disk_usage=$(df -h "$BASE_DIR" | tail -1)
    local disk_used=$(echo $disk_usage | awk '{print $5}' | sed 's/%//')
    local disk_avail=$(echo $disk_usage | awk '{print $4}')
    if [ "$disk_used" -gt 80 ]; then
        echo -e "Disk: ${RED}⚠ ${disk_used}% used${NC}, ${disk_avail} available"
    else
        echo -e "Disk: ${GREEN}✓ ${disk_used}% used${NC}, ${disk_avail} available"
    fi
    
    # Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    echo -e "Load: ${load_avg}"
}

# Function to check infrastructure services
check_infrastructure() {
    echo -e "\n${PURPLE}━━━ Infrastructure Services ━━━${NC}"
    
    # PostgreSQL
    echo -e "\n${CYAN}PostgreSQL Database:${NC}"
    if port_in_use 5432; then
        echo -e "Status: ${GREEN}✓ RUNNING${NC} (Port 5432)"
        # Try to connect
        if command -v psql >/dev/null 2>&1; then
            if PGPASSWORD=admin psql -h localhost -U postgres -d utmstack -c "SELECT 1;" >/dev/null 2>&1; then
                echo -e "Connection: ${GREEN}✓ Accessible${NC}"
            else
                echo -e "Connection: ${YELLOW}⚠ Cannot connect with test credentials${NC}"
            fi
        else
            echo -e "Connection: ${YELLOW}⚠ psql not available for testing${NC}"
        fi
    else
        echo -e "Status: ${RED}✗ NOT RUNNING${NC} (Port 5432 not listening)"
    fi
    
    # Elasticsearch
    echo -e "\n${CYAN}Elasticsearch:${NC}"
    if port_in_use 9200; then
        echo -e "Status: ${GREEN}✓ RUNNING${NC} (Port 9200)"
        # Try to get cluster health
        if command -v curl >/dev/null 2>&1; then
            local es_health=$(curl -s http://localhost:9200/_cluster/health 2>/dev/null)
            if [ ! -z "$es_health" ]; then
                local cluster_status=$(echo "$es_health" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
                case "$cluster_status" in
                    "green") echo -e "Health: ${GREEN}✓ GREEN${NC}" ;;
                    "yellow") echo -e "Health: ${YELLOW}⚠ YELLOW${NC}" ;;
                    "red") echo -e "Health: ${RED}✗ RED${NC}" ;;
                    *) echo -e "Health: ${YELLOW}⚠ Unknown${NC}" ;;
                esac
            else
                echo -e "Health: ${YELLOW}⚠ Cannot get cluster status${NC}"
            fi
        else
            echo -e "Health: ${YELLOW}⚠ curl not available for testing${NC}"
        fi
    else
        echo -e "Status: ${RED}✗ NOT RUNNING${NC} (Port 9200 not listening)"
    fi
    
    # Logstash
    echo -e "\n${CYAN}Logstash:${NC}"
    if port_in_use 9600; then
        echo -e "Status: ${GREEN}✓ RUNNING${NC} (Port 9600)"
    else
        echo -e "Status: ${RED}✗ NOT RUNNING${NC} (Port 9600 not listening)"
    fi
}

# Main execution
echo -e "${BLUE}Generated at: $(date)${NC}"

check_infrastructure

echo -e "\n${PURPLE}━━━ UTMStack Application Services ━━━${NC}"

# Check each UTMStack service
check_service_status "correlation" "8085"
check_service_status "agent-manager" "9000"  
check_service_status "log-auth-proxy" "8081"
check_service_status "soc-ai" "8084"
check_service_status "backend" "8080"
check_service_status "frontend" "4200"
check_service_status "user-auditor" "8082"
check_service_status "web-pdf" "8083"
check_service_status "mutate" ""
check_service_status "aws-connector" ""
check_service_status "office365-connector" ""
check_service_status "sophos-connector" ""
check_service_status "bitdefender-connector" ""
check_service_status "mock-logstash" "9600"

check_system_resources

# Summary
echo -e "\n${PURPLE}━━━ Summary ━━━${NC}"

running_services=0
total_services=0

for pidfile in "$LOG_DIR"/*.pid; do
    if [ -f "$pidfile" ]; then
        total_services=$((total_services + 1))
        service_name=$(basename "$pidfile" .pid)
        pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            running_services=$((running_services + 1))
        fi
    fi
done

if [ $total_services -eq 0 ]; then
    echo -e "Services: ${YELLOW}No services started via scripts${NC}"
else
    echo -e "Services: ${GREEN}$running_services/$total_services running${NC}"
    if [ $running_services -eq $total_services ]; then
        echo -e "Overall Status: ${GREEN}✓ ALL SYSTEMS OPERATIONAL${NC}"
    elif [ $running_services -gt 0 ]; then
        echo -e "Overall Status: ${YELLOW}⚠ PARTIAL OPERATION${NC}"
    else
        echo -e "Overall Status: ${RED}✗ SERVICES DOWN${NC}"
    fi
fi

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Use: ./start-utmstack-simple.sh to start services${NC}"
echo -e "${BLUE}Use: ./stop-utmstack.sh to stop services${NC}"
echo -e "${BLUE}Use: ./status-utmstack.sh to check status${NC}"
