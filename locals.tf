locals {
  ssh_key_name = format("%s-%s", var.cluster_name, random_string.ssh_key_suffix.result)
  pool_nw_cidr = equinix_metal_reserved_ip_block.public_ips.cidr_notation
  pool_admin   = cidrhost(local.pool_nw_cidr, 2)                                                       // will be assigned to eksa-admin within the VLAN. First available IP after gateway
  pool_vip     = cidrhost(local.pool_nw_cidr, equinix_metal_reserved_ip_block.public_ips.quantity - 2) // floating IPv4 public address assigned to the current lead kubernetes control plane. Using last available IPs
  tink_vip     = cidrhost(local.pool_nw_cidr, equinix_metal_reserved_ip_block.public_ips.quantity - 3)
  node_ids     = concat(equinix_metal_device.eksa_node_cp[*].id, equinix_metal_device.eksa_node_dp[*].id)
}
