resource "local_file" "hosts_cfg" {
  content = templatefile("${path.module}/templates/hosts.tpl",
    {
      master_ipv4_addresses = {
        for idx, instance in aws_instance.master :
        idx => {
          private = instance.private_ip
          public  = instance.public_ip
        }
      }
      worker_ipv4_addresses = {
        for idx, instance in aws_instance.worker :
        idx => {
          private = instance.private_ip
          public  = instance.public_ip
        }
      }
    }
  )
  filename = "../ansible/inventory/aws-hosts.yaml"
}