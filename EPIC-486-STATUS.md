# GlueKube Ansible review (#486) — what is still unfinished

Re-derived **2026-08-27** from the working tree of `feat/solving_issue_486` @ `f22d2f9`
**plus uncommitted changes**, which is **42 commits ahead of `origin/main`** (`27a2ae9`) and 1
behind. Every "done" below means *done on this branch*, not shipped.

> **#510 says this file should be deleted before #211 merges**, on the grounds that a second copy
> of the status drifts from the tickets and reads as authoritative while being wrong — which is
> exactly what happened to the 2026-08-19 version of this file. That objection still stands. If it
> is kept, it has to be re-derived from the code every time the branch moves; the tracker #486 and
> the tickets remain the source of truth.

Rows marked **⧗ uncommitted** exist only in the working tree.

## Scoreboard

| Epic | Theme | Done | Partial | Open | Verdict |
|---|---|---|---|---|---|
| **B** #424 | Control plane taken down all at once | 5 | 0 | 0 | ✅ **Finished** (1 accepted risk) |
| **C** #431 | Credentials static / world-readable | 3 | 0 | 0 | ✅ **Finished** (4 closed won't-do) |
| **G** #459 | CI cannot catch regressions | 5 | 0 | 0 | ✅ **Finished** |
| **H** #465 | Variable plumbing, tooling, docs | 6 | 0 | 1 | 🟢 Only #469 left |
| **E** #446 | Upgrades have no safety rails | 4 | 1 | 1 | 🟢 #447 is the one that matters |
| **I** #473 | Duplication and misleading names | 3 | 1 | 0 | 🟢 One decision, one deliberate |
| **A** #415 | Sync/scale destroys or skips nodes | 5 | 2 | 1 | 🟡 #417 and #422 are real |
| **D** #439 | Re-runs unsafe against a live cluster | 4 | 2 | 0 | 🟡 Two halves left |
| **F** #453 | Nexus mirror, apt signatures | 3 | 0 | 2 | 🟡 Both are code, no longer gated |
| **J** #479 | Calico policy and config defects | 2 | 0 | 2 | 🟠 #480 is the highest-value bug left |
| **#505** | New findings from the review of PR #211 | 2 | 0 | 3 | 🟡 Raised against this branch |

**What is actually left is small and specific.** In rough value order: **#480** (every egress
NetworkPolicy in the cluster is inert), **#447** (no etcd snapshot before `kubeadm upgrade apply`),
**#422** (departing nodes keep working credentials), **#417** (destructive scale-down runs
unattended), then the housekeeping.

Four items are **decisions, not engineering**: #477 (`bump_version.yaml`), #485 (`email_verified`
fail-closed), #484 (confirm the Felix block is meant to be inert), #510 (this file).

---

## 🟠 Epic J #479 — Calico policy and configuration defects (2 of 4 actionable)

| # | Finding | Status | Evidence |
|---|---|---|---|
| #480 | `allow-all-egress` GNP nullifies every Kubernetes egress NetworkPolicy | **OPEN** | `calico-global-network-policy.yaml.j2:26-32` — the policy is named `allow-all-egress-lb-nodes` but its `selector` is still `all()`. The name claims a scope the selector does not implement, so it reads as fixed. Unchanged since the review. |
| #481 | Merge the two Calico value templates | ✅ **DONE** | `calico-without-firstFound.yaml.j2` is gone; `install-calico.yaml` renders `calico.yaml.j2` alone. |
| #482 | `install-calico` only waits for the operator, not Calico | ✅ **DONE** | Waits for the `calico-node` daemonset and its rollout. |
| #483 | LB nodes without a public-interface file are silently skipped | **OPEN** | `apply-calico-firewall.yaml:47-60` — `failed_when: false`, then `selectattr('rc','equalto',0) \| rejectattr('stdout','equalto','')`. A node that fails the read is dropped from the map with no warning and never gets a HostEndpoint. Unchanged. |
| #484 | Felix configuration gated on the WireGuard toggle | **NEEDS CONFIRMATION** | `calico.yaml.j2:94-96` is now `enabled: false` / `logSeverityScreen: Info`. The WireGuard gate the ticket objected to is gone, but the block is inert either way — `logSeverityScreen` is not applied. If the intent was "always apply the Felix config, independent of encryption", this needs `enabled: true`. Confirm which was meant. |
| #485 | Question: is `email_verified` fail-closed intentional? | **UNANSWERED** | A decision, not code. |

#480 is still the single highest-value bug in the review.

## 🟡 Epic A #415 — Sync and scale (5 done, 2 partial, 1 open)

