provider "aws" {
  region = "us-west-1"
}

# Configure the Equinix Provider.
provider "equinix" {
  auth_token = var.metal_api_token
  client_id  = var.fabric_client_id
  client_secret = var.fabric_client_secret
}

resource "local_file" "tinkerbelltemplateconfig" {
  content = templatefile("${path.module}/basetinkerbelltemplateconfig.tftpl", {
    RDS_SUBNET1 = "10.0.1.0/25",
    RDS_SUBNET2 = "10.0.1.128/25",
    GW_BIRD_ROUTER_IP = cidrhost(var.aws_dx_vif_customer_address, 2)
  })
  filename        = pathexpand("${path.module}/tinkerbelltemplateconfig.tftpl")
  file_permission = "0600"
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
  worker_device_type      = var.worker_device_type
  worker_device_count     = var.worker_device_count
  tags                    = var.tags
  eksa_version            = var.eksa_version
  bottlerocket_image_url  = var.bottlerocket_image_url
  tinkerbell_images       = var.tinkerbell_images
  tinkerbelltemplateconfig = local_file.tinkerbelltemplateconfig.filename
}