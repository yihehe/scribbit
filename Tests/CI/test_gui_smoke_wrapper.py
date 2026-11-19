"""Validate the GUI runner's exit/marker contract without launching any UI."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
RICH_MARKERS = [
    "RICH_EDITOR_SMOKE_PASS", "RICH_BRIDGE_UNCHANGED_PASS",
    "RICH_BRIDGE_MODES_PASS", "RICH_BRIDGE_SAVE_CONFLICT_PASS",
    "RICH_BRIDGE_INVALID_REPLY_PASS", "RICH_BRIDGE_INACTIVE_TERMINATION_PASS",
    "RICH_BRIDGE_RECOVERY_PASS", "RICH_BRIDGE_RESTORE_RETRY_PASS",
]


class SmokeWrapperTests(unittest.TestCase):
    def run_wrapper(self, lines, exit_code=0, engine="rich"):
        (ROOT / ".build").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / ".build") as temporary:
            root = Path(temporary)
            app = root / "Fixture App.app"
            executable = app / "Contents/MacOS/Scribbit"
            executable.parent.mkdir(parents=True)
            executable.write_text("#!/bin/bash\ncat <<'MARKERS'\n"
                                  + "\n".join(lines)
                                  + f"\nMARKERS\nexit {exit_code}\n")
            executable.chmod(0o755)
            return subprocess.run(
                ["/bin/bash", str(ROOT / "Scripts/gui-smoke.sh"), engine, str(root / "output")],
                cwd=ROOT, env={**os.environ, "APP_PATH": str(app)},
                capture_output=True, text=True, timeout=10,
            ).returncode

    def test_complete_rich_run_succeeds(self):
        self.assertEqual(self.run_wrapper(RICH_MARKERS), 0)

    def test_missing_contract_marker_fails(self):
        for marker in RICH_MARKERS:
            with self.subTest(marker=marker):
                self.assertNotEqual(self.run_wrapper([m for m in RICH_MARKERS if m != marker]), 0)

    def test_process_failure_wins_over_pass_markers(self):
        self.assertEqual(self.run_wrapper(RICH_MARKERS, exit_code=7), 7)

    def test_logged_failure_wins_over_zero_exit(self):
        self.assertNotEqual(self.run_wrapper(RICH_MARKERS + ["RICH_EDITOR_SMOKE_FAIL: fixture"]), 0)

    def test_continuation_leak_wins_over_pass_markers(self):
        self.assertNotEqual(self.run_wrapper(RICH_MARKERS + ["SWIFT TASK CONTINUATION MISUSE: fixture"]), 0)

    def test_unknown_engine_is_rejected(self):
        self.assertEqual(self.run_wrapper(RICH_MARKERS, engine="unknown"), 64)

    def test_rich_pass_cannot_satisfy_native_gate(self):
        self.assertNotEqual(self.run_wrapper(RICH_MARKERS, engine="native"), 0)