| # | Status | Note |
|---|---|---|
| #416 Node diff returns every node when kubectl fails | ✅ **DONE** | `common/tasks/collect-node-lists.yaml` has `set -euo pipefail` and a "refuse to diff against an empty cluster" assert. |
| #417 Restore the confirmation gate the README documents | **PARTIAL** | The *documentation* half is fixed — the README no longer promises a `Do you want to apply the above changes?` prompt, so it no longer lies. The **gate itself still does not exist**: the only `pause:` in `roles/` is the DNS propagation sleep in `update-dns-records.yaml:111`. `make sync` still cordons, drains, deletes nodes and removes etcd members unattended. Filed as a Blocker; still worth one. |
| #418 Master removal crashes on `hostvars` for de-inventoried nodes | ✅ **DONE** | `update-dns-records.yaml:20-27` matches IPs by node name against kubectl output. |
| #419 Rotation's `nodes_to_remove` returns all cluster nodes | **PARTIAL / by design** | Still returns every node, now documented as deliberate in `master-node-rotation/compare-node.yaml:1-8`: a rotation replaces the whole control plane, so every node is a candidate and `rotate-nodes.yaml` narrows it. The narrowing itself is no longer a hostname substring match — see #506. |
| #420 Unanchored etcd member grep | ✅ **DONE** | `scale-down.yaml` uses `grep -P '(?<![\w-]){{ item }}(?![\w-])'`. |
| #421 Worker join substring matching | ✅ **DONE** | List membership against `stdout_lines`. |
| #422 Removed nodes are never reset and keep valid credentials | **OPEN** | `scale-down.yaml` cordons, drains, deletes the Node and removes the etcd member. It never runs `kubeadm reset` on the departing node. `roles/master/tasks/reset-nodes.yaml` exists but is the *pre-join* reset, not a teardown. A removed node keeps its kubelet client cert and its etcd peer keypair. |
| #423 Molecule coverage for control-plane scale-down | ✅ **DONE** | `side_effect/remove_control_plane.yaml` + `tests/test_scale_down.yaml`, wired into `test_sequence`. |

## 🟢 Epic E #446 — Upgrades have no safety rails (4 of 6)

| # | Status | Evidence |
|---|---|---|
| #447 No etcd snapshot, no upgrade gate, no version-skew check | **OPEN** | `grep -rn "snapshot save\|skew" roles/ playbooks/` returns nothing. `first-node-upgrade.yaml` runs `kubeadm upgrade apply {{ kubernetes_version }} -y` with no backup ahead of it. |
| #448 Worker kubelet patches silently discarded at first upgrade | ✅ **DONE** | Every kubeadm call that rewrites a kubelet config re-renders the patch and passes `--patches /etc/kubernetes/patches`: `worker/tasks/upgrade.yaml`, `master/tasks/upgrade.yaml`, `master/tasks/first-node-upgrade.yaml`. ⧗ The render now lives once in `roles/common/tasks/render-kubelet-patch.yaml` (#474) rather than a copy per role. |
| #449 Secondary masters have no kubelet patch mechanism at all | ✅ **DONE** | `master/templates/kubeletConfigurationPatch.yaml.j2` plus `patches.directory` in `kubeadm-join-config.j2`, rendered before the join on both the steady-state and rotation paths. The master and worker templates stay separate on purpose — the worker's small tier is `1024Mi` against the master's `512Mi`. |
| #450 Cert rotation overwrites cluster-wide `ClusterConfiguration` | ✅ **DONE** | `rotate-certs-with-config.yaml:31-94` fetches the live ClusterConfiguration, compares the env-derived fields, prints the difference and fails unless `-e allow_config_change=true`. The upload runs only on that opt-in. |
| #451 `AuthenticationConfiguration` pins an apiVersion requiring 1.34 | ✅ **DONE** | Template selects `v1` at ≥1.34 and `v1beta1` below; preflight floor is 1.31. |
| #452 Housekeeping: kubeadm hold asymmetry, kubelet reservation math | **PARTIAL** | Hold half fixed and de-duplicated: `common/tasks/upgrade-kubeadm.yaml:49` and `upgrade-kubelet.yaml:18,24`. **The reservation math is untouched** — `kubeReserved` still equals `systemReserved` (doubled headroom), `systemReservedCgroup: "/system.slice"` is still set while `enforceNodeAllocatable` is `["pods"]` only (so it does nothing), and the `>= 16384` tier is still unreachable on a nominal 16 GiB VM. |

**#447 remains the highest-value item in Epic E**: an etcd snapshot is the only thing between a
failed `kubeadm upgrade apply` and an unrecoverable cluster.

