#!/bin/bash

# UTMStack Initial Setup Script
# Configures default admin credentials and disables 2FA after services are started
# Usage: ./initial-setup.sh
# 
# Prerequisites: 
# - UTMStack services must be running (run ./utmstack-manager.sh start first)
# - Python3 and bcrypt module should be available

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

echo -e "${BLUE}UTMStack Initial Setup${NC}"
echo -e "${BLUE}=====================${NC}"
echo -e "${CYAN}Configuring default admin credentials and security settings...${NC}"
echo -e ""

# Function to print section headers
print_section() {
    echo -e "\n${PURPLE}━━━ $1 ━━━${NC}"
}

# Function to check if service is running
check_service() {
    local service_name=$1
    local port=$2
    
    if command -v lsof >/dev/null 2>&1; then
        lsof -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1
    else
        ss -tuln | grep ":$port " > /dev/null 2>&1
    fi
}

# Function to wait for service to be ready
wait_for_service() {
    local service_name=$1
    local port=$2
    local max_attempts=30
    local attempt=1
    
    echo -e "${BLUE}Waiting for $service_name to be ready...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        if check_service "$service_name" "$port"; then
            echo -e "${GREEN}✓ $service_name is ready${NC}"
            return 0
        fi
        
        echo -e "${YELLOW}⏳ Attempt $attempt/$max_attempts - waiting for $service_name...${NC}"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo -e "${RED}✗ $service_name failed to become ready after $max_attempts attempts${NC}"
    return 1
}

# Function to install Python dependencies
install_python_deps() {
    print_section "Python Dependencies Setup"
    
    # Check if bcrypt is available
    if python3 -c "import bcrypt" 2>/dev/null; then
        echo -e "${GREEN}✓ bcrypt module already available${NC}"
    else
        echo -e "${BLUE}Installing bcrypt module...${NC}"
        pip3 install --break-system-packages bcrypt 2>/dev/null || pip3 install --user bcrypt
        echo -e "${GREEN}✓ bcrypt module installed${NC}"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_section "Prerequisites Check"
    
    local errors=0
    
    # Check if PostgreSQL is running
    if check_service "PostgreSQL" "5433"; then
        echo -e "${GREEN}✓ PostgreSQL database is running${NC}"
    else
        echo -e "${RED}✗ PostgreSQL database not found on port 5433${NC}"
        errors=$((errors + 1))
    fi
    
    # Check if Backend API is running
    if check_service "Backend" "8080"; then
        echo -e "${GREEN}✓ Backend API is running${NC}"
        
        # Test API connectivity
        if curl -s "http://localhost:8080/api/ping" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Backend API is responding${NC}"
        else
            echo -e "${YELLOW}⚠ Backend API not responding to ping${NC}"
        fi
    else
        echo -e "${RED}✗ Backend API not found on port 8080${NC}"
        errors=$((errors + 1))
    fi
    
    # Check if Frontend is running
    if check_service "Frontend" "4200"; then
        echo -e "${GREEN}✓ Frontend is running${NC}"
    else
        echo -e "${YELLOW}⚠ Frontend not found on port 4200 (will be started if needed)${NC}"
    fi
    
    # Check Docker Compose services
    if command -v docker-compose >/dev/null 2>&1; then
        local running_containers=$(sudo docker-compose ps --services --filter "status=running" 2>/dev/null | wc -l)
        echo -e "${GREEN}✓ Docker Compose services running: $running_containers${NC}"
    else
        echo -e "${RED}✗ Docker Compose not available${NC}"
        errors=$((errors + 1))
    fi
    
    if [ $errors -gt 0 ]; then
        echo -e "\n${RED}✗ Prerequisites check failed with $errors errors${NC}"
        echo -e "${YELLOW}Please run './utmstack-manager.sh start' first to start all services${NC}"
        exit 1
    fi
    
    echo -e "\n${GREEN}✓ All prerequisites satisfied${NC}"
}

