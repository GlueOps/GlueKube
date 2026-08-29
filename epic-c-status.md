# Epic C (#431) — status on `feat/solving_issue_486`

Epic C is *Control-plane credentials are static, world-readable, and reach logs and GitHub*:
7 tickets, 4 closed as won't-do (#432, #433, #434, #435), 3 open (#436, #437, #438).

Standing constraint from the tracker, unchanged by anything below:
**`ansible/ansible.log` must never be committed, uploaded as a CI artifact, or attached to a
support bundle.** `ansible.cfg:4` writes every task result there, the repo has no `no_log`
(#433 closed as won't-do), and `GlueOps/GlueKube` is public.

---

## #436 — Etcd client certificate is copied into the monitoring namespace

**Partly solved on arrival; the remaining clause is now addressed.**

`ansible/roles/master/tasks/create-etcd-secret.yaml` mints a dedicated `CN=prometheus` keypair off
the etcd CA with `extendedKeyUsage = clientAuth`, keeps the apiserver's `apiserver-etcd-client.*`
out of the monitoring namespace, verifies the new cert can actually scrape `:2379/metrics` before
publishing, and applies with `--dry-run=client -o yaml | kubectl apply -f -` so it is idempotent —
which also clears the `creates:` sentinel the ticket cross-referenced to Epic D. The secret keys are
deliberately still named `apiserver-etcd-client.*` so the kube-prometheus-stack serviceMonitor
(`caFile`/`certFile`/`keyFile`) keeps working unchanged.

Two things worth knowing, neither a defect:

- **etcd RBAC is not enabled.** `ansible/roles/master/templates/kubeadm-stacked-config.yaml.j2:66-84`
  carries no `auth-enable`, and nothing in the repo runs `etcdctl user`/`etcdctl role`. etcd with
  `--client-cert-auth` accepts *any* certificate signed by its CA, so `CN=prometheus` still has full
  read/write on etcd. What the rewrite bought is a **separate, revocable identity with a narrow
  EKU** — not a reduction in privilege. The ticket's "if etcd RBAC is enabled, scope the user to
  read-only" clause is still outstanding.
- `etcd_monitoring_cert_validity_days` defaults to **3650** while the renewal check is
  `checkend 2592000` (30 days), so the renewal branch can never fire and the certificate is
  effectively permanent. That is a deliberate tradeoff: a 365-day certificate would auto-renew on
  each run, but would break etcd scraping on a cluster nobody runs the playbook against for a year.
  The value is overridable via `etcd_monitoring_cert_validity_days`.

### The read-only clause — resolved by removing the credential instead of scoping it

Rather than enable etcd RBAC — which on a running cluster means restarting etcd with `auth-enable`
before the apiserver's own user and role exist, taking the control plane down — the credential is
being removed from the picture entirely.

`kubeadm-stacked-config.yaml.j2` now sets `listen-metrics-urls: http://0.0.0.0:2381` in the etcd
`extraArgs`. That listener serves `/metrics` and `/health` only, with no client-certificate auth and
no write path, which is everything Prometheus actually needs from etcd. It is additive: it opens a
new port and changes nothing about 2379/2380, so it is safe against running clusters. They pick it
up the next time the etcd static pod manifest is regenerated, i.e. on the next `upgrade-cluster.yaml`.

Two things this deliberately does **not** do:

- **The bind address is `0.0.0.0`, not the node's private IP.** `ClusterConfiguration` is
  cluster-wide — kubeadm uploads it to the `kubeadm-config` ConfigMap and replays it verbatim on
  every member — so a per-node address cannot be expressed there. The per-node alternative is
  kubeadm's `patches` directory, which would also have to be threaded through the join and upgrade
  paths or the flag silently disappears on the next upgrade. 2381 is unauthenticated, so it must be
  blocked from outside the cluster at the network layer. Nothing in `ansible/` does that -- the
  Calico policy covers load-balancer HostEndpoints only. The molecule scenarios do, via the
  per-VM firewall in `molecule/common/proxmox-provision.yml`, and
  `molecule/common/test-public-ports-closed.yml` fails the run if they stop (#508). Any public-IP
  deployment needs the equivalent. Documented in `readme.md` under "Etcd metrics".
- ~~**`create-etcd-secret.yaml` is not deleted yet.**~~ It has since been deleted, along with its
  import from `roles/master/tasks/main.yaml`. The cluster no longer publishes an
  `etcd-client-certs` secret, so the glueops-core kube-prometheus-stack serviceMonitor **must** now
  scrape `http://<node>:2381` — one still pointing at `https://<node>:2379` with
  `etcd-client-certs` will find no secret. **That chart change is the remaining work and it lives
  in another repo.** The leftover secret has to be removed by hand on clusters that already have
  one: `kubectl -n <etcd_secret_namespace> delete secret etcd-client-certs`.

## #437 — Test VMs are internet-exposed and the published image has no provenance

**Half solved on arrival; the rest is now done.**

Already done before this pass: `ssh_pwauth: false` in all three molecule scenarios, and `sbom: true`
on the build step.

### Firewall — was not done, now fixed

All three `create.yml` still opened TCP **and** UDP `1-65535` from `0.0.0.0/0` and `::/0`. Changed in
`test-cluster`, `scale-cluster` and `rotate-master-nodes`:

- The bootstrap ruleset is now **TCP 22 only**, sourced from the controller's own public address
  (looked up from `api.ipify.org`), overridable with a comma-separated `MOLECULE_SSH_SOURCE_CIDRS`
  for self-hosted runners.
- A second task, `Restrict the firewall to SSH and node-to-node traffic`, runs once `worker_nodes`
  is registered and re-applies SSH plus full TCP/UDP scoped to the nodes' own `/32`s.

The two-stage shape is forced by ordering: servers attach to the firewall, so the firewall must
exist before any node address is known.

**Node-to-node had to stay open on the public interface.** The molecule scenarios do not set
`calico_node_address_autodetection_v4` — only `ansible/inventory/group_vars/masters.yaml:13` does —
so Calico falls back to `firstFound` and picks Hetzner's `eth0`. Closing UDP outright would have
killed VXLAN. Cluster-internal traffic is unaffected either way: the `ctrp` record is published from
`private_networks_info[0].ip`, and Hetzner firewalls do not filter the private network.

### Image provenance — now added

In `.github/workflows/container_image.yaml`:

- `provenance: mode=max` on `docker/build-push-action`.
- `actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8 # v4.2.2` with
  `push-to-registry: true`.
- The `id-token: write` and `attestations: write` permissions that step requires.
- A `Normalize the image reference` step, because the attestation subject must be the exact pushed
  reference and GHCR rejects the uppercase in `GlueOps/GlueKube`.

Verification for an operator:
`gh attestation verify oci://ghcr.io/glueops/gluekube:<tag> --repo GlueOps/GlueKube`

Not added: cosign. The GitHub attestation covers the same ground with no key management.

## #438 — Housekeeping: tracked inventory file and third-party key generation

**Was not solved; now done.**

`ansible/inventory/hosts.yaml` was still tracked (mode `100755`, empty blob), and the `.gitignore`
rule that commit `1982939` was meant to restore had been dropped entirely rather than uncommented.
It is now `git rm --cached`'d, with an anchored `/ansible/inventory/hosts.yaml` rule.

While in `.gitignore`, one live footgun the ticket did not name: `rotate-master-nodes.yaml` was
listed as a **bare filename**, which also matches `ansible/playbooks/rotate-master-nodes.yaml` and
`ansible/roles/master/tasks/rotate-master-nodes.yaml`. Those survive only because they are already
tracked — anyone recreating either file would have it silently ignored. All molecule-generated
inventories are now anchored to `/ansible/molecule/*/inventory/`, and the previously unmatched
`second-rotate-master-nodes.yaml` was added.

Confirmed with `git check-ignore --no-index`: generated inventories ignored, the two real source
files no longer shadowed, and molecule's tracked placeholder `hosts.yaml` files untouched — molecule
links them via `provisioner.inventory.links.hosts`, so untracking those would break scenario setup.

`readme.md` had already lost the `electricneutron.com` link but replaced it with nothing. It now
documents `kubeadm token generate` and `kubeadm certs certificate-key`, with `openssl rand -hex 32`
as the no-kubeadm fallback, plus a line on why the key must be generated locally.

---

## Verification performed

- YAML parses on all four edited files.
- Both new Jinja expressions exercised under a real `ansible-playbook` run:
  - autodetect branch → `ssh=['203.0.113.9/32'] nodes=['1.2.3.4/32', '1.2.3.5/32', '1.2.3.6/32']`
  - override branch → `ssh=['10.0.0.0/8', '198.51.100.7/32']` with `controller_public_ip` entirely
    undefined, which confirms the inline `if/else` is lazy and the skipped `uri` task cannot break it.
- `git check-ignore --no-index` results as described under #438.
- `ansible/ansible.log` absent from the working tree.

**Not verified:** the firewall was dropped in `66daf5e` and has since been restored on Proxmox in
`molecule/common/proxmox-provision.yml`, where it now covers all three scenarios rather than
`test-cluster` alone. It has not yet run green. It needs the datacenter firewall enabled on the PVE
cluster — provisioning asserts that rather than setting it — so the first symptom of a host that
has not had `pvesh set /cluster/firewall/options --enable 1` run on it is an early, explicit
failure in `create`.

## Still open

- **glueops-core, per existing cluster -- see "After the merge" below.** Repoint the
  kube-prometheus-stack etcd serviceMonitor from `https://<node>:2379` + `etcd-client-certs` to
  `http://<node>:2381`. The GlueKube half is already done -- `create-etcd-secret.yaml` and its
  import are deleted -- so this is now overdue rather than merely pending. Nothing else in Epic C
  is outstanding in this repo.
- No comment has been posted to #436, #437 or #438.

## After the merge -- etcd monitoring migration on existing clusters

Every cluster built from `main` scrapes etcd on **`https://<node>:2379` with the
`etcd-client-certs` secret**, and that works today: kubeadm binds the etcd *client* port to
loopback and the node's advertise address, and etcd serves `/metrics` there as well as on 2381.
Nothing on `main` ever used 2381 -- it had no `listen-metrics-urls`, so it took kubeadm's
loopback-only default. This branch moves monitoring to the unauthenticated metrics-only listener on
2381 so the monitoring stack stops holding an etcd client credential (#436). Different port,
different scheme, different auth model, so the chart has to move with the branch.

Two things make the ordering matter more than it looks:

- **2381 does not appear by upgrading, and rotating a master does not open it either.** The
  listener is an `extraArgs` entry in `ClusterConfiguration`, and a cluster built before this
  change has a `kubeadm-config` ConfigMap without it. `kubeadm upgrade apply` runs with no
  `--config` (`first-node-upgrade.yaml:41`), so it re-renders etcd from that ConfigMap and etcd
  comes back on kubeadm's default `127.0.0.1:2381`; `kubeadm join` on a rotated-in master
  (`master-node-rotation/join-nodes.yaml:34`) passes a `JoinConfiguration` and reads etcd settings
  from the same place. The ConfigMap has to be updated first -- step 2 below. Do not repoint the
  chart on the assumption that a GlueKube run opened the port; check the node.
- **The old secret survives the merge.** Deleting `create-etcd-secret.yaml` stops the secret being
  *created*, not *kept*, so the existing scrape keeps working until someone deletes it. That is
  what makes a no-gap migration possible, and also what makes it easy to stop at step 6 and think
  the job is done.

1. **Confirm the master firewall first**, before anything else -- see the readme's Etcd metrics
   section. 2381 binds to `0.0.0.0` by deliberate decision, so on any master with a public
   interface the firewall is the only thing keeping an unauthenticated `/metrics` off the
   internet. On Hetzner the firewall is attached per server: a master added later, or rebuilt,
   comes up with no rules at all.
2. **Merge, then put the flag in the cluster's ConfigMap:**
   `ansible-playbook -i inventory/hosts.yaml playbooks/rotate-certs-with-config.yaml -e allow_config_change=true`.
   That is the only `kubeadm init phase upload-config kubeadm --config` in the repo
   (`rotate-certs-with-config.yaml:115`), and `allow_config_change` is #450's drift guard: it
   re-uploads the whole rendered ClusterConfiguration from the current `.env`, not just this flag.
   Diff the rendered config against the live one before running it, and do not omit the flag: the
   guard's comparison covers `kubernetesVersion`, `controlPlaneEndpoint`, `networking`, `certSANs`
   and `apiServerExtraArgs` only, so an etcd-`extraArgs`-only difference raises nothing and the
   upload is simply skipped by its own `when` -- a green run that changed nothing.

   This step is safe to do early and on its own -- it changes what a future `upgrade` or `join`
   reads, and nothing about the running etcd.

3. **Wait for the next version upgrade.** The manifests are regenerated by `upgrade-cluster.yaml`,
   which covers every master (`upgrade apply` on the orchestrator, `upgrade node` on the rest,
   `serial: 1`) and preserves the uploaded flag, because `upgrade apply` reads the ConfigMap and
   writes it back with the new version. There is no way to trigger this without a real version
   bump: **`kubeadm upgrade apply <same version>` does not work -- tested.** And a master rotation
   is not a substitute either: `rotate-nodes.yaml:37` excludes the orchestrator from the remove
   list, so that node keeps its old manifest and its etcd member stays unscrapable, and rotation
   only covers hosts actually swapped in the inventory.

   Nothing is broken while waiting. The cluster keeps scraping `https://<node>:2379` with the
   `etcd-client-certs` secret, which is still there because deleting `create-etcd-secret.yaml`
   stopped the secret being created, not kept. The steps below are what closes #436 for that
   cluster, and they wait for the upgrade.

   If a cluster genuinely cannot wait, the manual equivalent is to edit
   `/etc/kubernetes/manifests/etcd.yaml` on each master -- `--listen-metrics-urls=http://127.0.0.1:2381`
   to `http://0.0.0.0:2381` -- **one master at a time**, waiting for
   `etcdctl endpoint health --cluster` between nodes, since the kubelet restarts etcd on the write.
   Do that only with the firewall from step 1 confirmed.
4. **Verify the listener**, from inside the cluster: `curl -sS http://<master ip>:2381/health` on
   each master, and `curl -sS --max-time 5 http://<master public ip>:2381/health` from off-site to
   confirm the firewall answers with nothing. `molecule verify` asserts the second one
   (`ansible/molecule/common/test-public-ports-closed.yml`) but says nothing about a real cluster.
5. **Repoint the serviceMonitor in glueops-core** to `http://<node ip>:2381` -- plain HTTP, no
   `tlsConfig`, no secret mount. kube-prometheus-stack's `kubeEtcd` defaults moved to 2381
   upstream, so this may be closer to deleting overrides than adding them.
6. **Check the etcd targets are up in Prometheus.** This is the step that proves the migration;
   everything before it is reversible without touching a dashboard.
7. **Delete the leftover credential, per cluster:**
   `kubectl -n <etcd_secret_namespace> delete secret etcd-client-certs`
   (`etcd_secret_namespace` is `glueops-core-kube-prometheus-stack`). Until this runs the cluster
   is still publishing an etcd client certificate to the monitoring namespace -- which is the whole
   of #436 -- so the migration is not done at step 6.

Rollback, if the 2381 scrape does not come up: put the serviceMonitor back on
`https://<node>:2379` with `etcd-client-certs` before step 7. After step 7 the secret has to be
minted by hand from `/etc/kubernetes/pki/etcd/ca.crt` and
`/etc/kubernetes/pki/apiserver-etcd-client.{crt,key}` on a master -- `git show
main:ansible/roles/master/tasks/create-etcd-secret.yaml` has the exact commands.