## 🟡 Epic D #439 — Re-run safety (4 of 6)

| # | Status | Note |
|---|---|---|
| #440 containerd config rewritten, non-atomic window | ✅ **DONE** | `copy` with registered content — idempotent and atomic. |
| #441 containerd/kubelet restarted on every run | ✅ **DONE** | `state: "{{ 'restarted' if containerd_config_file is changed else 'started' }}"`. |
| #442 Every run dist-upgrades; kube packages never held at install | **PARTIAL** | Holds are in place (`common/tasks/prepare-node.yaml:233,251`) and `cache_valid_time: 3600` is unified at `:57`. **`upgrade: dist` at `prepare-node.yaml:61` is still ungated** — every `make sync` dist-upgrades every live node. |
| #443 Four `creates:` sentinels never written | ✅ **DONE** | All remaining `creates:` point at paths their task writes. |
| #444 Swap and kernel modules do not survive a reboot | ✅ **DONE** | fstab edit + `persistent: present` modprobe + `/etc/sysctl.d/99-kubernetes.conf`. |
| #445 No entrypoint survives `--check` | **PARTIAL** | `check_mode: false` at the two places that need it (`select-orchestrator.yaml:27`, `sync.yaml:13`). No dry run has been demonstrated end to end. Treat as unverified. |

## 🟡 Epic F #453 — Nexus mirror and apt signatures (3 of 5)

The airgapped question that gated #455 and #456 has been answered in practice: the images were
mirrored. Both remaining items are now ordinary code, not decisions.

| # | Status | Note |
|---|---|---|
| #454 `allow_unauthenticated: true` | **OPEN** | 4 sites: `common/tasks/prepare-node.yaml:221,244`, `upgrade-kubeadm.yaml:41`, `upgrade-kubelet.yaml:12`. It was 7 before; the drop is de-duplication (#474), not a fix. |
| #455 Calico/metrics-server/local-path images not mirrored | ✅ **DONE** | `calico.yaml.j2:2-3` (`quay.repo.gpkg.io`), `metrics-server-values.yaml.j2:17`, `local-path-provisioner-values.yaml.j2:10,14`, and `kubeadm-stacked-config.yaml.j2:56,60` (`k8s.repo.gpkg.io`). **The pause image is the gap** — see #507. |
| #456 Seven public hosts contacted, no checksums | **OPEN** | 5 `get_url` calls across `common/tasks/prepare-node.yaml:80,194`, `common/tasks/upgrade-kubeadm.yaml:11` and `master/tasks/prepare-nodes.yaml:16,50`. `grep -rn "checksum:" roles/` returns nothing. |
| #457 Pin collections with `requirements.yml` | ✅ **DONE** | `ansible/requirements.yml` pins 5 collections; CI installs from it. |
| #458 Deprecated `apt_key`, unreferenced mirror template | ✅ **DONE** | Only a comment mentions `apt_key`. |

## 🟢 Epic H #465 — Plumbing, tooling, docs (6 of 7)

| # | Status | Note |
|---|---|---|
| #466 Preflight play | ✅ **DONE** | `playbooks/preflight.yaml`, imported by `setup-cluster.yaml` and `upgrade-cluster.yaml`. |
| #467 `AUTOGLUE_ORG_ID` has no producer | ✅ **DONE** | `parser.py:157` writes `AUTOGLUE_BASE_URL={autoglue_base_url}`. The copy-paste bug the previous version of this file flagged was fixed and `org_id` removed entirely. |
| #468 `parser.py` misses four version variables | ✅ **DONE** | `version_fields`. |
| #469 `ansible.cfg` uses env-var names as ini keys | **OPEN** | Unchanged. `ANSIBLE_HOST_KEY_CHECKING="False"` and `ANSIBLE_ROLES_PATH=$PWD/roles` are still ini keys under `[defaults]` that ansible does not read. Only `log_path` is valid. |
| #470 Makefile | ✅ **DONE** | The bare `export ;` that leaked credentials is gone. |
| #471 README haproxy / Terraform | ✅ **DONE** | `readme.md:71,166` state that neither exists. |
| #472 `check-network-connectivity` reports success without checking | ✅ **DONE** ⧗ | Every probe is now live: host ping under `any_errors_fatal`, the `ip` inventory assert, node-to-node private path, mirror reachability, the `ctrp` lookup and the 2379/2380/6443 matrix. Nine tasks, none commented out. |

## ✅ Epic G #459 — CI (5 of 5, finished)

#460 (PR trigger with `yamllint`/`ansible-lint` actually invoked), #461 (`concurrency:`),
#462 (real molecule health checks) and #463 (`domain_name` produced in CI) were already done.

