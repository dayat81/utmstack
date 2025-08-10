#!/bin/bash

# Quick Health Check Script
# UTMStack Production System Status

set -euo pipefail

echo "🏥 UTMStack Quick Health Check"
echo "=============================="
echo "$(date)"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_service() {
    local service_name="$1"
    local check_command="$2"
    local expected="$3"
    
    printf "%-25s " "$service_name:"
    
    if eval "$check_command" >/dev/null 2>&1; then
        if [ "$expected" = "success" ]; then
            echo -e "${GREEN}UP${NC}"
            return 0
        else
            echo -e "${YELLOW}PARTIAL${NC}"
            return 1
        fi
    else
        echo -e "${RED}DOWN${NC}"
        return 1
    fi
}

echo "🔍 Service Status Check"
echo "----------------------"

# Database
check_service "PostgreSQL Database" "PGPASSWORD=pos_password docker exec pos-db psql -U pos_user -d pos_db -c 'SELECT 1'" "success"

# Elasticsearch
check_service "Elasticsearch" "curl -s http://localhost:9200/_cluster/health | grep -q green" "success"

# Frontend
check_service "Frontend (Angular)" "curl -s http://localhost:4200 | grep -q html" "success"

# Backend API  
check_service "Backend API" "curl -s -k https://localhost:8080/api/health | grep -q 'error\|not found'" "partial"

# Agent Manager
check_service "Agent Manager" "ss -tlnp | grep -q :8080" "success"

# Logstash
check_service "Logstash" "docker ps | grep -q utmstack-logstash" "success"

# Redis
check_service "Redis Cache" "docker exec utmstack-redis redis-cli -a utmstack_redis_pass ping | grep -q PONG" "success"

# Prometheus
check_service "Prometheus" "curl -s http://localhost:9090/-/healthy" "success"

# Grafana  
check_service "Grafana" "curl -s http://localhost:3001/api/health" "success"

# Load Balancer
check_service "Load Balancer (HTTP)" "curl -s -o /dev/null -w '%{http_code}' http://localhost/ | grep -q 301" "success"
check_service "Load Balancer (HTTPS)" "curl -s -k https://localhost/health | grep -q healthy" "success"

echo ""
echo "🐳 Container Status"
echo "------------------"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep utmstack || echo "No UTMStack containers running"

echo ""
echo "🌐 Port Status"
echo "-------------"
echo "Active ports:"
ss -tlnp | grep -E ":4200|:5432|:8080|:9200|:9600|:443" | awk '{print $4}' | sort

echo ""
echo "📊 Resource Usage"
echo "----------------"
echo "Memory: $(free -h | grep Mem | awk '{print $3"/"$2}')"
echo "Disk: $(df -h / | tail -1 | awk '{print $3"/"$2" ("$5" used)"}')"
echo "Load: $(uptime | awk -F'load average:' '{print $2}')"

echo ""
echo "🎯 Quick Status Summary"
echo "----------------------"

TOTAL_SERVICES=10
UP_SERVICES=0

# Count UP services  
if PGPASSWORD=pos_password docker exec pos-db psql -U pos_user -d pos_db -c 'SELECT 1' >/dev/null 2>&1; then ((UP_SERVICES++)); fi
if curl -s http://localhost:9200/_cluster/health | grep -q green 2>/dev/null; then ((UP_SERVICES++)); fi
if curl -s http://localhost:4200 | grep -q html 2>/dev/null; then ((UP_SERVICES++)); fi
if ss -tlnp | grep -q :8080 2>/dev/null; then ((UP_SERVICES++)); fi
if docker ps | grep -q utmstack-logstash 2>/dev/null; then ((UP_SERVICES++)); fi
if docker exec utmstack-redis redis-cli -a utmstack_redis_pass ping 2>/dev/null | grep -q PONG; then ((UP_SERVICES++)); fi
if curl -s http://localhost:9090/-/healthy 2>/dev/null >/dev/null; then ((UP_SERVICES++)); fi
if curl -s http://localhost:3001/api/health 2>/dev/null >/dev/null; then ((UP_SERVICES++)); fi
if curl -s -k https://localhost/health 2>/dev/null | grep -q healthy; then ((UP_SERVICES++)); fi

PERCENTAGE=$((UP_SERVICES * 100 / TOTAL_SERVICES))

if [ $PERCENTAGE -ge 80 ]; then
    echo -e "System Status: ${GREEN}HEALTHY${NC} ($UP_SERVICES/$TOTAL_SERVICES services up)"
elif [ $PERCENTAGE -ge 50 ]; then
    echo -e "System Status: ${YELLOW}DEGRADED${NC} ($UP_SERVICES/$TOTAL_SERVICES services up)"
else
    echo -e "System Status: ${RED}CRITICAL${NC} ($UP_SERVICES/$TOTAL_SERVICES services up)"
fi

echo ""
echo "🔗 Access URLs"
echo "-------------"
echo "Frontend:      https://localhost/ (via load balancer)"
echo "Backend API:   https://localhost/api/ (via load balancer)"
echo "Elasticsearch: https://localhost/elasticsearch/ (via load balancer)"
echo "Prometheus:    https://localhost/prometheus/ (auth: monitor/monitor)"
echo "Grafana:       https://localhost/grafana/"
echo "Health Check:  https://localhost/health"
echo ""
echo "Direct Access (development):"
echo "Frontend:      http://localhost:4200"
echo "Elasticsearch: http://localhost:9200"
echo "Backend API:   http://localhost:8080"
echo "Logstash:      http://localhost:9600"
echo "Prometheus:    http://localhost:9090"
echo "Grafana:       http://localhost:3001"
echo "Redis:         localhost:6379"

echo ""
echo "For detailed status: cat PRODUCTION_STATUS.md"

# Prometheus
check_service "Prometheus" "curl -s http://localhost:9090/-/healthy" "success"

# Grafana  
check_service "Grafana" "curl -s http://localhost:3001/api/health" "success"

# Load Balancer
check_service "Load Balancer (HTTP)" "curl -s -o /dev/null -w '%{http_code}' http://localhost/ | grep -q 301" "success"
check_service "Load Balancer (HTTPS)" "curl -s -k https://localhost/health | grep -q healthy" "success"
