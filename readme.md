# Prerequisite

this arhcitecture need at least:

- 1 LoadBalancers
- 1 master node
- 1 worker node
  

for system level, you need to do:

- install ansible
- pip install jmespath
- install the below ansible collections

ansible.netcommon                        7.1.0
ansible.posix                            2.0.0
ansible.utils                            5.1.2
community.crypto                         2.24.0
community.docker                         4.3.1
community.general                        10.3.0
hetzner.hcloud                           4.2.2
kubernetes.core                          5.1.0

## Scenario # 1 (You have VMs)

create a folder `keys` in **the same level as ansible folder**. If you have already created VMs, copy the private keys into the `keys` folder and replace the `ansible_ssh_private_key_file` inside `hosts.yaml` with each VM private key.

here is an example of the `hosts.yaml` format:

```yaml

all:
  children:
    loadbalancer:
      hosts:
        lb-node-1:
          ansible_host: IP
          ansible_user: haproxyadmin
          ip: PRIVATE_IP
          ansible_ssh_private_key_file: ../keys/lb_node

        lb-node-2:
          ansible_host: IP
          ansible_user: haproxyadmin
          ip: PRIVATE_IP
          ansible_ssh_private_key_file: ../keys/lb_node

        lb-node-3:
          ansible_host: IP
          ansible_user: haproxyadmin
          ip: PRIVATE_IP
          ansible_ssh_private_key_file: ../keys/lb_node

    masters:
      hosts:
        master-node-1:
          ansible_host: IP
          ansible_user: cluster
          ip: PRIVATE_IP
          ansible_ssh_private_key_file: ../keys/master_node
          extra:
            taints:
              - node-role.kubernetes.io/control-plane:NoSchedule-
    workers:
      hosts:
        worker-node-1:
          ansible_host: IP
          ansible_user: cluster
          ip: PRIVATE_IP
          ansible_ssh_private_key_file: ../keys/worker_node
          extra:
            taints:
              - glueops.dev/role=glueops-platform:NoSchedule

```

then test if ansible can ssh into all the hosts using:

`ansible all -i inventory/hosts.yaml -m ping`

## Scenario # 2 (else)

If you didn't create VMs, you can run the terraform file `main.tf` to  create ones.

first, you need to create ssh-keys, you either create an ssh-key for each (loadbalancer,master,worker) Vms or single ssh-key for all Vms

to create an ssh-key run the following:

`ssh-keygen -o -a 100 -t ed25519 -f vm_node`

then move into terraform folder and because we're using hetzner to create Vms, create a file .tfvars and add the following:

```bash
  hcloud_token = "XXXXXX"
  public_key = "the_public_key_you_copied" 

```

finally run

```bash
    terraform init
    terraform apply -var-file .tfvars

```

If terraform finished succesfully a `hosts.yaml` file will be created under `ansible/inventory`

# Install Kubernetes

Now after you got `hosts.yaml`

move into the `ansible` folder and run the following commands

`export ANSIBLE_ROLES_PATH=$PWD/roles`
`export ANSIBLE_HOST_KEY_CHECKING=False`

create a file `.env` and add  the following secrets:

`RANDOM_TOKEN`: the format of token must be like the following: abcdef.abcdef0123456789

`CERTIFICATE_KEY`: The certificate key is a hex encoded string that is an AES key of size 32 bytes. you can use [https://www.electricneutron.com/encryption-key-generator/] and choose AES 256 bit(HEX).

then to allow ansible noticing the .env file, we need to export it like the following: `export $(grep -v '^#' .env | xargs)`

then test if ansible can ssh into all the hosts using:

`ansible all -i inventory/hosts.yaml -m ping`

if all the hosts pinged just fine, start creating the cluster by running:

`ansible-playbook -i inventory/hosts.yaml playbooks/setup-cluster.yaml`

after the playbook run successfully, you will see a kubeconfig file in `ansible/playbooks/.kube/config`

# Scale Nodes

we treat the `hosts.yaml` as the source of truth to our resources, so to **scale up or down** the nodes, it will be enough to modify the hosts.yaml file

example, the current `hosts.yaml` is:

```yaml

workers:
    hosts:
        worker-node-1:
            ansible_host: 138.199.157.195
            ansible_user: cluster
            ip: 10.0.0.21
            ansible_ssh_private_key_file: ../keys/worker_node
            extra:
              taints:
                  - glueops.dev/role=glueops-platform:NoSchedule

        worker-node-2:
            ansible_host: 138.199.163.163
            ansible_user: cluster
            ip: 10.0.0.22
            ansible_ssh_private_key_file: ../keys/worker_node
            extra:
              taints:
                  - glueops.dev/role=glueops-platform:NoSchedule

```

If we need to scale it up, we can just add another worker node

```yaml
workers:
  hosts:
    worker-node-1:
      ansible_host: 138.199.157.195
      ansible_user: cluster
      ip: 10.0.0.21
      ansible_ssh_private_key_file: ../keys/worker_node
      extra:
          taints:
              - glueops.dev/role=glueops-platform:NoSchedule

    worker-node-2:
      ansible_host: 138.199.163.163
      ansible_user: cluster
      ip: 10.0.0.22
      ansible_ssh_private_key_file: ../keys/worker_node
      extra:
          taints:
              - glueops.dev/role=glueops-platform:NoSchedule

    worker-node-3:
      ansible_host: 138.199.163.164
      ansible_user: cluster
      ip: 10.0.0.23
      ansible_ssh_private_key_file: ../keys/worker_node
      extra:
          taints:
              - glueops.dev/role=glueops-platform:NoSchedule

```

or to scale down we remove the desired worker node

```yaml

workers:
    hosts:
        worker-node-1:
            ansible_host: 138.199.157.195
            ansible_user: cluster
            ip: 10.0.0.21
            ansible_ssh_private_key_file: ../keys/worker_node
            extra:
              taints:
                  - glueops.dev/role=glueops-platform:NoSchedule

```

**Note:** you can both scale up and down at the same time, but if you do it, we will run the scale up first then scale down

**Note:** the number of control-plane nodes need to be odd number 

Now to run the syncing process, use the following command:

`ansible-playbook  -i inventory/hosts.yaml playbooks/sync-resources.yaml`

you will prompted with following message:

```txt
ok: [master-node-1] => {
    "msg": [
        "Nodes to remove: '[]'.",
        "Nodes to add '['worker-node-3']'."
    ]
}

TASK [master : pause] ****************************************************************************************************************************************************************************************************************************************
[master : pause]
Do you want to apply the above changes? (Y/n):

```

after you accept changes the kubernetes cluster will scale up/down depends on your desired state, also it will **update the loadbalancer haproxyconfig** file to the desired workloads

to verify, run :

```bash
    export KUBECONFIG=$PWD/playbooks/.kube/config
    kubectl get nodes
```

# Upgrade Cluster

## Rotate Certs

`ansible-playbook  -i inventory/hosts.yaml playbooks/upgrade-cluster.yaml --tags rotate-certs`


## Upgrade Version

this will update the whole cluster versions(NOT tested)

`ansible-playbook  -i inventory/hosts.yaml playbooks/upgrade-cluster.yaml --tags upgrade`


## OS Security Patch

to patch os with the security patches run :
`ansible-playbook  -i inventory/hosts.yaml playbooks/os-patch.yaml`
