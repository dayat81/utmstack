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

# Start services
echo -e "\n${YELLOW}=== Starting Infrastructure Services ===${NC}"
start_service "mock-logstash" "python3 $BASE_DIR/mock-logstash.py" "$BASE_DIR"

echo -e "\n${YELLOW}=== Starting Core Services ===${NC}"
start_service "correlation" "go run main.go" "$BASE_DIR/correlation"
start_service "agent-manager" "go run main.go" "$BASE_DIR/agent-manager"
start_service "log-auth-proxy" "go run main.go" "$BASE_DIR/log-auth-proxy"

echo -e "\n${YELLOW}=== Starting Backend Services ===${NC}"
start_service "backend" "./mvnw spring-boot:run" "$BASE_DIR/backend"

echo -e "\n${YELLOW}=== Starting Frontend Services ===${NC}"
if [ ! -d "$BASE_DIR/frontend/node_modules" ]; then
    echo -e "${YELLOW}Installing frontend dependencies...${NC}"
    cd "$BASE_DIR/frontend"
    npm install
fi
start_service "frontend" "npm start" "$BASE_DIR/frontend"

echo -e "\n${GREEN}=== UTMStack Platform Started Successfully ===${NC}"
echo -e "${BLUE}Services Status:${NC}"
echo -e "  Frontend:        http://localhost:4200"
echo -e "  Backend API:     http://localhost:8080"
echo -e "  Log Auth Proxy:  http://localhost:8081"

echo -e "\n${BLUE}Logs are available in: $LOG_DIR${NC}"
echo -e "\n${YELLOW}To stop all services, run: ./stop-utmstack.sh${NC}"
