variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "talos_image" {
  type = string
}

locals {
  apiserver_port_name = "tcp6443"
}

resource "google_compute_global_address" "talos_lb" {
  name = "${var.cluster_name}-lb-ip"
}

resource "google_compute_health_check" "talos_k8s_api" {
  name = "${var.cluster_name}-health-check"

  timeout_sec        = 5
  check_interval_sec = 5

  tcp_health_check {
    port = "6443"
  }
}

resource "google_compute_backend_service" "talos_k8s_api" {
  name        = "${var.cluster_name}-be"
  port_name   = local.apiserver_port_name
  protocol    = "TCP"
  timeout_sec = 5 * 60

  backend {
    group = google_compute_region_instance_group_manager.talos_bootstrap.instance_group
  }

  backend {
    group = google_compute_region_instance_group_manager.talos_controlplane.instance_group
  }

  health_checks = [
    google_compute_health_check.talos_k8s_api.id
  ]
}

resource "google_compute_target_tcp_proxy" "talos_k8s_api" {
  name            = "${var.cluster_name}-tcp-proxy"
  backend_service = google_compute_backend_service.talos_k8s_api.id
  proxy_header    = "NONE"
}

resource "google_compute_global_forwarding_rule" "talos_k8s_api" {
  name        = "${var.cluster_name}-fwd-rule"
  target      = google_compute_target_tcp_proxy.talos_k8s_api.id
  port_range  = "443"
  ip_address  = google_compute_global_address.talos_lb.id
  ip_protocol = "TCP"
}

resource "google_compute_firewall" "talos_k8s_api" {
  name    = "${var.cluster_name}-apiserver-firewall"
  network = var.vpc_id

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16"
  ]

  target_tags = [
    "${var.cluster_name}-controlplane"
  ]
}

resource "google_compute_firewall" "talos_k8s" {
  name    = "${var.cluster_name}-k8s-firewall"
  network = var.vpc_id

  allow {
    protocol = "all"
  }

  source_tags = [
    "${var.cluster_name}-controlplane",
    "${var.cluster_name}-worker",
  ]

  target_tags = [
    "${var.cluster_name}-controlplane",
    "${var.cluster_name}-worker",
  ]
}

resource "google_compute_firewall" "talos_ctl_api" {
  name    = "${var.cluster_name}-talosctl"
  network = var.vpc_id

  allow {
    protocol = "tcp"
    ports    = ["50000"]
  }

  source_ranges = [
    "0.0.0.0/0"
  ]

  target_tags = [
    "${var.cluster_name}-controlplane"
  ]
}

resource "talos_cluster_config" "talos_config" {
  cluster_name = var.cluster_name
  endpoint     = "https://${google_compute_global_address.talos_lb.address}:443"
}

resource "google_compute_instance_template" "talos_bootstrap" {
  name_prefix    = "${var.cluster_name}-bootstrap-"
  machine_type   = "e2-medium"
  can_ip_forward = false

  tags = [
    "${var.cluster_name}-controlplane"
  ]

  disk {
    source_image = var.talos_image
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
  }

  network_interface {
    network = var.vpc_id
    access_config {
      network_tier = "STANDARD"
    }
  }

  metadata = {
    "user-data" = talos_cluster_config.talos_config.bootstrap_user_data
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_instance_group_manager" "talos_bootstrap" {
  name               = "${var.cluster_name}-bootstrap"
  base_instance_name = "${var.cluster_name}-bootstrap"
  target_size        = "1"
  distribution_policy_zones = [
    "us-east1-b",
  ]

  version {
    name = "${var.cluster_name}-bootstrap"

    instance_template = google_compute_instance_template.talos_bootstrap.id
  }

  named_port {
    name = local.apiserver_port_name
    port = 6443
  }
}

resource "google_compute_instance_template" "talos_controlplane" {
  name_prefix    = "${var.cluster_name}-controlplane-"
  machine_type   = "e2-medium"
  can_ip_forward = false

  tags = [
    "${var.cluster_name}-controlplane"
  ]

  disk {
    source_image = var.talos_image
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
  }

  network_interface {
    network = var.vpc_id
    access_config {
      network_tier = "STANDARD"
    }
  }

  metadata = {
    "user-data" = talos_cluster_config.talos_config.controlplane_user_data
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_instance_group_manager" "talos_controlplane" {
  name               = "${var.cluster_name}-controlplane"
  base_instance_name = "${var.cluster_name}-controlplane"
  target_size        = "2"
  region             = "us-east1"
  distribution_policy_zones = [
    "us-east1-c",
    "us-east1-d",
  ]

  version {
    name = "${var.cluster_name}-controlplane"

    instance_template = google_compute_instance_template.talos_controlplane.id
  }

  named_port {
    name = local.apiserver_port_name
    port = 6443
  }
}

resource "google_compute_instance_template" "talos_worker" {
  name_prefix    = "${var.cluster_name}-worker-"
  machine_type   = "e2-medium"
  can_ip_forward = false

  tags = [
    "${var.cluster_name}-worker"
  ]

  disk {
    source_image = var.talos_image
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
  }

  network_interface {
    network = var.vpc_id
    access_config {
      network_tier = "STANDARD"
    }
  }

  metadata = {
    "user-data" = talos_cluster_config.talos_config.join_user_data
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_instance_group_manager" "talos_worker" {
  name               = "${var.cluster_name}-worker"
  base_instance_name = "${var.cluster_name}-worker"
  target_size        = "3"
  region             = "us-east1"

  version {
    name = "${var.cluster_name}-worker"

    instance_template = google_compute_instance_template.talos_worker.id
  }
}

output "lb_ip_address" {
  value = google_compute_global_address.talos_lb.address
}

output "talos_config" {
  value = talos_cluster_config.talos_config.talos_config
}
