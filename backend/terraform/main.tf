terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Network resources
resource "google_compute_network" "utmstack_network" {
  name                    = "${var.environment}-utmstack-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "utmstack_subnet" {
  name          = "${var.environment}-utmstack-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.utmstack_network.id
}

# Firewall rules
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.environment}-allow-ssh"
  network = google_compute_network.utmstack_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_ssh_ranges
  target_tags   = ["utmstack-dev"]
}

resource "google_compute_firewall" "allow_dev_ports" {
  name    = "${var.environment}-allow-dev-ports"
  network = google_compute_network.utmstack_network.name

  allow {
    protocol = "tcp"
    ports    = ["3000", "4200", "8080", "8443", "9200", "5432", "9000"]
  }

  source_ranges = var.allowed_dev_ranges
  target_tags   = ["utmstack-dev"]
}

resource "google_compute_firewall" "allow_internal" {
  name    = "${var.environment}-allow-internal"
  network = google_compute_network.utmstack_network.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["utmstack-dev"]
}

# Service account for VMs
resource "google_service_account" "utmstack_sa" {
  account_id   = "${var.environment}-utmstack-sa"
  display_name = "UTMStack Development Service Account"
  description  = "Service account for UTMStack development VMs"
}

resource "google_project_iam_member" "utmstack_sa_roles" {
  for_each = toset([
    "roles/compute.instanceAdmin.v1",
    "roles/storage.objectViewer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.utmstack_sa.email}"
}

# Boot disk snapshot schedule
resource "google_compute_resource_policy" "daily_backup" {
  name   = "${var.environment}-daily-backup"
  region = var.region

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "04:00"
      }
    }
    retention_policy {
      max_retention_days    = 7
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
  }
}

# Single data disk for all tenants
resource "google_compute_disk" "utmstack_data_disk" {
  name  = "${var.environment}-utmstack-data-disk"
  type  = "pd-standard"
  zone  = var.zone
  size  = var.data_disk_size

  labels = {
    environment = var.environment
    purpose     = "multi-tenant-data"
  }
}

# Single VM instance for all tenants
resource "google_compute_instance" "utmstack_vm" {

  name         = "${var.environment}-utmstack-vm"
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["utmstack-dev", "multi-tenant"]

  labels = {
    environment = var.environment
    purpose     = "multi-tenant-development"
  }

  boot_disk {
    initialize_params {
      image = var.boot_disk_image
      size  = var.boot_disk_size
      type  = "pd-ssd"
    }
  }

  attached_disk {
    source      = google_compute_disk.utmstack_data_disk.id
    device_name = "data-disk"
  }

  network_interface {
    network    = google_compute_network.utmstack_network.id
    subnetwork = google_compute_subnetwork.utmstack_subnet.id
    
    access_config {
      # Ephemeral public IP
    }
  }

  service_account {
    email  = google_service_account.utmstack_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    ssh-keys               = "${var.ssh_user}:${file(var.ssh_public_key_path)}"
    enable-oslogin        = "TRUE"
    tenants-config        = jsonencode(var.tenants)
    git-repo-url          = var.git_repo_url
    startup-script        = templatefile("${path.module}/startup-script.sh", {
      tenants_config = jsonencode(var.tenants)
      git_repo_url   = var.git_repo_url
    })
  }



  # Allow stopping for maintenance
  allow_stopping_for_update = true

  # Scheduling for cost optimization
  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = var.use_preemptible
  }
}

# Load balancer for multi-tenant access (optional)
resource "google_compute_global_address" "utmstack_lb_ip" {
  count = var.enable_load_balancer ? 1 : 0
  name  = "${var.environment}-utmstack-lb-ip"
}

resource "google_compute_health_check" "utmstack_health_check" {
  count = var.enable_load_balancer ? 1 : 0
  name  = "${var.environment}-utmstack-health-check"

  http_health_check {
    port         = 8080
    request_path = "/health"
  }

  check_interval_sec  = 30
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
}

# Instance group for each tenant (if load balancer enabled)
resource "google_compute_instance_group" "utmstack_ig" {
  for_each = var.enable_load_balancer ? var.tenants : {}

  name = "${var.environment}-${each.key}-ig"
  zone = var.zone

  instances = [google_compute_instance.utmstack_vm[each.key].id]

  named_port {
    name = "http"
    port = "8080"
  }

  named_port {
    name = "https"
    port = "8443"
  }
}
