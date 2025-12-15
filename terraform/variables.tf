# Declare the hcloud_token variable from .tfvars
variable "hcloud_token" {
  sensitive = true # Requires terraform >= 0.14
}
variable "public_key" {
  sensitive = true # Requires terraform >= 0.14
}
variable "master_node_count" {
  type = number
  default = 3
}

variable "worker_node_count" {
  type = number
  default = 6
}

variable "location" {
  type = string
  default = "hel1"
  
}

variable "autoglue_key" {
  type = string
  sensitive = true
}

variable "autoglue_org_secret" {
  type = string
  sensitive = true
}

variable "zone_id" {
  type = string
  sensitive = true
}

variable "aws_access_key_id" {
  type = string
  sensitive = true
}

variable "aws_secret_access_key" {
  type = string
  sensitive = true
}

variable "domain_name" {
  type = string
  sensitive = true
}