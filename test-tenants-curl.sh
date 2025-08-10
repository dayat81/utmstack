#!/bin/bash

echo "🧪 Testing Multi-Tenant API with cURL"
echo "====================================="

# Backend URL - try both HTTP and HTTPS
BACKEND_HTTP="http://localhost:8080"
BACKEND_HTTPS="https://localhost:8080"

# Test tenant data
declare -a TENANTS=("default" "acme" "globalsec")

echo "📊 Database Verification:"
echo "Checking tenants in database..."
docker exec pos-db psql -U pos_user -d pos_db -c "SELECT id, name, subdomain, status, tier FROM utm_tenant ORDER BY created_at;"
echo ""

echo "🔍 Testing API Endpoints:"
echo ""

# Test different endpoints
ENDPOINTS=(
    "/api/tenants"
    "/api/tenant/current" 
    "/management/health"
    "/management/info"
    "/api/authenticate"
    "/"
)

for endpoint in "${ENDPOINTS[@]}"; do
    echo "Testing endpoint: $endpoint"
    
    # Test HTTP
    echo "  HTTP:"
    response=$(curl -s -w "Status: %{http_code}" "$BACKEND_HTTP$endpoint" 2>/dev/null)
    echo "    $response"
    
    # Test HTTPS
    echo "  HTTPS:"
    response=$(curl -s -k -w "Status: %{http_code}" "$BACKEND_HTTPS$endpoint" 2>/dev/null)
    echo "    $response"
    
    echo ""
done

echo "🏢 Testing Tenant-Specific Headers:"
echo ""

for tenant in "${TENANTS[@]}"; do
    echo "Testing tenant: $tenant"
    
    # Test with X-Tenant-ID header
    echo "  With X-Tenant-ID header:"
    response=$(curl -s -k -H "X-Tenant-ID: $tenant" -w "Status: %{http_code}" "$BACKEND_HTTPS/api/tenant/current" 2>/dev/null)
    echo "    $response"
    
    # Test with Host header
    echo "  With Host header:"
    response=$(curl -s -k -H "Host: $tenant.localhost" -w "Status: %{http_code}" "$BACKEND_HTTPS/api/tenant/current" 2>/dev/null)
    echo "    $response"
    
    echo ""
done

echo "🔄 Checking Service Status:"
echo ""

# Check if services are running
echo "Java processes:"
ps aux | grep java | grep -v grep

echo ""
echo "Port status:"
netstat -tlnp 2>/dev/null | grep -E "(8080|4200|9200|5432)" || echo "No UTMStack ports found"

echo ""
echo "Docker containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(postgres|elasticsearch|utmstack)"

echo ""
echo "✅ Test completed"
