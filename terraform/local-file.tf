resource "local_file" "hosts_cfg" {
  content = templatefile("${path.module}/templates/hosts.tpl",
    {
      master_ipv4_addresses = {for key, server in hcloud_server.master-node : key => {private = tolist(server.network)[0].ip, public = server.ipv4_address}}
      worker_ipv4_addresses = {for key, server in hcloud_server.worker-node : key => {private = tolist(server.network)[0].ip, public = server.ipv4_address}}
    }
  )
  filename = "../ansible/inventory/hosts.yaml"
}