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
  users = csvdecode(file(var.csv_file))
}

data "equinix_metal_organization" "org" {
  organization_id = var.organization_id
}

module "lab" {
  for_each                 = { for user in local.users : trimspace(user.email) => user }
  source                   = "../project-collaborator"
  organization_id          = data.equinix_metal_organization.org.id
  collaborator             = each.value.email
  metal_api_token          = var.metal_api_token
  metro                    = trimspace(each.value.metro)
  provisioner_device_type  = trimspace(each.value.plan)
  cp_device_type           = trimspace(each.value.plan)
  dp_device_type           = trimspace(each.value.plan)
  permit_root_ssh_password = var.permit_root_ssh_password
  send_invites             = var.send_invites
}
