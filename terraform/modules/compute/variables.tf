variable "master_name" {
  description = "Master node VM name"
  type        = string
}

variable "worker_names" {
  description = "Worker node VM names"
  type        = list(string)
}

variable "machine_type" {
  description = "VM machine type"
  type        = string
}

variable "zone" {
  description = "GCP zone"
  type        = string
}

variable "disk_size_master_gb" {
  description = "Master node boot disk size in GB"
  type        = number
}

variable "disk_size_worker_gb" {
  description = "Worker node boot disk size in GB"
  type        = number
}

variable "subnet_id" {
  description = "Subnet self-link ID"
  type        = string
}