output "master_public_ip" {
  description = "Master node public IP"
  value       = module.compute.master_public_ip
}

output "worker_public_ips" {
  description = "Worker nodes public IPs"
  value       = module.compute.worker_public_ips
}

output "master_ssh_command" {
  description = "SSH command to connect to master node"
  value       = module.compute.master_ssh_command
}
