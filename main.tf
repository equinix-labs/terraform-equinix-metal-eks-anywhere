# Configure the Equinix Provider.
provider "equinix" {
  auth_token = var.metal_api_token
}

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
  tags       = var.tags
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

  hostname         = format("eksa-node-cp-%03d", count.index + 1)
  plan             = var.cp_device_type
  metro            = var.metro
  operating_system = "custom_ipxe"
  ipxe_script_url  = "http://${local.pool_admin}/ipxe/"
  always_pxe       = "true"
  billing_cycle    = "hourly"
  project_id       = var.project_id
  tags             = concat(var.tags, ["tink-worker", "control-plane"])
}

# Convert eksa nodes to Layer2-Unbonded (Layer2-Bonded would require custom Tinkerbell workflow steps to define the LACP bond for the correct interface names)
resource "equinix_metal_device_network_type" "eksa_node_cp_network_type" {
  count = var.cp_device_count

  device_id = equinix_metal_device.eksa_node_cp[count.index].id
  type      = "layer2-individual"
}

# Attach VLAN to eksa nodes
resource "equinix_metal_port_vlan_attachment" "eksa_node_cp_vlan_attach" {
  count = var.cp_device_count

  device_id = equinix_metal_device.eksa_node_cp[count.index].id
  port_name = "eth0"
  vlan_vnid = equinix_metal_vlan.provisioning_vlan.vxlan

  depends_on = [equinix_metal_device_network_type.eksa_node_cp_network_type]
}

######################
## data-plane nodes ##
######################

# Create eksa-node/tinkerbell-worker devices for k8s data-plane
# Note that the ipxe-script-url doesn't actually get used in this process, we're just setting it
# as it's a requirement for using the custom_ipxe operating system type.
resource "equinix_metal_device" "eksa_node_dp" {
  count = var.dp_device_count

  hostname         = format("eksa-node-dp-%03d", count.index + 1)
  plan             = var.dp_device_type
  metro            = var.metro
  operating_system = "custom_ipxe"
  ipxe_script_url  = "http://${local.pool_admin}/ipxe/"
  always_pxe       = "true"
  billing_cycle    = "hourly"
  project_id       = var.project_id
  tags             = concat(var.tags, ["tink-worker", "data-plane"])
}

# Convert eksa nodes to Layer2-Unbonded (Layer2-Bonded would require custom Tinkerbell workflow steps to define the LACP bond for the correct interface names)
resource "equinix_metal_device_network_type" "eksa_node_dp_network_type" {
  count = var.dp_device_count

  device_id = equinix_metal_device.eksa_node_dp[count.index].id
  type      = "layer2-individual"
}

# Attach VLAN to eksa nodes
resource "equinix_metal_port_vlan_attachment" "eksa_node_dp_vlan_attach" {
  count = var.dp_device_count

  device_id = equinix_metal_device.eksa_node_dp[count.index].id
  port_name = "eth0"
  vlan_vnid = equinix_metal_vlan.provisioning_vlan.vxlan

  depends_on = [equinix_metal_device_network_type.eksa_node_dp_network_type]
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
  hostname         = "eksa-admin"
  plan             = var.provisioner_device_type
  metro            = var.metro
  operating_system = "ubuntu_20_04"
  billing_cycle    = "hourly"
  project_id       = var.project_id
  tags             = concat(var.tags, ["tink-provisioner"])

  user_data = templatefile("${path.module}/setup.cloud-init.tftpl", {
    admin_ip  = local.pool_admin
    netmask   = equinix_metal_reserved_ip_block.public_ips.netmask
    vlan_vnid = equinix_metal_vlan.provisioning_vlan.vxlan
  })

  depends_on = [equinix_metal_ssh_key.ssh_pub_key]
}

# Convert eksa nodes to hybrid-bonded to keep internet ssh access for admins and still let attach VLANs
resource "equinix_metal_device_network_type" "eksa_admin_network_type" {
  device_id = equinix_metal_device.eksa_admin.id
  type      = "hybrid"
}

