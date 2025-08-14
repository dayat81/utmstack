#!/bin/bash

# UTMStack Service Manager
# Unified script to start, stop, and check status of all UTMStack services
# Usage: ./utmstack-manager.sh [start|stop|status|restart]

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
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LOG_DIR="$BASE_DIR/logs"

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to print usage
print_usage() {
    echo -e "${BLUE}UTMStack Service Manager${NC}"
    echo -e "${BLUE}Usage: $0 [start|stop|status|restart]${NC}"
    echo -e ""
    echo -e "Commands:"
    echo -e "  ${GREEN}start${NC}   - Start all UTMStack services"
    echo -e "  ${GREEN}stop${NC}    - Stop all UTMStack services"
    echo -e "  ${GREEN}status${NC}  - Show status of all services"
    echo -e "  ${GREEN}restart${NC} - Restart all services (stop + start)"
    echo -e ""
    echo -e "Examples:"
    echo -e "  $0 start     # Start all services"
    echo -e "  $0 status    # Check service status"
    echo -e "  $0 stop      # Stop all services"
}

# Function to check if port is in use
port_in_use() {
    if command -v lsof >/dev/null 2>&1; then
        lsof -iTCP:$1 -sTCP:LISTEN >/dev/null 2>&1
    else
        ss -tuln | grep ":$1 " > /dev/null 2>&1
    fi
}

