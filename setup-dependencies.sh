#!/bin/bash

# UTMStack Dependencies Setup Script
# This script installs all required dependencies for UTMStack services

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
BASE_DIR="/home/ptsec/utmstack"
CONFIG_FILE="$BASE_DIR/config/utmstack.yml"

# System information
OS_NAME=$(lsb_release -si 2>/dev/null || echo "Unknown")
OS_VERSION=$(lsb_release -sr 2>/dev/null || echo "Unknown")
ARCH=$(uname -m)

echo -e "${BLUE}UTMStack Dependencies Setup${NC}"
echo -e "${BLUE}===========================${NC}"
echo -e "${CYAN}OS: $OS_NAME $OS_VERSION${NC}"
echo -e "${CYAN}Architecture: $ARCH${NC}"
echo -e "${CYAN}Base Directory: $BASE_DIR${NC}"
echo -e ""

# Function to print section headers
print_section() {
    echo -e "\n${PURPLE}━━━ $1 ━━━${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if service is running
service_running() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

# Function to install package with error handling
install_package() {
    local package_name=$1
    echo -e "${BLUE}Installing $package_name...${NC}"
    
    if command_exists apt-get; then
        sudo apt-get update >/dev/null 2>&1 || true
        sudo apt-get install -y "$package_name"
    elif command_exists yum; then
        sudo yum install -y "$package_name"
    elif command_exists pacman; then
        sudo pacman -S --noconfirm "$package_name"
    else
        echo -e "${RED}Package manager not supported. Please install $package_name manually.${NC}"
        return 1
    fi
}

# Function to setup Node.js
setup_nodejs() {
    print_section "Node.js Setup"
    
    if command_exists node; then
        local node_version=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
        echo -e "${GREEN}✓ Node.js already installed: $(node -v)${NC}"
        
        # Check if version is compatible with Angular 7
        if [ "$node_version" -ge 10 ] && [ "$node_version" -le 18 ]; then
            echo -e "${GREEN}✓ Node.js version is compatible with Angular 7${NC}"
        else
            echo -e "${YELLOW}⚠ Node.js version may not be optimal for Angular 7 (10-18 recommended)${NC}"
        fi
    else
        echo -e "${BLUE}Installing Node.js (LTS)...${NC}"
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        install_package nodejs
    fi
    
    # Install/update npm
    if command_exists npm; then
        echo -e "${GREEN}✓ npm already installed: $(npm -v)${NC}"
    else
        install_package npm
    fi
    
    # Set npm configuration for Angular 7 compatibility
    echo -e "${BLUE}Configuring npm for Angular 7...${NC}"
    npm config set legacy-peer-deps true
    
    # Install global packages
    echo -e "${BLUE}Installing global npm packages...${NC}"
    sudo npm install -g @angular/cli@7.3.6 || npm install -g @angular/cli@7.3.6
    
    echo -e "${GREEN}✓ Node.js setup complete${NC}"
}

# Function to setup Java
setup_java() {
    print_section "Java Development Kit Setup"
    
    if command_exists java; then
        local java_version=$(java -version 2>&1 | head -n1 | cut -d'"' -f2 | cut -d'.' -f1-2)
        echo -e "${GREEN}✓ Java already installed: $java_version${NC}"
        
        # Check if Java 11 is available
        if command_exists java && java -version 2>&1 | grep -q "11\|17\|21"; then
            echo -e "${GREEN}✓ Java version is compatible${NC}"
        else
            echo -e "${YELLOW}⚠ Java 11+ recommended for Spring Boot${NC}"
        fi
    else
        echo -e "${BLUE}Installing OpenJDK 11...${NC}"
        install_package openjdk-11-jdk
    fi
    
    # Install Maven
    if command_exists mvn; then
        echo -e "${GREEN}✓ Maven already installed: $(mvn -v | head -n1)${NC}"
    else
        echo -e "${BLUE}Installing Apache Maven...${NC}"
        install_package maven
    fi
    
    # Set JAVA_HOME if not set
    if [ -z "$JAVA_HOME" ]; then
        echo -e "${BLUE}Setting JAVA_HOME...${NC}"
        export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
        echo 'export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"' >> ~/.bashrc
    fi
    
    echo -e "${GREEN}✓ Java setup complete${NC}"
}

# Function to setup Go
setup_go() {
    print_section "Go Programming Language Setup"
    
    if command_exists go; then
        local go_version=$(go version | awk '{print $3}' | cut -d'o' -f2)
        echo -e "${GREEN}✓ Go already installed: $go_version${NC}"
        
        # Check if version is 1.20+
        local major_version=$(echo $go_version | cut -d'.' -f1)
        local minor_version=$(echo $go_version | cut -d'.' -f2)
        if [ "$major_version" -eq 1 ] && [ "$minor_version" -ge 20 ]; then
            echo -e "${GREEN}✓ Go version is up to date${NC}"
        else
            echo -e "${YELLOW}⚠ Go 1.20+ recommended${NC}"
        fi
    else
        echo -e "${BLUE}Installing Go...${NC}"
        
        # Download and install Go
        local go_version="1.23.4"
        local go_arch="amd64"
        if [ "$ARCH" = "aarch64" ]; then
            go_arch="arm64"
        fi
        
        cd /tmp
        wget -q "https://golang.org/dl/go${go_version}.linux-${go_arch}.tar.gz"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "go${go_version}.linux-${go_arch}.tar.gz"
        
        # Add Go to PATH
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
        export PATH=$PATH:/usr/local/go/bin
        
        rm "go${go_version}.linux-${go_arch}.tar.gz"
    fi
    
    # Set GOPATH and GOROOT
    if [ -z "$GOPATH" ]; then
        echo -e "${BLUE}Setting Go environment variables...${NC}"
        mkdir -p "$HOME/go"
        echo 'export GOPATH=$HOME/go' >> ~/.bashrc
        echo 'export GOROOT=/usr/local/go' >> ~/.bashrc
        export GOPATH="$HOME/go"
        export GOROOT="/usr/local/go"
    fi
    
    echo -e "${GREEN}✓ Go setup complete${NC}"
}

# Function to setup Python
setup_python() {
    print_section "Python Setup"
    
    # Check Python 3
    if command_exists python3; then
        local python_version=$(python3 --version | awk '{print $2}')
        echo -e "${GREEN}✓ Python 3 already installed: $python_version${NC}"
    else
        echo -e "${BLUE}Installing Python 3...${NC}"
        install_package python3
        install_package python3-pip
        install_package python3-venv
    fi
    
    # Check pip
    if command_exists pip3; then
        echo -e "${GREEN}✓ pip3 already installed: $(pip3 --version | awk '{print $2}')${NC}"
    else
        install_package python3-pip
    fi
    
    # Install pipenv for Mutate service
    if command_exists pipenv; then
        echo -e "${GREEN}✓ pipenv already installed${NC}"
    else
        echo -e "${BLUE}Installing pipenv...${NC}"
        pip3 install --user pipenv
        echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.bashrc
        export PATH=$PATH:$HOME/.local/bin
    fi
    
    echo -e "${GREEN}✓ Python setup complete${NC}"
}

# Function to setup PostgreSQL
setup_postgresql() {
    print_section "PostgreSQL Database Setup"
    
    if command_exists psql; then
        echo -e "${GREEN}✓ PostgreSQL client already installed${NC}"
    else
        echo -e "${BLUE}Installing PostgreSQL...${NC}"
        install_package postgresql
        install_package postgresql-contrib
        install_package postgresql-client
    fi
    
    # Check if PostgreSQL service is running
    if service_running postgresql; then
        echo -e "${GREEN}✓ PostgreSQL service is running${NC}"
    else
        echo -e "${BLUE}Starting PostgreSQL service...${NC}"
        sudo systemctl start postgresql
        sudo systemctl enable postgresql
    fi
    
    # Create UTMStack database and user
    echo -e "${BLUE}Setting up UTMStack database...${NC}"
    sudo -u postgres psql -c "CREATE DATABASE utmstack;" 2>/dev/null || echo -e "${YELLOW}Database 'utmstack' may already exist${NC}"
    sudo -u postgres psql -c "CREATE USER postgres WITH PASSWORD 'admin';" 2>/dev/null || echo -e "${YELLOW}User 'postgres' may already exist${NC}"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE utmstack TO postgres;" 2>/dev/null || true
    sudo -u postgres psql -c "ALTER USER postgres CREATEDB;" 2>/dev/null || true
    
    echo -e "${GREEN}✓ PostgreSQL setup complete${NC}"
}

# Function to setup Elasticsearch/OpenSearch
setup_elasticsearch() {
    print_section "Elasticsearch/OpenSearch Setup"
    
    # Check if Elasticsearch is already running
    if curl -s "http://localhost:9200" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Elasticsearch/OpenSearch is already running${NC}"
        return 0
    fi
    
    echo -e "${BLUE}Installing OpenSearch (Elasticsearch alternative)...${NC}"
    
    # Add OpenSearch repository
    curl -o- https://artifacts.opensearch.org/publickeys/opensearch.pgp | sudo gpg --dearmor --batch --yes -o /usr/share/keyrings/opensearch-keyring
    echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring] https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/apt stable main" | sudo tee /etc/apt/sources.list.d/opensearch-2.x.list
    
    # Update and install
    sudo apt-get update
    sudo apt-get install -y opensearch
    
    # Configure OpenSearch
    sudo tee /etc/opensearch/opensearch.yml > /dev/null <<EOF
cluster.name: utmstack-cluster
node.name: utmstack-node-1
path.data: /var/lib/opensearch
path.logs: /var/log/opensearch
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
plugins.security.disabled: true
EOF
    
    # Start and enable OpenSearch
    sudo systemctl daemon-reload
    sudo systemctl enable opensearch
    sudo systemctl start opensearch
    
    # Wait for OpenSearch to start
    echo -e "${BLUE}Waiting for OpenSearch to start...${NC}"
    local count=0
    while [ $count -lt 30 ]; do
        if curl -s "http://localhost:9200" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ OpenSearch is running${NC}"
            break
        fi
        sleep 2
        count=$((count + 1))
    done
    
    if [ $count -eq 30 ]; then
        echo -e "${YELLOW}⚠ OpenSearch may take longer to start${NC}"
    fi
    
    echo -e "${GREEN}✓ Elasticsearch/OpenSearch setup complete${NC}"
}

