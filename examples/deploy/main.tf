# Configure the Equinix Provider.
provider "equinix" {
  auth_token = var.metal_api_token
}
terraform {
  required_version = ">= 1.3"

  required_providers {
    equinix = {
      source = "equinix/equinix"
    }
  }
}
module "eksa" {
  source                  = "../.."
  metal_api_token         = var.metal_api_token
  project_id              = var.project_id
  cluster_name            = var.cluster_name
  metro                   = var.metro
  provisioner_device_type = var.provisioner_device_type
  node_device_os          = var.node_device_os
  cp_device_type          = var.cp_device_type
  cp_device_count         = var.cp_device_count
  dp_device_type          = var.dp_device_type
  dp_device_count         = var.dp_device_count
  tags                    = var.tags
  eksa_version            = var.eksa_version
  bottlerocket_image_url  = var.bottlerocket_image_url
  tinkerbell_images       = var.tinkerbell_images
}

variable "metal_api_token" {
  description = "Equinix Metal user api token"
  type        = string
  sensitive   = true
}

