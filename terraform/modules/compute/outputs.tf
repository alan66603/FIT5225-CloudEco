output "master_public_ip" {
  description = "Master node public IP"
  value       = google_compute_instance.master.network_interface[0].access_config[0].nat_ip
}

output "worker_public_ips" {
  description = "Worker nodes public IPs"
  value       = [for w in google_compute_instance.workers : w.network_interface[0].access_config[0].nat_ip]
}

output "master_ssh_command" {
  description = "SSH command to connect to master node"
  value       = "ssh ubuntu@${google_compute_instance.master.network_interface[0].access_config[0].nat_ip}"
}