# Function to setup Docker
setup_docker() {
    print_section "Docker Setup"
    
    if command_exists docker; then
        echo -e "${GREEN}✓ Docker already installed: $(docker --version)${NC}"
    else
        echo -e "${BLUE}Installing Docker...${NC}"
        
        # Install prerequisites
        install_package apt-transport-https
        install_package ca-certificates
        install_package curl
        install_package gnupg
        install_package lsb-release
        
        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        # Add Docker repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    fi
    
    # Check if Docker service is running
    if service_running docker; then
        echo -e "${GREEN}✓ Docker service is running${NC}"
    else
        echo -e "${BLUE}Starting Docker service...${NC}"
        sudo systemctl start docker
        sudo systemctl enable docker
    fi
    
    # Add current user to docker group
    if groups "$USER" | grep -q docker; then
        echo -e "${GREEN}✓ User already in docker group${NC}"
    else
        echo -e "${BLUE}Adding user to docker group...${NC}"
        sudo usermod -aG docker "$USER"
        echo -e "${YELLOW}⚠ Please log out and back in for docker group changes to take effect${NC}"
    fi
    
    # Install Docker Compose
    if command_exists docker-compose; then
        echo -e "${GREEN}✓ Docker Compose already installed${NC}"
    else
        echo -e "${BLUE}Installing Docker Compose...${NC}"
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi
    
    echo -e "${GREEN}✓ Docker setup complete${NC}"
}

