data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_key_pair" "ssh-key" {
  key_name   = "ssh-key"
  public_key = var.public_key
}


resource "aws_security_group" "k8s_nodes" {
  name        = "${var.cluster_name}-nodes"
  description = "Kubernetes nodes security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow-all"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-nodes"
  }
}



resource "aws_instance" "master" {
    for_each = toset([for i in range(0, var.master_node_count) : tostring(i)])
    ami           = data.aws_ami.ubuntu.id
    instance_type = "t3.medium"
    subnet_id     = aws_subnet.public.id
    vpc_security_group_ids = [aws_security_group.k8s_nodes.id]
    key_name      = aws_key_pair.ssh-key.key_name
    tags = {
        Name = "master-node-${each.key}"
        Role = "master"
    }
    private_ip         = "10.0.0.3${each.key}"
    user_data_base64 = base64encode("${templatefile("${path.module}/cloudinit/cloud-init-master.yaml",{
        public_key = var.public_key,
        hostname = "master-node-${each.key}",
    })}")
}

resource "aws_instance" "worker" {
    for_each = toset([for i in range(0, var.worker_node_count) : tostring(i)])
    ami           = data.aws_ami.ubuntu.id
    instance_type = "t3.medium"
    subnet_id     = aws_subnet.public.id
    vpc_security_group_ids = [aws_security_group.k8s_nodes.id]
    key_name      = aws_key_pair.ssh-key.key_name
    tags = {
        Name = "worker-node-${each.key}"
        Role = "worker"
    }
    private_ip         = "10.0.0.2${each.key}"
    user_data_base64 = base64encode("${templatefile("${path.module}/cloudinit/cloud-init-worker.yaml",{
        public_key = var.public_key,
        hostname = "worker-node-${each.key}"
    })}")
}

resource "aws_network_interface" "master" {
  for_each = aws_instance.master

  subnet_id       = aws_subnet.private.id
  security_groups = [aws_security_group.k8s_nodes.id]
  private_ips     = ["10.0.1.3${each.key}"]
}

resource "aws_network_interface_attachment" "master_attach" {
  for_each      = aws_instance.master
  instance_id   = each.value.id
  network_interface_id = aws_network_interface.master[each.key].id
  device_index  = 1
  depends_on    = [aws_instance.master]
}

resource "aws_network_interface" "worker" {
  for_each = aws_instance.worker

  subnet_id       = aws_subnet.private.id
  security_groups = [aws_security_group.k8s_nodes.id]
  private_ips     = ["10.0.1.2${each.key}"]
}

resource "aws_network_interface_attachment" "worker_attach" {
  for_each      = aws_instance.worker
  instance_id   = each.value.id
  network_interface_id = aws_network_interface.worker[each.key].id
  device_index  = 1
  depends_on    = [aws_instance.worker]
}