**#464 is now done too**, all six sub-items: the artifact uploads `~/.cache/molecule`
(`molecule_test.yaml:308`) instead of two paths that matched nothing; `latest_release.yaml`
triggers on `types: [published]` alone and has a `concurrency:` group; `ansible/inventory/hosts.yaml`
is untracked and ignored, and every generated molecule inventory including
`second-rotate-master-nodes.yaml` is listed in `.gitignore:67-72`; `scale-cluster/create.yml:89`
points `ctrp` at `master_nodes_list[:1]` rather than pre-satisfying its own assertion; the
control-plane untaint appears only in the masters block of `common/hosts.yaml.j2`; and
`molecule/test-cluster-aws/` is gone.

## ✅ Epic C #431 — Credentials (3 of 3 actionable, finished)

Four of the seven were closed won't-do.

| # | Status | Note |
|---|---|---|
| #436 Etcd client cert copied into monitoring namespace | ✅ **DONE** ⧗ | `create-etcd-secret.yaml` and its import from `main.yaml` are deleted. etcd exposes an unauthenticated metrics-only listener on 2381 (`kubeadm-stacked-config.yaml.j2`), which is all Prometheus needs, so no etcd client credential is published at all. **Remaining work is in another repo**: the glueops-core kube-prometheus-stack serviceMonitor must be repointed to `http://<node>:2381`, and the leftover `etcd-client-certs` secret removed per cluster. |
| #437 Test VMs internet-exposed, image has no provenance | ✅ **DONE** ⧗ | *Image:* `container_image.yaml` sets `sbom: true`, `provenance: mode=max` and runs `actions/attest-build-provenance`. *VMs:* the per-VM firewall is back in `molecule/common/proxmox-provision.yml` and now covers all three scenarios rather than `test-cluster` alone — `firewall=1` on net0, `policy_in: DROP`, `policy_out: ACCEPT`, one inbound rule for TCP 22, `dhcp: 1`. net1 stays unflagged so the cluster needs no rules. `cloud-init.yaml.j2:25` sets `ssh_pwauth: false`. ⚠️ Requires the datacenter firewall enabled on the PVE cluster (`pvesh set /cluster/firewall/options --enable 1`); provisioning asserts it rather than setting hypervisor-wide state. |
| #438 Tracked inventory file, third-party key generation | ✅ **DONE** | `ansible/inventory/hosts.yaml` is untracked and `.gitignore:55` covers it; only `hosts.yaml.example` is tracked. The `electricneutron.com` link is gone from the README, and CI generates its own keys with `ssh-keygen` per run. |

> **Standing constraint, unchanged:** `ansible/ansible.log` must never be published. #433 was closed
> won't-do, so credentials keep landing in that file (`ansible.cfg:4`, no `no_log` anywhere) and
> `.gitignore` does not cover it. `GlueOps/GlueKube` is public and artifacts are world-downloadable.
> The CI artifact upload at `.github/workflows/molecule_test.yaml:305-308` uploads
> `~/.cache/molecule` and **only** that — verified. It must stay that way.

## ✅ Epic B #424 — Finished

#425 and #426 were the two halves of the non-reentrant cert rotation. #425 was resolved by deleting
`rotate-certs.yaml` (dead code superseded by `rotate-certs-with-config.yaml`). ⧗ **#426 is now
fixed properly**: the park → wait → restore sequence in `rotate-certs-with-config.yaml:144-170` is a
`block:`/`always:`, so the restore runs even when the wait exhausts its retries, and the park
carries `creates:`/`removes:` so a recovery run walks past it instead of dying on an `mv` with no
source and never reaching the restore.

#427 was resolved by deleting `playbooks/os-patch.yaml` and `roles/common/tasks/patch-os.yaml`.
#429 has `--cluster` on the etcd health probe. #430 is fixed by `select-orchestrator.yaml`:
`orchestrator_node` appears at 81 sites and every one of the 8 remaining `masters[0]` references is
inside a comment.

#428 (`kubectl drain --timeout`) is still absent but was **closed as not planned** — accepted risk.

## 🟢 Epic I #473 — Duplication and misleading names (3 of 5)

