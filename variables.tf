variable "metal_api_token" {
  description = "Equinix Metal user api token"
  type        = string
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

variable "provisioner_device_type" {
  description = "Equinix Metal device type to deploy an admin machine with internet access to configure and manage the eks-anywhere infrastructure stack"
  default     = "m3.small.x86"
}

variable "node_device_os" {
  description = <<EOT
   EKS-A supported operating system to deploy to nodes (*bottlerocket, ubuntu)

   <https://anywhere.eks.amazonaws.com/docs/reference/clusterspec/baremetal/#osfamily-required>
   EOT
  default     = "bottlerocket"
}

variable "cp_device_type" {
  description = "Equinix Metal device type to deploy control plane nodes"
  default     = "m3.small.x86"
}

variable "cp_device_count" {
  type        = number
  description = "Number of baremetal control plane nodes. Set 3 or 5 for a highly available control plane"
  default     = 1
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

variable "tags" {
  type        = list(any)
  description = "String list of common tags for Equinix resources"
  default     = ["eksa", "terraform"]
}

variable "kubernetes_version" {
  description = "Kubernetes version to deploy"
  default     = "1.25"
}

variable "eksa_version" {
  description = "EKS-A version to deploy"
  default = {
    release        = "0.14.3"
    release_number = 30
  }
  type = object({
    release        = string
    release_number = number
  })
}

variable "bottlerocket_image_url" {
  description = "URL of the Bottlerocket OS image to use"
  default     = "https://anywhere-assets.eks.amazonaws.com/releases/bundles/29/artifacts/raw/1-25/bottlerocket-v1.25.6-eks-d-1-25-7-eks-a-29-amd64.img.gz"
}

variable "tinkerbell_images" {
  description = "Tinkerbell images to use"
  default     = {} # I'm not sure if we need this. We may get the type defined defaults without it.
  type = object({
    image2disk = optional(string, "public.ecr.aws/eks-anywhere/tinkerbell/hub/image2disk:6c0f0d437bde2c836d90b000312c8b25fa1b65e1-eks-a-29")
    writefile  = optional(string, "public.ecr.aws/eks-anywhere/tinkerbell/hub/writefile:6c0f0d437bde2c836d90b000312c8b25fa1b65e1-eks-a-29")
    reboot     = optional(string, "public.ecr.aws/eks-anywhere/tinkerbell/hub/reboot:6c0f0d437bde2c836d90b000312c8b25fa1b65e1-eks-a-29")
  })
}

variable "plan_nic" {
  description = "Map of plans to expected NIC device name."
  default = {
    "m3.small.x86"  = "enp1s0f0np0"
    "c2.medium.x86" = "enp131s0f0np0"
  }
  type = map(string)
}

variable "permit_root_ssh_password" {
  description = "Enable root SSH logins via password. This is intended for lab environments."
  default     = false
  type        = bool
}

variable "create_cluster_timeout" {
  description = "Time to wait for the create_cluster phase (example: 25m)"
  default     = "25m"
}
