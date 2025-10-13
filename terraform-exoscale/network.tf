resource "exoscale_private_network" "my_managed_private_network" {
  zone = "ch-gva-2"
  name = "my-managed-private-network"

  netmask  = "255.255.255.0"
  start_ip = "10.0.0.20"
  end_ip   = "10.0.0.253"
}

resource "exoscale_private_network" "my_managed_private_network" {
  zone = "ch-gva-2"
  name = "my-managed-private-network"

  netmask  = "255.255.255.0"
  start_ip = "10.0.0.20"
  end_ip   = "10.0.0.253"
}