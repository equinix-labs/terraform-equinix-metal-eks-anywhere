
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

variable "csv_file" {
  type        = string
  description = "Path to a CSV file containing a list of projects to provision: email,metro,plan. Email address is used as the project name and the collaborator. Metro and plan are used to provision the project."
  default     = "users.csv"
}