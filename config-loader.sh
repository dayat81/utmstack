#!/bin/bash

# UTMStack Configuration Loader
# This script reads the unified config file and sets environment variables for all services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Base directory
BASE_DIR="/home/ptsec/utmstack"
CONFIG_FILE="$BASE_DIR/config/utmstack.yml"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Configuration file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Function to parse YAML and extract values
parse_yaml() {
    local yaml_file=$1
    local prefix=$2
    
    # Simple YAML parser using awk
    awk -v prefix="$prefix" '
    BEGIN { 
        level = 0 
        path[0] = ""
    }
    
    # Skip comments and empty lines
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    
    # Handle yaml sections
    {
        # Calculate indentation level
        match($0, /^[[:space:]]*/)
        indent = RLENGTH
        
        # Remove leading whitespace
        gsub(/^[[:space:]]*/, "")
        
        # Skip if line starts with dash (array item)
        if (/^-/) next
        
        # If this is a key-value pair
        if (/:/) {
            split($0, kv, ":")
            key = kv[1]
            value = kv[2]
            
            # Clean up key and value
            gsub(/[[:space:]]*$/, "", key)
            gsub(/^[[:space:]]*/, "", value)
            gsub(/[[:space:]]*$/, "", value)
            
            # Remove quotes from value
            gsub(/^["'"'"']|["'"'"']$/, "", value)
            
            # Update path based on indentation
            level = int(indent / 2)
            path[level] = key
            
            # Build full path
            full_path = ""
            for (i = 0; i <= level; i++) {
                if (path[i] != "") {
                    if (full_path != "") full_path = full_path "."
                    full_path = full_path path[i]
                }
            }
            
            # If value is not empty, print the variable
            if (value != "") {
                # Convert path to uppercase environment variable format
                env_var = toupper(full_path)
                gsub(/\./, "_", env_var)
                gsub(/-/, "_", env_var)
                
                # Add prefix if specified
                if (prefix != "") {
                    env_var = prefix "_" env_var
                }
                
                print "export " env_var "=\"" value "\""
            }
        }
    }' "$yaml_file"
}

# Function to load configuration
load_config() {
    echo -e "${BLUE}Loading UTMStack configuration from $CONFIG_FILE${NC}"
    
    # Parse the YAML file and generate environment variables
    local env_vars=$(parse_yaml "$CONFIG_FILE" "UTMSTACK")
    
    # Create temporary environment file
    local temp_env_file="/tmp/utmstack_env_$$"
    echo "$env_vars" > "$temp_env_file"
    
    # Source the environment variables
    source "$temp_env_file"
    
    # Clean up
    rm -f "$temp_env_file"
    
    echo -e "${GREEN}✓ Configuration loaded successfully${NC}"
}

# Function to export commonly used variables
export_common_vars() {
    # Database configuration
    export DB_HOST="${UTMSTACK_INFRASTRUCTURE_DATABASE_HOST:-localhost}"
    export DB_PORT="${UTMSTACK_INFRASTRUCTURE_DATABASE_PORT:-5432}"
    export DB_NAME="${UTMSTACK_INFRASTRUCTURE_DATABASE_NAME:-utmstack}"
    export DB_USER="${UTMSTACK_INFRASTRUCTURE_DATABASE_USER:-postgres}"
    export DB_PASSWORD="${UTMSTACK_INFRASTRUCTURE_DATABASE_PASSWORD:-admin}"
    
    # Elasticsearch configuration
    export ELASTICSEARCH_HOST="${UTMSTACK_INFRASTRUCTURE_ELASTICSEARCH_HOST:-localhost}"
    export ELASTICSEARCH_PORT="${UTMSTACK_INFRASTRUCTURE_ELASTICSEARCH_PORT:-9200}"
    export ELASTICSEARCH_URL="http://$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT"
    
    # Service ports
    export BACKEND_PORT="${UTMSTACK_SERVICES_BACKEND_PORT:-8080}"
    export FRONTEND_PORT="${UTMSTACK_SERVICES_FRONTEND_PORT:-4200}"
    export CORRELATION_PORT="${UTMSTACK_SERVICES_CORRELATION_PORT:-8085}"
    export AGENT_MANAGER_PORT="${UTMSTACK_SERVICES_AGENT_MANAGER_PORT:-9000}"
    export LOG_AUTH_PROXY_PORT="${UTMSTACK_SERVICES_LOG_AUTH_PROXY_PORT:-8081}"
    export SOC_AI_PORT="${UTMSTACK_SERVICES_SOC_AI_PORT:-8084}"
    export USER_AUDITOR_PORT="${UTMSTACK_SERVICES_USER_AUDITOR_PORT:-8082}"
    export WEB_PDF_PORT="${UTMSTACK_SERVICES_WEB_PDF_PORT:-8083}"
    
    # URLs
    export LOGSTASH_URL="http://localhost:9600"
    export CORRELATION_URL="http://localhost:$CORRELATION_PORT"
    
    # Security
    export JWT_SECRET="${UTMSTACK_SERVICES_BACKEND_JWT_SECRET:-your-jwt-secret-key-here}"
    export ENCRYPTION_KEY="${UTMSTACK_SERVICES_MUTATE_ENCRYPTION_KEY:-your-encryption-key-here}"
    
    # Node.js compatibility
    export NODE_OPTIONS="${NODE_OPTIONS:-} --openssl-legacy-provider"
    
    # Spring profiles
    export SPRING_PROFILES_ACTIVE="${UTMSTACK_GLOBAL_ENVIRONMENT:-development}"
    
    echo -e "${GREEN}✓ Common environment variables exported${NC}"
}

