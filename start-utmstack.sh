#!/bin/bash

# UTMStack Start Script
# Starts all UTMStack SIEM platform services in the correct order

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

echo -e "${BLUE}Starting UTMStack SIEM Platform...${NC}"

# Function to start service in background
start_service() {
    local service_name=$1
    local command=$2
    local working_dir=$3
    
    echo -e "${BLUE}Starting $service_name...${NC}"
    
    # Change to working directory and start service
    cd "$working_dir"
    nohup bash -c "$command" > "$LOG_DIR/${service_name}.log" 2>&1 &
    local pid=$!
    echo "$pid" > "$LOG_DIR/${service_name}.pid"
    
    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "${GREEN}✓ $service_name started (PID: $pid)${NC}"
    else
        echo -e "${RED}✗ $service_name failed to start${NC}"
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

echo -e "${BLUE}Environment variables configured${NC}"

# Start services (skip mock-logstash if port 9600 is already in use)
echo -e "\n${YELLOW}=== Starting Infrastructure Services ===${NC}"
if ss -tuln | grep ":9600 " > /dev/null 2>&1; then
    echo -e "${YELLOW}Port 9600 already in use - skipping mock-logstash (real Logstash may be running)${NC}"
else
    start_service "mock-logstash" "python3 $BASE_DIR/mock-logstash.py" "$BASE_DIR"
fi

echo -e "\n${YELLOW}=== Starting Core Services ===${NC}"
# Check if correlation port (8080) is available, use alternative if needed
if ss -tuln | grep ":8080 " > /dev/null 2>&1; then
    echo -e "${YELLOW}Port 8080 already in use - correlation will use port 8085${NC}"
    export CORRELATION_PORT=8085
else
    export CORRELATION_PORT=8080
fi
start_service "correlation" "go run main.go" "$BASE_DIR/correlation"

# Check if agent-manager port (9000) is available
if ! ss -tuln | grep ":9000 " > /dev/null 2>&1; then
    start_service "agent-manager" "go run main.go" "$BASE_DIR/agent-manager"
else
    echo -e "${YELLOW}Port 9000 already in use - skipping agent-manager${NC}"
fi

# Check if log-auth-proxy port (8081) is available
if ! ss -tuln | grep ":8081 " > /dev/null 2>&1; then
    start_service "log-auth-proxy" "go run main.go" "$BASE_DIR/log-auth-proxy"
else
    echo -e "${YELLOW}Port 8081 already in use - skipping log-auth-proxy${NC}"
fi

echo -e "\n${YELLOW}=== Starting Backend Services ===${NC}"
# Check if backend port (8080) is available
if ss -tuln | grep ":8080 " > /dev/null 2>&1; then
    echo -e "${YELLOW}Port 8080 already in use - skipping backend (may already be running)${NC}"
else
    start_service "backend" "./mvnw spring-boot:run" "$BASE_DIR/backend"
fi

echo -e "\n${YELLOW}=== Starting Frontend Services ===${NC}"
# Check if frontend port (4200) is available
if ss -tuln | grep ":4200 " > /dev/null 2>&1; then
    echo -e "${YELLOW}Port 4200 already in use - skipping frontend (may already be running)${NC}"
else
    # Check if node_modules exists
    if [ ! -d "$BASE_DIR/frontend/node_modules" ]; then
        echo -e "${YELLOW}Installing frontend dependencies...${NC}"
        cd "$BASE_DIR/frontend"
        npm install
    fi
    start_service "frontend" "npm start" "$BASE_DIR/frontend"
fi

echo -e "\n${GREEN}=== UTMStack Platform Started Successfully ===${NC}"
echo -e "${BLUE}Services Status:${NC}"
echo -e "  Frontend:        http://localhost:4200"
echo -e "  Backend API:     http://localhost:8080"
echo -e "  Log Auth Proxy:  http://localhost:8081"

echo -e "\n${BLUE}Logs are available in: $LOG_DIR${NC}"
echo -e "\n${YELLOW}To stop all services, run: ./stop-utmstack.sh${NC}"
