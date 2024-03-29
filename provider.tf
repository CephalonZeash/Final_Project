terraform {
 required_providers {
  proxmox = {
    source  = "telmate/proxmox"
    version = "2.9.11"
  }

  null = {
    source  = "hashicorp/null"
    version = "3.2.1"
  }
 }
}

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = true
}