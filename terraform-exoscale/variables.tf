variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "gluekube-aws"
}

variable "public_key" {
  sensitive = true
}

variable "master_node_count" {
  type = number
  default = 3
}

variable "worker_node_count" {
  type = number
  default = 6
}