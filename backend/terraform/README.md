# UTMStack Multi-Tenant GCP Terraform Deployment

This Terraform configuration deploys multi-tenant UTMStack development environments on Google Cloud Platform.

## Quick Start

1. **Prerequisites**
   ```bash
   # Install Terraform
   curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
   sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
   sudo apt-get update && sudo apt-get install terraform
   
   # Install gcloud CLI
   curl https://sdk.cloud.google.com | bash
   exec -l $SHELL
   gcloud init
   ```

2. **Authentication**
   ```bash
   # Authenticate with GCP
   gcloud auth login
   gcloud auth application-default login
   
   # Set project
   gcloud config set project comp-468008
   ```

3. **Generate SSH Key**
   ```bash
   ssh-keygen -t rsa -b 4096 -C "utmstack-dev-key"
   # Use default path: ~/.ssh/id_rsa
   ```

4. **Configure Variables**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific configuration
   ```

5. **Deploy**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## Configuration

### Basic Configuration (`terraform.tfvars`)

```hcl
project_id = "comp-468008"
region     = "asia-southeast2"  # Jakarta
zone       = "asia-southeast2-a"

tenants = {
  client1 = {
    domain      = "client1.utmstack.local"
    admin_email = "admin@client1.com"
  }
  client2 = {
    domain      = "client2.utmstack.local"
    admin_email = "admin@client2.com"
  }
}
```

### Security Configuration

**IMPORTANT**: Update these for production:

```hcl
# Restrict SSH access to your IP range
allowed_ssh_ranges = ["YOUR_IP/32"]

# Restrict development ports
allowed_dev_ranges = ["YOUR_OFFICE_CIDR/24"]
```

## Architecture

```
GCP Project: comp-468008
Region: asia-southeast2 (Jakarta)
├── VPC Network
│   ├── Subnet: 10.0.1.0/24
│   └── Firewall Rules (SSH, Dev Ports, Internal)
├── VM Instances (per tenant)
│   ├── Machine Type: e2-standard-4
│   ├── Boot Disk: 100GB Ubuntu 24.04
│   ├── Data Disk: 200GB SSD
│   └── Service Account
├── Backup Policy (Daily Snapshots)
└── Load Balancer (Optional)
```

## Features

### Per-Tenant Resources
- Dedicated VM instance
- Isolated data disk (200GB)
- Separate PostgreSQL database
- Individual configuration
- Isolated logs and backups

### Installed Software (per VM)
- **Java**: OpenJDK 11
- **Node.js**: v18 + Angular CLI 7
- **Go**: v1.21
- **Python**: v3.11
- **Database**: PostgreSQL
- **Containers**: Docker + Docker Compose
- **Development**: Git, Maven, VS Code
- **Monitoring**: GCP Ops Agent

### Networking
- Internal communication between tenants
- External access via firewall rules
- Health check endpoints
- Load balancer support (optional)

## Usage

### Connect to VMs

```bash
# SSH to specific tenant
ssh -i ~/.ssh/id_rsa utmstack@<EXTERNAL_IP>

# Or use gcloud
gcloud compute ssh tenant1-vm --project=comp-468008 --zone=asia-southeast2-a

# Port forwarding for development
gcloud compute ssh tenant1-vm --project=comp-468008 --zone=asia-southeast2-a -- -L 4200:localhost:4200 -L 8080:localhost:8080
```

### Development Workflow

```bash
# On each VM
cd /home/utmstack/utmstack

# Backend development
cd backend
./mvnw spring-boot:run

# Frontend development  
cd frontend
npm start

# View logs
tail -f /data/tenant1/logs/*.log
```

### Management Commands

```bash
# List all instances
terraform output tenant_vm_info

# Start/Stop all VMs
gcloud compute instances start tenant1-vm tenant2-vm --zone=asia-southeast2-a
gcloud compute instances stop tenant1-vm tenant2-vm --zone=asia-southeast2-a

# Check costs
gcloud billing budgets list
```

## Cost Optimization

### Preemptible Instances
```hcl
# In terraform.tfvars
use_preemptible = true  # Save ~80% on compute costs
```

### Scheduled Shutdown
```bash
# Add to VM startup script or use Cloud Scheduler
# Stop VMs at night, start in morning
```

### Current Estimated Costs
- **Per VM**: ~$150/month (e2-standard-4, 24/7)
- **Storage**: ~$60/month (300GB SSD)
- **Network**: ~$10/month
- **Total for 2 tenants**: ~$440/month
- **With preemptible**: ~$90/month

## Monitoring

### Health Checks
- Endpoint: `http://<EXTERNAL_IP>:8080/health`
- Monitors: PostgreSQL, Docker, application status

### GCP Console Links
```bash
terraform output monitoring_links
```

### Log Aggregation
- VM logs: `/data/<tenant>/logs/`
- GCP Logging: Automatic collection
- Log rotation: 30 days retention

## Backup & Recovery

### Automatic Backups
- Daily snapshots of all disks
- 7-day retention policy
- Scheduled at 04:00 UTC

### Manual Backup
```bash
gcloud compute disks snapshot tenant1-vm --snapshot-names=tenant1-backup-$(date +%Y%m%d)
```

### Disaster Recovery
```bash
# Restore from snapshot
gcloud compute disks create tenant1-vm-restored --source-snapshot=tenant1-backup-20240101
```

## Scaling

### Add New Tenant
```hcl
# In terraform.tfvars
tenants = {
  tenant1 = { ... }
  tenant2 = { ... }
  tenant3 = {  # Add new tenant
    domain      = "tenant3.utmstack.local"
    admin_email = "admin@tenant3.com"
  }
}
```

```bash
terraform plan  # Review changes
terraform apply # Deploy new tenant
```

### Vertical Scaling
```hcl
# In terraform.tfvars
machine_type = "e2-standard-8"  # Upgrade to 8 vCPUs, 32GB RAM
```

## Troubleshooting

### Common Issues

1. **SSH Connection Failed**
   ```bash
   # Check firewall rules
   gcloud compute firewall-rules list
   
   # Verify SSH key
   gcloud compute project-info describe --format="value(commonInstanceMetadata.items[ssh-keys])"
   ```

2. **VM Startup Issues**
   ```bash
   # Check startup script logs
   gcloud compute ssh tenant1-vm -- sudo tail -f /var/log/utmstack-startup.log
   ```

3. **Service Not Starting**
   ```bash
   # Check systemd status
   gcloud compute ssh tenant1-vm -- sudo systemctl status utmstack-tenant1
   ```

### Log Locations
- Startup script: `/var/log/utmstack-startup.log`
- Application logs: `/data/<tenant>/logs/`
- System logs: `journalctl -u utmstack-<tenant>`

## Security Best Practices

1. **Network Security**
   - Restrict SSH access to known IPs
   - Use private subnets for production
   - Enable VPC Flow Logs

2. **Access Control**
   - Use IAM service accounts
   - Enable OS Login
   - Regular key rotation

3. **Data Protection**
   - Enable disk encryption
   - Regular backups
   - Access logging

## Support

For issues or questions:
1. Check terraform logs: `terraform apply -auto-approve 2>&1 | tee deploy.log`
2. Review VM startup logs: `/var/log/utmstack-startup.log`
3. Verify GCP quotas and billing
4. Check UTMStack documentation

## Cleanup

```bash
# Destroy all resources
terraform destroy

# Confirm resource cleanup
gcloud compute instances list
gcloud compute disks list
```

**Warning**: This will permanently delete all VMs, disks, and data!
