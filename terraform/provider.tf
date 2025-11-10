# Tell Terraform to include the hcloud provider
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.49.1"
    }
    autoglue = {
      source = "GlueOps/autoglue"
      version = "0.0.2"
    }
  }
}

# Configure the Hetzner Cloud Provider with your token
provider "hcloud" {
  token = var.hcloud_token
}

provider "autoglue" {
  addr = "https://autoglue.apps.nonprod.earth.onglueops.rocks/api/v1"
  org_key = var.autoglue_key
  org_secret = var.autoglue_org_secret
}