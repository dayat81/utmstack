#!/bin/bash
echo "🔐 Quick Login Verification"
echo "=========================="

# Test API authentication
echo "📡 Testing API authentication..."
response=$(curl -s -w "%{http_code}" -X POST \
    "http://localhost:8080/api/authenticate" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"admin","rememberMe":false}')

http_code="${response: -3}"
if [ "$http_code" = "200" ]; then
    echo "✅ API authentication successful"
else
    echo "❌ API authentication failed: $http_code"
fi

# Test frontend availability
echo "🌐 Testing frontend availability..."
if curl -s "http://localhost:4200" | grep -q "UTMSTACK Technology"; then
    echo "✅ Frontend is responding"
else
    echo "❌ Frontend not responding properly"
fi

echo ""
echo "🔗 Access UTMStack at: http://localhost:4200"
echo "🔑 Login with: admin / admin"
