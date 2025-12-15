# Tell Terraform to include the hcloud provider
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.49.1"
    }
    autoglue = {
      source = "registry.terraform.io/GlueOps/autoglue"
      version = "0.9.2"
    }
  }
}

# Configure the Hetzner Cloud Provider with your token
provider "hcloud" {
  token = var.hcloud_token
}

provider "autoglue" {
  org_id = "dd3d6db4-8a9b-473f-a416-04fd3fcd9dc2"
  base_url = "https://autoglue.glueopshosted.com/api/v1"
  org_key = var.autoglue_key
  org_secret = var.autoglue_org_secret
}

provider "aws" {
  region  = "us-west-2"
}
