output "provisioner_ip" {
  value = equinix_metal_device.eksa_admin.network[0].address
}

output "worker_sos" {
  value = formatlist("%s@sos.%s.platformequinix.com", concat(equinix_metal_device.eksa_node_cp[*].id, equinix_metal_device.eksa_node_dp[*].id), concat(equinix_metal_device.eksa_node_cp[*].deployed_facility, equinix_metal_device.eksa_node_dp[*].deployed_facility))
}