# Attach VLAN to eksa-admin
resource "equinix_metal_port_vlan_attachment" "eksa_admin_vlan_attach" {
  device_id = equinix_metal_device.eksa_admin.id
  port_name = "bond0"
  vlan_vnid = equinix_metal_vlan.provisioning_vlan.vxlan

  depends_on = [equinix_metal_device_network_type.eksa_admin_network_type]
}

################################
## Steps to run on eksa-admin ##
################################

resource "null_resource" "wait_for_cloud_init" {
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
    ids = join(",", concat(equinix_metal_device.eksa_node_cp.*.id, equinix_metal_device.eksa_node_dp.*.id))
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = equinix_metal_device.eksa_admin.network[0].address
    private_key = chomp(tls_private_key.ssh_key_pair.private_key_pem)
  }

  provisioner "file" {
    content  = templatefile("${path.module}/hardware.csv.tftpl", { 
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

  provisioner "remote-exec" {
    inline = [
      "export TINKERBELL_HOST_IP=${local.tink_vip}",
      "export CLUSTER_NAME=${var.cluster_name}",
      "export TINKERBELL_PROVIDER=true",
      "export CONTROL_PLANE_VIP=${local.pool_vip}",
      "export CLUSTER_CONFIG_FILE=$CLUSTER_NAME.yaml",
      "export PUB_SSH_KEY=\"$(cat /root/.ssh/${local.ssh_key_name}.pub)\"",
      "eksctl-anywhere generate clusterconfig $CLUSTER_NAME --provider tinkerbell > $CLUSTER_CONFIG_FILE",
      "cp $CLUSTER_CONFIG_FILE $CLUSTER_CONFIG_FILE.orig",
      "yq e -i \"select(.kind == \\\"Cluster\\\").spec.controlPlaneConfiguration.endpoint.host |= \\\"$CONTROL_PLANE_VIP\\\"\" $CLUSTER_CONFIG_FILE",
      "yq e -i 'select(.kind == \"Cluster\").spec.controlPlaneConfiguration.count |= ${var.cp_device_count}' $CLUSTER_CONFIG_FILE",
      "yq e -i 'select(.spec.workerNodeGroupConfigurations[].machineGroupRef.kind == \"TinkerbellMachineConfig\").spec.workerNodeGroupConfigurations[0].count |= ${var.dp_device_count}' $CLUSTER_CONFIG_FILE",
      "yq e -i \"select(.kind == \\\"TinkerbellDatacenterConfig\\\").spec.tinkerbellIP |= \\\"$TINKERBELL_HOST_IP\\\"\" $CLUSTER_CONFIG_FILE",
      "yq e -i \"select(.kind == \\\"TinkerbellMachineConfig\\\").spec.users[].sshAuthorizedKeys[0] |= \\\"$PUB_SSH_KEY\\\"\" $CLUSTER_CONFIG_FILE",
      "yq e -i 'select(.kind == \"TinkerbellMachineConfig\").spec.osFamily |= \"ubuntu\"' $CLUSTER_CONFIG_FILE",
      "yq e -i 'select(.kind == \"TinkerbellMachineConfig\").spec.hardwareSelector |= { \"type\": \"HW_TYPE\" }' $CLUSTER_CONFIG_FILE",
      "sed -i '0,/^\\([[:blank:]]*\\)type: HW_TYPE.*$/ s//\\1type: cp/' $CLUSTER_CONFIG_FILE",
      "sed -i '0,/^\\([[:blank:]]*\\)type: HW_TYPE.*$/ s//\\1type: dp/' $CLUSTER_CONFIG_FILE",
      "eksctl-anywhere create cluster --filename $CLUSTER_CONFIG_FILE --hardware-csv hardware.csv --tinkerbell-bootstrap-ip ${local.pool_admin}"
    ]
  }

  depends_on = [
    null_resource.wait_for_cloud_init,
    equinix_metal_port_vlan_attachment.eksa_admin_vlan_attach,
    equinix_metal_port_vlan_attachment.eksa_node_cp_vlan_attach,
    equinix_metal_port_vlan_attachment.eksa_node_dp_vlan_attach
  ]
}
