terraform {
  required_version = ">= 1.17"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.108"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}
