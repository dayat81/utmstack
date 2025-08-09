#!/bin/bash

# UTMStack Stop Script
# Stops all UTMStack SIEM platform services

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

echo -e "${BLUE}Stopping UTMStack SIEM Platform...${NC}"

# Function to stop service by PID file
stop_service_by_pid() {
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

# Stop services in reverse order
echo -e "\n${YELLOW}=== Stopping Frontend Services ===${NC}"
stop_service_by_pid "frontend"

echo -e "\n${YELLOW}=== Stopping Backend Services ===${NC}"
stop_service_by_pid "backend"

echo -e "\n${YELLOW}=== Stopping Core Services ===${NC}"
stop_service_by_pid "log-auth-proxy"
stop_service_by_pid "agent-manager"
stop_service_by_pid "correlation"

echo -e "\n${YELLOW}=== Stopping Infrastructure Services ===${NC}"
stop_service_by_pid "mock-logstash"

# Clean up any remaining processes
pkill -f "UtmstackApp" 2>/dev/null || true
pkill -f "ng serve" 2>/dev/null || true

echo -e "\n${GREEN}=== UTMStack Platform Stopped Successfully ===${NC}"
