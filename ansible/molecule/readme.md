## Which scenario runs where

`test-cluster` builds on **Proxmox**. `scale-cluster` and `rotate-master-nodes` are still on
**Hetzner**. Both collections are pinned in `ansible/requirements.yml`, and the `.env` below
carries the credentials for both.

## ⚠️ Do not run a scenario while CI is running one

Every scenario reuses a fixed resource identity, and all three create the same DNS domain,
`$domain_name`. On Hetzner that identity is the names — network `test-molecule-network`, firewall
`my-firewall`, servers `master-node-N` / `worker-node-N`; on Proxmox it is the **vmid range**
starting at `$PROXMOX_VMID_BASE` (masters `base+1..3`, workers `base+11..13`). Both providers'
create steps are idempotent on that identity, so a second run does not fail: it silently *adopts*
the first run's VMs and writes their IPs into its own inventory. Whichever run reaches `destroy`
first deletes the other's VMs, and its DNS teardown removes the domain the other run is still
using.

Pick a `PROXMOX_VMID_BASE` in a range reserved for molecule. `destroy` deletes those vmids
outright, so a base that collides with a real VM destroys it.

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
export AUTOGLUE_ORG_ID=""

# create.yml creates the DNS domain and the ctrp A record, and destroy.yml deletes both.
# these two drive that; the calls authenticate with the x-org-key/x-org-secret pair above.
export AUTOGLUE_CREDENTIAL_ID=""
export AUTOGLUE_ZONE_ID=""

# fallback only. create.yml writes the id of the record it just made to
# <scenario>/autoglue-record-id, and inventory/group_vars/masters.yaml reads that file first;
# this variable is used only for a run whose create step did not make a record.
export AUTOGLUE_RECORD_ID=""

export AUTOGLUE_CLUSTER_ID=empty

# HCLOUD TOKEN -- scale-cluster and rotate-master-nodes only
export HCLOUD_TOKEN=""

# optional: CIDRs allowed to SSH into the test nodes. defaults to this machine's public
# address, discovered at create time. used by every scenario.
export MOLECULE_SSH_SOURCE_CIDRS=""

# optional: Hetzner location for the test VMs. defaults to hel1.
export HCLOUD_LOCATION=""


# ---- Proxmox: test-cluster only ----
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

# target storage for the full clones.
export PROXMOX_STORAGE="local-lvm"

# each node gets two NICs, and BOTH bridges have to serve DHCP -- create.yml reads the addresses
# back out of the qemu guest agent.
#   net0, public bridge: the address molecule SSHes to. this is the inventory's ansible_host, and
#                        the only NIC with a firewall on it (SSH from your address, nothing else).
#   net1, LAN bridge:    the address the cluster runs on -- kubelet, etcd, Calico VXLAN, and what
#                        the ctrp record resolves to. this is the inventory's `ip`. unfiltered.
export PROXMOX_BRIDGE_PUBLIC="vmbr_public"
export PROXMOX_BRIDGE_LAN="vmbr_lan"

# REQUIRED. the subnet the LAN bridge hands out. the guest agent reports both addresses in one
# list with no hint which NIC each came from, so this is the only thing that tells them apart:
# in-range is `ip`, out-of-range is ansible_host. get it wrong and every node fails the LAN assert
# after all six VMs are already built. it is also what Calico's nodeAddressAutodetectionV4 is
# pinned to, via inventory/group_vars/masters.yaml.
export PROXMOX_LAN_CIDR="10.10.0.0/16"

# storage with the "snippets" content type enabled, and where that storage keeps them on disk.
export PROXMOX_SNIPPET_STORAGE="local"
export PROXMOX_SNIPPET_DIR="/var/lib/vz/snippets"

# vmids: masters base+1..3, workers base+11..13. must be free, and must not be VMs you care
# about -- destroy.yml deletes them.
export PROXMOX_VMID_BASE="9000"

# per-node hardware. defaults are roughly a Hetzner ccx13.
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
  route in `cloudinit/cloud-init.yaml.j2` — stops reliably naming the public NIC. Hand out an
  address and a netmask on `$PROXMOX_BRIDGE_LAN`, nothing else.
- **the datacenter firewall switched on.** The scenario attaches its rules at `level: vm`, and
  those do nothing while the datacenter firewall is off — the nodes would sit on a public address
  with no filtering at all, so `create.yml` asserts on it. Only `net0` carries `firewall=1`, so
  the ruleset governs the public NIC alone and is just SSH from `$MOLECULE_SSH_SOURCE_CIDRS`;
  `net1` is deliberately unfiltered, which is how the cluster protocols get through without a
  single rule. Anything else on `$PROXMOX_BRIDGE_LAN` can therefore reach etcd and the kubelet —
  fine for a throwaway cluster on a private bridge, worth knowing before you put one elsewhere. Enabling it is deliberately left to a
  human: it applies a default-DROP input policy across the whole cluster and can lock you out of
  unrelated VMs and of the PVE host itself. Read your default policies first, then
  `pvesh set /cluster/firewall/options --enable 1`.

The firewall rules themselves live on the VM, so `destroy.yml` has no firewall teardown to do —
deleting a VM takes its rules with it.

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
never the public one: `private_networks_info[0].ip` on Hetzner, the `$PROXMOX_LAN_CIDR` address on
Proxmox. That is the same value as the inventory's `ip`, which is what the apiserver listens on:

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
- **`AUTOGLUE_ORG_ID` has to be set.** The calls send it as `x-org-id`, the workflow sets it from
  a secret and `parser.py` now writes it from `platform.json`'s `org_id` (#467). Preflight fails
  the run if it is empty, so a scenario with the secret unset stops at converge rather than
  halfway through a DNS update.
