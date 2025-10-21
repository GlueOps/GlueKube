resource "exoscale_private_network" "private_network" {
  zone = var.zone
  name = "${var.prefix}-network"

  netmask  = "255.255.255.0"
  start_ip = "10.0.0.20"
  end_ip   = "10.0.0.250"
}

resource "exoscale_security_group" "default_sg" {
  name        = "${var.prefix}-default-sg"
  description = "Default security group"
}

resource "exoscale_security_group_rule" "default_sg_rule_tcp" {
  security_group_id = exoscale_security_group.default_sg.id

  type       = "INGRESS"
  start_port = 1
  end_port   = 65535
  protocol   = "TCP"
  cidr       = "0.0.0.0/0"
}
resource "exoscale_security_group_rule" "default_sg_rule_udp" {
  security_group_id = exoscale_security_group.default_sg.id

  type       = "INGRESS"
  start_port = 1
  end_port   = 65535
  protocol   = "UDP"
  cidr       = "0.0.0.0/0"
}