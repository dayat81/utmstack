# UTMStack Multi-Tenant VM Deployment Status

**Deployment Date:** August 10, 2025  
**Project ID:** comp-468008  
**Region:** asia-southeast2 (Jakarta)  
**Zone:** asia-southeast2-a  

## ✅ Successfully Deployed VMs

### Tenant 1 VM
- **Status:** ✅ RUNNING
- **VM Name:** `dev-tenant1-vm`
- **Machine Type:** e2-standard-4 (4 vCPUs, 16GB RAM)
- **Internal IP:** 10.0.1.2
- **External IP:** 34.101.114.12
- **Domain:** tenant1.utmstack.local
- **Admin Email:** admin@tenant1.com

### Tenant 2 VM  
- **Status:** ❌ FAILED (SSD quota exceeded)
- **VM Name:** `dev-tenant2-vm`
- **Machine Type:** e2-standard-4 (4 vCPUs, 16GB RAM)
- **Note:** Creation failed due to SSD quota limit (400GB) in asia-southeast2 region

## 🔐 Access Credentials

### SSH Access
```bash
# SSH using private key
ssh -i ~/.ssh/id_rsa utmstack@34.101.114.12

# SSH using gcloud (recommended)
gcloud compute ssh dev-tenant1-vm --project=comp-468008 --zone=asia-southeast2-a
```

### Database Credentials
```
Database: postgresql://localhost:5432/utmstack_tenant1
Username: utmstack_tenant1
Password: utmstack123
```

### System User
```
Username: utmstack
Password: sudo access (passwordless)
SSH Key: ~/.ssh/id_rsa (your private key)
```

## 🌐 Service URLs

### Tenant 1 (Active)
- **Frontend:** http://34.101.114.12:4200
- **Backend API:** http://34.101.114.12:8080
- **Health Check:** http://34.101.114.12:8080/health
- **GCP Console:** [VM Details](https://console.cloud.google.com/compute/instancesDetail/zones/asia-southeast2-a/instances/dev-tenant1-vm?project=comp-468008)

### Port Forwarding (for local development)
```bash
# Frontend only
gcloud compute ssh dev-tenant1-vm --project=comp-468008 --zone=asia-southeast2-a -- -L 4200:localhost:4200

# Backend only  
gcloud compute ssh dev-tenant1-vm --project=comp-468008 --zone=asia-southeast2-a -- -L 8080:localhost:8080

# Full stack (frontend + backend + database)
gcloud compute ssh dev-tenant1-vm --project=comp-468008 --zone=asia-southeast2-a -- -L 4200:localhost:4200 -L 8080:localhost:8080 -L 5432:localhost:5432
```

## 📊 Infrastructure Details

### Network Configuration
- **VPC Network:** dev-utmstack-network
- **Subnet:** dev-utmstack-subnet (10.0.1.0/24)
- **Firewall Rules:** SSH (22), Dev ports (3000,4200,8080,8443,9200,5432)

### Storage
- **Boot Disk:** 100GB SSD (Ubuntu 24.04 LTS)
- **Data Disk:** 100GB Standard HDD (mounted at `/data/tenant1`)
- **Backup Policy:** Daily snapshots at 04:00 UTC, 7-day retention

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

### Infrastructure
- **Database:** PostgreSQL with tenant-specific database
- **Containers:** Docker + Docker Compose
- **Web Server:** Nginx (health checks and reverse proxy)
- **Monitoring:** GCP Ops Agent
- **Editor:** VS Code (optional)

### UTMStack Project
- **Repository:** https://github.com/utmstack/UTMStack.git
- **Location:** `/home/utmstack/utmstack`
- **Data Directory:** `/data/tenant1`
- **Logs:** `/data/tenant1/logs`

## 🚀 Getting Started

### 1. Connect to VM
```bash
gcloud compute ssh dev-tenant1-vm --project=comp-468008 --zone=asia-southeast2-a
```

### 2. Check Startup Progress
```bash
# View startup script logs
sudo tail -f /var/log/utmstack-startup.log

# Check system status
systemctl status utmstack-tenant1
```

### 3. Start UTMStack Services
```bash
# Switch to utmstack user
sudo su - utmstack

# Navigate to project
cd /home/utmstack/utmstack

# Start backend (Spring Boot)
cd backend && ./mvnw spring-boot:run

# In another terminal, start frontend (Angular)
cd frontend && npm start
```

### 4. Access Applications
- Frontend: http://34.101.114.12:4200
- Backend API: http://34.101.114.12:8080/api
- Health Check: http://34.101.114.12:8080/health

## 📋 Management Commands

### VM Operations
```bash
# List all instances
gcloud compute instances list --project=comp-468008

# Stop VM (cost saving)
gcloud compute instances stop dev-tenant1-vm --project=comp-468008 --zone=asia-southeast2-a

# Start VM
gcloud compute instances start dev-tenant1-vm --project=comp-468008 --zone=asia-southeast2-a

# View VM details
gcloud compute instances describe dev-tenant1-vm --project=comp-468008 --zone=asia-southeast2-a
```

### Service Management
```bash
# On the VM, check service status
sudo systemctl status utmstack-tenant1

# Start/stop UTMStack service
sudo systemctl start utmstack-tenant1
sudo systemctl stop utmstack-tenant1

# View application logs
tail -f /data/tenant1/logs/*.log
```

### Backup Management
```bash
# List snapshots
gcloud compute snapshots list --filter="sourceDisk:dev-tenant1"

# Create manual snapshot
gcloud compute disks snapshot dev-tenant1-vm --snapshot-names=manual-backup-$(date +%Y%m%d) --zone=asia-southeast2-a
```

## ⚠️ Known Issues

### Tenant 2 VM Creation Failed
- **Issue:** SSD quota exceeded (400GB limit in asia-southeast2)
- **Current Usage:** ~300GB (boot disks + existing GKE cluster)
- **Required:** Additional 200GB for Tenant 2

### Solutions:
1. **Request Quota Increase:** Increase SSD quota to 600GB
2. **Use Different Region:** Deploy Tenant 2 in asia-southeast1 or us-central1
3. **Optimize Storage:** Use standard disks instead of SSD for data disks

## 💰 Cost Estimation

### Current Deployment (1 VM)
- **Compute:** ~$75/month (e2-standard-4, 24/7)
- **Storage:** ~$30/month (200GB total)
- **Network:** ~$5/month
- **Total:** ~$110/month

### Full Deployment (2 VMs)
- **Compute:** ~$150/month
- **Storage:** ~$60/month  
- **Network:** ~$10/month
- **Total:** ~$220/month

### Cost Optimization Options
- Use preemptible instances: 80% cost reduction
- Schedule VM shutdown: Stop VMs outside business hours
- Use standard disks: 50% storage cost reduction

## 📞 Support & Troubleshooting

### Log Locations
- **Startup Script:** `/var/log/utmstack-startup.log`
- **UTMStack Logs:** `/data/tenant1/logs/`
- **System Logs:** `journalctl -u utmstack-tenant1`

### Common Issues
1. **Services not starting:** Check `/var/log/utmstack-startup.log`
2. **Port access issues:** Verify firewall rules
3. **Database connection:** Check PostgreSQL service status
4. **Disk space:** Monitor `/data/tenant1` usage

### Contact Information
- **GCP Project:** comp-468008
- **Terraform State:** `/home/ptsec/utmstack/backend/terraform/`
- **Documentation:** [README.md](./README.md)

---
**Last Updated:** August 10, 2025  
**Generated by:** Terraform deployment automation