# Function to setup system tools
setup_system_tools() {
    print_section "System Tools Setup"
    
    # Essential tools
    local tools=("curl" "wget" "git" "unzip" "build-essential" "lsof" "net-tools" "htop" "tree")
    
    for tool in "${tools[@]}"; do
        if command_exists "${tool%% *}"; then  # Extract command name from package name
            echo -e "${GREEN}✓ $tool already installed${NC}"
        else
            install_package "$tool"
        fi
    done
    
    # Install specific tools for UTMStack
    if command_exists lsof; then
        echo -e "${GREEN}✓ lsof already installed${NC}"
    else
        install_package lsof
    fi
    
    echo -e "${GREEN}✓ System tools setup complete${NC}"
}

# Function to install project dependencies
install_project_dependencies() {
    print_section "Project Dependencies Installation"
    
    # Backend dependencies (Maven)
    if [ -f "$BASE_DIR/backend/pom.xml" ]; then
        echo -e "${BLUE}Installing backend dependencies...${NC}"
        cd "$BASE_DIR/backend"
        ./mvnw dependency:resolve -q
        echo -e "${GREEN}✓ Backend dependencies installed${NC}"
    fi
    
    # Frontend dependencies (npm)
    if [ -f "$BASE_DIR/frontend/package.json" ]; then
        echo -e "${BLUE}Installing frontend dependencies...${NC}"
        cd "$BASE_DIR/frontend"
        
        # Set Node.js options for Angular 7 compatibility
        export NODE_OPTIONS="--openssl-legacy-provider"
        
        npm install --legacy-peer-deps
        echo -e "${GREEN}✓ Frontend dependencies installed${NC}"
    fi
    
    # Go services dependencies
    local go_services=("correlation" "agent-manager" "log-auth-proxy" "soc-ai" "aws" "installer")
    for service in "${go_services[@]}"; do
        if [ -f "$BASE_DIR/$service/go.mod" ]; then
            echo -e "${BLUE}Installing $service dependencies...${NC}"
            cd "$BASE_DIR/$service"
            go mod download
            echo -e "${GREEN}✓ $service dependencies installed${NC}"
        fi
    done
    
    # Python dependencies (Mutate service)
    if [ -f "$BASE_DIR/mutate/requirements.txt" ]; then
        echo -e "${BLUE}Installing mutate service dependencies...${NC}"
        cd "$BASE_DIR/mutate"
        if [ -f "Pipfile" ]; then
            pipenv install
        else
            pip3 install -r requirements.txt
        fi
        echo -e "${GREEN}✓ Mutate service dependencies installed${NC}"
    fi
    
    echo -e "${GREEN}✓ Project dependencies installation complete${NC}"
}

