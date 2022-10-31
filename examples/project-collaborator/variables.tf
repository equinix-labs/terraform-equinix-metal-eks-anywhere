variable "organization_id" {
  type        = string
  description = "Equinix Metal organization id"
}

variable "collaborator" {
  type        = string
  description = "Collaborator email to join the organization"
}

variable "send_invites" {
  type        = bool
  description = "Wether Collaborator invitations should be sent. This could be toggled after a successful provision to prevent sending invitations to a project that could be deleted during a reprovision"
  default     = true
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

variable "permit_root_ssh_password" {
  description = "Enable root SSH logins via password. This is intended for lab environments."
  default     = false
  type        = bool
}
