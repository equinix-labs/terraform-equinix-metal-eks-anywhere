locals {
  ssh_key_name = "eksa-cluster-key"
  pool_nw_cidr = equinix_metal_reserved_ip_block.public_ips.cidr_notation
  pool_gw      = equinix_metal_reserved_ip_block.public_ips.gateway
  pool_nm      = equinix_metal_reserved_ip_block.public_ips.netmask
  pool_admin   = cidrhost(local.pool_nw_cidr, 2)                                                       // will be assigned to eksa-admin within the VLAN. First available IP after gateway
  pool_vip     = cidrhost(local.pool_nw_cidr, equinix_metal_reserved_ip_block.public_ips.quantity - 2) // floating IPv4 public address assigned to the current lead kubernetes control plane. Using last available IPs
  tink_vip     = cidrhost(local.pool_nw_cidr, equinix_metal_reserved_ip_block.public_ips.quantity - 3)

  eksa_nodes_cp_hw_info = [for idx, node in equinix_metal_device.eksa_node_cp : {
    id          = node.id
    hostname    = node.hostname
    vendor      = "Equinix"
    mac         = [for port in node.ports : port.mac if port.name == "eth0"][0] // TODO replace with node.ports[0].mac once this pr is merged https://github.com/equinix/terraform-provider-equinix/pull/206
    ip_address  = cidrhost(local.pool_nw_cidr, idx + 3)
    gateway     = local.pool_gw
    netmask     = local.pool_nm
    nameservers = "8.8.8.8" //TODO metal namerservers ??
    disk        = "/dev/sda"
    type        = "type=cp" //One of: type=cp (control plane), type=dp (data plane / worker)
  }]

  eksa_nodes_dp_hw_info = [for idx, node in equinix_metal_device.eksa_node_dp : {
    id          = node.id
    hostname    = node.hostname
    vendor      = "Equinix"
    mac         = [for port in node.ports : port.mac if port.name == "eth0"][0] // TODO replace with node.ports[0].mac once this pr is merged https://github.com/equinix/terraform-provider-equinix/pull/206
    ip_address  = cidrhost(local.pool_nw_cidr, length(equinix_metal_device.eksa_node_dp) + idx + 3)
    gateway     = local.pool_gw
    netmask     = local.pool_nm
    nameservers = "8.8.8.8"
    disk        = "/dev/sda"
    type        = "type=dp"
  }]

  eks_nodes_hw_info_str = [for n in concat(local.eksa_nodes_cp_hw_info, local.eksa_nodes_dp_hw_info) :
    "${n.hostname},${n.vendor},${n.mac},${n.ip_address},${n.gateway},${n.netmask},${n.nameservers},${n.disk},${n.type}"
  ]
}
