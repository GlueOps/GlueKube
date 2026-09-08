## Which scenario runs where

All three scenarios — `test-cluster`, `scale-cluster` and `rotate-master-nodes` — build on
**Proxmox**. They share one implementation in `molecule/common/`:

| file | what it is |
| --- | --- |
| `common/proxmox-vars.yml` | every `PROXMOX_*` setting, loaded by each scenario's `vars_files` |
| `common/node-list.yml` | the list of VMs a scenario owns, imported by provision **and** teardown |
| `common/proxmox-provision.yml` | preflights, VM create, address discovery — imported by every `create.yml` |
| `common/proxmox-teardown.yml` | the matching delete, imported by every `destroy.yml` |
| `common/autoglue-create.yml` / `-destroy.yml` | the DNS domain and `ctrp` record |
| `common/cloud-init.yaml.j2` | the per-node snippet, rendered once per VM |
| `common/bastion-cloud-init.yaml.j2` | the bastion's snippet — no kubelet, no k8s sysctls |
| `common/hosts.yaml.j2` | the **cluster** inventory, templated onto the bastion |
| `common/bastion-hosts.yaml.j2` | the **bastion** inventory, the only one written locally |
| `common/bastion-vars.yml` | paths and names both bastion-side files share |
| `common/bastion-prepare.yml` | toolchain, code ship and `.env` — imported by every `create.yml` |
| `common/bastion-run.yml` / `bastion-poll.yml` | runs one playbook on the bastion and streams it back |
| `common/bastion-env.j2` | the `.env` the remote runs source |

A scenario's own `create.yml` is then only the parts that genuinely differ: how many nodes, which
vmid range, which inventory files, and what `ctrp` resolves to.

## How a run reaches the nodes

The cluster nodes have **no publicly reachable address**. Each scenario builds a bastion, and that
bastion is the only thing molecule talks to:

```
molecule (laptop / CI runner)
        │  ssh, vmbr_public          ← the only inbound path into the scenario
        ▼
   bastion-node          net0 vmbr_public   net1 vmbr_lan
   /opt/gluekube/ansible                    │
   ansible-playbook                         │  vmbr_lan is routed to vmbr_nat
                         ┌──────────────────┘
        ┌────────────────┴───────────────────────────┐
        ▼                                            ▼
   master-node-N                               worker-node-N
   net0 vmbr_nat  ─ one NIC, one address ─     net0 vmbr_nat
```

A cluster node has **exactly one NIC**, on `vmbr_nat`. That single address is everything: its
route out to apt and `registry.k8s.io`, the address the bastion SSHes to, and what etcd, the
kubelet, Calico and the `ctrp` record all bind to — `ansible_host` and `ip` in the inventory are
the same value. Nothing outside the scenario can reach it. The bastion can, because its LAN leg is
routed to the NAT segment.

The bastion is the only VM with two NICs, and `$PROXMOX_LAN_CIDR` exists solely to tell its two
DHCP leases apart: in range is the LAN address it reaches the cluster over, out of range is the
public address molecule connects to.

This is the production topology. AutoGlue SSHes into a cluster's bastion and runs GlueKube there
as a container, and `parser.py` writes the nodes' **private** addresses into `ansible_host`; until
now molecule tested the exact opposite, connecting straight to a wide-open public address.

Mechanically:

- `create.yml`'s first play builds the VMs — the bastion with two NICs, every master and worker
  with one on the NAT bridge — makes the DNS record, and writes `inventory/hosts.yaml`, which now
  holds **the bastion and nothing else**. That is the file `molecule.yml` links.
- `create.yml`'s second play (`hosts: bastion`) installs the toolchain, copies the whole `ansible/`
  tree to `/opt/gluekube/ansible`, writes a root-only `/opt/gluekube/.env`, and templates the
  cluster inventories into the **mirrored** scenario directory on the bastion.
- Every later step — `converge`, each `side_effect`, `verify` — is a thin wrapper play against the
  bastion that runs `ansible-playbook` there and tails its output back. The wrappers live in
  `<scenario>/remote/`, plus `converge.yml` and `verify.yml`.
- **`playbooks/`, `roles/`, `side_effect/` and `tests/` are unchanged and unaware.** The mirror
  preserves the repo layout and the remote run `chdir`s to the scenario directory, which is the
  same cwd molecule uses locally, so `keys/vm_node`, `../inventory/scale-up-ctrp.yaml` and
  `import_playbook: ../../../playbooks/sync-resources.yaml` all resolve exactly as before.

