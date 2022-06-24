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

variable "device_type" {
  type        = string
  description = "Type of device to provision"
  default     = "c3.small.x86"
}

variable "tags" {
  type        = list
  description = "String list of common tags for Equinix resources"
  default     = ["eksa", "terraform"]
}
