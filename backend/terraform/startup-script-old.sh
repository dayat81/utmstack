#!/bin/bash

# UTMStack Multi-Tenant VM Startup Script
# This script initializes a single GCP VM for multiple UTMStack tenants

set -e

# Configuration from metadata
TENANTS_CONFIG=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/tenants-config" -H "Metadata-Flavor: Google")
GIT_REPO_URL=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/git-repo-url" -H "Metadata-Flavor: Google" || echo "https://github.com/utmstack/UTMStack.git")

# Logging
LOG_FILE="/var/log/utmstack-startup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "=== UTMStack Multi-Tenant Startup Script Started at $(date) ==="
echo "Tenants Configuration: $TENANTS_CONFIG"
echo "Git Repository: $GIT_REPO_URL"

# Update system
echo ">>> Updating system packages..."
apt-get update
apt-get upgrade -y

# Install essential tools
echo ">>> Installing essential tools..."
apt-get install -y curl wget git vim htop tree unzip software-properties-common apt-transport-https ca-certificates gnupg lsb-release

# Mount data disk
echo ">>> Setting up data disk..."
DATA_DISK="/dev/disk/by-id/google-data-disk"
if [ -b "$DATA_DISK" ]; then
    # Format if not already formatted
    if ! blkid "$DATA_DISK"; then
        mkfs.ext4 -F "$DATA_DISK"
    fi
    
    # Create mount point and mount
    mkdir -p "/data"
    echo "$DATA_DISK /data ext4 defaults 0 2" >> /etc/fstab
    mount "/data"
    
    # Set permissions
    chmod 755 "/data"
    chown utmstack:utmstack "/data" 2>/dev/null || true
fi

# Create utmstack user if doesn't exist
echo ">>> Creating utmstack user..."
if ! id "utmstack" &>/dev/null; then
    useradd -m -s /bin/bash utmstack
    usermod -aG sudo utmstack
    echo "utmstack ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/utmstack
fi

# Install Java 11
echo ">>> Installing Java 11..."
apt-get install -y openjdk-11-jdk
echo 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64' >> /etc/environment
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

# Install Maven
echo ">>> Installing Maven..."
apt-get install -y maven

# Install Node.js 18.x
echo ">>> Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# Install Angular CLI
echo ">>> Installing Angular CLI..."
npm install -g @angular/cli@7

# Install Go 1.21
echo ">>> Installing Go..."
wget -q https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/environment
export PATH=$PATH:/usr/local/go/bin
rm go1.21.0.linux-amd64.tar.gz

# Install Python 3.11
echo ">>> Installing Python..."
apt-get install -y python3.11 python3.11-venv python3-pip

# Install PostgreSQL
echo ">>> Installing PostgreSQL..."
apt-get install -y postgresql postgresql-contrib
systemctl start postgresql
systemctl enable postgresql

# Create databases for all tenants
echo ">>> Creating tenant databases..."
echo "$TENANTS_CONFIG" | jq -r 'to_entries[] | @base64' | while read tenant_data; do
    TENANT_JSON=$(echo "$tenant_data" | base64 -d)
    TENANT_NAME=$(echo "$TENANT_JSON" | jq -r '.key')
    
    echo "Creating database for tenant: $TENANT_NAME"
    sudo -u postgres psql -c "CREATE DATABASE utmstack_$TENANT_NAME;" || true
    sudo -u postgres psql -c "CREATE USER utmstack_$TENANT_NAME WITH PASSWORD 'utmstack123';" || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE utmstack_$TENANT_NAME TO utmstack_$TENANT_NAME;" || true
done

# Install Docker
echo ">>> Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker utmstack
systemctl start docker
systemctl enable docker
rm get-docker.sh

# Install Docker Compose
echo ">>> Installing Docker Compose..."
apt-get install -y docker-compose-plugin

# Install monitoring tools
echo ">>> Installing monitoring tools..."
apt-get install -y htop iotop nethogs net-tools

# Configure firewall (ufw)
echo ">>> Configuring firewall..."
ufw --force enable
ufw allow ssh
ufw allow 3000
ufw allow 4200
ufw allow 8080
ufw allow 8443
ufw allow 9200
ufw allow 5432

