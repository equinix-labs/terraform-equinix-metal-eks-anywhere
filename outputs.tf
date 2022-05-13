output "provisioner_ip" {
  value = equinix_metal_device.tink_provisioner.network[0].address
}

output "worker_sos" {
  value = formatlist("%s@sos.%s.platformequinix.com", equinix_metal_device.tink_worker[*].id, equinix_metal_device.tink_worker[*].deployed_facility)
}
