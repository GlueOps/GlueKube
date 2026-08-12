# Prerequisite

this architecture needs at least:

- 1 master node (the control-plane count has to be **odd** — see
  [the control-plane endpoint](#the-control-plane-endpoint))
- 1 worker node

there is no load-balancer tier. clients reach the API servers through a multi-value DNS record,
described below.

for system level, you need to do:

- install ansible
- `pip install jmespath netaddr` — jmespath backs the `json_query` used when labelling nodes,
  netaddr backs the CIDR overlap check in `playbooks/preflight.yaml`
- install the ansible collections, pinned in `ansible/requirements.yml` (CI installs from the
  same file, so keep the two in step):

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

ansible.posix                            2.2.2
ansible.utils                            6.0.3
community.general                        13.2.0
hetzner.hcloud                           6.11.0
kubernetes.core                          5.4.4

## Scenario # 1 (You have VMs)

create a folder `keys` in **the same level as ansible folder**. If you have already created VMs, copy the private keys into the `keys` folder and replace the `ansible_ssh_private_key_file` inside `hosts.yaml` with each VM private key.

here is an example of the `hosts.yaml` format:

```yaml

all:
  children:
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

## Scenario # 2 (you need VMs)

There is no terraform in this repository — the modules that provision the VMs live in their own
repositories, and they are what generates `hosts.yaml`:

- `opentofu-module-GlueKube-AWS`
- `opentofu-module-GlueKube-Proxmox`

In the hosted flow you do not run either by hand: AutoGlue provisions the nodes and drops a
`platform.json` next to this Makefile, and `parser.py` turns it into `ansible/inventory/hosts.yaml`
and `.env` (`make .env`).

If you want throwaway Hetzner VMs to try things on, the molecule scenarios under
`ansible/molecule/` build and destroy a whole cluster — see
[ansible/molecule/readme.md](ansible/molecule/readme.md).

# Install Kubernetes

Now after you got `hosts.yaml`

move into the `ansible` folder and run the following commands

`export ANSIBLE_ROLES_PATH=$PWD/roles`
`export ANSIBLE_HOST_KEY_CHECKING=False`

create a file `.env` and add  the following secrets:

`RANDOM_TOKEN`: the format of token must be like the following: abcdef.abcdef0123456789

`CERTIFICATE_KEY`: The certificate key is a hex encoded string that is an AES key of size 32 bytes(AES 256 bit(HEX).

generate both locally — never with an online generator. the certificate key decrypts the
`kubeadm-certs` Secret, which holds the cluster CA private key, so anything that sees it owns the
cluster:

```bash
    kubeadm token generate                 # RANDOM_TOKEN
    kubeadm certs certificate-key          # CERTIFICATE_KEY
```

if you do not have `kubeadm` on your workstation, `openssl rand -hex 32` produces an equivalent
certificate key.

the `.env` also has to supply every variable `inventory/group_vars/` reads from the environment.
these have no default and no other producer — an unset one becomes an empty string and surfaces
much later as a broken cluster rather than an error:

```bash
export kubernetes_version=v1.34.5
export kubernetes_package_version=1.34.5-1.1
export loadbalancer_apiserver=ctrp.example.com   # the apiserver DNS record
export domain_name=example.com                   # kube-api.$domain_name goes in the certSANs,
                                                 # and the dex issuer is built from it
export network_service_cidr=192.168.0.0/16       # service_subnet
export calico_network_calico_cidr=172.16.0.0/16  # calico pod CIDR
export calico_nodeAddressAutodetectionV4=        # e.g. cidrs=10.0.0.0/8; leave empty for
                                                 # calico's firstFound, which picks the public
                                                 # interface on most cloud images
export calico_chart_version=v3.31.4
export calico_tigera_operator_version=v1.40.7

export AUTOGLUE_BASE_URL= AUTOGLUE_ORG_KEY= AUTOGLUE_ORG_SECRET=
export AUTOGLUE_ORG_ID= AUTOGLUE_RECORD_ID= AUTOGLUE_CLUSTER_ID=empty
```

`AUTOGLUE_ORG_ID` is sent as the `x-org-id` header on every AutoGlue DNS call. `parser.py` writes
it from `platform.json`'s `org_id`, and CI sets it from a secret — before that it had no producer
at all outside CI, so the header went out empty (#467). Preflight refuses to run without it.

in the container these come from `.env`, which `parser.py` writes from `platform.json`. the four
version variables above are the exception: `parser.py` only writes them when `platform.json`
carries them, and otherwise the pinned `ENV` defaults in the `Dockerfile` apply.

`playbooks/preflight.yaml` runs first on every `setup-cluster`, `sync-resources` and
`upgrade-cluster` run and names whichever of these is empty, before any node is touched.

then to allow ansible noticing the .env file, we need to export it like the following: `export $(grep -v '^#' .env | xargs)`

then test if ansible can ssh into all the hosts using:

`ansible all -i inventory/hosts.yaml -m ping`

to check the network before building anything:

`ansible-playbook -i inventory/hosts.yaml playbooks/check-network-connectivity.yaml`

it fails if a node is unreachable, if a node cannot reach the other nodes' private addresses, or
if the package mirrors are not reachable. it reports — without failing — whether the control-plane
endpoint resolves and which etcd/apiserver ports are open, both of which are expected to be
"not yet" before the first build.

if all the hosts pinged just fine, start creating the cluster by running:

`ansible-playbook -i inventory/hosts.yaml playbooks/setup-cluster.yaml`

after the playbook run successfully, you will see a kubeconfig file in `ansible/playbooks/.kube/config`

# The control-plane endpoint

`loadbalancer_apiserver` (`ctrp.<domain>`) is **not** a load balancer and there is no haproxy tier
in this repository. It is a single DNS A record holding the private address of **every** master,
created in AutoGlue and updated through its API by
`roles/master/tasks/master-node-rotation/update-dns-records.yaml` whenever the control plane
changes. `kubeadm`'s `controlPlaneEndpoint` points at it, so every joining node and every
kubeconfig resolves the API server through it.

What that means operationally:

- **Failover is client-side.** A client picks one of the returned addresses and, if it cannot
  connect, tries another. There is no health checking and no VIP, so a dead master keeps being
  handed out until DNS is updated.
- **DNS is only updated by a run.** `sync-resources.yaml` and `rotate-master-nodes.yaml` PATCH the
  record; nothing does it continuously. A master that dies unexpectedly stays in the record until
  you run one of them.
- **TTL bounds the recovery.** The record is written with a 60 second TTL, and the rotation path
  waits for at least two authoritative nameservers to agree before it continues.
- **The count must be odd.** etcd needs a quorum, so an even number of masters buys nothing over
  the odd number below it. `playbooks/preflight.yaml` refuses to run against an even count.

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

The cluster will scale up/down depending on your desired state. When the control plane changes,
the sync also **updates the `ctrp` DNS record** so it lists the masters that now exist — see
[the control-plane endpoint](#the-control-plane-endpoint).

to verify, run :

```bash
    export KUBECONFIG=$PWD/playbooks/.kube/config
    kubectl get nodes
```

# Day-2 operations

Everything below runs from the `ansible/` directory with `.env` sourced. `preflight.yaml` runs
first on the starred ones and stops the run if a variable or the inventory shape is wrong.

| I want to | Run | |
|---|---|---|
| add or remove a worker or a master | edit `hosts.yaml`, then `playbooks/sync-resources.yaml` | ★ |
| replace every master with new machines | `playbooks/rotate-master-nodes.yaml` | |
| upgrade Kubernetes | bump the versions in `.env`, then `playbooks/upgrade-cluster.yaml` | ★ |
| rotate the control-plane certificates | `playbooks/rotate-certs-with-config.yaml` | |
| re-apply labels and taints only | `playbooks/setup-cluster.yaml --tags label_nodes` | |
| move local-path-provisioner to Helm (once per old cluster) | `playbooks/migrate-local-path-provisioner.yaml` | |
| check the network before any of the above | `playbooks/check-network-connectivity.yaml` | |

**There is no etcd backup or restore path in this repository.** Nothing here snapshots etcd before
an upgrade and there is no playbook to restore one, so an upgrade is not recoverable from within
this tooling — take a snapshot yourself, or restore from the platform's own backups. Adding it is
tracked separately.

# Upgrade Cluster

## Rotate Certs

`ansible-playbook  -i inventory/hosts.yaml playbooks/rotate-certs-with-config.yaml`


## Upgrade Version

this will update the whole cluster versions

first you need to change the `kubernetes_version` and `kubernetes_package_version` to the desired version, then apply:

`ansible-playbook  -i inventory/hosts.yaml playbooks/upgrade-cluster.yaml`

## Etcd metrics

etcd exposes a metrics/health-only listener on **port 2381** over plain HTTP. it serves `/metrics`
and `/health` and nothing else — no key data and no write path — so Prometheus can scrape it without
holding an etcd client certificate.

that port is **unauthenticated**, so it must not be reachable from outside the cluster. it binds to
`0.0.0.0` because kubeadm's `ClusterConfiguration` is replayed verbatim on every control-plane node
and cannot carry a per-node bind address. if your control-plane nodes have public IPs, block 2381
at the cloud firewall or host firewall. the molecule scenarios already do this in their `create.yml`.

existing clusters pick the listener up the next time the etcd static pod manifest is regenerated,
i.e. on the next `upgrade-cluster.yaml` run.

until the kube-prometheus-stack serviceMonitor in glueops-core is repointed from
`https://<node>:2379` to `http://<node>:2381`, the cluster still publishes an `etcd-client-certs`
secret into the monitoring namespace. see the header of
`ansible/roles/master/tasks/create-etcd-secret.yaml` for the removal steps.

## Migrate local-path-provisioner to Helm

local-path-provisioner is now installed with its Helm chart. clusters that were provisioned before
that change still carry the resources created with `kubectl apply`, and Helm refuses to take them
over, so run once per cluster:

`ansible-playbook  -i inventory/hosts.yaml playbooks/migrate-local-path-provisioner.yaml`

the playbook keeps the `local-path` storage class in place and recreates the provisioner itself with
Helm. existing volumes and their data are not touched, only the provisioning of new volumes pauses
for a few seconds. it is safe to re-run and it does nothing on clusters that are already migrated.
