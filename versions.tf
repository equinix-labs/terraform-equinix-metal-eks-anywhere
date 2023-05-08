terraform {
  required_version = ">= 1.3"
  provider_meta "equinix" {
    module_name = "equinix-metal-eks-anywhere"
  }
  required_providers {
    equinix = {
      source  = "equinix/equinix"
      version = ">= 1.11.0"
    }
  }
}
