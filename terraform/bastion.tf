resource "hcloud_server" "bastion" {
  name        = "bastion"
  image       = "ubuntu-24.04"
  server_type = "cpx21"
  location    = var.location
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  network {
    network_id = hcloud_network.private_network.id
    ip         = "10.0.0.50"
  }
  user_data = base64encode("${templatefile("${path.module}/cloudinit/cloud-init-master.yaml",{
    public_key = autoglue_ssh_key.bastion.public_key
    hostname = "bastion"
  })}")

  # If we don't specify this, Terraform will create the resources in parallel
  # We want this node to be created after the private network is created
  depends_on = [hcloud_network_subnet.private_network_subnet]
}