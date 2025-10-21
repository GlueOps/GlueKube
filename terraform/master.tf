resource "hcloud_server" "master-node" {
  for_each = toset([for i in range(0, var.master_node_count) : tostring(i)])
  name        = "master-node-${each.key}"
  image       = "ubuntu-24.04"
  server_type = "cpx21"
  location    = var.location
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  network {
    network_id = hcloud_network.private_network.id
    ip         = "10.0.0.3${each.key}"
  }
  user_data = base64encode("${templatefile("${path.module}/cloudinit/cloud-init-master.yaml",{
    public_key = var.public_key
    hostname = "master-node-${each.key}"
  })}")

  # If we don't specify this, Terraform will create the resources in parallel
  # We want this node to be created after the private network is created
  depends_on = [hcloud_network_subnet.private_network_subnet]
  firewall_ids = [hcloud_firewall.myfirewall.id]
}

resource "hcloud_firewall" "myfirewall" {
  name = "my-firewall"

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

