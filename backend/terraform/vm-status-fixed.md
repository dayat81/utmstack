# UTMStack Multi-Tenant VM Deployment Status (FIXED)

**Deployment Date:** August 10, 2025  
**Project ID:** comp-468008  
**Region:** asia-southeast2 (Jakarta)  
**Zone:** asia-southeast2-a  

## ✅ Successfully Deployed - Single Multi-Tenant VM

### Multi-Tenant Development VM
- **Status:** ✅ RUNNING
- **VM Name:** `dev-utmstack-vm`
- **Machine Type:** e2-standard-4 (4 vCPUs, 16GB RAM)
- **Internal IP:** 10.0.1.2
- **External IP:** 34.128.77.232
- **Purpose:** Single VM serving all tenants

### Configured Tenants
1. **Tenant 1**
   - Domain: tenant1.utmstack.local
   - Admin Email: admin@tenant1.com
   - Database: utmstack_tenant1

2. **Tenant 2**  
   - Domain: tenant2.utmstack.local
   - Admin Email: admin@tenant2.com
   - Database: utmstack_tenant2

## 🔐 Access Credentials

### SSH Access
```bash
# SSH using private key
ssh -i ~/.ssh/id_rsa utmstack@34.128.77.232

# SSH using gcloud (recommended)
gcloud compute ssh dev-utmstack-vm --project=comp-468008 --zone=asia-southeast2-a
```

### Database Credentials (Multi-Tenant)
```
# Tenant 1 Database
Database: postgresql://localhost:5432/utmstack_tenant1
Username: utmstack_tenant1
Password: utmstack123

# Tenant 2 Database  
Database: postgresql://localhost:5432/utmstack_tenant2
Username: utmstack_tenant2
Password: utmstack123
```

### System User
```
Username: utmstack
Password: sudo access (passwordless)
SSH Key: ~/.ssh/id_rsa (your private key)
```

## 🌐 Service URLs

