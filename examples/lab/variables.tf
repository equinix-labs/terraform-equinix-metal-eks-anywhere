
variable "metal_api_token" {
  description = "Equinix Metal user api token"
  type        = string
  sensitive   = true
}

variable "organization_id" {
  type        = string
  description = "Equinix Metal organization id"
}