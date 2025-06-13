resource "hcloud_server" "lb-node" {
  for_each = toset([for i in range(1, var.lb_node_count) : tostring(i)])
  name        = "lb-node-${each.key}"
  image       = "ubuntu-24.04"
  server_type = "cpx11"
  location    = var.location
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  network {
    network_id = hcloud_network.private_network.id
    ip         = "10.0.0.4${each.key}"
  }
  user_data = base64encode("${templatefile("${path.module}/cloudinit/cloud-init-lb.yaml",{
    public_key = var.public_key
  })}")

  # If we don't specify this, Terraform will create the resources in parallel
  # We want this node to be created after the private network is created
  depends_on   = [hcloud_network_subnet.private_network_subnet]
  firewall_ids = [hcloud_firewall.lb-firewall.id]
}




resource "hcloud_firewall" "lb-firewall" {
  name = "lb-firewall"

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "any"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
  rule {
    direction = "in"
    protocol  = "udp"
    port      = "any"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}