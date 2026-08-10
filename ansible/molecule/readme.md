## ⚠️ Do not run a scenario while CI is running one

Every scenario uses the same fixed Hetzner resource names — network `test-molecule-network`,
firewall `my-firewall`, servers `master-node-N` / `worker-node-N` — and all three PATCH the one
shared `AUTOGLUE_RECORD_ID`. `hetzner.hcloud.server` is idempotent **by name**, so a second run
does not fail: it silently *adopts* the first run's servers, writes their IPs into its own
inventory, and re-points the shared `ctrp` record. Whichever run reaches `destroy` first deletes
the other's VMs.

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

export AUTOGLUE_RECORD_ID=""

export AUTOGLUE_CLUSTER_ID=empty

# HCLOUD TOKEN
export HCLOUD_TOKEN=""

# optional: CIDRs allowed to SSH into the test nodes. defaults to this machine's public
# address, discovered at create time.
export MOLECULE_SSH_SOURCE_CIDRS=""
```

`domain_name` is required — `kubeadm-stacked-config.yaml.j2` puts `kube-api.$domain_name` in the
apiserver certSANs and `authentication-configuration.yaml.j2` builds the Dex issuer from it.
Without it every scenario dies at *Init kubeadm* with `AnsibleUndefinedVariable`.

- install the collections: `ansible-galaxy collection install -r ansible/requirements.yml`

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
