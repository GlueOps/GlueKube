data "exoscale_template" "os_image" {
  zone = var.zone
  name = "Linux Ubuntu 24.04 LTS 64-bit"
}



resource "exoscale_compute_instance" "master" {
  for_each = toset([for i in range(0, var.master_node_count) : tostring(i)])
  name               = "master-node-${each.key}"
  template_id        = data.exoscale_template.os_image.id
  type               = "standard.medium"
  disk_size          = "30"
  state              = "Running"
  zone               = var.zone
  security_group_ids = [exoscale_security_group.default_sg.id]
  network_interface {
    network_id = exoscale_private_network.private_network.id
    ip_address = "10.0.0.3${each.key}"
  }

  user_data = templatefile("${path.module}/cloudinit/cloud-init-master.yaml",{
      public_key = var.public_key,
      hostname = "master-node-${each.key}"
  })
}

resource "exoscale_compute_instance" "worker" {
  for_each = toset([for i in range(0, var.worker_node_count) : tostring(i)])
  name               = "worker-node-${each.key}"
  template_id        = data.exoscale_template.os_image.id
  type               = "standard.medium"
  disk_size          = "30"
  state              = "Running"
  zone               = var.zone
  security_group_ids = [exoscale_security_group.default_sg.id]
  network_interface {
    network_id = exoscale_private_network.private_network.id
    ip_address = "10.0.0.2${each.key}"

  }

  user_data = templatefile("${path.module}/cloudinit/cloud-init-worker.yaml",{
      public_key = var.public_key,
      hostname = "worker-node-${each.key}"
  })
}