# Setup log rotation
echo ">>> Configuring log rotation..."
cat > /etc/logrotate.d/utmstack << EOF
/data/*/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF

# Clone UTMStack repository
echo ">>> Cloning UTMStack repository..."
sudo -u utmstack git clone "$GIT_REPO_URL" "/home/utmstack/utmstack" || true

# Setup project directories for all tenants
echo ">>> Setting up project directories..."
sudo -u utmstack mkdir -p "/home/utmstack/utmstack"

echo "$TENANTS_CONFIG" | jq -r 'to_entries[] | @base64' | while read tenant_data; do
    TENANT_JSON=$(echo "$tenant_data" | base64 -d)
    TENANT_NAME=$(echo "$TENANT_JSON" | jq -r '.key')
    
    echo "Setting up directories for tenant: $TENANT_NAME"
    sudo -u utmstack mkdir -p "/data/$TENANT_NAME/logs"
    sudo -u utmstack mkdir -p "/data/$TENANT_NAME/backups"
    sudo -u utmstack mkdir -p "/data/$TENANT_NAME/config"
    sudo -u utmstack mkdir -p "/home/utmstack/tenants/$TENANT_NAME"
done

# Create main data symlink
sudo -u utmstack ln -sf "/data" "/home/utmstack/data" 2>/dev/null || true

# Set up main environment file
cat > "/home/utmstack/.env" << EOF
# UTMStack Multi-Tenant Environment Configuration
TENANTS_CONFIG='$TENANTS_CONFIG'
GIT_REPO_URL=$GIT_REPO_URL

# Application Configuration
JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
NODE_ENV=development
GO_ENV=development

# Paths
PROJECT_ROOT=/home/utmstack/utmstack
DATA_ROOT=/data
LOG_DIR=/data

# Database Configuration
DB_HOST=localhost
DB_PORT=5432

# Default Ports (can be customized per tenant)
FRONTEND_PORT=4200
BACKEND_PORT=8080
API_PORT=8080
ELASTICSEARCH_PORT=9200
EOF

chown utmstack:utmstack "/home/utmstack/.env"

# Create individual tenant environment files
echo "$TENANTS_CONFIG" | jq -r 'to_entries[] | @base64' | while read tenant_data; do
    TENANT_JSON=$(echo "$tenant_data" | base64 -d)
    TENANT_NAME=$(echo "$TENANT_JSON" | jq -r '.key')
    TENANT_DOMAIN=$(echo "$TENANT_JSON" | jq -r '.value.domain')
    ADMIN_EMAIL=$(echo "$TENANT_JSON" | jq -r '.value.admin_email')
    
    cat > "/home/utmstack/tenants/$TENANT_NAME/.env" << EOF
# UTMStack Environment Configuration for $TENANT_NAME
TENANT_NAME=$TENANT_NAME
TENANT_DOMAIN=$TENANT_DOMAIN
ADMIN_EMAIL=$ADMIN_EMAIL

# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=utmstack_$TENANT_NAME
DB_USER=utmstack_$TENANT_NAME
DB_PASSWORD=utmstack123

# Paths
PROJECT_ROOT=/home/utmstack/utmstack
DATA_ROOT=/data/$TENANT_NAME
LOG_DIR=/data/$TENANT_NAME/logs

# Tenant-specific Ports (adjust as needed)
FRONTEND_PORT=4200
BACKEND_PORT=8080
API_PORT=8080
EOF
    
    chown utmstack:utmstack "/home/utmstack/tenants/$TENANT_NAME/.env"
done

# Install VS Code (optional)
echo ">>> Installing VS Code..."
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
apt-get update
apt-get install -y code

# Build UTMStack project (if repository exists)
if [ -d "/home/utmstack/utmstack" ]; then
    echo ">>> Building UTMStack project..."
    cd "/home/utmstack/utmstack"
    
    # Backend build
    if [ -d "backend" ]; then
        cd backend
        sudo -u utmstack ./mvnw clean install -DskipTests || true
        cd ..
    fi
    
    # Frontend build
    if [ -d "frontend" ]; then
        cd frontend
        sudo -u utmstack npm install || true
        cd ..
    fi
    
    # Go services
    if [ -d "correlation" ]; then
        cd correlation
        sudo -u utmstack go mod download || true
        cd ..
    fi
fi

# Create startup services
echo ">>> Creating systemd services..."
cat > "/etc/systemd/system/utmstack-$TENANT_NAME.service" << EOF
[Unit]
Description=UTMStack Service for $TENANT_NAME
After=network.target postgresql.service

[Service]
Type=simple
User=utmstack
WorkingDirectory=/home/utmstack/utmstack
Environment=TENANT_NAME=$TENANT_NAME
EnvironmentFile=/home/utmstack/.env
ExecStart=/home/utmstack/start-utmstack.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create startup script
cat > "/home/utmstack/start-utmstack.sh" << EOF
#!/bin/bash
source /home/utmstack/.env
cd /home/utmstack/utmstack

# Start backend (if exists)
if [ -d "backend" ]; then
    cd backend
    nohup ./mvnw spring-boot:run > /data/$TENANT_NAME/logs/backend.log 2>&1 &
    cd ..
fi

# Start frontend (if exists)
if [ -d "frontend" ]; then
    cd frontend
    nohup npm start > /data/$TENANT_NAME/logs/frontend.log 2>&1 &
    cd ..
fi

wait
EOF

chmod +x "/home/utmstack/start-utmstack.sh"
chown utmstack:utmstack "/home/utmstack/start-utmstack.sh"

# Enable and start services
systemctl daemon-reload
systemctl enable "utmstack-$TENANT_NAME"

# Install GCP monitoring agent
echo ">>> Installing GCP monitoring agent..."
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install
rm add-google-cloud-ops-agent-repo.sh

# Create health check endpoint
echo ">>> Creating health check endpoint..."
mkdir -p /var/www/html
cat > /var/www/html/health << EOF
{
  "status": "healthy",
  "tenant": "$TENANT_NAME",
  "timestamp": "$(date -Iseconds)",
  "services": {
    "postgresql": "running",
    "docker": "running"
  }
}
EOF

# Install nginx for health checks
apt-get install -y nginx
systemctl start nginx
systemctl enable nginx

# Configure nginx for health endpoint
cat > /etc/nginx/sites-available/health << EOF
server {
    listen 8080;
    server_name _;
    
    location /health {
        root /var/www/html;
        default_type application/json;
    }
    
    location / {
        proxy_pass http://localhost:4200;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -sf /etc/nginx/sites-available/health /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl reload nginx

# Final setup
echo ">>> Final setup..."
# Set timezone
timedatectl set-timezone Asia/Jakarta

# Create welcome message
cat > "/home/utmstack/README-$TENANT_NAME.txt" << EOF
=== UTMStack Development Environment ===
Tenant: $TENANT_NAME
Domain: $TENANT_DOMAIN
Admin: $ADMIN_EMAIL

Project Directory: /home/utmstack/utmstack
Data Directory: /data/$TENANT_NAME
Logs Directory: /data/$TENANT_NAME/logs

Services:
- Frontend: http://localhost:4200
- Backend: http://localhost:8080
- Database: postgresql://localhost:5432/utmstack_$TENANT_NAME

Useful Commands:
- Start UTMStack: sudo systemctl start utmstack-$TENANT_NAME
- Stop UTMStack: sudo systemctl stop utmstack-$TENANT_NAME
- View logs: tail -f /data/$TENANT_NAME/logs/*.log
- Check health: curl http://localhost:8080/health

To get started:
1. cd /home/utmstack/utmstack
2. Follow the project README for development setup

Installed Software:
- Java 11 (OpenJDK)
- Node.js 18 + Angular CLI 7
- Go 1.21
- Python 3.11
- PostgreSQL
- Docker + Docker Compose
- Git, Maven, npm
EOF

chown utmstack:utmstack "/home/utmstack/README-$TENANT_NAME.txt"

echo "=== UTMStack Startup Script Completed at $(date) ==="
echo "VM is ready for $TENANT_NAME tenant development"
echo "Check /home/utmstack/README-$TENANT_NAME.txt for details"
