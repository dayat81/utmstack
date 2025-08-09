#!/bin/bash

# UTMStack Simple Start Script - for testing and development
# Starts available UTMStack services, skipping those already running

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Base directory
BASE_DIR="/home/ptsec/utmstack"
LOG_DIR="$BASE_DIR/logs"

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

echo -e "${BLUE}Starting UTMStack SIEM Platform (Simple Mode)...${NC}"

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

# Function to start service in background
start_service_simple() {
    local service_name=$1
    local command=$2
    local working_dir=$3
    local port=$4
    
    if [ ! -z "$port" ] && port_in_use "$port"; then
        echo -e "${YELLOW}$service_name: Port $port already in use - skipping${NC}"
        return 0
    fi
    
    echo -e "${BLUE}Starting $service_name...${NC}"
    
    # Change to working directory and start service
    cd "$working_dir"
    nohup bash -c "$command" > "$LOG_DIR/${service_name}.log" 2>&1 &
    local pid=$!
    echo "$pid" > "$LOG_DIR/${service_name}.pid"
    
    sleep 3
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "${GREEN}✓ $service_name started (PID: $pid)${NC}"
        if [ ! -z "$port" ]; then
            echo -e "  Available at: http://localhost:$port"
        fi
    else
        echo -e "${RED}✗ $service_name failed to start${NC}"
        echo -e "  Check log: $LOG_DIR/${service_name}.log"
        if [ -f "$LOG_DIR/${service_name}.log" ]; then
            echo -e "${YELLOW}  Last few log lines:${NC}"
            tail -3 "$LOG_DIR/${service_name}.log" | sed 's/^/    /'
        fi
        return 1
    fi
}

# Set environment variables
export LOGSTASH_URL=http://localhost:9600
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=utmstack
export DB_USER=postgres
export DB_PASS=admin
export ELASTICSEARCH_HOST=localhost
export ELASTICSEARCH_PORT=9200

# Node.js compatibility for Angular 7 + Node 17+
if command -v node >/dev/null 2>&1; then
    NODE_MAJOR=$(node -v | cut -d. -f1 | tr -d 'v')
    if [ "$NODE_MAJOR" -ge 17 ]; then
        export NODE_OPTIONS="--openssl-legacy-provider $NODE_OPTIONS"
        echo -e "${YELLOW}Node.js $NODE_MAJOR detected - enabling OpenSSL legacy provider for Angular 7 compatibility${NC}"
    fi
fi

echo -e "${BLUE}Environment variables configured${NC}"

echo -e "\n${YELLOW}=== Checking Available Services ===${NC}"

# Try starting each service if not already running (allow failures to continue)
start_service_simple "correlation" "PORT=8085 go run main.go" "$BASE_DIR/correlation" "8085" || true
start_service_simple "agent-manager" "go run main.go" "$BASE_DIR/agent-manager" "9000" || true
start_service_simple "log-auth-proxy" "go run main.go" "$BASE_DIR/log-auth-proxy" "8081" || true
start_service_simple "backend" "./mvnw spring-boot:run" "$BASE_DIR/backend" "8080" || true

# Check if node is available for frontend
if command -v npm >/dev/null 2>&1; then
    start_service_simple "frontend" "npm start" "$BASE_DIR/frontend" "4200" || true
else
    echo -e "${YELLOW}npm not found - skipping frontend${NC}"
fi

echo -e "\n${GREEN}=== UTMStack Services Status ===${NC}"
echo -e "${BLUE}Started services check logs in: $LOG_DIR${NC}"
echo -e "${BLUE}PIDs stored in: $LOG_DIR/*.pid${NC}"

# Show running services
echo -e "\n${BLUE}Currently running UTMStack services:${NC}"
for pidfile in "$LOG_DIR"/*.pid; do
    if [ -f "$pidfile" ]; then
        service_name=$(basename "$pidfile" .pid)
        pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${GREEN}✓ $service_name (PID: $pid)${NC}"
        else
            echo -e "${RED}✗ $service_name (not running)${NC}"
        fi
    fi
done

echo -e "\n${YELLOW}To stop all services, run: ./stop-utmstack.sh${NC}"