# Function to verify installation
verify_installation() {
    print_section "Installation Verification"
    
    local errors=0
    
    # Check Node.js and npm
    if command_exists node && command_exists npm; then
        echo -e "${GREEN}✓ Node.js: $(node -v), npm: $(npm -v)${NC}"
    else
        echo -e "${RED}✗ Node.js or npm not found${NC}"
        errors=$((errors + 1))
    fi
    
    # Check Java and Maven
    if command_exists java && command_exists mvn; then
        echo -e "${GREEN}✓ Java: $(java -version 2>&1 | head -n1), Maven: $(mvn -v | head -n1 | awk '{print $3}')${NC}"
    else
        echo -e "${RED}✗ Java or Maven not found${NC}"
        errors=$((errors + 1))
    fi
    
    # Check Go
    if command_exists go; then
        echo -e "${GREEN}✓ Go: $(go version | awk '{print $3}')${NC}"
    else
        echo -e "${RED}✗ Go not found${NC}"
        errors=$((errors + 1))
    fi
    
    # Check Python
    if command_exists python3 && command_exists pip3; then
        echo -e "${GREEN}✓ Python: $(python3 --version), pip: $(pip3 --version | awk '{print $2}')${NC}"
    else
        echo -e "${RED}✗ Python 3 or pip3 not found${NC}"
        errors=$((errors + 1))
    fi
    
    # Check PostgreSQL
    if command_exists psql; then
        echo -e "${GREEN}✓ PostgreSQL client installed${NC}"
        if service_running postgresql; then
            echo -e "${GREEN}✓ PostgreSQL service running${NC}"
        else
            echo -e "${YELLOW}⚠ PostgreSQL service not running${NC}"
        fi
    else
        echo -e "${RED}✗ PostgreSQL not found${NC}"
        errors=$((errors + 1))
    fi
    
    # Check Elasticsearch/OpenSearch
    if curl -s "http://localhost:9200" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Elasticsearch/OpenSearch running on port 9200${NC}"
    else
        echo -e "${YELLOW}⚠ Elasticsearch/OpenSearch not responding on port 9200${NC}"
    fi
    
    # Check Docker
    if command_exists docker; then
        echo -e "${GREEN}✓ Docker: $(docker --version)${NC}"
        if service_running docker; then
            echo -e "${GREEN}✓ Docker service running${NC}"
        else
            echo -e "${YELLOW}⚠ Docker service not running${NC}"
        fi
    else
        echo -e "${RED}✗ Docker not found${NC}"
        errors=$((errors + 1))
    fi
    
    if [ $errors -eq 0 ]; then
        echo -e "\n${GREEN}✓ All dependencies successfully installed and verified!${NC}"
        return 0
    else
        echo -e "\n${YELLOW}⚠ Installation completed with $errors errors. Please review the output above.${NC}"
        return 1
    fi
}

