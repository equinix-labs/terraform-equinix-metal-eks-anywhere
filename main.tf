
# Create a new VLAN in specified datacenter
resource "equinix_metal_vlan" "provisioning_vlan" {
  description = "provisioning_vlan"
  metro       = var.metro
  project_id  = var.project_id
}

# Create a Public IP Reservation (16 addresses)
resource "equinix_metal_reserved_ip_block" "public_ips" {
  project_id = var.project_id
  type       = "public_ipv4"
  metro      = var.metro
  quantity   = 16
  tags       = concat(var.tags, ["eksa-${random_string.resource_suffix.result}"])
}

# Create a Metal Gateway
resource "equinix_metal_gateway" "gw" {
  project_id        = var.project_id
  vlan_id           = equinix_metal_vlan.provisioning_vlan.id
  ip_reservation_id = equinix_metal_reserved_ip_block.public_ips.id
}

#########################
## control-plane nodes ##
#########################

# Create eksa-node/tinkerbell-worker devices for k8s control-plane
# Note that the ipxe-script-url doesn't actually get used in this process, we're just setting it
# as it's a requirement for using the custom_ipxe operating system type.
resource "equinix_metal_device" "eksa_node_cp" {
  count = var.cp_device_count

  hostname         = format("eksa-${random_string.resource_suffix.result}-node-cp-%03d", count.index + 1)
  plan             = var.cp_device_type
  metro            = var.metro
  operating_system = "custom_ipxe"
  ipxe_script_url  = "http://${local.pool_admin}/ipxe/"
  always_pxe       = "false"
  billing_cycle    = "hourly"
  project_id       = var.project_id
  tags             = concat(var.tags, ["tink-worker", "control-plane", "eksa-${random_string.resource_suffix.result}"])
}

# Convert eksa nodes to Layer2-Unbonded (Layer2-Bonded would require custom Tinkerbell workflow steps to define the LACP bond for the correct interface names)
resource "equinix_metal_port" "cp_bond0" {
  count = var.cp_device_count

  port_id = [for p in equinix_metal_device.eksa_node_cp[count.index].ports : p.id if p.name == "bond0"][0]
  layer2  = true
  bonded  = false
}

resource "equinix_metal_port" "cp_eth0" {
  count = var.cp_device_count

  depends_on = [equinix_metal_port.cp_bond0]
  port_id    = [for p in equinix_metal_device.eksa_node_cp[count.index].ports : p.id if p.name == "eth0"][0]
  bonded     = false
  vlan_ids   = [equinix_metal_vlan.provisioning_vlan.id]
}

######################
## data-plane nodes ##
######################

# Create eksa-node/tinkerbell-worker devices for k8s data-plane
# Note that the ipxe-script-url doesn't actually get used in this process, we're just setting it
# as it's a requirement for using the custom_ipxe operating system type.
resource "equinix_metal_device" "eksa_node_dp" {
  count = var.dp_device_count

  hostname         = format("eksa-${random_string.resource_suffix.result}-node-dp-%03d", count.index + 1)
  plan             = var.dp_device_type
  metro            = var.metro
  operating_system = "custom_ipxe"
  ipxe_script_url  = "http://${local.pool_admin}/ipxe/"
  always_pxe       = "false"
  billing_cycle    = "hourly"
  project_id       = var.project_id
  tags             = concat(var.tags, ["tink-worker", "data-plane", "eksa-${random_string.resource_suffix.result}"])
}

# Convert eksa nodes to Layer2-Unbonded (Layer2-Bonded would require custom Tinkerbell workflow steps to define the LACP bond for the correct interface names)
resource "equinix_metal_port" "dp_bond0" {
  count = var.dp_device_count

  port_id = [for p in equinix_metal_device.eksa_node_dp[count.index].ports : p.id if p.name == "bond0"][0]
  layer2  = true
  bonded  = false
}

resource "equinix_metal_port" "dp_eth0" {
  count = var.dp_device_count

  depends_on = [equinix_metal_port.dp_bond0]
  port_id    = [for p in equinix_metal_device.eksa_node_dp[count.index].ports : p.id if p.name == "eth0"][0]
  bonded     = false
  vlan_ids   = [equinix_metal_vlan.provisioning_vlan.id]
}

######################
## admin/ops device ##
######################

# Generate ssh_key_pair for eksa-admin and nodes
resource "tls_private_key" "ssh_key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Generate random suffix to build ssh key name
resource "random_string" "ssh_key_suffix" {
  length  = 3
  special = false
  upper   = false
}

# Generate random suffix for resource names
resource "random_string" "resource_suffix" {
  length  = 6
  special = false
  upper   = false
}

# Upload ssh_pub_key to Equinix Metal
resource "equinix_metal_ssh_key" "ssh_pub_key" {
  name       = local.ssh_key_name
  public_key = chomp(tls_private_key.ssh_key_pair.public_key_openssh)
}

# Store ssh_pub_key locally
resource "local_file" "ssh_private_key" {
  content         = chomp(tls_private_key.ssh_key_pair.private_key_pem)
  filename        = pathexpand(format("~/.ssh/%s", local.ssh_key_name))
  file_permission = "0600"
}

