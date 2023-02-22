variable "project_id" {
  type        = string
  description = "Billing account to associate with the project being created."
  default = "concise-honor-368108"
}

variable "services" {
  type = list(string)
  description = "List of services to enable for project"
  default = [
    "compute.googleapis.com",
    "appengine.googleapis.com",
    "appengineflex.googleapis.com",
    "cloudbuild.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com"
  ]
}

variable "region" {
  type        = string
  description = "Default region to use for the project"
  default     = "us-east1"
}

variable "zone" {
  type        = string
  description = "Default zone to use for MIG runner deployment"
  default     = "us-east1-b"
}

variable "prefix" {
  type        = string
  description = "Prefix for naming the project and other resources"
  default     = "flask"
}

variable "network_name" {
  type        = string
  description = "Name for the VPC network"
  default     = "flask-network"
}

variable "subnet_ip" {
  type        = string
  description = "IP range for the subnet"
  default     = "10.0.0.0/24"
}
variable "subnet_name" {
  type        = string
  description = "Name for the subnet"
  default     = "flask-subnet"
}

variable "instance_name" {
  type        = string
  description = "The gce instance name"
  default     = "flask"
}

variable "target_size" {
  type        = number
  description = "The number of runner instances"
  default     = 1
}

variable "machine_type" {
  type        = string
  description = "The GCP machine type to deploy"
  default     = "e2-micro"
}

variable "source_image_family" {
  type        = string
  description = "Source image family. If neither source_image nor source_image_family is specified, defaults to the latest public Ubuntu image."
  default     = "ubuntu-minimal-1804-lts"
}

variable "source_image_project" {
  type        = string
  description = "Project where the source image comes from"
  default     = "ubuntu-os-cloud"
}

variable "source_image" {
  type        = string
  description = "Source disk image. If neither source_image nor source_image_family is specified, defaults to the latest public CentOS image."
  default     = ""
}

variable "cooldown_period" {
  description = "The number of seconds that the autoscaler should wait before it starts collecting information from a new instance."
  default     = 60
}

# Random id for naming
resource "random_id" "id" {
  byte_length = 4
  prefix      = var.prefix
}

locals {
  gcp_service_account_name = "${var.prefix}-flask-app"
}