Each remote step's stdout is streamed into the molecule transcript roughly every 15 seconds and
fetched to `<scenario>/logs/` at the end, so a failure is still diagnosable after `destroy` has
deleted the bastion. The bastion's own `ansible.log` is never fetched — it contains the join
token, the certificate key and the AutoGlue org secret.

## ⚠️ Do not run a scenario while CI is running one

Every scenario reuses a fixed resource identity, and all three create the same DNS domain,
`$domain_name`. That identity is the **vmid range** each scenario owns — `$PROXMOX_VMID_BASE`
plus a per-scenario offset, masters at `base+1..`, workers at `base+11..`:

| scenario | offset | bastion | masters | workers |
| --- | --- | --- | --- | --- |
| `test-cluster` | 0 | 9000 | 9001–9003 | 9011–9013 |
| `scale-cluster` | 100 | 9100 | 9101–9103 | 9111–9113 |
| `rotate-master-nodes` | 200 | 9200 | 9201–9209 | 9211 |

The offsets keep the three scenarios from colliding with **each other**. They do nothing about a
second run of the *same* scenario: create is idempotent on the vmid, so it does not fail, it
silently *adopts* the first run's VMs and writes their IPs into its own inventory. Whichever run
reaches `destroy` first deletes the other's VMs, and its DNS teardown removes the domain the
other run is still using.

Pick a `PROXMOX_VMID_BASE` leaving 9000–9211 (at the default) free and reserved for molecule. The
range starts at the base itself now — that is the bastion. `destroy` deletes those vmids outright,
so a base that collides with a real VM destroys it. The offsets live in each scenario's
`create.yml` *and* `destroy.yml` — change one, change both, or destroy will delete the wrong range.
The list of VMs itself is no longer duplicated: provision and teardown both import
`common/node-list.yml`, so a VM added to a scenario cannot be forgotten by teardown.

The symptoms are inexplicable SSH failures, or — worse — a green run against a cluster somebody
else half-built.

The CI workflow now has a `concurrency:` group, so CI runs queue behind each other. It cannot see
your laptop. Before running locally, check that
[Molecule Tests](../../.github/workflows/molecule_test.yaml) is not in progress.

## ⚠️ `create` dirties tracked files

`create.yml` writes `<scenario>/inventory/hosts.yaml` with the bastion's live public IP, SSH
username and key path. That file is git-tracked as an empty placeholder and cannot be gitignored:
molecule resolves `inventory.links.hosts` before it runs anything and aborts with *"The source
path ... does not exist"* if the target is missing.

So after a run, `git status` is dirty with real infrastructure data. **`git checkout
ansible/molecule/*/inventory/hosts.yaml` before committing**, and never `git add -A` blind.

It is one file per scenario now, and only the bastion. The cluster inventories — the real
`hosts.yaml` with the nodes in it, and `scale-up-ctrp.yaml` and friends — are templated straight
onto the bastion and never touch the working tree at all. `<scenario>/logs/`, where each remote
step's output is fetched back to, is gitignored.

## Setup

- create a `.env` file with the following data:

```
export kubernetes_version=v1.34.5
export kubernetes_package_version=1.34.5-1.1
export loadbalancer_apiserver="ctrp.<your-domain>"
export domain_name="<your-domain>"
export CERTIFICATE_KEY=""
export RANDOM_TOKEN=""
export calico_chart_version=v3.31.4
export calico_tigera_operator_version=v1.40.7

# point this at your own checkout
export ANSIBLE_ROLES_PATH=/path/to/GlueKube/ansible/roles


# this envs because we are using internal tool to manage route53 records

export AUTOGLUE_BASE_URL=""

export AUTOGLUE_ORG_KEY=""
export AUTOGLUE_ORG_SECRET=""

# create.yml creates the DNS domain and the ctrp A record, and destroy.yml deletes both.
# these two drive that; the calls authenticate with the x-org-key/x-org-secret pair above.
export AUTOGLUE_CREDENTIAL_ID=""
export AUTOGLUE_ZONE_ID=""

# fallback only. create.yml writes the id of the record it just made to
# <scenario>/autoglue-record-id, and inventory/group_vars/masters.yaml reads that file first;
# this variable is used only for a run whose create step did not make a record.
export AUTOGLUE_RECORD_ID=""

export AUTOGLUE_CLUSTER_ID=empty

# ---- Proxmox: all three scenarios ----
#
# community.proxmox reads these four itself, which is why no module in create.yml passes any
# api_* parameter. PROXMOX_TOKEN_ID is the token name alone, not user@realm!name.
export PROXMOX_HOST=""
export PROXMOX_USER="root@pam"
export PROXMOX_TOKEN_ID=""
export PROXMOX_TOKEN_SECRET=""

# optional: 8006 and true. Set PROXMOX_VALIDATE_CERTS=false for a self-signed PVE certificate.
export PROXMOX_PORT="8006"
export PROXMOX_VALIDATE_CERTS="true"

# the node the six VMs are built on. required.
export PROXMOX_NODE=""

# the Ubuntu 24.04 cloud image the nodes are built from. there is NO template to clone: the VMs
# are created straight from this import volume, the same way the Terraform module provisions them,
# and the cloud-init drive is attached by create.yml as ide2. the volume has to be on a storage's
# "import" content type. create.yml checks it exists before building anything and lists what it
# did find, so a wrong value costs one API call.
export PROXMOX_IMPORT_FROM="local:import/noble-server-cloudimg-amd64.qcow2"

# the imported disk starts at the image's own virtual size (~3.5G), which does not fit a kubelet
# and its images. create.yml grows it to this.
export PROXMOX_DISK_SIZE="40G"

# target storage for the node disks, the cloud-init drives and the EFI disks. the nodes boot
# UEFI (q35 + OVMF), the same as the Terraform module, so each gets a 4MB efidisk0 with Secure
# Boot left off. this storage therefore has to accept qcow2. create.yml asserts it exists on
# the node and lists what does, so a wrong value fails before anything is built.
export PROXMOX_STORAGE="local"

# the guest CPU model. Proxmox defaults a new VM to `kvm64`, which only advertises x86-64-v1.
# Calico's binaries from v3.29 are built with GOAMD64=v2, so on kvm64 calico-typha and
# calico-node abort at startup with "this program can only run on amd64 processors with v2
# microarchitecture support" and the daemonset never goes ready. anything v2 or better works;
# this matches the Terraform module. use "host" only on a single-host cluster.
export PROXMOX_CPU="x86-64-v2-AES"

# the bridges. every one involved has to serve DHCP -- create.yml reads the addresses back out of
# the qemu guest agent. note the VMs do NOT all have the same number of NICs:
#   bastion, net0 on the public bridge: the address molecule SSHes to, and the only inbound path
#                        into the scenario.
#   bastion, net1 on the LAN bridge:    how it reaches the cluster. the LAN has to be routed to
#                        the NAT segment; nothing here sets that up.
#   node,    net0 on the NAT bridge:    a master or worker's ONLY NIC. outbound internet -- apt,
#                        registry.k8s.io, the helm repos, github releases -- and the address the
#                        cluster runs on: kubelet, etcd, Calico VXLAN, and what ctrp resolves to.
#                        it is both `ansible_host` and `ip` in the inventory.
export PROXMOX_BRIDGE_PUBLIC="vmbr_public"
export PROXMOX_BRIDGE_NAT="vmbr_nat"
export PROXMOX_BRIDGE_LAN="vmbr_lan"

# VLAN tags for those bridges, matching what the Terraform module does: the LAN bridge is
# VLAN-aware and DHCP is on 101, the public and NAT ones are untagged. empty means the NIC gets no
# tag. an untagged NIC on a VLAN-aware bridge takes no lease, and that only shows up much later as
# "the guest agent never reported an address".
export PROXMOX_BRIDGE_PUBLIC_VLAN=""
export PROXMOX_BRIDGE_NAT_VLAN=""
export PROXMOX_BRIDGE_LAN_VLAN="101"

# REQUIRED, and it is only about the BASTION -- the one VM with two NICs. the guest agent reports
# both of its addresses in one list with no hint which came from which, so this is the only thing
# that tells them apart: in-range is the LAN address it reaches the cluster over, out-of-range is
# the public address molecule connects to. a cluster node has a single NIC and needs no such
# disambiguation.
export PROXMOX_LAN_CIDR="10.10.0.0/16"

# REQUIRED. the subnet the NAT bridge hands out, which is now the cluster's own subnet. create.yml
# asserts every master and worker came up inside it -- that is how a node which landed on the
# wrong bridge fails immediately instead of being written into the inventory with an address
# nothing can reach. it is also what Calico's nodeAddressAutodetectionV4 is pinned to, via
# inventory/group_vars/masters.yaml. must not overlap PROXMOX_LAN_CIDR; create.yml checks.
export PROXMOX_NAT_CIDR="10.20.0.0/16"

# storage with the "snippets" content type enabled, and where that storage keeps them on disk.
export PROXMOX_SNIPPET_STORAGE="local"
export PROXMOX_SNIPPET_DIR="/var/lib/vz/snippets"

# tags applied to every VM the scenario builds, comma-separated. the vmid range already
# identifies them, but a tag is what makes a leaked node findable: `qm list` plus the tag column
# in the PVE UI, without having to remember the range.
export PROXMOX_TAGS="qa-gluekube-molecule"

# the bottom of the vmid range. each scenario adds its own offset on top -- see the table under
# "Do not run a scenario while CI is running one". everything from base to base+211 must be free,
# and must not be VMs you care about: destroy.yml deletes them.
export PROXMOX_VMID_BASE="9000"

# per-node hardware. defaults are roughly a Hetzner ccx13.
#
# rotate-master-nodes builds NINE masters plus a worker plus the bastion. at these defaults that
# is 42 vCPU and 82G of RAM in one scenario -- cheap when the nodes were rented per-hour on
# Hetzner, less so on a single PVE host. turn these down if the host cannot seat it.
export PROXMOX_CORES="4"
export PROXMOX_MEMORY="8192"

# the bastion's own hardware. it runs ansible-playbook and nothing else -- no kubelet, no
# container images -- so it does not need a node's size, and giving it one would cost a third of
# a node per scenario.
export PROXMOX_BASTION_CORES="2"
export PROXMOX_BASTION_MEMORY="2048"
export PROXMOX_BASTION_DISK_SIZE="20G"

# SSH to the hypervisor. the Proxmox API's storage upload endpoint does not accept snippets, so
# create.yml writes the cloud-init files to the PVE host directly. host defaults to PROXMOX_HOST,
# user to root, and the key to whatever your ssh-agent/config offers if left empty.
export PROXMOX_SSH_HOST=""
export PROXMOX_SSH_USER="root"
export PROXMOX_SSH_KEY_FILE=""
```