# Create an eksa-admin/tink-provisioner device
resource "equinix_metal_device" "eksa_admin" {
  hostname         = "eksa-${random_string.resource_suffix.result}-admin"
  plan             = var.provisioner_device_type
  metro            = var.metro
  operating_system = "ubuntu_20_04"
  billing_cycle    = "hourly"
  project_id       = var.project_id
  tags             = concat(var.tags, ["tink-provisioner", "eksa-${random_string.resource_suffix.result}"])

  user_data = templatefile("${path.module}/setup.cloud-init.tftpl", {
    ADMIN_IP                    = local.pool_admin
    EKSA_VERSION_RELEASE        = var.eksa_version.release
    EKSA_VERSION_RELEASE_NUMBER = var.eksa_version.release_number
    NETMASK                     = equinix_metal_reserved_ip_block.public_ips.netmask
    VLAN_VNID                   = equinix_metal_vlan.provisioning_vlan.vxlan
  })

  depends_on = [equinix_metal_ssh_key.ssh_pub_key]
}

resource "equinix_metal_port" "eksa_admin_bond0" {
  port_id  = [for p in equinix_metal_device.eksa_admin.ports : p.id if p.name == "bond0"][0]
  layer2   = false
  bonded   = true
  vlan_ids = [equinix_metal_vlan.provisioning_vlan.id]
}

################################
## Steps to run on eksa-admin ##
################################

resource "null_resource" "wait_for_cloud_init" {
  depends_on = [
    equinix_metal_port.eksa_admin_bond0,
    equinix_metal_port.dp_bond0,
    equinix_metal_port.cp_bond0,
  ]
  connection {
    type        = "ssh"
    user        = "root"
    host        = equinix_metal_device.eksa_admin.network[0].address
    private_key = chomp(tls_private_key.ssh_key_pair.private_key_pem)
  }
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
  }
}

resource "null_resource" "create_cluster" {
  triggers = {
    ids = join(",", local.node_ids)
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = equinix_metal_device.eksa_admin.network[0].address
    private_key = chomp(tls_private_key.ssh_key_pair.private_key_pem)
    timeout     = var.create_cluster_timeout
  }

  provisioner "file" {
    source      = "${path.module}/reboot_nodes.sh"
    destination = "/root/reboot_nodes.sh"
  }

  provisioner "file" {
    content = templatefile("${path.module}/hardware.csv.tftpl", {
      nodes_cp = equinix_metal_device.eksa_node_cp
      nodes_dp = equinix_metal_device.eksa_node_dp
      nw_cidr  = local.pool_nw_cidr
      gateway  = equinix_metal_reserved_ip_block.public_ips.gateway
      netmask  = equinix_metal_reserved_ip_block.public_ips.netmask
    })
    destination = "/root/hardware.csv"
  }

  provisioner "file" {
    content     = chomp(tls_private_key.ssh_key_pair.private_key_pem)
    destination = "/root/.ssh/${local.ssh_key_name}"
  }

  provisioner "file" {
    content     = chomp(tls_private_key.ssh_key_pair.public_key_openssh)
    destination = "/root/.ssh/${local.ssh_key_name}.pub"
  }

  provisioner "file" {
    destination = "/root/setup-clusterconfig.sh"
    content = templatefile("${path.module}/setup.clusterconfig.tftpl", {
      tink_vip                 = local.tink_vip,
      cluster_name             = var.cluster_name,
      pool_vip                 = local.pool_vip,
      ssh_key_name             = local.ssh_key_name,
      cp_template              = replace("cp-${var.cluster_name}-${var.cp_device_type}", ".", "-"),
      dp_template              = replace("dp-${var.cluster_name}-${var.dp_device_type}", ".", "-"),
      cp_device_count          = var.cp_device_count,
      dp_device_count          = var.dp_device_count,
      node_device_os           = var.node_device_os,
      pool_admin               = local.pool_admin,
      api_token                = var.metal_api_token,
      permit_root_ssh_password = var.permit_root_ssh_password
      nodes_id = zipmap(
        local.node_ids,
        formatlist("%s@sos.%s.platformequinix.com",
          local.node_ids,
          concat(equinix_metal_device.eksa_node_cp[*].deployed_facility, equinix_metal_device.eksa_node_dp[*].deployed_facility)
        )
      )
    })
  }

  provisioner "file" {
    destination = "/root/cp-tinkerbelltemplateconfig.yaml"
    content = templatefile("${path.module}/tinkerbelltemplateconfig.tftpl", {
      POOL_ADMIN                  = local.pool_admin,
      TINK_VIP                    = local.tink_vip,
      BOTTLEROCKET_IMAGE_URL      = var.bottlerocket_image_url,
      TEMPLATE_NAME               = replace("cp-${var.cluster_name}-${var.cp_device_type}", ".", "-"),
      TINKERBELL_IMAGE_IMAGE2DISK = var.tinkerbell_images.image2disk,
      TINKERBELL_IMAGES_WRITEFILE = var.tinkerbell_images.writefile,
      TINKERBELL_IMAGES_REBOOT    = var.tinkerbell_images.reboot
    })
  }

  provisioner "file" {
    destination = "/root/dp-tinkerbelltemplateconfig.yaml"
    content = templatefile("${path.module}/tinkerbelltemplateconfig.tftpl", {
      POOL_ADMIN                  = local.pool_admin,
      TINK_VIP                    = local.tink_vip,
      BOTTLEROCKET_IMAGE_URL      = var.bottlerocket_image_url,
      TEMPLATE_NAME               = replace("dp-${var.cluster_name}-${var.dp_device_type}", ".", "-"),
      TINKERBELL_IMAGE_IMAGE2DISK = var.tinkerbell_images.image2disk,
      TINKERBELL_IMAGES_WRITEFILE = var.tinkerbell_images.writefile,
      TINKERBELL_IMAGES_REBOOT    = var.tinkerbell_images.reboot
    })
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /root/setup-clusterconfig.sh",
      "/root/setup-clusterconfig.sh"
    ]
  }

  depends_on = [
    null_resource.wait_for_cloud_init,
  ]
}
