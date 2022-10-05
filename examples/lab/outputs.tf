output "metal_project" {
  value = module.lab.metal_project
}

output "metal_project_api_key" {
  value     = module.lab.metal_project_api_key
  sensitive = true
}

output "eksa_addon_ip" {
  value = module.lab.eksa_addon_ip
}

output "eksa_addon_ports" {
  value = module.lab.eksa_addon_ports
}

output "eksa_admin_ip" {
  value = module.lab.eksa_admin_ip
}

output "eksa_admin_ssh_user" {
  value = module.lab.eksa_admin_ssh_user
}

output "eksa_admin_ssh_key" {
  value = module.lab.eksa_admin_ssh_key
}

output "eksa_public_ips_cidr" {
  value = module.lab.eksa_public_ips_cidr
}

output "eksa_pool_admin" {
  value = module.lab.eksa_pool_admin
}

output "eksa_public_ips_gateway" {
  value = module.lab.eksa_public_ips_gateway
}

output "eksa_public_ips_netmask" {
  value = module.lab.eksa_public_ips_netmask
}

output "eksa_vlan_id" {
  description = "UUID of the Equinix Metal VLAN"
  value       = module.lab.eksa_vlan_id
}

# Out-of-band console ( Serial Over SSH - https://metal.equinix.com/developers/docs/resilience-recovery/serial-over-ssh/)
output "eksa_nodes_sos" {
  value = module.lab.eksa_nodes_sos
}
