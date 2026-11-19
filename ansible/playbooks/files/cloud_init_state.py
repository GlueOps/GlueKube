#!/usr/bin/env python3
"""Classify a node's cloud-init state for playbooks/wait-for-cloud-init.yaml.

Run on the node (ansible.builtin.script, as root). Waits for cloud-init to finish, then prints one
JSON object:

    {"state": "...", "reason": "...", "rc": <status rc>, "errors": [...], "warnings": [...]}

States:

    legacy        the cloud-config does not mention the first-boot marker: a node built before
                  opentofu-module-GlueKube-cloudinit wrote one. Judged on today's status only,
                  and only warned about.
    provisioning  cloud-init is still running.
    pending       no marker yet, or the marker was written during this boot: the power_state
                  reboot has not happened yet.
    failed        a new boot, and the marker records first-boot errors, says cloud-init was still
                  running when it was written (power_state's timeout fired first), or can't be
                  parsed; or this boot's own cloud-init failed.
    ready         a new boot, a clean marker, and this boot's status rc is 0 or 2.

Boot 1 is told apart from boot 2 by /proc/sys/kernel/random/boot_id, not by timestamps, so a
clock correction during first boot cannot fool it.

classify() is pure, so tests/test_cloud_init_state.py can drive it from fixtures.
"""

import json
import subprocess
import sys

MARKER = "/var/lib/cloud/instance/first-boot.json"
CLOUD_CONFIG = "/var/lib/cloud/instance/cloud-config.txt"
BOOT_ID = "/proc/sys/kernel/random/boot_id"


def _errors(status):
    """The errors and warnings in a `cloud-init status --format json` object."""
    if not isinstance(status, dict):
        return [], []
    errors = [str(e) for e in status.get("errors") or []]
    warnings = []
    recoverable = status.get("recoverable_errors") or {}
    if isinstance(recoverable, dict):
        for level, messages in recoverable.items():
            warnings += ["%s: %s" % (level, m) for m in messages or []]
    return errors, warnings


def classify(cloud_config, marker_text, boot_id, status, status_rc):
    """Return the result dict for one node.

    cloud_config  text of the instance cloud-config ("" if unreadable)
    marker_text   text of the first-boot marker, or None if it does not exist
    boot_id       this boot's id
    status        `cloud-init status --format json` for this boot, parsed (None if unparsable)
    status_rc     its exit code
    """
    errors, warnings = _errors(status)
    current = status.get("status") if isinstance(status, dict) else None
    result = {"rc": status_rc, "errors": errors, "warnings": warnings}

    if MARKER not in cloud_config:
        return dict(result, state="legacy",
                    reason="cloud-config predates the first-boot marker")

    if current in ("running", "not started", "not run"):
        return dict(result, state="provisioning", reason="cloud-init status: %s" % current)

    if marker_text is None:
        return dict(result, state="pending", reason="first-boot marker not written yet")

    try:
        marker = json.loads(marker_text)
        marker_boot = marker["boot_id"]
        first = marker["cloud_init"]
    except (ValueError, KeyError, TypeError) as exc:
        return dict(result, state="failed",
                    reason="first-boot marker is unparsable (%s)" % exc)

    if marker_boot.strip() == boot_id.strip():
        return dict(result, state="pending", reason="power_state reboot has not happened yet")

    first_errors, first_warnings = _errors(first)
    # Boot 2 usually repeats boot 1's schema warnings; report each once.
    result["warnings"] = list(dict.fromkeys(first_warnings + warnings))
    first_status = first.get("status") if isinstance(first, dict) else None

    if not isinstance(first, dict):
        return dict(result, state="failed", errors=first_errors,
                    reason="first-boot marker holds no cloud-init status")
    if first_status == "running":
        return dict(result, state="failed", errors=first_errors,
                    reason="cloud-init was still running when the first boot rebooted "
                           "(power_state's timeout fired first)")
    if first_errors or first_status == "error":
        return dict(result, state="failed", errors=first_errors,
                    reason="cloud-init reported %d error(s) before its reboot" % len(first_errors))
    if status_rc not in (0, 2):
        return dict(result, state="failed",
                    reason="cloud-init failed on the current boot (rc=%s)" % status_rc)

    return dict(result, state="ready", reason="first boot clean, reboot done")


def _read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None


def main():
    proc = subprocess.run(
        ["cloud-init", "status", "--wait", "--format", "json"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, universal_newlines=True,
    )
    try:
        status = json.loads(proc.stdout)
    except ValueError:
        status = None
    result = classify(
        cloud_config=_read(CLOUD_CONFIG) or "",
        marker_text=_read(MARKER),
        boot_id=_read(BOOT_ID) or "",
        status=status,
        status_rc=proc.returncode,
    )
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