In CI these come from the repository's GitHub settings. `molecule_test.yaml` reads each name from
`vars` first and then from `secrets`, so either tab works — but only those two: a value put
anywhere else, or spelled differently, expands to the empty string and `create.yml`'s first assert
fails on a name that looks set in the UI (#486). `PROXMOX_HOST`, `PROXMOX_USER`, `PROXMOX_TOKEN_ID`
and `PROXMOX_TOKEN_SECRET` are read from `secrets` only. Note that anything stored as a secret is
masked in the logs, so a short node name put there will redact every occurrence of that string in
the run's output; prefer `vars` for the non-sensitive settings.

`PROXMOX_SSH_KEY` is the private key for the PVE host, and it is the one secret whose formatting
matters: OpenSSH rejects a PEM that has lost its line breaks or picked up CRLF endings with
`Load key ...: error in libcrypto`, then quietly falls back to password auth and surfaces as
`Permission denied (publickey,password)` — a message that points at the wrong problem. Store it
base64-encoded to sidestep that entirely:

```bash
base64 -w0 < ~/.ssh/id_ed25519      # paste the single line into the secret
```

The workflow accepts the raw PEM too, and now verifies either form with `ssh-keygen -y` before
molecule runs, so a bad key fails in the "Install the Proxmox host SSH key" step with the actual
reason. The key must have no passphrase, and its public half must be in `~/.ssh/authorized_keys`
for `$PROXMOX_SSH_USER` on the PVE host — that step prints the public key so you can compare.

### Proxmox prerequisites

`create.yml` does not build any of these — it assumes them and fails early with a message if it
can:

- the cloud-init template above, with a cloud-init drive
- a storage with the `snippets` content type enabled
- SSH access to the PVE host
- all three bridges, with DHCP on each
- **`$PROXMOX_BRIDGE_NAT` must actually route out.** It is the cluster nodes' only path to apt,
  `repo.gpkg.io`, `registry.k8s.io`, the Helm repos and GitHub releases, so its DHCP scope has to
  hand out a router option *and* nameservers. If it does not, cloud-init never finishes on any
  node and the run dies at *Wait for the guest agent to report an address*. `create.yml` checks the
  bridge exists; it cannot check that it NATs. The `test_nodes_pingable` step right after `create`
  is the thing that does — it probes `repo.gpkg.io:443` and `pkgs.k8s.io:443` from every node.
- **`$PROXMOX_BRIDGE_LAN` must be routed to `$PROXMOX_BRIDGE_NAT`.** The bastion sits on the LAN
  and every node sits on the NAT segment, so that route is the only way it reaches them. Nothing
  here builds it. If it is missing, `create` gets as far as *Wait for SSH on every cluster node*
  in `common/bastion-prepare.yml` and times out there — which is deliberately early, and names the
  node it could not reach.
- **no default gateway in the LAN bridge's DHCP scope.** This now applies to the bastion alone —
  it is the only VM left with two NICs, and a second default route would make its outbound path,
  and the return path for molecule's own SSH, nondeterministic. Hand out an address and a netmask
  on `$PROXMOX_BRIDGE_LAN`, nothing else. The cluster nodes have a single NIC and a single default
  route, so `/etc/glueops/public-interface` is unambiguous on them for the first time.

> **What is exposed.** Nothing here builds a PVE firewall: no NIC carries `firewall=1`, no per-VM
> ruleset is written, and the datacenter firewall is neither read nor required. What changed is
> that there is now only **one** VM with a publicly reachable address — the bastion — and all it
> answers on is `22`. The masters and workers are on `$PROXMOX_BRIDGE_NAT` only, so `6443`,
> `10250`, etcd's unauthenticated metrics port `2381` and the NodePort range are no longer
> reachable from outside that segment. They are still wide open *within* it, and note that the
> cluster's own traffic now runs on the NAT segment rather than an isolated LAN — anything else
> with a route to `$PROXMOX_NAT_CIDR`, the bastion's LAN included, can reach those ports
> unfiltered.

`domain_name` is required — `kubeadm-stacked-config.yaml.j2` puts `kube-api.$domain_name` in the
apiserver certSANs and `authentication-configuration.yaml.j2` builds the Dex issuer from it.
Without it every scenario dies at *Init kubeadm* with `AnsibleUndefinedVariable`.

- install the collections: `ansible-galaxy collection install -r ansible/requirements.yml`

- install the pinned python side: `pip install -r ansible/requirements.txt`. That is where
  `ansible-core` is pinned too, and the version matters: the bastion installs from the same file,
  and the two controllers behaving differently is a failure that only ever shows up on one of
  them. `molecule` itself is not in there — install it separately.

- source .env

- move to Gluekube/ansible and run: molecule test -s "name_of_test", example: molecule test -s scale-cluster

## What each scenario asserts

`tests/test_cluster_healthy.yaml` is the shared health check, and `verify.yaml` imports it so the
`verify` step and the mid-sequence checks cannot drift apart. It asserts that the set of node names
`kubectl` reports **equals** the inventory's masters + workers, and that the etcd member count
equals the number of masters — not merely that whatever nodes happen to be listed are Ready, which
passes just as happily on an empty cluster.

`test-cluster` **does not** run molecule's `idempotence` step — it is commented out in its
`molecule.yml`, and it could not work here anyway: molecule counts changed tasks in the *local*
run, and the task that launches the remote playbook is always changed. The equivalent check lives
in `common/bastion-run.yml` as `bastion_run_assert_no_changes`, which reads the remote
`PLAY RECAP`. Set it on a second converge to restore the regression guard for #439.

## DNS lifecycle

`create.yml` creates the AutoGlue DNS domain named by `$domain_name`, then creates the `ctrp` A
record inside it pointing at the master node addresses — their `$PROXMOX_NAT_CIDR` addresses, the
only ones they have. That is the same value as the inventory's `ip`, which is what the apiserver
listens on:

```
POST /api/v1/dns/domains                        {credential_id, domain_name, zone_id}
POST /api/v1/dns/domains/{domain_id}/records    {name: ctrp, ttl, type: A, values: [...]}
```

It writes both ids to `<scenario>/autoglue-ids.yaml` (gitignored), and `destroy.yml` reads that
file and deletes the record and then the domain. A `DELETE` that 404s is treated as success, so
re-running `destroy` is harmless.

It also writes the record id on its own to `<scenario>/autoglue-record-id`, which
`inventory/group_vars/masters.yaml` reads through `$MOLECULE_SCENARIO_DIRECTORY`. That is how the
scale and rotate scenarios' `update-dns-records.yaml` PATCHes the record this run actually created
instead of whatever `$AUTOGLUE_RECORD_ID` happens to point at.

On the bastion that indirection is deliberately short-circuited. `MOLECULE_SCENARIO_DIRECTORY` is
not exported into `/opt/gluekube/.env`, so the file lookup misses, `errors='ignore'` yields an
empty string, and the `$AUTOGLUE_RECORD_ID` fallback fires — and that variable is written into the
`.env` with **this run's** record id, read off the local `autoglue-record-id` at ship time. Same
result, one indirection fewer, and it cannot pick up a stale id from an operator's environment.
`.env` is written after `autoglue-create.yml` for exactly this reason: `playbooks/preflight.yaml`
fails every master on an empty `autoglue_record_id`.

Two things worth knowing:

- **The domain create is not idempotent.** If a run dies between creating the domain and reaching
  `destroy`, the next run's `POST /dns/domains` will hit the leftover. Delete it in AutoGlue
  before re-running.

