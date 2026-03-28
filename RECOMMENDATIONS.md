# GlueKube — Dead Code & Duplication Audit

**Date:** 2026-03-28
**Repo baseline:** ~8,672 lines across ~137 files on `main`

---

## How to read this document

- Items are grouped by priority (P0 = do first, P3 = do when convenient)
- **Status** shows whether the work was already done in the current PR or is still pending
- **Lines** = approximate lines of dead code that would be removed or deduplicated

---

## 🔴 P0 — CRITICAL (biggest impact, do first)

> Removing all Cilium code cuts **44% of the entire repo** in one shot. `cni_type` is hardcoded to `calico` in every inventory file; the Cilium path is never executed.

| # | Recommendation | File(s) | Lines | Status |
|---|----------------|---------|------:|--------|
| 1 | **Delete `cilium.yaml`** — vendored Cilium Helm values, never deployed | `ansible/roles/master/files/addons/cilium.yaml` | 3,797 | ❌ TODO |
| 2 | **Delete `install-cilium.yaml`** — Cilium install tasks, gated behind `cni_type == "cilium"` which is never true | `ansible/roles/master/tasks/install-cilium.yaml` | 60 | ❌ TODO |
| 3 | **Remove Cilium conditional block from `main.yaml`** — the `import_tasks: install-cilium.yaml when cni_type == "cilium"` block | `ansible/roles/master/tasks/main.yaml` | ~4 | ❌ TODO |
| 4 | **Remove Cilium variables from inventory** — `cilium_node_to_node_encryption` and `cilium_hubble_enabled` vars, and `# calico, cilium` comments | `*/inventory/group_vars/masters.yaml` (×4 files) | ~10 | ❌ TODO |

**P0 subtotal: ~3,871 lines (44.6% of repo)**

---

## 🟠 P1 — HIGH (dead files that are never executed)

> Files that exist on disk but are never applied or imported by any running task.

| # | Recommendation | File(s) | Lines | Status |
|---|----------------|---------|------:|--------|
| 5 | **Delete `felix.yaml`** — copied to nodes by `install-calico.yaml` but the `kubectl apply` is commented out; never applied | `ansible/roles/master/files/addons/felix.yaml` | 135 | ❌ TODO |
| 6 | **Delete `calico-hostendpoint.yaml`** — same situation as above | `ansible/roles/master/files/addons/calico-hostendpoint.yaml` | 6 | ❌ TODO |
| 7 | **Delete `calico-global-network-policy.yaml.j2`** — templated to node but the `kubectl apply` is commented out | `ansible/roles/master/templates/calico-global-network-policy.yaml.j2` | 17 | ❌ TODO |
| 8 | **Clean up `install-calico.yaml`** — remove the 3 copy/template tasks for the dead files above + the 13 commented-out `kubectl apply` lines | `ansible/roles/master/tasks/install-calico.yaml` | ~19 | ✅ Done |
| 9 | **Delete `test_node_to_node_encryption.yaml`** — Wireguard/encryption test, not referenced in any molecule `test_sequence` | `ansible/molecule/test-cluster/tests/test_node_to_node_encryption.yaml` | 36 | ✅ Done |
| 10 | **Delete `worker/tasks/compare-nodes.yaml`** — never imported by any task file | `ansible/roles/worker/tasks/compare-nodes.yaml` | 33 | ✅ Done |
| 11 | **Delete `worker/templates/containerd-config-hosts.toml.j2`** — never referenced by any task | `ansible/roles/worker/templates/containerd-config-hosts.toml.j2` | 27 | ✅ Done |
| 12 | **Delete `common/handlers/main.yml`** — empty handler file, never triggered | `ansible/roles/common/handlers/main.yml` | 5 | ✅ Done |
| 13 | **Delete `test_scale_down.yaml`** — not in any `test_sequence` | `ansible/molecule/scale-cluster/tests/test_scale_down.yaml` | 25 | ✅ Done |
| 14 | **Delete `.vscode/settings.json`** — contains hardcoded local path, should not be committed | `.vscode/settings.json` | 3 | ✅ Done |

**P1 subtotal: ~306 lines. ~148 already done, ~158 remaining.**

---

## 🟡 P2 — MEDIUM (commented-out code blocks, dead variables)

> Large blocks of commented-out code that add confusion and make the codebase harder to maintain.