⧗ **#474 is now complete.** `render-kubelet-patch.yaml` was the last genuinely duplicated task file
and lives once in `roles/common/tasks/`, imported from six call sites. The template stays per-role
by design (see #449). The earlier steps landed previously: `prepare-node.yaml`,
`create-join-credentials.yaml`, `collect-node-lists.yaml`, `upgrade-kubeadm.yaml` and
`upgrade-kubelet.yaml` are all shared out of `roles/common/`. The remaining `compare-node.yaml` and
`join-nodes.yaml` deltas are the documented deliberate ones — the rotation diff computes
`nodes_to_remove` differently on purpose (#419), and the two join paths differ in their gating.

#475 (renames) and #478 (nits) are done. Two things are left, neither of them work:

- **#476** — the tag errors are fixed (`join_worker` → `join_master` on the control-plane join,
  `kubeconfig_setup` → `kubeadm_config`), but the duplicate task *names* remain by choice: 9 ×
  "Select the orchestrator node", 6 × "Generate Kubeadm configuration", 6 × "Render the per-node
  kubelet patch", 5 × "Elect the orchestrator", 4 × "Preflight". These are the same operation
  reached from different paths, so repeating the name is honest. **Close or re-scope the ticket.**
- **#477** — `.github/configs/workflows/bump_version.yaml` is still parked outside
  `.github/workflows/` and therefore inert. The ticket says *check with the team first*; moving it
  starts running release automation that has never run. **Needs a decision.**

The two unnamed plays in `setup-cluster.yaml` were explicitly excluded from scope.

## 🟡 Epic #505 — New findings from the review of PR #211 (2 of 5)

Raised against this branch, not against `main`.

| # | Status | Note |
|---|---|---|
| #506 Control-plane detection by hostname substring | ✅ **DONE** ⧗ | `select('search','master')` is gone from `rotate-nodes.yaml` and `sync.yaml`. `common/tasks/collect-node-lists.yaml` registers `current_control_plane_nodes` from `kubectl get nodes -l node-role.kubernetes.io/control-plane`; the removal lists intersect against it and the add list against `groups['masters']`. The two are tested differently on purpose — a node being added has no label and no etcd member yet, which is why #475's fix did not transfer. |
| #507 Pause image not mirrored | **OPEN** | `grep -rn sandbox_image ansible/` returns nothing. `common/tasks/prepare-node.yaml` generates the containerd config from `containerd config default` and only flips `SystemdCgroup`, so `sandbox_image` stays at `registry.k8s.io/pause:3.x`. On a mirror-only network no pod sandbox can start on any node. This is the one gap left in #455. |
| #508 etcd metrics on 0.0.0.0:2381 unauthenticated, code falsely claims molecule firewalls them | ✅ **DONE** ⧗ | The false claims are gone from `kubeadm-stacked-config.yaml.j2` and `readme.md`, which now say plainly that **nothing in `ansible/` closes 2381**. The molecule half is no longer a claim: the firewall is real (see #437) and `molecule/common/test-public-ports-closed.yml` fails `verify` if 2381, 6443, 10250 or 30000 answers on a node's public address. The `0.0.0.0` bind stays — `ClusterConfiguration` is replayed verbatim on every member and cannot carry a per-node address. |
| #509 CI reuses static `CERTIFICATE_KEY` and `RANDOM_TOKEN` | **OPEN** | `molecule_test.yaml:127-128,177-178` still passes both from repository secrets into every run. `CERTIFICATE_KEY` decrypts the `kubeadm-certs` Secret, which holds the CA private key. The firewall from #437 shrinks the exposure but does not remove it — generating both per run inside the workflow is a few lines and drops the two secrets entirely. |
| #510 This file is stale and should not be merged | **OPEN** | See the note at the top. This revision addresses the drift; it does not address the objection. |

---

## What to do next

1. **Epic J #480** — the `all()` selector on the allow-all-egress GNP. Every Kubernetes egress
   NetworkPolicy in the cluster is currently a no-op, and the rename makes it look handled.
2. **Epic E #447** — an etcd snapshot before `kubeadm upgrade apply`.
3. **Epic A #422 and #417** — reset departing nodes so their credentials die with them, and put a
   confirmation gate in front of destructive scale operations.
4. **#509** — generate the CI bootstrap credentials per run. Small, and it retires two secrets.
5. **Answer the four questions.** #477 (`bump_version.yaml`), #485 (`email_verified` fail-closed),
   #484 (is the Felix block meant to be inert?), #510 (keep or delete this file). Four decisions,
   no engineering time.
6. **Then the housekeeping:** #507 (pause image), #454, #456, #469, #442's `upgrade: dist`, #452's
   reservation math, #445's dry run.
7. **Merge the branch.** 42 commits of fixes sitting on `feat/solving_issue_486` protect nobody.
8. **Close what is done on GitHub.** The great majority of the 61 tickets are complete in code and
   still read as open, which is why this file had to be derived from the tree rather than the
   tracker.