# Function to create environment configuration
create_environment_config() {
    print_section "Environment Configuration"
    
    # Create .env file for development
    local env_file="$BASE_DIR/.env"
    echo -e "${BLUE}Creating environment configuration file...${NC}"
    
    cat > "$env_file" <<EOF
# UTMStack Environment Configuration
# Generated by setup-dependencies.sh on $(date)

# Environment
NODE_ENV=development
SPRING_PROFILES_ACTIVE=dev

# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=utmstack
DB_USER=postgres
DB_PASSWORD=admin

# Elasticsearch Configuration
ELASTICSEARCH_HOST=localhost
ELASTICSEARCH_PORT=9200

# Service Ports
BACKEND_PORT=8080
FRONTEND_PORT=4200
CORRELATION_PORT=8085
AGENT_MANAGER_PORT=9000
LOG_AUTH_PROXY_PORT=8081
SOC_AI_PORT=8084
USER_AUDITOR_PORT=8082
WEB_PDF_PORT=8083

# URLs
LOGSTASH_URL=http://localhost:9600
CORRELATION_URL=http://localhost:8085

# Security
JWT_SECRET=your-jwt-secret-key-here-change-in-production
ENCRYPTION_KEY=your-encryption-key-here

# Node.js compatibility for Angular 7
NODE_OPTIONS=--openssl-legacy-provider

# Go settings
GOOS=linux
GOARCH=amd64
EOF
    
    echo -e "${GREEN}✓ Environment configuration created at $env_file${NC}"
    echo -e "${BLUE}You can source this file with: source $env_file${NC}"
}

# Main execution
main() {
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}Please do not run this script as root. Use sudo when prompted.${NC}"
        exit 1
    fi
    
    # Update system packages
    echo -e "${BLUE}Updating system packages...${NC}"
    sudo apt-get update >/dev/null 2>&1 || true
    
    # Run setup functions
    setup_system_tools
    setup_nodejs
    setup_java
    setup_go
    setup_python
    setup_postgresql
    setup_elasticsearch
    setup_docker
    install_project_dependencies
    create_environment_config
    
    # Verify installation
    if verify_installation; then
        echo -e "\n${GREEN}🎉 UTMStack dependencies setup completed successfully!${NC}"
        echo -e "\n${BLUE}Next steps:${NC}"
        echo -e "1. Source the environment: ${CYAN}source $BASE_DIR/.env${NC}"
        echo -e "2. Start services: ${CYAN}./utmstack-manager.sh start${NC}"
        echo -e "3. Check status: ${CYAN}./utmstack-manager.sh status${NC}"
        echo -e "\n${YELLOW}Note: If you were added to the docker group, please log out and back in.${NC}"
    else
        echo -e "\n${YELLOW}Setup completed with some issues. Please review the output above.${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
