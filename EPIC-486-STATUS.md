# GlueKube Ansible review (#486) — what is still unfinished

Assessed **2026-08-19** against `origin/feat/solving_issue_486` @ `756e07c`, which is **16 commits
ahead of `main` and not merged**. Every "done" below therefore means *done on that branch*, not
shipped. `main` @ `27a2ae9` still contains none of this work.

All 10 epics and all 61 tickets are still **OPEN on GitHub** — nothing has been closed out, so the
tracker is not a usable status signal. This file is the code-derived status instead.

## Scoreboard

| Epic | Theme | Done | Partial | Open | Verdict |
|---|---|---|---|---|---|
| **B** #424 | Control plane taken down all at once | 5 | 0 | 0 | ✅ **Finished** (1 accepted risk) |
| **E** #446 | Upgrades have no safety rails | 5 | 1 | 0 | 🟢 Nearly finished — only #447 left |
| **G** #459 | CI cannot catch regressions | 4 | 1 | 0 | 🟢 Nearly finished |
| **A** #415 | Sync/scale destroys or skips nodes | 5 | 1 | 2 | 🟡 Two real gaps left |
| **H** #465 | Variable plumbing, tooling, docs | 5 | 1 | 1 | 🟡 Two gaps left |
| **I** #473 | Duplication and misleading names | 3 | 2 | 0 | 🟡 Deferred items only |
| **D** #439 | Re-runs unsafe against a live cluster | 4 | 2 | 0 | 🟡 Two halves left |
| **C** #431 | Credentials static / world-readable | 1 | 2 | 0 | 🟡 4 of 7 accepted as won't-do |
| **F** #453 | Nexus mirror, apt signatures | 2 | 0 | 3 | 🟠 Two gated on an unanswered question |
| **J** #479 | Calico policy and config defects | 1 | 0 | 5 | 🔴 **Largely untouched** |

