#!/bin/bash

# Set Admin Testing Password Script
# UTMStack Development - Simple Admin Password for Testing

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "👤 UTMStack Admin Testing Password Configuration"
echo "==============================================="

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

# Set simple testing password for admin
info "Setting simple testing password for admin user..."

# BCrypt hash for password "admin" (commonly used for testing)
# Generated with: echo -n "admin" | bcrypt-cli
ADMIN_PASSWORD_HASH='$2a$10$gSAhZrxMllrbgj/kkK9UceBPpChGWJA7SYIb1Mqo.n5aNLq1/oRrC'

PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -c "
    UPDATE jhi_user 
    SET password_hash = '$ADMIN_PASSWORD_HASH',
        activated = true,
        email = 'admin@localhost'
    WHERE login = 'admin';
" >/dev/null 2>&1

success "Admin password updated for testing"

# Verify the change
ADMIN_EXISTS=$(PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -t -c "
    SELECT COUNT(*) FROM jhi_user WHERE login = 'admin' AND activated = true;
" 2>/dev/null | tr -d ' ')

if [ "$ADMIN_EXISTS" = "1" ]; then
    success "Admin user is active and ready for testing"
else
    warning "Admin user verification failed"
fi

# Show current admin user info
info "Current admin user configuration:"
PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -c "
    SELECT login, email, activated, created_date, last_modified_date
    FROM jhi_user 
    WHERE login = 'admin';
"

# Create testing instructions
cat << 'EOF'

============================================
👤 Admin Testing Credentials Set
============================================

✅ Admin Password: UPDATED for testing
✅ Account Status: ACTIVATED
✅ Ready for login testing

🔑 Testing Credentials:
   Username: admin
   Password: admin
   Email: admin@localhost

🌐 Access URLs:
   Frontend: https://localhost/
   Direct: http://localhost:4200

🧪 Testing Steps:
1. Go to https://localhost/
2. Login with: admin / admin
3. Should login without 2FA prompts
4. Access full UTMStack functionality

🔧 If login fails:
1. Clear browser cache/cookies
2. Try incognito/private mode
3. Check browser console for errors
4. Verify backend service is running

📋 Other Available Accounts:
- fsclient (federation service client)
- Any other accounts in the system

⚠️  Security Note:
Simple passwords are for TESTING/DEVELOPMENT only.
Use strong passwords for production deployment.

EOF

echo ""
echo "👤 Admin testing credentials are now configured!"
echo ""
