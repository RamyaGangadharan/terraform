resource "google_project_service" "service" {
  for_each = toset(var.services)

  service = each.key

  project            = var.project_id
  disable_on_destroy = false
}

# Create a service account

resource "google_service_account" "service_account" {
  account_id   = local.gcp_service_account_name
  display_name = local.gcp_service_account_name
  project      = var.project_id
}

# Create a VPC for the application
resource "google_compute_network" "flask-network" {
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode = "REGIONAL"
}

resource "google_compute_subnetwork" "flask-subnetwork-private" {
  project       = var.project_id
  name          = "private-flask-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.flask-network.name
  private_ip_google_access = false
}

resource "google_compute_subnetwork" "flask-subnetwork-public" {
  project       = var.project_id
  name          = "public-flask-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.flask-network.name
  private_ip_google_access = true
}

resource "google_compute_router" "default" {
  name    = "${var.network_name}-router"
  network = google_compute_network.flask-network.self_link
  region  = var.region
  project = var.project_id
}

resource "google_compute_router_nat" "nat" {
  project                            = var.project_id
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.default.name
  region                             = google_compute_router.default.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  #source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.flask-subnetwork-private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "google_compute_firewall" "rules" {
  project     = var.project_id
  name        = "${var.network_name}-http-allow"
  network     = google_compute_network.flask-network.name
  description = "Creates firewall rule targeting tagged instances"
  

  allow {
    protocol  = "tcp"
    ports     = ["80","22"]
  }
  # target_tags = ["allow-http","flask-runner-vm"]
  source_ranges = ["130.211.0.0/22","35.191.0.0/16","209.85.152.0/22","209.85.204.0/22","0.0.0.0/0"]
}

# Runner GCE Instance Template

locals {
  instance_name = "flask-runner-vm"
}


module "mig_template" {
  source             = "terraform-google-modules/vm/google//modules/instance_template"
  version            = "~> 7.9.0"
  project_id         = var.project_id
  machine_type       = var.machine_type
  network            = var.network_name
  subnetwork         = google_compute_subnetwork.flask-subnetwork-private.id
  region             = var.region
  subnetwork_project = var.project_id
  service_account = {
    email = google_service_account.service_account.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
  disk_size_gb         = 10
  disk_type            = "pd-ssd"
  auto_delete          = true
  name_prefix          = var.instance_name
  source_image_family  = var.source_image_family
  source_image_project = var.source_image_project
  startup_script       = file("${path.module}/startup.sh")
  source_image         = var.source_image
  tags = [
    "flask-runner-vm", "allow-http","http-server","https-server"
  ]
}

# Runner MIG

module "mig" {
  source             = "terraform-google-modules/vm/google//modules/mig"
  version            = "~> 7.9.0"
  project_id         = var.project_id
  subnetwork_project = var.project_id
  hostname           = var.instance_name
  region             = var.region
  instance_template  = module.mig_template.self_link
  target_size        = var.target_size
  named_ports = [
    {
      name = "http",
      port = 80
    }
  ]
  network            = var.network_name
  subnetwork         = google_compute_subnetwork.flask-subnetwork-private.id

  /* autoscaler */
  autoscaling_enabled = true
  cooldown_period     = var.cooldown_period
}

# instance template

resource "google_compute_instance" "vm_test" {
  project      = var.project_id
  name         = "${var.prefix}-public-vm"
  zone         = var.zone
  machine_type = "e2-micro"
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }
  tags         = ["allow-http","http-server","https-server"]

  network_interface {
    network    = google_compute_network.flask-network.id
    subnetwork = google_compute_subnetwork.flask-subnetwork-public.id
    access_config {}
  }

  # install nginx and serve a simple web page
  lifecycle {
    create_before_destroy = true
  }
}

/*
module "firewall_rules" {
  source       = "terraform-google-modules/network/google//modules/firewall-rules"
  project_id   = var.project_id
  network_name = var.network_name

  rules = [{
    name                    = "allow-health-check"
    description             = null
    direction               = "INGRESS"
    priority                = null
    ranges                  = ["130.211.0.0/22","35.191.0.0/16","0.0.0.0/0"]
    source_tags             = null
    source_service_accounts = null
    target_tags             = null
    target_service_accounts = null
    allow = [{
      protocol = "tcp"
      ports    = ["80"]
    }]
    deny = []
    log_config = {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }]
}*/

# Add Load Balancer

module "gce-lb-http" {
  source  = "GoogleCloudPlatform/lb-http/google"
  version = "~> 4.4"
  name    = var.prefix
  project = var.project_id
  target_tags = [
    google_compute_router.default.name,
    google_compute_subnetwork.flask-subnetwork-private.name
  ]
  firewall_networks = [google_compute_network.flask-network.name]

  backends = {
    default = {

      description                     = null
      protocol                        = "HTTP"
      load_balancing_scheme           = "INTERNAL_MANAGED"
      port                            = 80
      port_name                       = "http"
      timeout_sec                     = 10
      connection_draining_timeout_sec = null
      enable_cdn                      = false
      security_policy                 = null
      session_affinity                = null
      affinity_cookie_ttl_sec         = null
      custom_request_headers          = null
      custom_response_headers         = null

      health_check = {
        check_interval_sec  = 10
        timeout_sec         = null
        healthy_threshold   = null
        unhealthy_threshold = 3
        request_path        = "/"
        port                = 80
        host                = null
        logging             = null
      }

      log_config = {
        enable      = true
        sample_rate = 1.0
      }

      groups = [
        {
          group                        = module.mig.instance_group
          balancing_mode               = null
          capacity_scaler              = null
          description                  = null
          max_connections              = null
          max_connections_per_instance = null
          max_connections_per_endpoint = null
          max_rate                     = null
          max_rate_per_instance        = null
          max_rate_per_endpoint        = null
          max_utilization              = null
        },
      ]

      iap_config = {
        enable               = false
        oauth2_client_id     = null
        oauth2_client_secret = null
      }
    }
  }
}