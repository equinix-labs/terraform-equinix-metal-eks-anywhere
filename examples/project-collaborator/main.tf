terraform {
  required_version = ">= 1.3"

  required_providers {
    equinix = {
      source  = "equinix/equinix"
      version = ">= 1.10.0"
    }
  }
}

resource "equinix_metal_project" "project" {
  name = replace(var.collaborator, "@", "-")
}

resource "equinix_metal_project_api_key" "project_key" {
  project_id  = equinix_metal_project.project.id
  description = "API token used to stand up individual user's clusters. Has limited permissions versus your user token."
  read_only   = false
}

resource "equinix_metal_organization_member" "user" {
  count           = var.send_invites ? 1 : 0
  organization_id = var.organization_id

  roles = ["limited_collaborator"] #required

  # message = "Please join my Equinix Metal organization to participate on the EKS Anywhere Hands-on lab"

  # project_ids is included in the invitation, but is also returned in the organization membership response
  projects_ids = [equinix_metal_project.project.id] # only used/needed for 'collaborators'

  # user is returned but we don't need to include all of that in this resource
  # presenting user.email as user_email fits our TF pattern in other resources.
  # user_email would act as the "invitee" in the invitation field.
  # Does this create a problem if the invitee email differs from the primary user email?
  invitee = var.collaborator # required
}

module "eksa" {
  # source = "equinix/metal-eks-anywhere/equinix"
  source = "../../"

  metal_api_token          = equinix_metal_project_api_key.project_key.token
  project_id               = equinix_metal_project.project.id
  cluster_name             = var.cluster_name
  metro                    = var.metro
  provisioner_device_type  = var.provisioner_device_type
  cp_device_type           = var.cp_device_type
  dp_device_type           = var.dp_device_type
  permit_root_ssh_password = var.permit_root_ssh_password
}

resource "equinix_metal_device" "addon_eksa_node_dp" {
  hostname         = "eksa-addon-node-dp"
  plan             = var.dp_device_type
  metro            = var.metro
  operating_system = "custom_ipxe"
  ipxe_script_url  = "http://${module.eksa.eksa_pool_admin}/ipxe/"
  always_pxe       = "false"
  billing_cycle    = "hourly"
  project_id       = equinix_metal_project.project.id
  tags             = ["tink-worker", "data-plane", "addon"]
}

# Convert eksa nodes to Layer2-Unbonded (Layer2-Bonded would require custom Tinkerbell workflow steps to define the LACP bond for the correct interface names)
resource "equinix_metal_port" "addon_dp_bond0" {
  port_id = [for p in equinix_metal_device.addon_eksa_node_dp.ports : p.id if p.name == "bond0"][0]
  layer2  = true
  bonded  = false
}

resource "equinix_metal_port" "addon_dp_eth0" {
  depends_on = [equinix_metal_port.addon_dp_bond0]
  port_id    = [for p in equinix_metal_device.addon_eksa_node_dp.ports : p.id if p.name == "eth0"][0]
  bonded     = false
  vlan_ids   = [module.eksa.eksa_vlan_id]
}

resource "null_resource" "readme" {
  depends_on = [
    equinix_metal_port.addon_dp_bond0,
    module.eksa
  ]

  connection {
    type        = "ssh"
    user        = module.eksa.eksa_admin_ssh_user
    host        = module.eksa.eksa_admin_ip
    private_key = file(module.eksa.eksa_admin_ssh_key)
  }

  provisioner "file" {
    content = templatefile("${path.module}/README.md.tftpl", {
      node    = equinix_metal_device.addon_eksa_node_dp
      ip      = cidrhost(module.eksa.eksa_public_ips_cidr, 5)
      gateway = module.eksa.eksa_public_ips_gateway
      netmask = module.eksa.eksa_public_ips_netmask
    })
    destination = "/root/README.md"
  }
}