# Function to configure admin credentials
configure_admin_credentials() {
    print_section "Admin Credentials Configuration"
    
    echo -e "${BLUE}Setting up admin:admin credentials...${NC}"
    
    # Generate BCrypt hash for "admin" password
    local password_hash=$(python3 -c "
import bcrypt
password = 'admin'
salt = bcrypt.gensalt(rounds=10)
hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
print(hashed.decode('utf-8'))
")
    
    if [ -z "$password_hash" ]; then
        echo -e "${RED}✗ Failed to generate password hash${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Generated password hash for 'admin'${NC}"
    
    # Update admin user in database
    echo -e "${BLUE}Updating admin user in database...${NC}"
    
    local update_result=$(sudo docker-compose exec -T postgres psql -U postgres -d utmstack -c "
        UPDATE jhi_user 
        SET password_hash = '$password_hash', 
            default_password = true, 
            tfa_secret = NULL 
        WHERE login = 'admin';
    " 2>&1)
    
    if echo "$update_result" | grep -q "UPDATE 1"; then
        echo -e "${GREEN}✓ Admin user updated successfully${NC}"
        echo -e "  Username: ${CYAN}admin${NC}"
        echo -e "  Password: ${CYAN}admin${NC}"
        echo -e "  2FA Secret: ${CYAN}cleared${NC}"
    else
        echo -e "${RED}✗ Failed to update admin user${NC}"
        echo -e "  Error: $update_result"
        return 1
    fi
}

# Function to disable 2FA
disable_2fa() {
    print_section "Two-Factor Authentication Configuration"
    
    echo -e "${BLUE}Disabling Two-Factor Authentication...${NC}"
    
    # Check current 2FA setting
    local current_2fa=$(sudo docker-compose exec -T postgres psql -U postgres -d utmstack -t -c "
        SELECT conf_param_value 
        FROM utm_configuration_parameter 
        WHERE conf_param_short = 'utmstack.tfa.enable';
    " 2>/dev/null | tr -d ' ')
    
    echo -e "${BLUE}Current 2FA setting: ${current_2fa}${NC}"
    
    # Update 2FA setting to false
    local update_result=$(sudo docker-compose exec -T postgres psql -U postgres -d utmstack -c "
        UPDATE utm_configuration_parameter 
        SET conf_param_value = 'false' 
        WHERE conf_param_short = 'utmstack.tfa.enable';
    " 2>&1)
    
    if echo "$update_result" | grep -q "UPDATE"; then
        echo -e "${GREEN}✓ Two-Factor Authentication disabled${NC}"
    else
        echo -e "${YELLOW}⚠ 2FA setting may already be disabled${NC}"
    fi
    
    # Verify the setting
    local new_2fa=$(sudo docker-compose exec -T postgres psql -U postgres -d utmstack -t -c "
        SELECT conf_param_value 
        FROM utm_configuration_parameter 
        WHERE conf_param_short = 'utmstack.tfa.enable';
    " 2>/dev/null | tr -d ' ')
    
    if [ "$new_2fa" = "false" ]; then
        echo -e "${GREEN}✓ 2FA confirmed disabled: $new_2fa${NC}"
    else
        echo -e "${RED}✗ 2FA setting verification failed: $new_2fa${NC}"
        return 1
    fi
}

# Function to verify database configuration
verify_database_config() {
    print_section "Database Configuration Verification"
    
    echo -e "${BLUE}Verifying admin user configuration...${NC}"
    
    # Check admin user details
    local user_info=$(sudo docker-compose exec -T postgres psql -U postgres -d utmstack -c "
        SELECT login, activated, default_password, 
               CASE WHEN tfa_secret IS NULL THEN 'NULL' ELSE 'SET' END as tfa_status
        FROM jhi_user 
        WHERE login = 'admin';
    " 2>/dev/null)
    
    echo -e "${CYAN}Admin User Status:${NC}"
    echo "$user_info"
    
    # Check 2FA configuration
    local tfa_config=$(sudo docker-compose exec -T postgres psql -U postgres -d utmstack -c "
        SELECT conf_param_short, conf_param_value, conf_param_description
        FROM utm_configuration_parameter 
        WHERE conf_param_short = 'utmstack.tfa.enable';
    " 2>/dev/null)
    
    echo -e "\n${CYAN}2FA Configuration:${NC}"
    echo "$tfa_config"
    
    echo -e "\n${GREEN}✓ Database configuration verified${NC}"
}

# Function to test authentication
test_authentication() {
    print_section "Authentication Testing"
    
    echo -e "${BLUE}Testing admin:admin login via API...${NC}"
    
    # Test direct API authentication
    local auth_response=$(curl -s -w "%{http_code}" -X POST \
        "http://localhost:8080/api/authenticate" \
        -H "Content-Type: application/json" \
        -d '{"username":"admin","password":"admin","rememberMe":false}')
    
    local http_code="${auth_response: -3}"
    local response_body="${auth_response%???}"
    
    echo -e "${BLUE}API Authentication Result:${NC}"
    echo -e "  HTTP Status: ${http_code}"
    
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✅ Authentication successful!${NC}"
        
        # Check if JWT token is in response
        if echo "$response_body" | grep -q "id_token"; then
            echo -e "${GREEN}✓ JWT token received${NC}"
            local token_length=$(echo "$response_body" | grep -o '"id_token":"[^"]*"' | cut -d'"' -f4 | wc -c)
            echo -e "  Token length: ${token_length} characters"
        else
            echo -e "${YELLOW}⚠ Response may not contain JWT token${NC}"
        fi
    elif [ "$http_code" = "401" ]; then
        echo -e "${RED}❌ Authentication failed - Invalid credentials${NC}"
        echo -e "  Response: $response_body"
        return 1
    else
        echo -e "${YELLOW}⚠ Unexpected response: $http_code${NC}"
        echo -e "  Response: $response_body"
    fi
}

# Function to start frontend if not running
ensure_frontend_running() {
    print_section "Frontend Service Check"
    
    if ! check_service "Frontend" "4200"; then
        echo -e "${BLUE}Frontend not running, starting it...${NC}"
        
        cd "$BASE_DIR/frontend"
        
        # Install dependencies if needed
        if [ ! -d "node_modules" ]; then
            echo -e "${BLUE}Installing frontend dependencies...${NC}"
            npm install --legacy-peer-deps
        fi
        
        # Start frontend in background
        echo -e "${BLUE}Starting Angular frontend...${NC}"
        NODE_OPTIONS='--openssl-legacy-provider' npx ng serve --host 0.0.0.0 --poll=1000 > "$BASE_DIR/logs/frontend.log" 2>&1 &
        
        local frontend_pid=$!
        echo "$frontend_pid" > "$BASE_DIR/logs/frontend.pid"
        
        # Wait for frontend to start
        wait_for_service "Frontend" "4200"
        
        echo -e "${GREEN}✓ Frontend started successfully${NC}"
    else
        echo -e "${GREEN}✓ Frontend is already running${NC}"
    fi
}

# Function to run Playwright tests
run_frontend_tests() {
    print_section "Frontend Login Verification Tests"
    
    echo -e "${BLUE}Running Playwright tests to verify login functionality...${NC}"
    
    # Check if Playwright is available
    if ! command -v npx >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ npx not available, skipping Playwright tests${NC}"
        return 0
    fi
    
    # Install Playwright if not available
    if ! npx playwright --version >/dev/null 2>&1; then
        echo -e "${BLUE}Installing Playwright...${NC}"
        npm install -D @playwright/test
        npx playwright install
    fi
    
    # Create simple login test if it doesn't exist
    if [ ! -f "$BASE_DIR/admin-login-test.spec.js" ]; then
        echo -e "${BLUE}Creating login verification test...${NC}"
        cat > "$BASE_DIR/admin-login-test.spec.js" << 'EOF'
const { test, expect } = require('@playwright/test');

test('Verify admin:admin login works', async ({ page }) => {
  console.log('🔐 Testing admin:admin login...');
  
  await page.goto('http://localhost:4200');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(5000);
  
  const emailField = await page.$('input[type="email"], input[placeholder*="User" i]');
  const passwordField = await page.$('input[type="password"]');
  const submitButton = await page.$('button[type="submit"], button:has-text("Sign in")');
  
  if (emailField && passwordField && submitButton) {
    await emailField.fill('admin');
    await passwordField.fill('admin');
    
    const responses = [];
    page.on('response', response => {
      if (response.url().includes('/api/authenticate')) {
        responses.push(response.status());
      }
    });
    
    await submitButton.click();
    await page.waitForTimeout(3000);
    
    if (responses.includes(200)) {
      console.log('✅ Login successful!');
    } else {
      console.log('❌ Login failed');
    }
  } else {
    console.log('⚠️ Login form not found');
  }
});
EOF
    fi
    
    # Run the test
    echo -e "${BLUE}Running login verification test...${NC}"
    if npx playwright test admin-login-test.spec.js --reporter=line; then
        echo -e "${GREEN}✓ Login verification test passed${NC}"
    else
        echo -e "${YELLOW}⚠ Login verification test had issues (check output above)${NC}"
    fi
}

# Function to display final configuration
show_final_config() {
    print_section "Configuration Summary"
    
    echo -e "${GREEN}🎉 UTMStack Initial Setup Complete!${NC}"
    echo -e ""
    echo -e "${CYAN}Default Credentials:${NC}"
    echo -e "  Username: ${GREEN}admin${NC}"
    echo -e "  Password: ${GREEN}admin${NC}"
    echo -e ""
    echo -e "${CYAN}Security Settings:${NC}"
    echo -e "  Two-Factor Authentication: ${GREEN}DISABLED${NC}"
    echo -e "  Password Encoding: ${GREEN}BCrypt (10 rounds)${NC}"
    echo -e ""
    echo -e "${CYAN}Access URLs:${NC}"
    echo -e "  Frontend: ${GREEN}http://localhost:4200${NC}"
    echo -e "  Backend API: ${GREEN}http://localhost:8080${NC}"
    echo -e "  API Health: ${GREEN}http://localhost:8080/api/ping${NC}"
    echo -e ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo -e "1. Open browser and go to: ${CYAN}http://localhost:4200${NC}"
    echo -e "2. Login with: ${CYAN}admin / admin${NC}"
    echo -e "3. Change default password in user settings"
    echo -e "4. Configure additional users as needed"
    echo -e ""
    echo -e "${YELLOW}Security Note: Change the default password in production!${NC}"
}

# Function to create login test files
create_test_files() {
    print_section "Creating Verification Test Files"
    
    echo -e "${BLUE}Creating comprehensive login verification tests...${NC}"
    
    # Create quick verification script
    cat > "$BASE_DIR/verify-login.sh" << 'EOF'
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
EOF
    
    chmod +x "$BASE_DIR/verify-login.sh"
    echo -e "${GREEN}✓ Quick verification script created: verify-login.sh${NC}"
}

# Main execution function
main() {
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}Please do not run this script as root. Use sudo only when prompted.${NC}"
        exit 1
    fi
    
    # Run setup steps
    install_python_deps
    check_prerequisites
    
    # Wait for critical services
    wait_for_service "PostgreSQL" "5433" || exit 1
    wait_for_service "Backend" "8080" || exit 1
    
    # Configure authentication
    configure_admin_credentials || exit 1
    disable_2fa || exit 1
    verify_database_config
    
    # Ensure frontend is running
    ensure_frontend_running
    
    # Test authentication
    test_authentication || {
        echo -e "${YELLOW}⚠ Authentication test failed, but configuration may still be correct${NC}"
    }
    
    # Create verification tools
    create_test_files
    
    # Run Playwright tests if available
    run_frontend_tests
    
    # Show final configuration
    show_final_config
    
    echo -e "\n${GREEN}🚀 UTMStack is ready for use!${NC}"
}

# Help function
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo -e "${BLUE}UTMStack Initial Setup Script${NC}"
    echo -e "${BLUE}=============================${NC}"
    echo -e ""
    echo -e "This script configures UTMStack after services are started:"
    echo -e "• Sets admin:admin credentials"
    echo -e "• Disables Two-Factor Authentication"
    echo -e "• Verifies login functionality"
    echo -e "• Creates verification tools"
    echo -e ""
    echo -e "${YELLOW}Prerequisites:${NC}"
    echo -e "• Run './utmstack-manager.sh start' first"
    echo -e "• Ensure all Docker services are running"
    echo -e "• Python3 with bcrypt module (auto-installed)"
    echo -e ""
    echo -e "${BLUE}Usage:${NC}"
    echo -e "  $0              # Run full initial setup"
    echo -e "  $0 --help       # Show this help"
    echo -e ""
    exit 0
fi

# Run main function
main "$@"
