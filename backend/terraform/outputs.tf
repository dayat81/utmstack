output "vm_info" {
  description = "Information about the multi-tenant VM"
  value = {
    name         = google_compute_instance.utmstack_vm.name
    internal_ip  = google_compute_instance.utmstack_vm.network_interface[0].network_ip
    external_ip  = google_compute_instance.utmstack_vm.network_interface[0].access_config[0].nat_ip
    zone         = google_compute_instance.utmstack_vm.zone
    machine_type = google_compute_instance.utmstack_vm.machine_type
    status       = google_compute_instance.utmstack_vm.current_status
    self_link    = google_compute_instance.utmstack_vm.self_link
    tenants      = var.tenants
  }
}

output "ssh_command" {
  description = "SSH command to connect to the multi-tenant VM"
  value = "ssh -i ~/.ssh/id_rsa ${var.ssh_user}@${google_compute_instance.utmstack_vm.network_interface[0].access_config[0].nat_ip}"
}

output "web_urls" {
  description = "Web URLs for the multi-tenant application"
  value = {
    frontend_url = "http://${google_compute_instance.utmstack_vm.network_interface[0].access_config[0].nat_ip}:4200"
    backend_url  = "http://${google_compute_instance.utmstack_vm.network_interface[0].access_config[0].nat_ip}:8080"
    api_url      = "http://${google_compute_instance.utmstack_vm.network_interface[0].access_config[0].nat_ip}:8080/api"
    health_url   = "http://${google_compute_instance.utmstack_vm.network_interface[0].access_config[0].nat_ip}:8080/health"
  }
}

output "network_info" {
  description = "Network configuration information"
  value = {
    network_name    = google_compute_network.utmstack_network.name
    network_id      = google_compute_network.utmstack_network.id
    subnet_name     = google_compute_subnetwork.utmstack_subnet.name
    subnet_cidr     = google_compute_subnetwork.utmstack_subnet.ip_cidr_range
    region          = var.region
    zone            = var.zone
  }
}

output "service_account_email" {
  description = "Service account email for VMs"
  value       = google_service_account.utmstack_sa.email
}

output "firewall_rules" {
  description = "Created firewall rules"
  value = {
    ssh_rule      = google_compute_firewall.allow_ssh.name
    dev_ports_rule = google_compute_firewall.allow_dev_ports.name
    internal_rule  = google_compute_firewall.allow_internal.name
  }
}

output "data_disk" {
  description = "Data disk information for multi-tenant storage"
  value = {
    name      = google_compute_disk.utmstack_data_disk.name
    size      = google_compute_disk.utmstack_data_disk.size
    type      = google_compute_disk.utmstack_data_disk.type
    zone      = google_compute_disk.utmstack_data_disk.zone
    self_link = google_compute_disk.utmstack_data_disk.self_link
  }
}

output "backup_policy" {
  description = "Backup policy information"
  value = {
    name               = google_compute_resource_policy.daily_backup.name
    retention_days     = google_compute_resource_policy.daily_backup.snapshot_schedule_policy[0].retention_policy[0].max_retention_days
    backup_time        = google_compute_resource_policy.daily_backup.snapshot_schedule_policy[0].schedule[0].daily_schedule[0].start_time
  }
}

output "load_balancer_ip" {
  description = "Load balancer external IP (if enabled)"
  value       = var.enable_load_balancer ? google_compute_global_address.utmstack_lb_ip[0].address : null
}

output "project_info" {
  description = "Project and deployment information"
  value = {
    project_id  = var.project_id
    region      = var.region
    zone        = var.zone
    environment = var.environment
  }
}

output "cost_estimation" {
  description = "Estimated monthly costs (approximation)"
  value = {
    per_vm_monthly_cost = "~$150 USD (e2-standard-4 24/7)"
    storage_cost_per_vm = "~$60 USD (300GB SSD)"
    total_vms           = length(var.tenants)
    estimated_total     = "~$${(150 + 60) * length(var.tenants)} USD/month"
    note               = "Costs can be reduced with preemptible instances and scheduled shutdown"
  }
}

output "management_commands" {
  description = "Useful management commands"
  value = {
    list_instances = "gcloud compute instances list --project=${var.project_id}"
    ssh_to_vm     = "gcloud compute ssh ${google_compute_instance.utmstack_vm.name} --project=${var.project_id} --zone=${google_compute_instance.utmstack_vm.zone}"
    start_vm      = "gcloud compute instances start ${google_compute_instance.utmstack_vm.name} --project=${var.project_id} --zone=${var.zone}"
    stop_vm       = "gcloud compute instances stop ${google_compute_instance.utmstack_vm.name} --project=${var.project_id} --zone=${var.zone}"
    manage_tenants = "ssh to VM and run: /home/utmstack/manage-tenants.sh {start|stop|status|list}"
  }
}

output "port_forwarding_commands" {
  description = "Port forwarding commands for local development"
  value = {
    frontend = "gcloud compute ssh ${google_compute_instance.utmstack_vm.name} --project=${var.project_id} --zone=${var.zone} -- -L 4200:localhost:4200"
    backend  = "gcloud compute ssh ${google_compute_instance.utmstack_vm.name} --project=${var.project_id} --zone=${var.zone} -- -L 8080:localhost:8080"
    database = "gcloud compute ssh ${google_compute_instance.utmstack_vm.name} --project=${var.project_id} --zone=${var.zone} -- -L 5432:localhost:5432"
    full     = "gcloud compute ssh ${google_compute_instance.utmstack_vm.name} --project=${var.project_id} --zone=${var.zone} -- -L 4200:localhost:4200 -L 8080:localhost:8080 -L 5432:localhost:5432"
  }
}

output "monitoring_link" {
  description = "GCP Console monitoring link"
  value = "https://console.cloud.google.com/compute/instancesDetail/zones/${google_compute_instance.utmstack_vm.zone}/instances/${google_compute_instance.utmstack_vm.name}?project=${var.project_id}"
}
