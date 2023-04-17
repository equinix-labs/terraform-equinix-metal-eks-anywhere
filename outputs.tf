output "eksa_admin_id" {
  value = equinix_metal_device.eksa_admin.id
}

output "eksa_admin_ip" {
  value = equinix_metal_device.eksa_admin.network[0].address
}

output "eksa_admin_ssh_user" {
  value = "root"
}

output "eksa_admin_ssh_key" {
  value = local_file.ssh_private_key.filename
}

output "eksa_public_ips_cidr" {
  value = local.pool_nw_cidr
}
output "eksa_pool_admin" {
  value = local.pool_admin
}


output "eksa_public_ips_gateway" {
  value = equinix_metal_reserved_ip_block.public_ips.gateway
}

output "eksa_public_ips_netmask" {
  value = equinix_metal_reserved_ip_block.public_ips.netmask
}

output "eksa_vlan_id" {
  description = "UUID of the Equinix Metal VLAN"
  value       = equinix_metal_vlan.provisioning_vlan.id
}

output "eksa_vlan_vnid" {
  description = "VNID of the Equinix Metal VLAN"
  value       = equinix_metal_vlan.provisioning_vlan.vxlan
}

# Out-of-band console ( Serial Over SSH - https://metal.equinix.com/developers/docs/resilience-recovery/serial-over-ssh/)
output "eksa_nodes_sos" {
  value = zipmap(
    concat(equinix_metal_device.eksa_node_cp[*].hostname, equinix_metal_device.eksa_node_worker[*].hostname),
    formatlist("%s@sos.%s.platformequinix.com", concat(equinix_metal_device.eksa_node_cp[*].id, equinix_metal_device.eksa_node_worker[*].id), concat(equinix_metal_device.eksa_node_cp[*].deployed_facility, equinix_metal_device.eksa_node_worker[*].deployed_facility))
  )
}
