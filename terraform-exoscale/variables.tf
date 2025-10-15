variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "gluekube"
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

variable "zone" {
  type = string
  default = "ch-gva-2"
  
}

variable "excoscale_key" {
  type = string
}

variable "excoscale_secret" {
  type = string
}