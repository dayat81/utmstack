# GCP Project Configuration
project_id = "comp-468008"
region     = "asia-southeast2"  # Jakarta
zone       = "asia-southeast2-a"

# Environment
environment = "dev"

# VM Configuration
machine_type     = "e2-standard-4"  # 4 vCPUs, 16GB RAM
boot_disk_size   = 100              # GB
data_disk_size   = 150              # GB for all tenants
use_preemptible  = false            # Set to true for cost savings

# Network Configuration
subnet_cidr = "10.0.1.0/24"

# Security - IMPORTANT: Restrict these in production!
allowed_ssh_ranges = ["0.0.0.0/0"]  # Replace with your IP range
allowed_dev_ranges = ["0.0.0.0/0"]  # Replace with your IP range

# SSH Configuration
ssh_user             = "utmstack"
ssh_public_key_path  = "~/.ssh/id_rsa.pub"  # Path to your public key

# UTMStack Repository
git_repo_url = "https://github.com/utmstack/UTMStack.git"

# Multi-Tenant Configuration
tenants = {
  tenant1 = {
    domain      = "tenant1.utmstack.local"
    admin_email = "admin@tenant1.com"
    description = "First tenant development environment"
  }
  tenant2 = {
    domain      = "tenant2.utmstack.local" 
    admin_email = "admin@tenant2.com"
    description = "Second tenant development environment"
  }
  # Add more tenants as needed
  # tenant3 = {
  #   domain      = "tenant3.utmstack.local"
  #   admin_email = "admin@tenant3.com"
  #   description = "Third tenant environment"
  # }
}

# Optional Features
enable_load_balancer = false  # Set to true if you need a load balancer
enable_monitoring    = true
enable_auto_backup   = true
backup_retention_days = 7

# Cost Optimization
# Set use_preemptible = true to save ~80% on compute costs
# VMs will be stopped/restarted automatically by GCP

# Labels for resource management
labels = {
  project     = "utmstack"
  environment = "development"
  team        = "engineering"
  managed_by  = "terraform"
}

# Additional firewall rules (optional)
firewall_rules = {
  # Example: Allow specific application port
  # "allow-app-port" = {
  #   ports         = ["9000"]
  #   source_ranges = ["10.0.0.0/8"]
  #   target_tags   = ["utmstack-dev"]
  #   protocol      = "tcp"
  # }
}

# Maintenance window
maintenance_window = {
  start_time = "02:00"  # UTC
  end_time   = "04:00"  # UTC
  day        = "SUNDAY"
}