**Epic J (#479) is now the one to tackle next.** #448, #449, #450 and #451 were fixed on
2026-08-19 (see the Epic E table); #447 — the etcd snapshot before `kubeadm upgrade apply` — is
the only thing left in E, and it is the single highest-value item remaining anywhere.

---

## 🟢 Epic E #446 — Upgrades have no safety rails (5 of 6 done)

Four of the five open findings were fixed on **2026-08-19**. What remains is #447, the one that
matters most: there is still no etcd snapshot taken before the upgrade begins.

| # | Finding | Status | Evidence |
|---|---|---|---|
| #447 | No etcd snapshot, no upgrade gate, no version-skew check | **OPEN** | `grep -rn "snapshot save\|skew"` across `roles/` and `playbooks/` returns nothing. `first-node-upgrade.yaml` runs `kubeadm upgrade apply {{ kubernetes_version }} -y` with no backup ahead of it. |
| #448 | Worker kubelet patches silently discarded at first upgrade | ✅ **DONE** (2026-08-19) | Every kubeadm call that rewrites a kubelet config now re-renders the patch and passes `--patches /etc/kubernetes/patches`: `worker/tasks/upgrade.yaml`, `master/tasks/upgrade.yaml`, `master/tasks/first-node-upgrade.yaml`. The render is shared via `render-kubelet-patch.yaml` in each role, because the join-time render is gated on the node not already being in the cluster and so never re-runs. |
| #449 | Secondary masters have no kubelet patch mechanism at all | ✅ **DONE** (2026-08-19) | `master/templates/kubeletConfigurationPatch.yaml.j2` added and `patches.directory` added to `master/templates/kubeadm-join-config.j2`; rendered before the join in both `master/tasks/join-nodes.yaml` and `master/tasks/master-node-rotation/join-nodes.yaml`. Its expressions are identical to the ones in `kubeadm-stacked-config.yaml.j2`, so on a homogeneous control plane the patch is a no-op — verified by rendering both at 2 vCPU/4 GiB and 8 vCPU/32 GiB. |
| #450 | Cert rotation overwrites cluster-wide `ClusterConfiguration` from local state | ✅ **DONE** (2026-08-19) | `rotate-certs-with-config.yaml` now fetches the live ClusterConfiguration, compares the env-derived fields (`kubernetesVersion`, `controlPlaneEndpoint`, `networking`, `certSANs`, apiserver `extraArgs`), prints the difference and fails unless `-e allow_config_change=true`. The upload runs **only** on that opt-in. The comparison is deliberately field-scoped, not whole-document — kubeadm normalises what it stores, so a full equality check would fail every run. |
| #451 | `AuthenticationConfiguration` pins an apiVersion requiring Kubernetes 1.34 | ✅ **DONE** (2026-08-19) | The template now selects `v1` at ≥1.34 and `v1beta1` below it. The preflight floor dropped from 1.34 to **1.31**, which is the repo's real minimum — it comes from `kubeadm.k8s.io/v1beta4` in `kubeadm-stacked-config.yaml.j2`, not from this file. Stale `1.32.6-1.1` examples in `inventory/group_vars` and all three molecule inventories updated to the actual CI/Dockerfile pin. |
| #452 | Housekeeping: kubeadm hold asymmetry, kubelet reservation math | **PARTIAL** | Hold asymmetry fixed — `roles/common/tasks/upgrade-kubeadm.yaml:51` and `upgrade-kubelet.yaml:20,26` now hold symmetrically. The reservation math in `kubeadm-stacked-config.yaml.j2:107-123` was not revisited. |

**#447 is what is left, and it is the highest-value item in the whole review**: an etcd snapshot
is the only thing standing between a failed `kubeadm upgrade apply` and an unrecoverable cluster.

Verification of the four fixes: all touched YAML parses; `ansible-playbook --syntax-check` passes
on `preflight.yaml`, `upgrade-cluster.yaml`, `rotate-certs-with-config.yaml` and on a probe
playbook that statically imports every changed task file so the nested `import_tasks` are walked;
the authn template was rendered at 1.31/1.33/1.34/1.40; the #450 comparison was exercised against
a kubeadm-normalised ConfigMap (passes), a stale `.env` (fails) and a missing ConfigMap (fails).
None of this has been run against a live cluster or through molecule.

## 🔴 Epic J #479 — Calico policy and configuration defects (1 of 6 done)

| # | Finding | Status | Evidence |
|---|---|---|---|
| #480 | `allow-all-egress` GNP nullifies every Kubernetes egress NetworkPolicy | **OPEN** | `calico-global-network-policy.yaml.j2:26-32` — the policy was *renamed* to `allow-all-egress-lb-nodes` but its `selector` is still `all()`. The name now claims a scope the selector does not implement, which is worse than before: it reads as fixed. |
| #481 | Merge the two Calico value templates | **OPEN** | `calico.yaml.j2` and `calico-without-firstFound.yaml.j2` are both live, selected at `install-calico.yaml:3` and `:10`. |
| #482 | `install-calico` only waits for the operator, not Calico | ✅ **DONE** | `install-calico.yaml:54-69` now waits for the `calico-node` daemonset and its rollout. |
| #483 | LB nodes without a public-interface file are silently skipped | **OPEN** | `apply-calico-firewall.yaml:52-60` — `failed_when: false`, then `selectattr('rc','equalto',0) \| rejectattr('stdout','equalto','')`. A node that fails the read is dropped from the map with no warning and simply never gets a HostEndpoint. |
| #484 | Felix configuration gated on the WireGuard toggle | **OPEN** | `calico.yaml.j2:93-96` — `defaultFelixConfiguration.enabled` is `{{ calico_node_to_node_encryption \| bool }}`, so turning encryption off also discards `logSeverityScreen`. |
| #485 | Question: is `email_verified` fail-closed intentional? | **UNANSWERED** | Needs a decision, not code. |

#480 is the one to fix first — it is listed in the tracker's own suggested start order and it means
every egress NetworkPolicy in the cluster is currently inert.

---

## 🟠 Epic F #453 — Nexus mirror and apt signatures (2 of 5)

| # | Status | Note |
|---|---|---|
| #454 `allow_unauthenticated: true` | **OPEN** | 4 sites remain: `common/tasks/prepare-node.yaml:234,257`, `upgrade-kubeadm.yaml:41`, `upgrade-kubelet.yaml:12`. It was 7 before; the drop is de-duplication (#474), not a fix. |
| #455 Calico/metrics-server/local-path images not mirrored | **GATED** | Blocked on the open question *"is airgapped/mirror-only an actual requirement?"* — unanswered on #453. |
| #456 Seven public hosts contacted, no checksums | **GATED** | Same question. |
| #457 Pin collections with `requirements.yml` | ✅ **DONE** | `ansible/requirements.yml` pins 5 collections; CI installs from it. |
| #458 Deprecated `apt_key`, unreferenced mirror template | ✅ **DONE** | Only a comment mentions `apt_key` now. |

**Answering the airgapped question unblocks two tickets at once** and is the cheapest thing on this
list — it is a decision, not work.

## 🟡 Epic A #415 — Sync and scale (5 of 8, 2 genuinely open)

| # | Status | Note |
|---|---|---|
| #416 Node diff returns every node when kubectl fails | ✅ **DONE** | `collect-node-lists.yaml` now has `set -euo pipefail` plus a "refuse to diff against an empty cluster" assert. |
| #417 Restore the confirmation gate the README documents | **OPEN** | No `pause`/`prompt` exists on the sync or scale path. The only pauses are the inter-node ones in `upgrade-cluster.yaml`. A destructive scale-down still runs unattended. |
| #418 Master removal crashes on `hostvars` for de-inventoried nodes | ✅ **DONE** | `update-dns-records.yaml:15` matches IPs by node name instead of `hostvars[node]`. |
| #419 Rotation's `nodes_to_remove` returns all cluster nodes | **PARTIAL / by design** | Still returns every node (`master-node-rotation/compare-node.yaml`), now documented as deliberate and narrowed by `rotate-nodes.yaml:20-21` via `select('search','master')`. That narrowing is a **hostname substring match**, so a control-plane node not named `*master*` is silently excluded. Same root cause as the `scale-down.yaml` regex. |
| #420 Unanchored etcd member grep | ✅ **DONE** | `scale-down.yaml:38` uses `grep -P '(?<![\w-]){{ item }}(?![\w-])'`. |
| #421 Worker join substring matching | ✅ **DONE** | Now list membership against `stdout_lines`. |
| #422 Removed nodes are never reset and keep valid credentials | **OPEN** | `scale-down.yaml` cordons, drains, deletes and removes the etcd member — it never runs `kubeadm reset` on the departing node. |
| #423 Molecule coverage for control-plane scale-down | ✅ **DONE** | `side_effect/remove_control_plane.yaml` + `tests/test_scale_down.yaml`, wired into `molecule.yml`'s `test_sequence`. |

## 🟡 Epic H #465 — Plumbing, tooling, docs (5 of 7)

| # | Status | Note |
|---|---|---|
| #466 Preflight play | ✅ **DONE** | `playbooks/preflight.yaml`, imported by `setup-cluster.yaml` and `upgrade-cluster.yaml`, so molecule gets it too. |
| #467 `AUTOGLUE_ORG_ID` has no producer | ✅ **DONE** | `parser.py:73,156`. ⚠️ **But `parser.py:160` writes `AUTOGLUE_BASE_URL={autoglue_org_id}`** — the base URL is set to the org id. That looks like a new copy-paste bug introduced by the fix; worth a ticket. |
| #468 `parser.py` misses four version variables | ✅ **DONE** | `version_fields` at `parser.py:131-135`. |
| #469 `ansible.cfg` uses env-var names as ini keys | **OPEN** | Unchanged: `ANSIBLE_HOST_KEY_CHECKING="False"` and `ANSIBLE_ROLES_PATH=$PWD/roles` are still ini keys ansible does not read. Only `log_path` is valid. |
| #470 Makefile | ✅ **DONE** | The bare `export ;` that leaked credentials into #414 is gone; `.env` rule works outside the container. |
| #471 README haproxy / Terraform | ✅ **DONE** | `readme.md:69,166` now state that neither exists. |
| #472 `check-network-connectivity` reports success without checking | **PARTIAL** | It now runs `ansible.builtin.ping` with `any_errors_fatal`, which is a real check. But **every substantive probe is commented out** — the node-to-node private path, the mirror reachability, the `ctrp` lookup and the 2379/2380/6443 probes are all inert. The file reads as done and is roughly 15% done. |

## 🟡 Epic D #439 — Re-run safety (4 of 6)

| # | Status | Note |
|---|---|---|
| #440 containerd config rewritten, non-atomic window | ✅ **DONE** | Now `copy` with registered content — idempotent and atomic. |
| #441 containerd/kubelet restarted on every run | ✅ **DONE** | `state: "{{ 'restarted' if containerd_config_file is changed else 'started' }}"`. |
| #442 Every run dist-upgrades; kube packages never held at install | **PARTIAL** | The hold half is fixed (`prepare-node.yaml:246,264`). **`upgrade: dist` at `prepare-node.yaml:75` still runs on every single sync** — every `make sync` dist-upgrades every live node. |
| #443 Four `creates:` sentinels never written | ✅ **DONE** | All remaining `creates:` point at paths their task actually writes. |
| #444 Swap and kernel modules do not survive a reboot | ✅ **DONE** | fstab edit + `persistent: present` modprobe + `/etc/sysctl.d/99-kubernetes.conf`. |
| #445 No entrypoint survives `--check` | **PARTIAL** | `check_mode: false` added at the two places that need it (`select-orchestrator.yaml:27`, `sync.yaml:13`), but no dry run has been demonstrated end to end. Treat as unverified. |

## 🟡 Epic C #431 — Credentials (3 open of 7; 4 closed won't-do)

| # | Status | Note |
|---|---|---|
| #436 Etcd client cert copied into monitoring namespace | ✅ **DONE** | `create-etcd-secret.yaml` now publishes a scoped secret into a dedicated `etcd_secret_namespace`. |
| #437 Test VMs internet-exposed, image has no provenance | **PARTIAL** | Molecule `create.yml` now builds a Hetzner firewall and attaches it. Image provenance is not addressed. |
| #438 Tracked inventory file, third-party key generation | **PARTIAL** | Only `hosts.yaml.example` is tracked now. The key-generation half was not verified. |

> **Standing constraint, unchanged:** `ansible/ansible.log` must never be published. #433 was closed
> won't-do, so credentials keep landing in that file (`ansible.cfg:4`, no `no_log` anywhere) and
> `.gitignore` does not cover it. `GlueOps/GlueKube` is public and artifacts are world-downloadable.
> The CI artifact upload at `.github/workflows/molecule_test.yaml:186` uploads `~/.cache/molecule` —
> **confirm that path cannot contain `ansible.log` before merging**, since molecule copies the
> scenario tree into its cache.

## 🟢 Epic G #459 — CI (4 of 5)

#460 (PR trigger + `yamllint`/`ansible-lint` actually invoked), #461 (`concurrency:` present),
#462 (real molecule health checks) and #463 (`domain_name` produced in CI) are all done.
#464 is partial — artifacts, release race and test-inventory hygiene were not all addressed.

## ✅ Epic B #424 — Finished

#425 and #426 were resolved by **deleting `rotate-certs.yaml`** (the open question was answered:
yes, it was dead code superseded by `rotate-certs-with-config.yaml`). #427 was resolved the same
way — `playbooks/os-patch.yaml` and `roles/common/tasks/patch-os.yaml` are both gone. #429 has
`--cluster` on the etcd health probe. #430 is fixed by `select-orchestrator.yaml`, which probes
`/readyz` and falls back to `masters[0]` only during bootstrap; `orchestrator_node` now appears at
78 sites against 4 remaining `masters[0]` references, all inside the selector itself.

