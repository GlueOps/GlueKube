resource "hcloud_server" "worker-node" {
  for_each = toset([for i in range(0, var.worker_node_count) : tostring(i)])
  # The name will be worker-node-0, worker-node-1, worker-node-2...
  name        = "worker-node-${each.key}"
  image       = "ubuntu-24.04"
  server_type = "cpx21"
  location    = var.location
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  network {
    network_id = hcloud_network.private_network.id
    ip         = "10.0.0.2${each.key}"
  }
  user_data = base64encode("${templatefile("${path.module}/cloudinit/cloud-init-worker.yaml",{
    public_key = var.public_key
    hostname = "master-node-${each.key}"
  })}")

  depends_on = [hcloud_network_subnet.private_network_subnet, hcloud_server.master-node]
  firewall_ids = [hcloud_firewall.workerfirewall.id]
}


resource "hcloud_firewall" "workerfirewall" {
  name = "worker-firewall"

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
