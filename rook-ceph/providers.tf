terraform {
  required_version = "~> 0.14.10"

  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.11.0"
    }
    helm = {
      version = "~> 2.1.1"
    }
  }
}
