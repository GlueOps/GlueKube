resource "local_file" "hosts_cfg" {
  content = templatefile("${path.module}/templates/hosts.tpl",
    {
      master_ipv4_addresses = {
        for idx, instance in exoscale_compute_instance.master :
        idx => {
          private = "10.0.0.3${idx}"
          public  = instance.public_ip_address
        }
      }
      worker_ipv4_addresses = {
        for idx, instance in exoscale_compute_instance.worker :
        idx => {
          private = "10.0.0.2${idx}"
          public  = instance.public_ip_address
        }
      }
    }
  )
  filename = "../ansible/inventory/exoscale-hosts.yaml"
}