### Multi-Tenant Application
- **Frontend:** http://34.128.77.232:4200
- **Backend API:** http://34.128.77.232:8080
- **Health Check:** http://34.128.77.232:8080/health
- **GCP Console:** [VM Details](https://console.cloud.google.com/compute/instancesDetail/zones/asia-southeast2-a/instances/dev-utmstack-vm?project=comp-468008)

### Port Forwarding (for local development)
```bash
# Frontend only
gcloud compute ssh dev-utmstack-vm --project=comp-468008 --zone=asia-southeast2-a -- -L 4200:localhost:4200

# Backend only  
gcloud compute ssh dev-utmstack-vm --project=comp-468008 --zone=asia-southeast2-a -- -L 8080:localhost:8080

# Database access
gcloud compute ssh dev-utmstack-vm --project=comp-468008 --zone=asia-southeast2-a -- -L 5432:localhost:5432

# Full stack (frontend + backend + database)
gcloud compute ssh dev-utmstack-vm --project=comp-468008 --zone=asia-southeast2-a -- -L 4200:localhost:4200 -L 8080:localhost:8080 -L 5432:localhost:5432
```

## 📊 Infrastructure Details

### Network Configuration
- **VPC Network:** dev-utmstack-network
- **Subnet:** dev-utmstack-subnet (10.0.1.0/24)
- **Firewall Rules:** SSH (22), Dev ports (3000,4200,8080,8443,9200,5432)

### Storage (Optimized for Multi-Tenant)
- **Boot Disk:** 100GB SSD (Ubuntu 24.04 LTS)
- **Shared Data Disk:** 150GB Standard HDD (mounted at `/data`)
- **Backup Policy:** Daily snapshots at 04:00 UTC, 7-day retention

### Multi-Tenant Data Structure
```
/data/
├── tenant1/
│   ├── logs/
│   ├── backups/
│   └── config/
└── tenant2/
    ├── logs/
    ├── backups/
    └── config/
```

### Service Account
- **Email:** dev-utmstack-sa@comp-468008.iam.gserviceaccount.com
- **Permissions:** Compute Instance Admin, Storage Object Viewer, Logging Writer, Monitoring Writer

## 🛠️ Installed Software

### Development Stack
- **Java:** OpenJDK 11 (`/usr/lib/jvm/java-11-openjdk-amd64`)
- **Node.js:** v18.x with Angular CLI v7
- **Go:** v1.21 (`/usr/local/go`)
- **Python:** v3.11 with pip and venv
- **Maven:** Latest version
- **jq:** JSON processor for tenant management

### Infrastructure
- **Database:** PostgreSQL with separate databases per tenant
- **Containers:** Docker + Docker Compose
- **Web Server:** Nginx (health checks and reverse proxy)
- **Monitoring:** GCP Ops Agent
- **Editor:** VS Code (optional)

### UTMStack Project
- **Repository:** https://github.com/utmstack/UTMStack.git
- **Location:** `/home/utmstack/utmstack`
- **Shared Data Directory:** `/data`
- **Tenant Configs:** `/home/utmstack/tenants/`

## 🚀 Getting Started

### 1. Connect to VM
```bash
gcloud compute ssh dev-utmstack-vm --project=comp-468008 --zone=asia-southeast2-a
```

### 2. Check Multi-Tenant Setup
```bash
# View tenant management script
/home/utmstack/manage-tenants.sh list

# Check available tenants
cat /home/utmstack/.env | grep TENANTS_CONFIG

# View tenant-specific configs
ls -la /home/utmstack/tenants/
```

### 3. Start UTMStack Services
```bash
# Switch to utmstack user
sudo su - utmstack

# Navigate to project
cd /home/utmstack/utmstack

# For Tenant 1 development:
source /home/utmstack/tenants/tenant1/.env

# Start backend (Spring Boot)
cd backend && ./mvnw spring-boot:run

# In another terminal, start frontend (Angular)
cd frontend && npm start
```

### 4. Access Applications
- Frontend: http://34.128.77.232:4200
- Backend API: http://34.128.77.232:8080/api
- Health Check: http://34.128.77.232:8080/health

## 📋 Multi-Tenant Management

### Tenant Management Commands
```bash
# On the VM - List all tenants
/home/utmstack/manage-tenants.sh list

# Check status
/home/utmstack/manage-tenants.sh status

# Start services (placeholder for tenant-specific logic)
/home/utmstack/manage-tenants.sh start

# Stop services
/home/utmstack/manage-tenants.sh stop
```

### Database Access per Tenant
```bash
# Connect to Tenant 1 database
psql -h localhost -U utmstack_tenant1 -d utmstack_tenant1

# Connect to Tenant 2 database  
psql -h localhost -U utmstack_tenant2 -d utmstack_tenant2

# List all databases
sudo -u postgres psql -c "\l"
```

### VM Management
```bash
# List all instances
gcloud compute instances list --project=comp-468008

# Stop VM (cost saving)
gcloud compute instances stop dev-utmstack-vm --project=comp-468008 --zone=asia-southeast2-a

# Start VM
gcloud compute instances start dev-utmstack-vm --project=comp-468008 --zone=asia-southeast2-a
```

## 💰 Cost Estimation (Optimized)

### Current Single VM Deployment
- **Compute:** ~$75/month (e2-standard-4, 24/7)
- **Storage:** ~$25/month (250GB total: 100GB SSD + 150GB Standard)
- **Network:** ~$5/month
- **Total:** ~$105/month (50% cost savings vs separate VMs)

### Cost Optimization Options
- Use preemptible instances: 80% cost reduction
- Schedule VM shutdown: Stop VM outside business hours
- Use standard disks: Already optimized

## 🔧 Development Workflow

### Working with Multiple Tenants

1. **Choose a Tenant Context**
   ```bash
   # For Tenant 1
   cd /home/utmstack
   source tenants/tenant1/.env
   
   # For Tenant 2
   source tenants/tenant2/.env
   ```

2. **Start Development**
   ```bash
   cd utmstack/backend
   ./mvnw spring-boot:run
   ```

3. **Switch Between Tenants**
   - Each tenant has its own database
   - Separate log directories: `/data/tenant1/logs/`, `/data/tenant2/logs/`
   - Individual environment configurations

### Port Management for Multi-Tenant
- **Default Ports:** All tenants share the same application ports
- **Database:** All tenants use PostgreSQL on port 5432 with different databases
- **Future Enhancement:** Can be configured for tenant-specific ports if needed

## 📞 Support & Troubleshooting

### Log Locations
- **Startup Script:** `/var/log/utmstack-startup.log`
- **Multi-Tenant Setup:** `/home/utmstack/README-MULTI-TENANT.txt`
- **Tenant 1 Logs:** `/data/tenant1/logs/`
- **Tenant 2 Logs:** `/data/tenant2/logs/`
- **System Logs:** `journalctl -u utmstack-multi-tenant`

### Common Multi-Tenant Issues
1. **Tenant context confusion:** Always source the correct tenant .env file
2. **Database connection:** Ensure using the correct tenant database
3. **Log separation:** Check the right tenant log directory
4. **Disk space:** Monitor `/data` usage across all tenants

### Health Checks
- **Multi-Tenant Health:** http://34.128.77.232:8080/health
- **Tenant List:** Included in health check response
- **Service Status:** Shows PostgreSQL, Docker, and tenant info

## ✅ Benefits of Single VM Multi-Tenant Setup

1. **Cost Efficiency:** 50% cost reduction vs separate VMs
2. **Resource Sharing:** Efficient use of CPU, memory, and storage
3. **Simplified Management:** Single VM to manage and monitor
4. **No Quota Issues:** Within SSD limits for the region
5. **Easy Scaling:** Can add more tenants to the same VM
6. **Unified Development:** Shared codebase with tenant-specific configs

---
**Last Updated:** August 10, 2025  
**Configuration:** Single multi-tenant VM with optimized resource usage  
**Status:** ✅ Successfully deployed and running
