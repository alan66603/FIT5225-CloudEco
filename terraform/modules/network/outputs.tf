output "network_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "subnet_id" {
  description = "Subnet self-link ID"
  value       = google_compute_subnetwork.subnet.id
}
