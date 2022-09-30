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

locals {
  users = csvdecode(file("users.csv"))
}

data "equinix_metal_organization" "org" {
  organization_id = var.organization_id
}

module "lab" {
  for_each                = { for user in local.users : user.email => user }
  source                  = "../project-collaborator"
  organization_id         = data.equinix_metal_organization.org.id
  collaborator            = each.value.email
  metal_api_token         = var.metal_api_token
  metro                   = each.value.metro
  provisioner_device_type = each.value.plan
  cp_device_type          = each.value.plan
  dp_device_type          = each.value.plan
}
