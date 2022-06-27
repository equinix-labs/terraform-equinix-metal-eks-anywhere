variable "metal_api_token" {
  description = "Equinix Metal user api token"
  type        = string
  default     = null
}

variable "project_id" {
  description = "Project ID"
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

variable provisioner_device_type {
  description = "Equinix Metal device type to deploy an admin machine with internet access to configure and manage the eks-anywhere infrastructure stack"
  default     = "c3.small.x86"
}

variable cp_device_type {
  description = "Equinix Metal device type to deploy control plane nodes"
  default     = "c3.small.x86"
}

variable cp_device_count {
  type        = number
  description = "Number of baremetal control plane nodes. Set 3 or 5 for a highly available control plane"
  default     = 1
}

variable dp_device_type {
  description = "Equinix Metal device type to deploy for data plane (worker) nodes"
  default     = "c3.small.x86"
}

variable dp_device_count {
  type        = number
  description = "Number of baremetal data plane (worker) nodes"
  default     = 1
}

variable "tags" {
  type        = list
  description = "String list of common tags for Equinix resources"
  default     = ["eksa", "terraform"]
}
