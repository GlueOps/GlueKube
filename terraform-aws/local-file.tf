resource "local_file" "hosts_cfg" {
  content = templatefile("${path.module}/templates/hosts.tpl",
    {
      master_ipv4_addresses = {
        for idx, instance in aws_instance.master :
        idx => {
          private = "10.0.1.3${idx}"
          public  = instance.public_ip
        }
      }
      worker_ipv4_addresses = {
        for idx, instance in aws_instance.worker :
        idx => {
          private = "10.0.1.2${idx}"
          public  = instance.public_ip
        }
      }
    }
  )
  filename = "../ansible/inventory/aws-hosts.yaml"
}