variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "alan-cloudeco"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "australia-southeast1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "australia-southeast1-a"
}

variable "machine_type" {
  description = "VM machine type (4 vCPU, 8 GB RAM)"
  type        = string
  default     = "e2-custom-4-8192"
}

variable "disk_size_master_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 50
}

variable "disk_size_worker_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 15
}

variable "network_name" {
  description = "VPC network name"
  type        = string
  default     = "cloudeco-vpc"
}

variable "subnet_name" {
  description = "Subnet name"
  type        = string
  default     = "cloudeco-subnet"
}

variable "subnet_cidr" {
  description = "Subnet CIDR range"
  type        = string
  default     = "10.0.0.0/24"
}

variable "master_name" {
  description = "Master node VM name"
  type        = string
  default     = "k8s-master"
}

variable "worker_names" {
  description = "Worker node VM names"
  type        = list(string)
  default     = ["k8s-worker-1", "k8s-worker-2"]
}