resource "autoglue_ssh_key" "master" {
  name = "gluekube-master"
  comment = "GlueKube Master SSH Key"
}

resource "autoglue_ssh_key" "worker" {
  name = "gluekube-worker"
  comment = "GlueKube worker SSH Key"
}

resource "autoglue_ssh_key" "bastion" {
  name = "gluekube-bastion"
  comment = "GlueKube bastion SSH Key"
}


resource "autoglue_cluster" "cluster" {
    cluster_provider = "hetzner"
    docker_image = "ghcr.io/glueops/gluekube"
    docker_tag = "v0.0.5"
    name = "test"
    region = "hl1"
}





resource "autoglue_server" "master" {
  for_each = toset([for i in range(0, var.master_node_count) : tostring(i)])
  hostname = "master-node-${each.key}"
  public_ip_address = hcloud_server.master-node[each.key].ipv4_address
  private_ip_address = tolist(hcloud_server.master-node[each.key].network)[0].ip
  role = "master"
  ssh_key_id = autoglue_ssh_key.master.id
  ssh_user = "cluster"
}


resource "autoglue_server" "worker" {
  for_each = toset([for i in range(0, var.worker_node_count) : tostring(i)])
  hostname = "worker-node-${each.key}"
  public_ip_address = hcloud_server.worker-node[each.key].ipv4_address
  private_ip_address = tolist(hcloud_server.worker-node[each.key].network)[0].ip
  role = "worker"
  ssh_key_id = autoglue_ssh_key.worker.id
  ssh_user = "cluster"
}


resource "autoglue_server" "bastion" {
  hostname = "bastion"
  public_ip_address = hcloud_server.bastion.ipv4_address
  private_ip_address = tolist(hcloud_server.bastion.network)[0].ip
  role = "bastion"
  ssh_key_id = autoglue_ssh_key.bastion.id
  ssh_user = "cluster"
}

resource "autoglue_node_pool" "master_node_pool" {
    name = "masters"
    role = "master"
}

resource "autoglue_node_pool_servers" "master_node_pool_servers" {
    node_pool_id = autoglue_node_pool.master_node_pool.id
    server_ids = [for s in autoglue_server.master : s.id]
}

resource "autoglue_node_pool" "worker_node_pool" {
  name = "workers"
  role = "worker"
}

resource "autoglue_node_pool" "public_lb_node_pool" {
  name = "public-lb"
  role = "worker"
}

resource "autoglue_node_pool" "platform_lb_node_pool" {
  name = "platform-lb"
  role = "worker"
}

resource "autoglue_node_pool_servers" "worker_node_pool_servers" {
  node_pool_id = autoglue_node_pool.worker_node_pool.id
  server_ids = [
    autoglue_server.worker["2"].id,
    autoglue_server.worker["5"].id
  ]
}

resource "autoglue_node_pool_servers" "public_loadbalancer_servers" {
    node_pool_id = autoglue_node_pool.public_lb_node_pool.id
    server_ids = [
      autoglue_server.worker["0"].id,
      autoglue_server.worker["1"].id
    ]
}

resource "autoglue_node_pool_servers" "platform_loadbalancer_servers" {
  node_pool_id = autoglue_node_pool.platform_lb_node_pool.id
  server_ids = [
    autoglue_server.worker["3"].id,
    autoglue_server.worker["4"].id
  ]
}



# resource "autoglue_cluster_bastion" "bastion" {
#     cluster_id = autoglue_cluster.cluster.id
#     server_id = autoglue_server.bastion.id
# }

resource "autoglue_annotation" "glueops_role_annotation" {
  key = "glueops.dev/role"
  value = "glueops-platform:NoSchedule"
}



resource "autoglue_credential" "route53" {
  name        = "route53-main"
  account_id = "1234567890"
  credential_provider = "aws"
  kind  = "aws_access_key"

  schema_version = "1"

  
  # Whatever your provider expects for the AWS/Route53 scope:
  scope = {
    service = "route53"
  }

  scope_version = 1
  scope_kind  = "service"

  secret = {
    access_key_id = var.aws_access_key_id 
    secret_access_key = var.aws_secret_access_key 
  }

  region     = "us-west-2"
}

resource "autoglue_domain" "captain" {
  domain_name   = var.domain_name
  credential_id = autoglue_credential.route53.id
  zone_id = var.zone_id 
}

resource "autoglue_record_set" "cluster_record" {
  domain_id = autoglue_domain.captain.id
  name = "ctrp"
  type = "A"
  ttl = 60
  values = [for s in autoglue_server.master : s.private_ip_address]
}


resource "autoglue_taint" "glueops_platform_noschedule" {
  key = "glueops.dev/role"
  value = "glueops-platform"
  effect = "NoSchedule"
}

resource "autoglue_label" "public_loadbalancer_label" {
  key = "use-as-loadbalancer"
  value = "public"
}


resource "autoglue_label" "platform_loadbalancer_label" {
  key = "use-as-loadbalancer"
  value = "platform"
}

resource "autoglue_node_pool_taints" "worker_node_taint" {
  node_pool_id = autoglue_node_pool.worker_node_pool.id
  taint_ids = [autoglue_taint.glueops_platform_noschedule.id]
}

resource "autoglue_node_pool_taints" "public_lb_node_taint" {
  node_pool_id = autoglue_node_pool.public_lb_node_pool.id
  taint_ids = [autoglue_taint.glueops_platform_noschedule.id]
}

resource "autoglue_node_pool_taints" "platform_lb_node_taint" {
  node_pool_id = autoglue_node_pool.platform_lb_node_pool.id
  taint_ids = [autoglue_taint.glueops_platform_noschedule.id]
}



resource "autoglue_node_pool_labels" "platform_loadbalancer_servers" {
  node_pool_id = autoglue_node_pool.platform_lb_node_pool.id
  label_ids = [
    autoglue_label.platform_loadbalancer_label.id
  ]
}

resource "autoglue_node_pool_labels" "public_loadbalancer_servers" {
  node_pool_id = autoglue_node_pool.public_lb_node_pool.id
  label_ids = [
    autoglue_label.public_loadbalancer_label.id
  ]
}