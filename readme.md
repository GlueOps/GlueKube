# Prerequisite

this architecture needs at least:

- 1 master node (the control-plane count has to be **odd** — see
  [the control-plane endpoint](#the-control-plane-endpoint))
- 1 worker node

there is no load-balancer tier. clients reach the API servers through a multi-value DNS record,
described below.

for system level, you need to do:

- install ansible
- `pip install jmespath netaddr proxmoxer requests` — jmespath backs the `json_query` used when
  labelling nodes, netaddr backs the CIDR overlap check in `playbooks/preflight.yaml`, and
  proxmoxer + requests back the `community.proxmox` modules that `molecule/test-cluster` uses
- install the ansible collections, pinned in `ansible/requirements.yml` (CI installs from the
  same file, so keep the two in step):

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

ansible.posix                            2.2.2
ansible.utils                            6.0.3
community.general                        13.2.0
community.proxmox                        2.0.0
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
and `.env` (`make .env`). See [how AutoGlue runs GlueKube](#how-autoglue-runs-gluekube) for what
drives that.

## How AutoGlue runs GlueKube

nothing in this repository is the entrypoint in the hosted flow. **AutoGlue** is: it SSHes into the
cluster's bastion host and runs GlueKube there as a container, mounting `platform.json` in as a
volume. the `Makefile` targets in this repository are what it calls inside that container —
`setup`, `sync`, `upgrade-cluster`, `rotate-master-nodes` and the rest are the interface between
the two tools, so renaming or removing one is an AutoGlue-visible change, not a local one.

the shape of the invocation:

```bash
# on the bastion, run by AutoGlue over ssh
docker run --rm \
  --volume /path/to/platform.json:/opt/gluekube/platform.json \
  <gluekube image> make setup
```

`/opt/gluekube` is not arbitrary — it is the `WORKDIR` in the `Dockerfile` and the default
`BASE_PATH` in `parser.py`, which is where `platform.json` is read from and where
`ansible/inventory/hosts.yaml` and `.env` are written. `make .env` runs `parser.py` before any
playbook, so a container started this way builds its own inventory and environment from the
mounted file.

running against a checkout on a workstation is the same thing without the container: set
`GLUEKUBE_BASE_PATH` to the checkout (the `.env` rule already does) so `parser.py` reads and writes
here instead of `/opt/gluekube`. that is the only difference between the two paths — everything
below this line is identical either way.

the SSH hop matters for a reason beyond convenience: the playbooks reach the nodes on their
**private** addresses, and the bastion is inside that network. the same run started from a
workstation outside it will fail at `ansible all -m ping` no matter what `hosts.yaml` says.

If you want throwaway VMs to try things on, the molecule scenarios under `ansible/molecule/`
build and destroy a whole cluster — `test-cluster` on Proxmox, `scale-cluster` and
`rotate-master-nodes` on Hetzner. See
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

# Firewalls

the two layers below only make sense against the normal topology, so start there: **every node
sits on a private subnet, except the load-balancer nodes, which are public.** masters and ordinary
workers have private addresses only and are reached through the bastion — which is why AutoGlue
SSHes into it to run anything, see [how AutoGlue runs GlueKube](#how-autoglue-runs-gluekube). the
nodes labelled `use-as-loadbalancer` are the deliberate exception: they hold the public addresses
and take ingress traffic on 80 and 443.

that split is what the firewalls are shaped around. a GlueKube cluster is normally protected by
**two independent firewalls**, and it is worth knowing which one covers what, because neither
covers everything and neither lives in this repository.

**1. the infrastructure firewall, in terraform/opentofu.** the cloud-level rules — security groups
on AWS, the Hetzner cloud firewall, the Proxmox per-VM firewall — are created by the same modules
that provision the VMs (`opentofu-module-GlueKube-AWS`, `opentofu-module-GlueKube-Proxmox`). this
is the layer that closes the node ports that must never be public: 2379/2380, 2381, 6443, 10250,
30000+. **there is no terraform in this repository**, so none of those rules are visible here and
nothing in `ansible/` will tell you if they are missing or wrong — check them in the module repo
for the cluster you are working on.

**2. Calico, on the load-balancer nodes only.** `roles/master/tasks/apply-calico-firewall.yaml`
selects the nodes labelled `use-as-loadbalancer`, reads the public interface each one persisted,
creates a Calico `HostEndpoint` per node for that interface, and applies the two policies in
`calico-global-network-policy.yaml.j2`: a `preDNAT` ingress policy allowing TCP 80 and 443 and
ICMP and denying everything else, plus an allow-all egress policy. the ingress half is what lets
ingress take public traffic on nodes that are deliberately exposed.

read the egress half carefully before relying on either: despite the name
(`allow-all-egress-lb-nodes`) it carries `selector: all()`, so it is **not** scoped to
load-balancer nodes — it is a cluster-wide allow-all egress `GlobalNetworkPolicy`, which outranks
Kubernetes `NetworkPolicy` and makes every egress NetworkPolicy in the cluster a no-op. that is
#480 and it is still open.

the gap between the two is the thing to hold onto: **Calico's policy applies to load-balancer nodes
and to nothing else.** masters and ordinary workers have no `HostEndpoint`, so no Calico policy is
enforced on their host interfaces. on the normal topology that is fine — those nodes have no public
address for anything to arrive on. it stops being fine the moment a master gets a public interface,
because then the infrastructure firewall is the only thing in front of the control-plane ports and
Calico will not catch a mistake there. treat "this master has a public IP" as the condition that
makes layer 1 load-bearing, and check it in the module repo rather than assuming.

the molecule scenarios stand in for layer 1, since they provision their own VMs:
`ansible/molecule/common/proxmox-provision.yml` sets `firewall=1` on the public NIC with a
default-DROP input policy and a single rule for SSH, and
`ansible/molecule/common/test-public-ports-closed.yml` fails the `verify` step if 2381, 6443,
10250 or 30000 answers on a node's public address (#508).

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
`0.0.0.0`, and that is not a choice this repo can make differently: kubeadm uploads
`ClusterConfiguration` to the `kubeadm-config` ConfigMap and replays it verbatim on every
control-plane node, so it cannot carry a per-node bind address. **nothing in `ansible/` closes
2381**: of the two firewalls described under [Firewalls](#firewalls), the Calico layer covers
load-balancer nodes only, so masters are protected by the terraform/opentofu layer alone. if your
control-plane nodes have public IPs, that is where 2381 has to be blocked.

binding to every interface is an accepted trade, not an oversight, and it rests on an assumption
worth stating: **masters are expected to be on private addresses, and any master that does have a
public interface must be firewalled.** if that stops being true for a cluster, 2381 is on the
internet. watch for the case where the infrastructure firewall is attached per server rather than
per project — on Hetzner it is — because a master added by a scale-up, or rebuilt, can come up
attached to nothing and serve `/metrics` publicly from the moment etcd starts. the alternative considered was binding each node
to its own LAN address by rewriting the rendered `etcd.yaml` after every kubeadm command that
writes it; it was dropped as more moving parts than the firewall requirement is worth.

**existing clusters do not pick this up by upgrading.** the listener is an `extraArgs` entry in
`ClusterConfiguration`, and a cluster built before this change has a `kubeadm-config` ConfigMap
without it. `kubeadm upgrade apply` runs with no `--config`, so it re-renders the etcd static pod
from that ConfigMap and etcd comes back on kubeadm's own default, `http://127.0.0.1:2381`. joining
or rotating a master does not help either — `kubeadm join` takes a `JoinConfiguration` and reads
its etcd settings from the same ConfigMap.

the ConfigMap has to be updated first, which in this repo means one playbook:

```
ansible-playbook -i inventory/hosts.yaml playbooks/rotate-certs-with-config.yaml -e allow_config_change=true
```

that runs `kubeadm init phase upload-config kubeadm --config`, and the opt-in is #450's drift
guard: it re-uploads the *whole* rendered ClusterConfiguration from your current `.env`, not just
this flag, so check what else has moved before running it. do not omit `-e allow_config_change=true`
— the guard compares `kubernetesVersion`, `controlPlaneEndpoint`, `networking`, `certSANs` and
`apiServerExtraArgs` only, so an etcd-only difference raises nothing and the upload is skipped
silently.

the listener then appears the next time the etcd manifest is regenerated, which in practice means
**the next real version upgrade** — `kubeadm upgrade apply` with the version the cluster is already
on does not work, so it cannot be triggered on demand, and a master rotation does not cover the
orchestrator (`rotate-nodes.yaml` excludes it from the remove list). nothing is broken while
waiting: a cluster built before this change is still scraping `https://<node>:2379` with its
existing `etcd-client-certs` secret. verify on the node (`curl -sS http://<master ip>:2381/health`)
before repointing anything. the full migration, with rollback, is in `epic-c-status.md` under
"After the merge".

the cluster no longer publishes an `etcd-client-certs` secret into the monitoring namespace: the
task that minted it is gone, because `http://<node>:2381` is all Prometheus needs. the
kube-prometheus-stack serviceMonitor in glueops-core has to be pointed there — a serviceMonitor
still scraping `https://<node>:2379` with `etcd-client-certs` will find neither the secret nor a
reason to hold one.

## Migrate local-path-provisioner to Helm

local-path-provisioner is now installed with its Helm chart. clusters that were provisioned before
that change still carry the resources created with `kubectl apply`, and Helm refuses to take them
over, so run once per cluster:

`ansible-playbook  -i inventory/hosts.yaml playbooks/migrate-local-path-provisioner.yaml`

the playbook keeps the `local-path` storage class in place and recreates the provisioner itself with
Helm. existing volumes and their data are not touched, only the provisioning of new volumes pauses
for a few seconds. re-running is safe because it reads the `meta.helm.sh/release-name` annotation
off the deployment first and skips the migration entirely once Helm owns it — the annotation, not a
guess. it ends by waiting on the rollout, so a run that leaves the cluster without a provisioner
fails loudly instead of silently.
