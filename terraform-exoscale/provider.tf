terraform {
  required_providers {
    exoscale = {
      source = "exoscale/exoscale"
      version = "0.65.1"
    }
  }
}

provider "exoscale" {
  key    = var.excoscale_key
  secret = var.excoscale_secret
}