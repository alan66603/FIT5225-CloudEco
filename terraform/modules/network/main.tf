resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
}

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
