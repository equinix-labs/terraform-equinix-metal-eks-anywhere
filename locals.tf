locals {
  ssh_key_name = "eksa-cluster-key"
  pool_nw_cidr = equinix_metal_reserved_ip_block.public_ips.cidr_notation
  pool_gw      = equinix_metal_reserved_ip_block.public_ips.gateway
  pool_nm      = equinix_metal_reserved_ip_block.public_ips.netmask
  pool_admin   = cidrhost(local.pool_nw_cidr, 2)                                                       // will be assigned to eksa-admin within the VLAN. First available IP after gateway
  pool_vip     = cidrhost(local.pool_nw_cidr, equinix_metal_reserved_ip_block.public_ips.quantity - 2) // floating IPv4 public address assigned to the current lead kubernetes control plane. Using last available IPs
  tink_vip     = cidrhost(local.pool_nw_cidr, equinix_metal_reserved_ip_block.public_ips.quantity - 3)
}