# Function to show configuration
show_config() {
    echo -e "${BLUE}UTMStack Configuration Summary${NC}"
    echo -e "${BLUE}==============================${NC}"
    
    echo -e "\n${YELLOW}Global Settings:${NC}"
    echo -e "Environment: ${UTMSTACK_GLOBAL_ENVIRONMENT:-development}"
    echo -e "Version: ${UTMSTACK_GLOBAL_VERSION:-unknown}"
    echo -e "Debug: ${UTMSTACK_GLOBAL_DEBUG:-false}"
    
    echo -e "\n${YELLOW}Database:${NC}"
    echo -e "Host: $DB_HOST:$DB_PORT"
    echo -e "Database: $DB_NAME"
    echo -e "User: $DB_USER"
    
    echo -e "\n${YELLOW}Elasticsearch:${NC}"
    echo -e "URL: $ELASTICSEARCH_URL"
    
    echo -e "\n${YELLOW}Service Ports:${NC}"
    echo -e "Backend API: $BACKEND_PORT"
    echo -e "Frontend: $FRONTEND_PORT"
    echo -e "Correlation: $CORRELATION_PORT"
    echo -e "Agent Manager: $AGENT_MANAGER_PORT"
    echo -e "Log Auth Proxy: $LOG_AUTH_PROXY_PORT"
    echo -e "SOC AI: $SOC_AI_PORT"
    echo -e "User Auditor: $USER_AUDITOR_PORT"
    echo -e "Web PDF: $WEB_PDF_PORT"
}

# Function to validate configuration
validate_config() {
    echo -e "${BLUE}Validating configuration...${NC}"
    
    local errors=0
    
    # Check required variables
    local required_vars=("DB_HOST" "DB_PORT" "DB_NAME" "DB_USER" "ELASTICSEARCH_HOST" "ELASTICSEARCH_PORT")
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            echo -e "${RED}✗ Required variable $var is not set${NC}"
            errors=$((errors + 1))
        else
            echo -e "${GREEN}✓ $var is set${NC}"
        fi
    done
    
    # Check port conflicts
    local ports=("$BACKEND_PORT" "$FRONTEND_PORT" "$CORRELATION_PORT" "$AGENT_MANAGER_PORT" "$LOG_AUTH_PROXY_PORT" "$SOC_AI_PORT" "$USER_AUDITOR_PORT" "$WEB_PDF_PORT")
    local seen_ports=()
    
    for port in "${ports[@]}"; do
        if [[ " ${seen_ports[@]} " =~ " $port " ]]; then
            echo -e "${RED}✗ Port conflict detected: $port${NC}"
            errors=$((errors + 1))
        else
            seen_ports+=("$port")
            echo -e "${GREEN}✓ Port $port is unique${NC}"
        fi
    done
    
    if [ $errors -eq 0 ]; then
        echo -e "${GREEN}✓ Configuration validation passed${NC}"
        return 0
    else
        echo -e "${RED}✗ Configuration validation failed with $errors errors${NC}"
        return 1
    fi
}