| # | Recommendation | File(s) | Lines | Status |
|---|----------------|---------|------:|--------|
| 15 | **Remove commented-out code in `copy-join-command.yaml`** — commented-out copy block | `ansible/roles/master/tasks/copy-join-command.yaml` | ~10 | ✅ Done |
| 16 | **Remove commented-out code in `kubeadm-init.yaml`** — commented-out Cilium/Wireguard/containerd blocks | `ansible/roles/master/tasks/kubeadm-init.yaml` | ~27 | ✅ Done |
| 17 | **Remove commented-out code in `prepare-nodes.yaml`** — Wireguard install block (commented out) | `ansible/roles/master/tasks/prepare-nodes.yaml` | ~8 | ✅ Done |
| 18 | **Remove dead worker `copy-join-command.yaml` lines** — commented-out join command copy block | `ansible/roles/worker/tasks/copy-join-command.yaml` | ~11 | ✅ Done |
| 19 | **Remove stale Makefile stub targets** — `rotate-certs` and `upgrade-cluster` were echo-only stubs | `Makefile` | ~15 | ✅ Done |
| 20 | **Remove stale molecule converge lines** — commented-out test lines and dead `lb-init.yaml` include | `ansible/molecule/test-cluster/converge.yml` | ~5 | ✅ Done |
| 21 | **Remove stale `molecule.yml` commented lines** — `patch_os` comments | `ansible/molecule/test-cluster/molecule.yml` | ~2 | ✅ Done |
| 22 | **Remove dead import in `test_nodes_pingable.yaml`** — references non-existent group `loadbalancer` | `ansible/molecule/rotate-master-nodes/tests/test_nodes_pingable.yaml` | ~3 | ✅ Done |
| 23 | **Remove empty placeholder files** — 0-byte files committed to git that serve no purpose | `ansible/ansible.log`, `molecule/test-cluster/side_effect/patch_os_security.yaml`, `molecule/test-cluster/tests/test_patch_os_security.yaml` | 0 (clutter) | ❌ TODO |
| 24 | **Remove `calico_node_to_node_encryption` from workers.yaml** — set in `workers.yaml` files but only read via `masters` group vars in `calico.yaml.j2`; workers don't need it | `*/group_vars/workers.yaml` (×4 files) | ~4 | ❌ TODO |

**P2 subtotal: ~85 lines. ~81 already done, ~4 remaining + empty file cleanup.**

---

## 🟢 P3 — LOW (duplication, refactor when convenient)

> These are not dead code, but they are identical copies that could be consolidated to reduce maintenance burden.

| # | Recommendation | File(s) | Lines saveable | Status |
|---|----------------|---------|---------------:|--------|
| 25 | **Deduplicate cloud-init templates** — `cloud-init-master.yaml.j2` (21 lines) and `cloud-init-worker.yaml.j2` (22 lines) are **100% identical** across all 3 molecule scenarios. Could use a shared `molecule/_common/` directory or symlinks. | `*/cloudinit/cloud-init-{master,worker}.yaml.j2` (×6 files) | ~86 | ❌ TODO |
| 26 | **Deduplicate `verify.yaml`** — identical across all 3 scenarios (22 lines × 2 redundant copies) | `*/verify.yaml` (×3 files) | ~44 | ❌ TODO |
| 27 | **Deduplicate `compare-node.yaml`** — `tasks/compare-node.yaml` (58 lines) and `master-node-rotation/compare-node.yaml` (60 lines) differ by only 2 lines (kubectl vs. Python script). Could be parameterized. | `ansible/roles/master/tasks/{,master-node-rotation/}compare-node.yaml` | ~50 | ❌ TODO |
| 28 | **Deduplicate `copy-join-command.yaml`** — the rotation version (21 lines) is a subset of the main one. Could be refactored to reuse the main file. | `ansible/roles/master/tasks/master-node-rotation/copy-join-command.yaml` | ~21 | ❌ TODO |
| 29 | **Deduplicate `masters.yaml` group_vars** — nearly identical across main inventory + 3 molecule scenarios (only 1 URL differs). Could use a shared defaults file. | `*/group_vars/masters.yaml` (×4 files) | ~50 | ❌ TODO |
| 30 | **Evaluate the `common` role** — `roles/common/tasks/main.yaml` is just a comment (1 line). The role does nothing when included. `patch-os.yaml` is only called by the standalone `os-patch.yaml` playbook. Consider inlining or removing the role structure. | `ansible/roles/common/` | ~17 | ❌ TODO |

**P3 subtotal: ~268 lines of duplication that could be consolidated.**

---

## Summary Table

| Priority | Description | Lines removable | Already done | Remaining |
|----------|-------------|----------------:|-------------:|----------:|
| **P0** | Cilium dead code removal | 3,871 | 0 | **3,871** |
| **P1** | Orphaned / dead files | 306 | 148 | **158** |
| **P2** | Commented-out blocks & dead vars | 85 | 81 | **4** |
| **P3** | Deduplication / refactoring | 268 | 0 | **268** |
| **Total** | | **4,530** | **229** | **4,301** |

**Bottom line:** The repo can be reduced from **8,672 → ~4,371 lines** — roughly a **50% reduction**. The single biggest win is deleting `cilium.yaml` which alone accounts for 3,797 lines (44% of the repo).

### Suggested execution order

1. **Items 1–4** (Cilium) → one PR, immediate — this is the elephant in the room
2. **Items 5–7** (dead Calico artifacts) → same or follow-up PR
3. **Items 23–24** (empty files, dead vars) → quick cleanup PR
4. **Items 25–30** (deduplication) → refactoring PR when convenient
