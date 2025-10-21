output "master_ipv4_addresses" {
  value = {
    for key, server in hcloud_server.master-node : key => server.ipv4_address
  }
  description = "The public IPv4 addresses of the Hetzner master servers."
}

output "worker_ipv4_addresses" {
  value = {
    for key, server in hcloud_server.worker-node : key => server.ipv4_address
  }
  description = "The public IPv4 addresses of the Hetzner worker servers"
}
