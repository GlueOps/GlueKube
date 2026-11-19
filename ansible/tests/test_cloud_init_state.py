"""Unit tests for playbooks/files/cloud_init_state.py.

Run with `python3 -m unittest discover -s ansible/tests` (the molecule workflow's lint job does).
Each case is a fixture of what a node would show: its cloud-config, the first-boot marker, this
boot's id, and `cloud-init status --format json` with its rc.
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "playbooks", "files"))

import cloud_init_state as cis  # noqa: E402

BOOT1 = "11111111-1111-1111-1111-111111111111"
BOOT2 = "22222222-2222-2222-2222-222222222222"

MANAGED_CONFIG = "#cloud-config\nwrite_files:\n- path: /usr/local/sbin/gluekube-first-boot-marker\n" \
                 "  content: |\n    out=%s\n" % cis.MARKER
LEGACY_CONFIG = "#cloud-config\npower_state:\n  mode: reboot\n"

DONE = {"status": "done", "errors": [], "recoverable_errors": {}}
ERROR = {"status": "error",
         "errors": ["('scripts_user', RuntimeError('Runparts: 1 failures (runcmd) in 1 attempted commands'))"],
         "recoverable_errors": {}}
WARN = {"status": "done", "errors": [],
        "recoverable_errors": {"WARNING": ["Invalid cloud-config provided: mounts ..."]}}
RUNNING = {"status": "running", "errors": [], "recoverable_errors": {}}


def marker(boot_id, status):
    return json.dumps({"boot_id": boot_id, "cloud_init": status})


class Classify(unittest.TestCase):

    def state(self, **kw):
        args = dict(cloud_config=MANAGED_CONFIG, marker_text=None, boot_id=BOOT2,
                    status=DONE, status_rc=0)
        args.update(kw)
        return cis.classify(**args)

    def test_legacy_node_without_marker_in_config(self):
        r = self.state(cloud_config=LEGACY_CONFIG, status=ERROR, status_rc=1)
        self.assertEqual(r["state"], "legacy")
        self.assertEqual(r["rc"], 1)
        self.assertEqual(len(r["errors"]), 1)

    def test_provisioning_while_cloud_init_runs(self):
        self.assertEqual(self.state(status=RUNNING, status_rc=0)["state"], "provisioning")

    def test_pending_before_marker_is_written(self):
        self.assertEqual(self.state(marker_text=None)["state"], "pending")

    def test_pending_when_marker_is_from_this_boot(self):
        r = self.state(boot_id=BOOT1, marker_text=marker(BOOT1, DONE))
        self.assertEqual(r["state"], "pending")

    def test_pending_ignores_trailing_newline_in_boot_id(self):
        r = self.state(boot_id=BOOT1 + "\n", marker_text=marker(BOOT1, DONE))
        self.assertEqual(r["state"], "pending")

    def test_ready_after_clean_first_boot(self):
        r = self.state(marker_text=marker(BOOT1, DONE))
        self.assertEqual(r["state"], "ready")
        self.assertEqual(r["errors"], [])

    def test_failed_first_boot_is_caught_though_boot2_says_done(self):
        # The case the old wait let through: boot 2 reports done/rc 0, boot 1 had a runcmd error.
        r = self.state(marker_text=marker(BOOT1, ERROR), status=DONE, status_rc=0)
        self.assertEqual(r["state"], "failed")
        self.assertIn("Runparts", r["errors"][0])

    def test_failed_when_first_boot_still_running_at_reboot(self):
        r = self.state(marker_text=marker(BOOT1, RUNNING))
        self.assertEqual(r["state"], "failed")
        self.assertIn("timeout", r["reason"])

    def test_failed_on_unparsable_marker(self):
        self.assertEqual(self.state(marker_text="{not json")["state"], "failed")

    def test_failed_on_marker_without_status(self):
        self.assertEqual(self.state(marker_text=marker(BOOT1, None))["state"], "failed")

    def test_failed_when_current_boot_fails(self):
        r = self.state(marker_text=marker(BOOT1, DONE), status=ERROR, status_rc=1)
        self.assertEqual(r["state"], "failed")

    def test_warnings_pass_and_are_reported(self):
        # rc 2 (recoverable errors) must not fail a node: every AWS node logs a mounts warning.
        r = self.state(marker_text=marker(BOOT1, WARN), status=WARN, status_rc=2)
        self.assertEqual(r["state"], "ready")
        self.assertEqual(r["warnings"], ["WARNING: Invalid cloud-config provided: mounts ..."])
        self.assertTrue(r["warnings"][0].startswith("WARNING: "))


if __name__ == "__main__":
    unittest.main()
