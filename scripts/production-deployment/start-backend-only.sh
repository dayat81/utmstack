#!/bin/bash

# Start UTMStack Backend Only Script
# Starts just the backend API service with correct database configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Base directory
BASE_DIR="/home/ptsec/utmstack"
LOG_DIR="$BASE_DIR/logs"

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

echo -e "${BLUE}Starting UTMStack Backend API Service...${NC}"

# Function to check if port is in use
port_in_use() {
    if command -v lsof >/dev/null 2>&1; then
        lsof -iTCP:$1 -sTCP:LISTEN >/dev/null 2>&1
    else
        ss -tuln | grep ":$1 " > /dev/null 2>&1
    fi
}

# Set environment variables for our database setup
export SPRING_DATASOURCE_URL="jdbc:postgresql://localhost:5432/pos_db"
export SPRING_DATASOURCE_USERNAME="pos_user"
export SPRING_DATASOURCE_PASSWORD="pos_password"
export SPRING_DATASOURCE_DRIVER_CLASS_NAME="org.postgresql.Driver"

# Additional environment variables
export SPRING_PROFILES_ACTIVE="dev"
export ELASTICSEARCH_HOST="localhost"
export ELASTICSEARCH_PORT="9200"
export REDIS_HOST="localhost"
export REDIS_PORT="6379"
export REDIS_PASSWORD="utmstack_redis_pass"

# JVM options for better performance
export MAVEN_OPTS="-Xmx2g -Xms512m -XX:+UseG1GC"

# Node.js compatibility (if needed for build tools)
if command -v node >/dev/null 2>&1; then
    NODE_MAJOR=$(node -v | cut -d. -f1 | tr -d 'v')
    if [ "$NODE_MAJOR" -ge 17 ]; then
        export NODE_OPTIONS="--openssl-legacy-provider $NODE_OPTIONS"
        echo -e "${YELLOW}Node.js $NODE_MAJOR detected - enabling OpenSSL legacy provider${NC}"
    fi
fi

echo -e "${BLUE}Environment variables configured for backend${NC}"
echo -e "  Database: $SPRING_DATASOURCE_URL"
echo -e "  User: $SPRING_DATASOURCE_USERNAME"
echo -e "  Elasticsearch: $ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT"
echo -e "  Redis: $REDIS_HOST:$REDIS_PORT"

# Check if backend port is already in use and find alternative
BACKEND_PORT=8080
if port_in_use 8080; then
    echo -e "${YELLOW}Port 8080 is already in use by:${NC}"
    if command -v lsof >/dev/null 2>&1; then
        lsof -iTCP:8080 -sTCP:LISTEN
    else
        ss -tlnp | grep :8080
    fi
    
    # Try alternative ports
    for alt_port in 8082 8083 8084 8086 8087 8088 8089; do
        if ! port_in_use $alt_port; then
            BACKEND_PORT=$alt_port
            echo -e "${YELLOW}Using alternative port: $BACKEND_PORT${NC}"
            break
        fi
    done
    
    if [ "$BACKEND_PORT" = "8080" ]; then
        echo -e "${RED}No alternative ports available (8082-8089)${NC}"
        exit 1
    fi
fi

# Set server port for Spring Boot
export SERVER_PORT=$BACKEND_PORT

# Check database connectivity
echo -e "\n${BLUE}Testing database connectivity...${NC}"
if PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -c "SELECT version();" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Database connection successful${NC}"
else
    echo -e "${RED}✗ Database connection failed${NC}"
    echo -e "${RED}Please ensure PostgreSQL is running with correct credentials${NC}"
    exit 1
fi

# Check if backend can compile (quick check)
echo -e "\n${BLUE}Checking if backend can compile...${NC}"
cd "$BASE_DIR/backend"

# Try to compile without running tests first
echo -e "${YELLOW}Attempting to compile backend (this may take a few minutes)...${NC}"
if timeout 300 ./mvnw compile -DskipTests -q; then
    echo -e "${GREEN}✓ Backend compilation successful${NC}"
else
    echo -e "${RED}✗ Backend compilation failed${NC}"
    echo -e "${YELLOW}This is expected if some dependencies are missing${NC}"
    echo -e "${YELLOW}Trying to start anyway (dependencies may be resolved at runtime)${NC}"
fi

# Start the backend service
echo -e "\n${BLUE}Starting UTMStack Backend API...${NC}"
cd "$BASE_DIR/backend"

