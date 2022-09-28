variable "organization_id" {
  type        = string
  description = "Equinix Metal organization id"
}

variable "collaborator" {
  type        = string
  description = "Collaborator email to join the organization"
}

variable "metal_api_token" {
  description = "Equinix Metal user api token"
  type        = string
}

variable "cluster_name" {
  type        = string
  description = "Cluster name"
  default     = "my-eksa-cluster"
}

variable "metro" {
  description = "Equinix metro to provision in"
  type        = string
  default     = "sv"
}

variable "provisioner_device_type" {
  description = "Equinix Metal device type to deploy an admin machine with internet access to configure and manage the eks-anywhere infrastructure stack"
  default     = "m3.small.x86"
}

variable "cp_device_type" {
  description = "Equinix Metal device type to deploy control plane nodes"
  default     = "m3.small.x86"
}

variable "dp_device_type" {
  description = "Equinix Metal device type to deploy for data plane (worker) nodes"
  default     = "m3.small.x86"
}

variable "dp_device_count" {
  type        = number
  description = "Number of baremetal data plane (worker) nodes"
  default     = 1
}
