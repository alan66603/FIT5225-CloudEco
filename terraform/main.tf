# AI-generated (Claude, Anthropic): modular network/compute structure.
# Modified: added worker_machine_type, disk size variables, NodePort firewall rule (30000-32767),
# and SSH firewall rule (tcp:22) for Ansible access.

module "network" {
  source = "./modules/network"

  network_name = var.network_name
  subnet_name  = var.subnet_name
  subnet_cidr  = var.subnet_cidr
  region       = var.region
}

module "compute" {
  source = "./modules/compute"

  master_name         = var.master_name
  worker_names        = var.worker_names
  machine_type        = var.machine_type
  worker_machine_type = var.worker_machine_type
  zone                = var.zone
  disk_size_master_gb = var.disk_size_master_gb
  disk_size_worker_gb = var.disk_size_worker_gb
  subnet_id           = module.network.subnet_id
}