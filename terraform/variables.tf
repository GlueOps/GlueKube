# Declare the hcloud_token variable from .tfvars
variable "hcloud_token" {
  sensitive = true # Requires terraform >= 0.14
}
variable "public_key" {
  sensitive = true # Requires terraform >= 0.14
}
variable "master_node_count" {
  type = number
  default = 3 # it means 3 vms will be created
}

variable "worker_node_count" {
  type = number
  default = 3 # it means 5 vms will be created
}

variable "lb_node_count" {
  type = number
  default = 1 # it means 3 vms will be created
}

variable "location" {
  type = string
  default = "fsn1"
  
}