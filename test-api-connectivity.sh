#!/bin/bash

# UTMStack API Connectivity Test Script
# Quick script to test basic connectivity to UTMStack services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
BACKEND_HOST="localhost:8080"
FRONTEND_HOST="localhost:4200"
AGENT_MANAGER_HOST="localhost:9000"
CORRELATION_HOST="localhost:8085"
LOG_AUTH_PROXY_HOST="localhost:8081"
TIMEOUT=5

echo -e "${BLUE}UTMStack Service Connectivity Test${NC}"
echo -e "${BLUE}=================================${NC}"
echo -e "Testing connectivity to UTMStack services...\n"

# Function to test HTTP connectivity
test_http_service() {
    local service_name="$1"
    local host="$2"
    local endpoint="$3"
    local expected_status="$4"
    
    echo -e "${CYAN}Testing $service_name at $host$endpoint${NC}"
    
    if command -v curl >/dev/null 2>&1; then
        # Use curl if available
        local response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout $TIMEOUT "http://$host$endpoint" 2>/dev/null || echo "000")
        
        if [ "$response" = "000" ]; then
            echo -e "  ${RED}✗ Connection failed - service may be down${NC}"
            return 1
        elif [ "$response" = "$expected_status" ] || [ "$expected_status" = "any" ]; then
            echo -e "  ${GREEN}✓ Connected (HTTP $response)${NC}"
            return 0
        else
            echo -e "  ${YELLOW}⚠ Connected but unexpected status (HTTP $response, expected $expected_status)${NC}"
            return 0  # Still connected, just different status
        fi
    else
        # Fallback to nc (netcat) for basic port check
        if echo -e "GET $endpoint HTTP/1.0\r\n\r\n" | nc -w $TIMEOUT ${host/:/ } >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓ Port is open and responding${NC}"
            return 0
        else
            echo -e "  ${RED}✗ Connection failed - port may be closed${NC}"
            return 1
        fi
    fi
}

# Function to test specific API endpoints
test_api_endpoints() {
    local host="$1"
    
    echo -e "\n${YELLOW}Testing Backend API Endpoints${NC}"
    echo -e "${YELLOW}============================${NC}"
    
    # Test basic endpoints that don't require authentication
    local endpoints=(
        "/api/ping:200"
        "/api/healthcheck:200"
        "/api/date-format:any"
        "/api/isInDevelop:any"
        "/api/check-credentials:any"
    )
    
    local passed=0
    local total=${#endpoints[@]}
    
    for endpoint_info in "${endpoints[@]}"; do
        IFS=':' read -r endpoint expected <<< "$endpoint_info"
        
        echo -e "${CYAN}GET $endpoint${NC}"
        
        if command -v curl >/dev/null 2>&1; then
            local response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout $TIMEOUT "http://$host$endpoint" 2>/dev/null || echo "000")
            
            if [ "$response" = "000" ]; then
                echo -e "  ${RED}✗ Connection failed${NC}"
            elif [ "$response" = "$expected" ] || [ "$expected" = "any" ]; then
                echo -e "  ${GREEN}✓ HTTP $response${NC}"
                ((passed++))
            else
                echo -e "  ${YELLOW}⚠ HTTP $response (expected $expected)${NC}"
                ((passed++))  # Still a valid response
            fi
        else
            echo -e "  ${YELLOW}⚠ curl not available, skipping detailed API test${NC}"
        fi
    done
    
    echo -e "\nAPI Test Summary: $passed/$total endpoints responded"
}

# Test each service
echo -e "${YELLOW}Service Connectivity Tests${NC}"
echo -e "${YELLOW}=========================${NC}"

services_up=0
total_services=5

# Backend API
if test_http_service "Backend API" "$BACKEND_HOST" "/api/ping" "200"; then
    ((services_up++))
fi
echo

# Frontend
if test_http_service "Frontend" "$FRONTEND_HOST" "/" "any"; then
    ((services_up++))
fi
echo

# Agent Manager
if test_http_service "Agent Manager" "$AGENT_MANAGER_HOST" "/health" "any"; then
    ((services_up++))
fi
echo

# Correlation
if test_http_service "Correlation" "$CORRELATION_HOST" "/health" "any"; then
    ((services_up++))
fi
echo

# Log Auth Proxy
if test_http_service "Log Auth Proxy" "$LOG_AUTH_PROXY_HOST" "/health" "any"; then
    ((services_up++))
fi
echo

# If backend is up, test API endpoints
if curl -s --connect-timeout $TIMEOUT "http://$BACKEND_HOST/api/ping" >/dev/null 2>&1; then
    test_api_endpoints "$BACKEND_HOST"
fi

# Overall summary
echo -e "\n${BLUE}Overall Service Status${NC}"
echo -e "${BLUE}=====================${NC}"
echo -e "Services responding: $services_up/$total_services"

if [ $services_up -eq $total_services ]; then
    echo -e "${GREEN}✓ All services are running${NC}"
    exit 0
elif [ $services_up -gt 0 ]; then
    echo -e "${YELLOW}⚠ Partial services running${NC}"
    exit 1
else
    echo -e "${RED}✗ No services responding${NC}"
    exit 2
fi
