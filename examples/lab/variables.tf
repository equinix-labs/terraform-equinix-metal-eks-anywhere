
variable "metal_api_token" {
  description = "Equinix Metal user api token."
  type        = string
  sensitive   = true
}

variable "organization_id" {
  type        = string
  description = "Equinix Metal organization id"
}

variable "permit_root_ssh_password" {
  description = "Enable root SSH logins via password. This is intended for lab environments."
  default     = true
  type        = bool
}

variable "send_invites" {
  type        = bool
  description = "Wether Collaborator invitations should be sent. This could be toggled after a successful provision to prevent sending invitations to a project that could be deleted during a reprovision"
  default     = true
}