#428 (`kubectl drain --timeout`) is still absent but was **closed as not planned** — accepted risk.

## 🟡 Epic I #473 — Deferred items only

#474 (de-duplication), #475 (renames) and #478 (nits) are done. Two things were deliberately left:

- **#476** — the tag errors are fixed (`join_worker` → `join_master` on the control-plane join,
  `kubeconfig_setup` → `kubeadm_config`), but the duplicate *names* remain by choice: 9 ×
  "Select the orchestrator node", 6 × "Generate Kubeadm configuration", 4 × "Preflight",
  4 × "Generate Authentication Configuration". These are the same operation reached from different
  paths, so repeating the name is honest. Close or re-scope the ticket rather than leaving it open.
- **#477** — `.github/configs/workflows/bump_version.yaml` is still parked outside
  `.github/workflows/` and therefore inert. The ticket says *check with the team first*; moving it
  starts running release automation that has never run. **Needs a decision.**
- The two unnamed plays in `setup-cluster.yaml` were explicitly excluded from scope.

---

## What to do next

1. **Answer the three gating questions.** Airgapped/mirror-only (#453, unblocks #455 + #456),
   `email_verified` fail-closed (#485), and `bump_version.yaml` (#477). Three decisions clear four
   tickets and cost no engineering time.
2. **Epic J #480** — the `all()` selector on the allow-all-egress GNP. Every Kubernetes egress
   NetworkPolicy in the cluster is currently a no-op, and the rename makes it look handled.
3. **Epic E #447 and #448** — an etcd snapshot before `kubeadm upgrade apply`, and `--patches` on
   `kubeadm upgrade node`.
4. **Epic A #422 and #417** — reset departing nodes so their credentials die with them, and put the
   confirmation gate back in front of destructive scale operations.
5. **Merge the branch.** 16 commits of fixes sitting on `feat/solving_issue_486` protect nobody.
6. **Close what is done on GitHub.** 25+ tickets are complete on the branch and all 61 still read
   as open, which is why this file had to be derived from code.

### Cross-cutting item not in any ticket

Both #419 and the `scale-down.yaml` etcd-removal gate decide *"is this a control-plane node?"* by
**matching the hostname string** — `select('search','master')` at
`master-node-rotation/rotate-nodes.yaml:20-21` and `item is search("master-node-*")` in
`scale-down.yaml`. A control-plane node named anything else is silently skipped, leaving a phantom
etcd member counting toward quorum. `item in groups['masters']` is the fix in both places. This
deserves its own ticket under Epic A.
