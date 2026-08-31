## Which scenario runs where

All three scenarios — `test-cluster`, `scale-cluster` and `rotate-master-nodes` — build on
**Proxmox**. They share one implementation in `molecule/common/`:

| file | what it is |
| --- | --- |
| `common/proxmox-vars.yml` | every `PROXMOX_*` setting, loaded by each scenario's `vars_files` |
| `common/proxmox-provision.yml` | preflights, VM create, address discovery — imported by every `create.yml` |
| `common/proxmox-teardown.yml` | the matching delete, imported by every `destroy.yml` |
| `common/autoglue-create.yml` / `-destroy.yml` | the DNS domain and `ctrp` record |
| `common/cloud-init.yaml.j2` | the per-node snippet, rendered once per VM |
| `common/hosts.yaml.j2` | the inventory template every scenario writes through |

A scenario's own `create.yml` is then only the parts that genuinely differ: how many nodes, which
vmid range, which inventory files, and what `ctrp` resolves to.

## ⚠️ Do not run a scenario while CI is running one

Every scenario reuses a fixed resource identity, and all three create the same DNS domain,
`$domain_name`. That identity is the **vmid range** each scenario owns — `$PROXMOX_VMID_BASE`
plus a per-scenario offset, masters at `base+1..`, workers at `base+11..`:

| scenario | offset | masters | workers |
| --- | --- | --- | --- |
| `test-cluster` | 0 | 9001–9003 | 9011–9013 |
| `scale-cluster` | 100 | 9101–9103 | 9111–9113 |
| `rotate-master-nodes` | 200 | 9201–9209 | 9211 |

The offsets keep the three scenarios from colliding with **each other**. They do nothing about a
second run of the *same* scenario: create is idempotent on the vmid, so it does not fail, it
silently *adopts* the first run's VMs and writes their IPs into its own inventory. Whichever run
reaches `destroy` first deletes the other's VMs, and its DNS teardown removes the domain the
other run is still using.

Pick a `PROXMOX_VMID_BASE` leaving 9000–9211 (at the default) free and reserved for molecule.
`destroy` deletes those vmids outright, so a base that collides with a real VM destroys it. The
offsets live in each scenario's `create.yml` *and* `destroy.yml` — change one, change both, or
destroy will delete the wrong range.

The symptoms are inexplicable SSH failures, or — worse — a green run against a cluster somebody
else half-built.

The CI workflow now has a `concurrency:` group, so CI runs queue behind each other. It cannot see
your laptop. Before running locally, check that
[Molecule Tests](../../.github/workflows/molecule_test.yaml) is not in progress.

## ⚠️ `create` dirties tracked files

`create.yml` writes `<scenario>/inventory/hosts.yaml` with the live public IPs, SSH usernames and
key paths of the test VMs. That file is git-tracked as an empty placeholder and cannot be
gitignored: molecule resolves `inventory.links.hosts` before it runs anything and aborts with
*"The source path ... does not exist"* if the target is missing.

So after a run, `git status` is dirty with real infrastructure data. **`git checkout
ansible/molecule/*/inventory/hosts.yaml` before committing**, and never `git add -A` blind. The
generated `scale-*.yaml` / `rotate-*.yaml` inventories in the same directory *are* gitignored.

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

# each node gets two NICs, and BOTH bridges have to serve DHCP -- create.yml reads the addresses
# back out of the qemu guest agent.
#   net0, public bridge: the address molecule SSHes to. this is the inventory's ansible_host, and
#                        no filtering is applied to it -- see the note under "prerequisites".
#   net1, LAN bridge:    the address the cluster runs on -- kubelet, etcd, Calico VXLAN, and what
#                        the ctrp record resolves to. this is the inventory's `ip`. unfiltered.
export PROXMOX_BRIDGE_PUBLIC="vmbr_public"
export PROXMOX_BRIDGE_LAN="vmbr_lan"

# VLAN tags for those two bridges, matching what the Terraform module does: the LAN bridge is
# VLAN-aware and DHCP is on 101, the public one is untagged. empty means the NIC gets no tag.
# an untagged NIC on a VLAN-aware bridge takes no lease, and that only shows up much later as
# "the guest agent never reported an address".
export PROXMOX_BRIDGE_PUBLIC_VLAN=""
export PROXMOX_BRIDGE_LAN_VLAN="101"

# REQUIRED. the subnet the LAN bridge hands out. the guest agent reports both addresses in one
# list with no hint which NIC each came from, so this is the only thing that tells them apart:
# in-range is `ip`, out-of-range is ansible_host. get it wrong and every node fails the LAN assert
# after all six VMs are already built. it is also what Calico's nodeAddressAutodetectionV4 is
# pinned to, via inventory/group_vars/masters.yaml.
export PROXMOX_LAN_CIDR="10.10.0.0/16"

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
# rotate-master-nodes builds NINE masters plus a worker. at these defaults that is 40 vCPU and
# 80G of RAM in one scenario -- cheap when the nodes were rented per-hour on Hetzner, less so on
# a single PVE host. turn these down if the host cannot seat it.
export PROXMOX_CORES="4"
export PROXMOX_MEMORY="8192"

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
- both bridges, with DHCP on each
- **no default gateway in the LAN bridge's DHCP scope.** Two default routes make the node's
  outbound path nondeterministic, and `/etc/glueops/public-interface` — derived from the default
  route in `common/cloud-init.yaml.j2` — stops reliably naming the public NIC. Hand out an
  address and a netmask on `$PROXMOX_BRIDGE_LAN`, nothing else.

> **What the nodes are exposed on.** Nothing here builds a PVE firewall: neither NIC carries
> `firewall=1`, no per-VM ruleset is written, and the datacenter firewall is neither read nor
> required. Both addresses are therefore wide open — the public one answers on `6443`, `10250`,
> etcd's unauthenticated metrics port `2381` and the NodePort range as readily as on `22`. Run
> these scenarios on a network you are willing to have that on.

`domain_name` is required — `kubeadm-stacked-config.yaml.j2` puts `kube-api.$domain_name` in the
apiserver certSANs and `authentication-configuration.yaml.j2` builds the Dex issuer from it.
Without it every scenario dies at *Init kubeadm* with `AnsibleUndefinedVariable`.

- install the collections: `ansible-galaxy collection install -r ansible/requirements.yml`

- install the python libraries the modules need on the controller:
  `pip install jmespath netaddr proxmoxer requests`

- source .env

- move to Gluekube/ansible and run: molecule test -s "name_of_test", example: molecule test -s scale-cluster

## What each scenario asserts

`tests/test_cluster_healthy.yaml` is the shared health check, and `verify.yaml` imports it so the
`verify` step and the mid-sequence checks cannot drift apart. It asserts that the set of node names
`kubectl` reports **equals** the inventory's masters + workers, and that the etcd member count
equals the number of masters — not merely that whatever nodes happen to be listed are Ready, which
passes just as happily on an empty cluster.

`test-cluster` additionally runs molecule's `idempotence` step: a second `converge` must report
zero changed tasks.

## DNS lifecycle

`create.yml` creates the AutoGlue DNS domain named by `$domain_name`, then creates the `ctrp` A
record inside it pointing at the master node addresses. Every scenario uses the private address,
never the public one — the `$PROXMOX_LAN_CIDR` address. That is the same value as the inventory's `ip`, which is what the apiserver listens on:

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

Two things worth knowing:

- **The domain create is not idempotent.** If a run dies between creating the domain and reaching
  `destroy`, the next run's `POST /dns/domains` will hit the leftover. Delete it in AutoGlue
  before re-running.

