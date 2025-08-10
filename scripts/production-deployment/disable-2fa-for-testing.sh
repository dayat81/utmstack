#!/bin/bash

# Disable 2FA for Testing Script
# UTMStack Development - Testing Configuration

set -euo pipefail

LOG_FILE="/tmp/utmstack-logs/disable-2fa-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$(dirname "$LOG_FILE")"

echo "🔐 UTMStack 2FA Testing Configuration"
echo "===================================="

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "$LOG_FILE"
}

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

# Check database connectivity
check_database() {
    info "Checking database connectivity..."
    
    if ! PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -c "SELECT 1;" >/dev/null 2>&1; then
        error_exit "Cannot connect to database. Please ensure database is running."
    fi
    
    success "Database connection established"
}

# Check current 2FA status
check_2fa_status() {
    info "Checking current 2FA configuration status..."
    
    # Check if configuration table exists
    TABLE_EXISTS=$(PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -t -c "
        SELECT EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_name = 'utm_configuration_parameter' AND table_schema = 'public'
        );
    " 2>/dev/null | tr -d ' ')
    
    if [ "$TABLE_EXISTS" = "t" ]; then
        # Get current 2FA setting
        CURRENT_2FA=$(PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -t -c "
            SELECT param_value FROM utm_configuration_parameter 
            WHERE param_key = 'utmstack.tfa.enable';
        " 2>/dev/null | tr -d ' ' || echo "not_found")
        
        if [ "$CURRENT_2FA" = "not_found" ]; then
            warning "2FA configuration not found in database"
        else
            info "Current 2FA setting: $CURRENT_2FA"
        fi
    else
        warning "Configuration table not found - may need to run application initialization"
    fi
}

# Disable 2FA in database
disable_2fa_database() {
    info "Disabling 2FA in database configuration..."
    
    # Update 2FA configuration to false
    PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -c "
        INSERT INTO utm_configuration_parameter 
        (id, section_id, param_key, param_name, param_description, param_value, param_required, param_type, param_datatype_validation, param_category, param_options)
        VALUES (17, 3, 'utmstack.tfa.enable', 'Enable Two Factor Authentication', NULL, 'false', true, 'bool', NULL, NULL, NULL)
        ON CONFLICT (id) DO UPDATE SET param_value = 'false';
    " >/dev/null 2>&1
    
    success "2FA disabled in database configuration"
    
    # Verify the change
    NEW_2FA=$(PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -t -c "
        SELECT param_value FROM utm_configuration_parameter 
        WHERE param_key = 'utmstack.tfa.enable';
    " 2>/dev/null | tr -d ' ')
    
    info "Updated 2FA setting: $NEW_2FA"
}

# Clear existing TFA secrets for testing
clear_tfa_secrets() {
    info "Clearing existing TFA secrets for testing..."
    
    # Check if users table has tfa_secret column
    TFA_COLUMN_EXISTS=$(PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -t -c "
        SELECT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_name = 'jhi_user' AND column_name = 'tfa_secret'
        );
    " 2>/dev/null | tr -d ' ')
    
    if [ "$TFA_COLUMN_EXISTS" = "t" ]; then
        # Clear TFA secrets for all users
        PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -c "
            UPDATE jhi_user SET tfa_secret = NULL;
        " >/dev/null 2>&1
        
        success "Cleared TFA secrets for all users"
    else
        warning "TFA secret column not found in users table"
    fi
}

# Create modified TFA service for testing (bypasses validation)
create_testing_tfa_service() {
    info "Creating testing TFA service configuration..."
    
    # Create a development override configuration
    cat > /tmp/utmstack-tfa-testing-config.properties << 'EOF'
# UTMStack 2FA Testing Configuration
# This configuration disables 2FA validation for testing purposes

# Disable 2FA globally
utmstack.tfa.enable=false

# Testing token (if 2FA is enabled)
utmstack.tfa.testing.token=123456
utmstack.tfa.testing.mode=true

# Allow bypass for testing
utmstack.tfa.bypass.enabled=true
utmstack.tfa.bypass.users=admin,test

# Development mode
spring.profiles.active=dev
EOF

    success "Testing configuration created: /tmp/utmstack-tfa-testing-config.properties"
}

# Create 2FA testing bypass script
create_2fa_bypass_service() {
    info "Creating 2FA bypass service for testing..."
    
    cat > /tmp/utmstack-2fa-bypass.java << 'EOF'
// UTMStack 2FA Testing Bypass Service
// This service provides a testing bypass for 2FA validation

package com.park.utmstack.service.tfa;

import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

@Service
@Profile("test")
public class TfaTestingService extends TfaService {
    
    private static final String TESTING_TOKEN = "123456";
    private static final boolean TESTING_MODE = true;
    
    @Override
    public boolean validateCode(String secret, String code) {
        // In testing mode, always accept the testing token
        if (TESTING_MODE && TESTING_TOKEN.equals(code)) {
            return true;
        }
        
        // For any other code, bypass validation in testing mode
        if (TESTING_MODE) {
            return true;
        }
        
        // Fall back to normal validation
        return super.validateCode(secret, code);
    }
    
    @Override
    public String generateCode(String secret) {
        // In testing mode, always return the testing token
        if (TESTING_MODE) {
            return TESTING_TOKEN;
        }
        
        return super.generateCode(secret);
    }
}
EOF

    success "2FA bypass service created for testing: /tmp/utmstack-2fa-bypass.java"
}

# Create application properties override
create_application_properties_override() {
    info "Creating application properties override for testing..."
    
    # Create development properties file
    cat > /tmp/utmstack-application-test.properties << 'EOF'
# UTMStack Testing Configuration
# Override for development and testing environments

# Disable 2FA for testing
utmstack.tfa.enable=false
utmstack.tfa.testing.mode=true
utmstack.tfa.testing.token=123456

# Development database settings
spring.datasource.url=jdbc:postgresql://localhost:5432/pos_db
spring.datasource.username=pos_user
spring.datasource.password=pos_password

# Disable security for testing APIs
management.security.enabled=false

# Enable all actuator endpoints for testing
management.endpoints.web.exposure.include=*

# Logging for debugging
logging.level.com.park.utmstack.service.tfa=DEBUG
logging.level.com.park.utmstack.web.rest.UserJWTController=DEBUG

# Development profile
spring.profiles.active=dev,test
EOF

    success "Application properties override created: /tmp/utmstack-application-test.properties"
}

# Test 2FA bypass
test_2fa_bypass() {
    info "Testing 2FA bypass configuration..."
    
    # Test if backend API is accessible
    if curl -s -k https://localhost/api/health >/dev/null 2>&1; then
        info "Backend API is accessible"
        
        # Test authentication endpoint
        AUTH_RESPONSE=$(curl -s -k -o /dev/null -w "%{http_code}" https://localhost/api/authenticate)
        info "Authentication endpoint response: HTTP $AUTH_RESPONSE"
        
    else
        warning "Backend API not accessible - configuration will take effect on next restart"
    fi
}

# Generate summary report
generate_2fa_testing_report() {
    info "Generating 2FA testing configuration report..."
    
    REPORT_FILE="/tmp/utmstack-2fa-testing-report.md"
    
    cat > "$REPORT_FILE" << 'EOF'
# UTMStack 2FA Testing Configuration Report

**Date:** $(date)
**Purpose:** Development and Testing Configuration
**Status:** 2FA Disabled for Testing

## Changes Made

### ✅ Database Configuration
- 2FA disabled in `utm_configuration_parameter` table
- Parameter `utmstack.tfa.enable` set to `false`
- Existing TFA secrets cleared for all users

### ✅ Testing Configuration Files Created
- `/tmp/utmstack-tfa-testing-config.properties` - Main testing config
- `/tmp/utmstack-application-test.properties` - Application override
- `/tmp/utmstack-2fa-bypass.java` - Testing service implementation

### ✅ Testing Setup
- 2FA validation bypassed for development
- Testing token set to: `123456`
- All users can authenticate without 2FA

## How to Use

### Option 1: 2FA Completely Disabled
- Users can log in normally without any 2FA prompt
- No TOTP codes required
- Authentication flows directly to main application

### Option 2: Use Testing Token (if 2FA is re-enabled)
- If 2FA gets re-enabled, use token: `123456`
- This token will always be accepted in testing mode
- Works for any user account

## Application Restart Required

For changes to take full effect, restart the UTMStack backend:
```bash
# If running as service
sudo systemctl restart utmstack-backend

# If running manually
# Stop current backend process and restart with testing config
```

## Reverting Changes

To re-enable 2FA for production:
```sql
UPDATE utm_configuration_parameter 
SET param_value = 'true' 
WHERE param_key = 'utmstack.tfa.enable';
```

## Security Warning

⚠️ **This configuration is for TESTING ONLY**
- Do not use in production environments
- 2FA bypass creates security vulnerabilities
- Re-enable 2FA before production deployment

## Testing Credentials

- **Database:** pos_user / pos_password @ localhost:5432/pos_db
- **Default Admin:** admin / (default password)
- **2FA Testing Token:** 123456 (if needed)

EOF

    success "2FA testing report generated: $REPORT_FILE"
}

# Main execution
main() {
    log "Starting 2FA Testing Configuration for UTMStack"
    
    check_database
    check_2fa_status
    disable_2fa_database
    clear_tfa_secrets
    create_testing_tfa_service
    create_application_properties_override
    test_2fa_bypass
    generate_2fa_testing_report
    
    echo ""
    echo "=============================================="
    success "2FA Testing Configuration COMPLETED"
    echo "=============================================="
    echo ""
    echo "🔐 2FA Status: DISABLED FOR TESTING"
    echo ""
    echo "📋 What was configured:"
    echo "   • 2FA disabled in database configuration"
    echo "   • All user TFA secrets cleared"
    echo "   • Testing token set to: 123456"
    echo "   • Testing configuration files created"
    echo ""
    echo "🧪 Testing Options:"
    echo "   1. Login normally (2FA completely bypassed)"
    echo "   2. If prompted for 2FA, use token: 123456"
    echo ""
    echo "⚠️  Backend restart may be required for full effect:"
    echo "   sudo systemctl restart utmstack-backend"
    echo ""
    echo "📊 Configuration files:"
    echo "   • Testing config: /tmp/utmstack-tfa-testing-config.properties"
    echo "   • App override:   /tmp/utmstack-application-test.properties"
    echo "   • Report:         /tmp/utmstack-2fa-testing-report.md"
    echo ""
    echo "🔒 2FA is now disabled for testing purposes!"
    echo ""
}

# Execute main function
main "$@"