# Use Maven wrapper to start Spring Boot application
nohup ./mvnw spring-boot:run \
    -Dspring-boot.run.jvmArguments="-Xmx2g -Xms512m -XX:+UseG1GC -Dserver.port=$BACKEND_PORT" \
    > "$LOG_DIR/backend.log" 2>&1 &

BACKEND_PID=$!
echo "$BACKEND_PID" > "$LOG_DIR/backend.pid"

echo -e "${BLUE}Backend starting with PID: $BACKEND_PID${NC}"
echo -e "${YELLOW}Waiting for backend to initialize (this may take 2-3 minutes)...${NC}"

# Wait for backend to start (with timeout)
TIMEOUT=180  # 3 minutes
COUNTER=0
STARTED=false

while [ $COUNTER -lt $TIMEOUT ]; do
    if kill -0 "$BACKEND_PID" 2>/dev/null; then
        # Check if backend port is now listening
        if port_in_use $BACKEND_PORT; then
            # Test if API is responding
            if curl -s -f -m 5 http://localhost:$BACKEND_PORT/api/health >/dev/null 2>&1 || 
               curl -s -f -m 5 http://localhost:$BACKEND_PORT/actuator/health >/dev/null 2>&1; then
                STARTED=true
                break
            fi
        fi
        sleep 5
        COUNTER=$((COUNTER + 5))
        echo -n "."
    else
        echo -e "\n${RED}✗ Backend process died${NC}"
        break
    fi
done

echo ""

if [ "$STARTED" = true ]; then
    echo -e "${GREEN}✓ UTMStack Backend API started successfully!${NC}"
    echo -e "\n${BLUE}Backend Service Information:${NC}"
    echo -e "  API URL: http://localhost:$BACKEND_PORT"
    echo -e "  Process ID: $BACKEND_PID"
    echo -e "  Log file: $LOG_DIR/backend.log"
    echo -e "  Database: Connected to pos_db"
    
    echo -e "\n${BLUE}Testing API endpoints:${NC}"
    
    # Test health endpoint
    if curl -s -f http://localhost:$BACKEND_PORT/api/health >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Health endpoint: http://localhost:$BACKEND_PORT/api/health${NC}"
    elif curl -s -f http://localhost:$BACKEND_PORT/actuator/health >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Actuator health: http://localhost:$BACKEND_PORT/actuator/health${NC}"
    else
        echo -e "${YELLOW}⚠ Health endpoints not accessible yet${NC}"
    fi
    
    # Test authentication endpoint
    AUTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$BACKEND_PORT/api/authenticate 2>/dev/null || echo "000")
    if [[ "$AUTH_RESPONSE" =~ ^(200|400|404|405)$ ]]; then
        echo -e "${GREEN}✓ Authentication endpoint responding (HTTP $AUTH_RESPONSE)${NC}"
    else
        echo -e "${YELLOW}⚠ Authentication endpoint not responding${NC}"
    fi
    
    echo -e "\n${BLUE}Access URLs:${NC}"
    echo -e "  Direct Backend: http://localhost:$BACKEND_PORT"
    echo -e "  Via Load Balancer: https://localhost/api/ (needs proxy config update)"
    echo -e "  Frontend: https://localhost/ (via load balancer)"
    
    echo -e "\n${YELLOW}Backend is now running! Check logs for details:${NC}"
    echo -e "  tail -f $LOG_DIR/backend.log"
    
else
    echo -e "${RED}✗ Backend failed to start within timeout${NC}"
    echo -e "\n${YELLOW}Last few lines from backend log:${NC}"
    if [ -f "$LOG_DIR/backend.log" ]; then
        tail -10 "$LOG_DIR/backend.log"
    fi
    
    echo -e "\n${YELLOW}Troubleshooting:${NC}"
    echo -e "  1. Check database connectivity"
    echo -e "  2. Review full log: cat $LOG_DIR/backend.log"
    echo -e "  3. Check for dependency issues"
    echo -e "  4. Verify Java version (requires Java 11+)"
    
    # Kill the backend process if it's still running
    if kill -0 "$BACKEND_PID" 2>/dev/null; then
        echo -e "\n${YELLOW}Stopping backend process...${NC}"
        kill "$BACKEND_PID"
    fi
    
    exit 1
fi

echo -e "\n${GREEN}Backend startup completed!${NC}"