# Function to start service in background
start_service() {
    local service_name=$1
    local command=$2
    local working_dir=$3
    local port=$4
    
    if [ ! -z "$port" ] && port_in_use "$port"; then
        echo -e "${YELLOW}$service_name: Port $port already in use - skipping${NC}"
        return 0
    fi
    
    echo -e "${BLUE}Starting $service_name...${NC}"
    
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
        return 0
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

# Function to stop service by PID file
stop_service() {
    local service_name=$1
    local pid_file="$LOG_DIR/${service_name}.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${BLUE}Stopping $service_name (PID: $pid)...${NC}"
            kill -TERM "$pid" 2>/dev/null || true
            
            # Wait for graceful shutdown
            local count=0
            while [ $count -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
                sleep 1
                count=$((count + 1))
            done
            
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                echo -e "${YELLOW}Force killing $service_name...${NC}"
                kill -KILL "$pid" 2>/dev/null || true
            fi
            
            echo -e "${GREEN}✓ $service_name stopped${NC}"
        else
            echo -e "${YELLOW}$service_name was not running${NC}"
        fi
        rm -f "$pid_file"
    else
        echo -e "${YELLOW}No PID file found for $service_name${NC}"
    fi
}

# Function to check service status
check_service_status() {
    local service_name=$1
    local expected_port=$2
    local pid_file="$LOG_DIR/${service_name}.pid"
    local log_file="$LOG_DIR/${service_name}.log"
    
    echo -e "\n${CYAN}━━━ $service_name ━━━${NC}"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "Status: ${GREEN}✓ RUNNING${NC} (PID: $pid)"
            
            if [ ! -z "$expected_port" ]; then
                if port_in_use "$expected_port"; then
                    echo -e "Port: ${GREEN}✓ $expected_port (listening)${NC}"
                else
                    echo -e "Port: ${YELLOW}⚠ $expected_port (not listening)${NC}"
                fi
            fi
            
            if [ -f "$log_file" ]; then
                local log_size=$(stat -c%s "$log_file" 2>/dev/null || echo "0")
                echo -e "Log: ${CYAN}$log_file${NC} (${log_size} bytes)"
                
                if grep -i "error\|exception\|fail" "$log_file" >/dev/null 2>&1; then
                    echo -e "Issues: ${RED}⚠ Errors found in log${NC}"
                else
                    echo -e "Issues: ${GREEN}✓ No errors detected${NC}"
                fi
            fi
        else
            echo -e "Status: ${RED}✗ STOPPED${NC} (PID file exists but process not running)"
            rm -f "$pid_file"
        fi
    else
        echo -e "Status: ${RED}✗ NOT STARTED${NC} (No PID file)"
        
        if [ ! -z "$expected_port" ] && port_in_use "$expected_port"; then
            local port_pid=$(lsof -ti:$expected_port 2>/dev/null | head -1)
            if [ ! -z "$port_pid" ]; then
                echo -e "Port: ${YELLOW}⚠ $expected_port occupied by PID $port_pid${NC}"
            fi
        elif [ ! -z "$expected_port" ]; then
            echo -e "Port: ${GREEN}✓ $expected_port (available)${NC}"
        fi
    fi
}

# Function to start all services
start_all_services() {
    echo -e "${BLUE}Starting UTMStack SIEM Platform...${NC}"

    # Node.js compatibility for Angular 7 + Node 17+
    if command -v node >/dev/null 2>&1; then
        NODE_MAJOR=$(node -v | cut -d. -f1 | tr -d 'v')
        if [ "$NODE_MAJOR" -ge 17 ]; then
            export NODE_OPTIONS="--openssl-legacy-provider $NODE_OPTIONS"
            echo -e "${YELLOW}Node.js $NODE_MAJOR detected - enabling OpenSSL legacy provider${NC}"
        fi
    fi

    echo -e "\n${YELLOW}=== Building Backend Service (Maven) ===${NC}"
    if [ -f "$BASE_DIR/backend/mvnw" ]; then
        echo -e "${BLUE}Building backend with Maven Wrapper...${NC}"
        cd "$BASE_DIR/backend"
        ./mvnw clean package -DskipTests
        cd "$BASE_DIR"
        echo -e "${GREEN}✓ Backend build complete${NC}"
    else
        echo -e "${RED}✗ Maven wrapper not found in backend directory - skipping build${NC}"
    fi

    echo -e "\n${YELLOW}=== Starting Backend and Core Services with Docker Compose ===${NC}"
    echo -e "${BLUE}Services: Backend API, Agent Manager, Correlation, Database, etc.${NC}"
    docker-compose up -d --build
    
    echo -e "\n${YELLOW}=== Starting Frontend Service (Native) ===${NC}"
    echo -e "${BLUE}Running Angular frontend with hot reload enabled${NC}"
    if command -v npm >/dev/null 2>&1; then
        if [ ! -d "$BASE_DIR/frontend/node_modules" ]; then
            echo -e "${YELLOW}Installing frontend dependencies...${NC}"
            cd "$BASE_DIR/frontend"
            npm install
        fi
        start_service "frontend" "npm start -- --host 0.0.0.0 --poll=1000 --live-reload" "$BASE_DIR/frontend" "4200"
    else
        echo -e "${RED}✗ npm not found - frontend cannot be started${NC}"
        echo -e "${YELLOW}  Please install Node.js and npm to run the frontend${NC}"
    fi
    
    # Wait for services to fully start
    echo -e "\n${BLUE}Waiting for services to initialize...${NC}"
    sleep 10
    
    echo -e "\n${GREEN}=== Startup Complete ===${NC}"
    echo -e "${GREEN}✓ All services started successfully${NC}"
    echo -e "${BLUE}Services Status:${NC}"
    echo -e "  Frontend (Hot Reload): http://localhost:4200"
    echo -e "  Backend API (Docker): http://localhost:8080"
    echo -e "  Log Auth Proxy:       http://localhost:8081"
    echo -e "  Agent Manager:        http://localhost:9000"
    echo -e "  Correlation:          http://localhost:8085"
    
    echo -e "\n${BLUE}Logs:${NC}"
    echo -e "  Frontend: $LOG_DIR/frontend.log"
    echo -e "  Docker services: 'docker-compose logs [service]'"
}

# Function to stop all services
stop_all_services() {
    echo -e "${BLUE}Stopping UTMStack SIEM Platform...${NC}"
    
    echo -e "\n${YELLOW}=== Stopping Frontend Service (Native) ===${NC}"
    stop_service "frontend"
    
    echo -e "\n${YELLOW}=== Stopping Backend and Core Services (Docker) ===${NC}"
    docker-compose down
    
    # Clean up any remaining processes
    pkill -f "ng serve" 2>/dev/null || true
    
    echo -e "\n${GREEN}✓ All services stopped successfully${NC}"
}

# Function to show status of all services
show_status() {
    echo -e "${BLUE}UTMStack SIEM Platform - Service Status${NC}"
    echo -e "${BLUE}=======================================${NC}"
    echo -e "${BLUE}Generated at: $(date)${NC}"
    
    echo -e "\n${PURPLE}━━━ Frontend Service (Native) ━━━${NC}"
    check_service_status "frontend" "4200"

    echo -e "\n${PURPLE}━━━ Backend Services (Docker) ━━━${NC}"
    docker-compose ps

    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Main execution
case "${1:-}" in
    start)
        start_all_services
        ;;
    stop)
        stop_all_services
        ;;
    status)
        show_status
        ;;
    restart)
        echo -e "${BLUE}Restarting UTMStack services...${NC}"
        stop_all_services
        echo -e "\n${BLUE}Waiting before restart...${NC}"
        sleep 5
        start_all_services
        ;;
    *)
        print_usage
        exit 1
        ;;
esac
