output "metal_project" {
  value = equinix_metal_project.project.id
}

output "metal_project_api_key" {
  value     = equinix_metal_project_api_key.project_key.token
  sensitive = true
}

output "eksa_addon_ip" {
  value = equinix_metal_device.addon_eksa_node_dp.access_public_ipv4
}

output "eksa_addon_ports" {
  value = equinix_metal_device.addon_eksa_node_dp.ports
}

output "eksa_admin_ip" {
  value = module.eksa.eksa_admin_ip
}

output "eksa_admin_ssh_user" {
  value = module.eksa.eksa_admin_ssh_user
}

output "eksa_admin_ssh_key" {
  value = module.eksa.eksa_admin_ssh_key
}

output "eksa_public_ips_cidr" {
  value = module.eksa.eksa_public_ips_cidr
}

output "eksa_pool_admin" {
  value = module.eksa.eksa_pool_admin
}

output "eksa_public_ips_gateway" {
  value = module.eksa.eksa_public_ips_gateway
}

output "eksa_public_ips_netmask" {
  value = module.eksa.eksa_public_ips_netmask
}

output "eksa_vlan_id" {
  description = "UUID of the Equinix Metal VLAN"
  value       = module.eksa.eksa_vlan_id
}

# Out-of-band console ( Serial Over SSH - https://metal.equinix.com/developers/docs/resilience-recovery/serial-over-ssh/)
output "eksa_nodes_sos" {
  value = module.eksa.eksa_nodes_sos
}