# Function to create service-specific configs
create_service_configs() {
    echo -e "${BLUE}Creating service-specific configuration files...${NC}"
    
    # Create backend application.yml
    mkdir -p "$BASE_DIR/backend/src/main/resources/config"
    cat > "$BASE_DIR/backend/src/main/resources/config/application-generated.yml" <<EOF
# Generated from unified config - DO NOT EDIT MANUALLY
spring:
  application:
    name: ${UTMSTACK_SERVICES_BACKEND_NAME:-UTMStack-API}
  profiles:
    active: ${UTMSTACK_GLOBAL_ENVIRONMENT:-development}
  datasource:
    url: jdbc:postgresql://$DB_HOST:$DB_PORT/$DB_NAME
    username: $DB_USER
    password: $DB_PASSWORD
    driver-class-name: org.postgresql.Driver

server:
  port: $BACKEND_PORT

elasticsearch:
  url: $ELASTICSEARCH_URL

management:
  endpoints:
    web:
      base-path: /management
      exposure:
        include: ['health', 'info', 'metrics', 'prometheus']
EOF
    
    # Create correlation config.yml
    mkdir -p "$BASE_DIR/correlation"
    cat > "$BASE_DIR/correlation/config-generated.yml" <<EOF
# Generated from unified config - DO NOT EDIT MANUALLY
rulesFolder: ${UTMSTACK_SERVICES_CORRELATION_RULES_FOLDER:-/app/rulesets/}
elasticsearch: $ELASTICSEARCH_URL
postgresql:
  server: $DB_HOST
  port: $DB_PORT
  user: $DB_USER
  password: $DB_PASSWORD
  database: $DB_NAME
errorLevel: ${UTMSTACK_SERVICES_CORRELATION_ERROR_LEVEL:-DEBUG}
EOF
    
    # Create frontend environment config
    mkdir -p "$BASE_DIR/frontend/src/environments"
    cat > "$BASE_DIR/frontend/src/environments/environment.generated.ts" <<EOF
// Generated from unified config - DO NOT EDIT MANUALLY
export const environment = {
  production: false,
  apiUrl: 'http://localhost:$BACKEND_PORT',
  name: '${UTMSTACK_SERVICES_FRONTEND_NAME:-UTMStack-Frontend}',
  version: '${UTMSTACK_GLOBAL_VERSION:-unknown}'
};
EOF
    
    echo -e "${GREEN}✓ Service-specific configuration files created${NC}"
}

# Main function
main() {
    case "${1:-load}" in
        "load")
            load_config
            export_common_vars
            ;;
        "show")
            load_config
            export_common_vars
            show_config
            ;;
        "validate")
            load_config
            export_common_vars
            validate_config
            ;;
        "generate")
            load_config
            export_common_vars
            create_service_configs
            ;;
        "env")
            load_config
            export_common_vars
            # Print all UTMSTACK_* variables for export
            env | grep "^UTMSTACK_" | sort
            echo "# Common variables:"
            echo "export DB_HOST=\"$DB_HOST\""
            echo "export DB_PORT=\"$DB_PORT\""
            echo "export DB_NAME=\"$DB_NAME\""
            echo "export DB_USER=\"$DB_USER\""
            echo "export DB_PASSWORD=\"$DB_PASSWORD\""
            echo "export ELASTICSEARCH_HOST=\"$ELASTICSEARCH_HOST\""
            echo "export ELASTICSEARCH_PORT=\"$ELASTICSEARCH_PORT\""
            echo "export ELASTICSEARCH_URL=\"$ELASTICSEARCH_URL\""
            ;;
        "help"|"-h"|"--help")
            echo -e "${BLUE}UTMStack Configuration Loader${NC}"
            echo -e ""
            echo -e "Usage: $0 [command]"
            echo -e ""
            echo -e "Commands:"
            echo -e "  load      Load configuration and export variables (default)"
            echo -e "  show      Show configuration summary"
            echo -e "  validate  Validate configuration"
            echo -e "  generate  Generate service-specific config files"
            echo -e "  env       Export environment variables"
            echo -e "  help      Show this help message"
            ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}"
            echo -e "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
