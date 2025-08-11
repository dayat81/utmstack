# GCP Development VM Setup Plan

## VM Configuration

### Instance Specs
- **Machine Type**: e2-standard-4 (4 vCPUs, 16 GB RAM)
- **Boot Disk**: Ubuntu 24.04 LTS, 100 GB SSD
- **Region**: us-central1-a (or closest to team)
- **Network**: Default VPC with custom firewall rules

### Storage
- Additional 200 GB persistent disk for Docker volumes/data
- Enable automatic backups (daily snapshots)

## Network & Security

### Firewall Rules
```bash
# Allow SSH (port 22)
gcloud compute firewall-rules create allow-ssh-dev \
  --allow tcp:22 --source-ranges 0.0.0.0/0

# Allow development ports
gcloud compute firewall-rules create allow-dev-ports \
  --allow tcp:3000,4200,8080,8443,9200,5432 \
  --source-ranges <your-ip-range>
```

### Security
- Use IAM service accounts with minimal permissions
- Enable OS Login for SSH key management
- Configure automatic OS updates
- Install fail2ban for SSH protection

## Software Installation

### Base System
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install essential tools
sudo apt install -y curl wget git vim htop tree unzip
```

### Java Development
```bash
# Install OpenJDK 11
sudo apt install -y openjdk-11-jdk
echo 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64' >> ~/.bashrc

# Install Maven
sudo apt install -y maven
```

### Node.js & Frontend
```bash
# Install Node.js 18.x
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Install Angular CLI
sudo npm install -g @angular/cli@7
```

### Go Development
```bash
# Install Go 1.21
wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
```

### Python Development
```bash
# Install Python 3.11 and pip
sudo apt install -y python3.11 python3.11-venv python3-pip
```

### Database & Infrastructure
```bash
# Install PostgreSQL
sudo apt install -y postgresql postgresql-contrib

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install -y docker-compose-plugin
```

## Development Environment Setup

### IDE Installation
```bash
# Install VS Code
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
sudo apt update && sudo apt install -y code
```

### Git Configuration
```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@company.com"
git config --global init.defaultBranch main
```

### UTMStack Project Setup
```bash
# Clone repository
git clone <utmstack-repo-url>
cd utmstack

# Backend setup
cd backend
./mvnw clean install

# Frontend setup
cd ../frontend
npm install

# Go services setup
cd ../correlation
go mod download
```

## Monitoring & Maintenance

### System Monitoring
```bash
# Install monitoring tools
sudo apt install -y htop iotop nethogs

# Setup log rotation
sudo logrotate -d /etc/logrotate.conf
```

### Backup Strategy
- Daily VM snapshots via GCP
- Weekly full disk backups
- Git repository backup to Cloud Source Repositories

## Cost Optimization

### Scheduled Operations
```bash
# Auto-shutdown at night (save costs)
# Create startup/shutdown scripts
sudo crontab -e
# Add: 0 22 * * 1-5 /usr/sbin/shutdown -h now  # Shutdown weekdays at 10 PM
```

### Preemptible Instances
- Consider preemptible instances for non-critical development
- 80% cost savings with automatic restart scripts

## Access & Collaboration

### SSH Setup
```bash
# Generate SSH key pair
ssh-keygen -t rsa -b 4096 -C "dev-vm-key"

# Add to GCP metadata
gcloud compute project-info add-metadata \
  --metadata-from-file ssh-keys=~/.ssh/id_rsa.pub
```

### Port Forwarding for Remote Development
```bash
# Forward ports for local development
ssh -L 4200:localhost:4200 -L 8080:localhost:8080 user@vm-external-ip
```

## Deployment Checklist

- [ ] Create VM instance with specified configuration
- [ ] Configure firewall rules
- [ ] Install all required software
- [ ] Clone and setup UTMStack project
- [ ] Configure monitoring and backups
- [ ] Test all development workflows
- [ ] Document team access procedures
- [ ] Setup cost alerts and budgets

## Estimated Monthly Cost
- e2-standard-4: ~$150/month (24/7)
- 300 GB storage: ~$60/month
- Network egress: ~$10/month
- **Total: ~$220/month** (can be reduced with scheduled shutdown)

## Next Steps
1. Request GCP project access and billing setup
2. Create VM using this plan
3. Automate setup with Terraform/scripts
4. Create team documentation for access
