terraform {
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

# ── VPC Network ────────────────────────────────────────────────────────────────
resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false  # manually manage subnets
}

# ── Subnet ─────────────────────────────────────────────────────────────────────
resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
}

# ── Firewall: allow SSH from anywhere ──────────────────────────────────────────
resource "google_compute_firewall" "allow_ssh" {
  name    = "cloudeco-allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["k8s-node"]
}

# ── Firewall: allow K8s API server and app traffic ─────────────────────────────
resource "google_compute_firewall" "allow_k8s" {
  name    = "cloudeco-allow-k8s"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["6443", "8000", "8080", "80", "443", "30000-32767"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["k8s-node"]
}

# ── Firewall: allow all internal traffic between nodes ─────────────────────────
resource "google_compute_firewall" "allow_internal" {
  name    = "cloudeco-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr]
}

# ── Master Node ────────────────────────────────────────────────────────────────
resource "google_compute_instance" "master" {
  name         = var.master_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["k8s-node"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.disk_size_master_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {}  # gives the VM a public IP
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
}

# ── Worker Nodes ───────────────────────────────────────────────────────────────
resource "google_compute_instance" "workers" {
  count        = length(var.worker_names)
  name         = var.worker_names[count.index]
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["k8s-node"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.disk_size_worker_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {}  # gives the VM a public IP
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
}