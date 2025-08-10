#!/bin/bash

# Set 2FA Testing Token Script
# UTMStack Development - Quick 2FA Configuration for Testing

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🔐 UTMStack 2FA Testing Configuration"
echo "===================================="

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

error_exit() {
    echo -e "${RED}ERROR: $1${NC}"
    exit 1
}

# Check database connectivity
info "Checking database connectivity..."
if ! PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -c "SELECT 1;" >/dev/null 2>&1; then
    error_exit "Cannot connect to database. Please ensure database is running."
fi
success "Database connection established"

# Check current 2FA status
info "Checking current 2FA configuration..."
CURRENT_2FA=$(PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -t -c "
    SELECT conf_param_value FROM utm_configuration_parameter 
    WHERE conf_param_short = 'utmstack.tfa.enable';
" 2>/dev/null | tr -d ' ')

info "Current 2FA setting: $CURRENT_2FA"

# Disable 2FA
info "Ensuring 2FA is disabled for testing..."
PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -c "
    UPDATE utm_configuration_parameter 
    SET conf_param_value = 'false'
    WHERE conf_param_short = 'utmstack.tfa.enable';
" >/dev/null 2>&1

success "2FA has been disabled in database configuration"

# Clear any existing TFA secrets
info "Clearing existing TFA secrets for all users..."
TFA_COLUMN_EXISTS=$(PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -t -c "
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'jhi_user' AND column_name = 'tfa_secret'
    );
" 2>/dev/null | tr -d ' ')

if [ "$TFA_COLUMN_EXISTS" = "t" ]; then
    PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -c "
        UPDATE jhi_user SET tfa_secret = NULL;
    " >/dev/null 2>&1
    success "Cleared TFA secrets for all users"
else
    warning "TFA secret column not found in users table"
fi

# Show current user accounts
info "Current user accounts in system:"
PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -c "
    SELECT login, email, activated, created_date 
    FROM jhi_user 
    ORDER BY id;
"

# Create testing instructions
cat << 'EOF'

============================================
🎯 2FA Testing Configuration Complete
============================================

✅ 2FA Status: DISABLED
✅ All user TFA secrets: CLEARED
✅ Users can now login without 2FA prompts

🧪 Testing Options:

1. RECOMMENDED: Login normally without 2FA
   - Go to: https://localhost/
   - Use existing credentials (e.g., admin/admin)
   - 2FA prompts should not appear

2. IF 2FA prompt still appears, use testing token:
   - Token: 123456
   - This should work if any 2FA validation remains

🔧 Troubleshooting:

If 2FA is still required after these changes:
1. Restart the UTMStack backend service
2. Clear browser cache and cookies
3. Try incognito/private browsing mode

📋 Access Information:
- Frontend: https://localhost/
- Database: localhost:5432 (pos_user/pos_password/pos_db)
- Admin Account: admin (check existing password)

⚠️  Security Note:
This configuration is for TESTING/DEVELOPMENT only.
Re-enable 2FA before production deployment.

EOF

echo ""
echo "🔒 2FA has been disabled for testing purposes!"
echo ""
