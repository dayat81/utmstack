variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "comp-468008"
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "asia-southeast2"  # Jakarta
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "asia-southeast2-a"  # Jakarta zone
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "machine_type" {
  description = "Machine type for VM instances"
  type        = string
  default     = "e2-standard-4"
}

variable "boot_disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 100
}

variable "data_disk_size" {
  description = "Data disk size in GB for multi-tenant storage"
  type        = number
  default     = 150
}

variable "boot_disk_image" {
  description = "Boot disk image"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_ssh_ranges" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production
}

variable "allowed_dev_ranges" {
  description = "CIDR blocks allowed for development ports"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production
}

variable "ssh_user" {
  description = "SSH username"
  type        = string
  default     = "utmstack"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "use_preemptible" {
  description = "Use preemptible instances for cost savings"
  type        = bool
  default     = false
}

variable "enable_load_balancer" {
  description = "Enable load balancer for multi-tenant access"
  type        = bool
  default     = false
}

variable "git_repo_url" {
  description = "Git repository URL for UTMStack"
  type        = string
  default     = "https://github.com/utmstack/UTMStack.git"
}

variable "tenants" {
  description = "Map of tenant configurations"
  type = map(object({
    domain      = string
    admin_email = string
    description = optional(string, "")
  }))
  default = {
    tenant1 = {
      domain      = "tenant1.utmstack.local"
      admin_email = "admin@tenant1.com"
      description = "First tenant environment"
    }
    tenant2 = {
      domain      = "tenant2.utmstack.local"
      admin_email = "admin@tenant2.com"
      description = "Second tenant environment"
    }
  }
}

variable "startup_script_path" {
  description = "Path to startup script"
  type        = string
  default     = "./startup-script.sh"
}

variable "enable_monitoring" {
  description = "Enable GCP monitoring and logging"
  type        = bool
  default     = true
}

variable "enable_auto_backup" {
  description = "Enable automatic disk backups"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "network_tags" {
  description = "Additional network tags for instances"
  type        = list(string)
  default     = ["utmstack", "development"]
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "utmstack"
    environment = "development"
    managed_by  = "terraform"
  }
}

variable "enable_os_login" {
  description = "Enable OS Login for SSH key management"
  type        = bool
  default     = true
}

variable "enable_ip_forwarding" {
  description = "Enable IP forwarding on VM instances"
  type        = bool
  default     = false
}

variable "disk_type" {
  description = "Disk type for persistent disks"
  type        = string
  default     = "pd-ssd"
  
  validation {
    condition     = contains(["pd-standard", "pd-ssd", "pd-balanced"], var.disk_type)
    error_message = "Disk type must be one of: pd-standard, pd-ssd, pd-balanced."
  }
}

variable "auto_delete_disk" {
  description = "Auto delete disk when instance is deleted"
  type        = bool
  default     = true
}

variable "maintenance_window" {
  description = "Maintenance window for instances (UTC)"
  type = object({
    start_time = string  # HH:MM format
    end_time   = string  # HH:MM format
    day        = string  # MONDAY, TUESDAY, etc.
  })
  default = {
    start_time = "02:00"
    end_time   = "04:00"
    day        = "SUNDAY"
  }
}

variable "firewall_rules" {
  description = "Additional firewall rules"
  type = map(object({
    ports         = list(string)
    source_ranges = list(string)
    target_tags   = list(string)
    protocol      = string
  }))
  default = {}
}
