"""Offline assertions for security/release-gating contracts in the CI workflow."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WebEditorWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        cls.web = cls.workflow.split("  web-editor:\n", 1)[1].split("  macos:\n", 1)[0]
        cls.release = cls.workflow.split("  development-release:\n", 1)[1]

    def test_web_job_is_read_only_pinned_and_does_not_checkout_pr_head(self):
        self.assertIn("permissions:\n  contents: read", self.workflow)
        self.assertNotIn("permissions:", self.web)
        self.assertEqual(self.workflow.count("contents: write"), 1)
        actions = re.findall(r"uses: ([^\s]+)", self.web)
        self.assertEqual(len(actions), 2)
        for action in actions:
            self.assertRegex(action, r"^actions/(checkout|setup-node)@[0-9a-f]{40}$")
        self.assertIn("node-version: '22.23.5'", self.web)
        self.assertIn("package-manager-cache: false", self.web)
        self.assertIn("persist-credentials: false", self.web)
        self.assertIn("ref: ${{ github.sha }}", self.web)
        self.assertNotIn("pull_request.head", self.web)
        self.assertNotIn("secrets.", self.web)

    def test_locked_install_runs_no_lifecycle_scripts_and_tests_regenerated_bundle(self):
        self.assertIn("working-directory: WebEditor/Milkdown", self.web)
        self.assertIn("npm --userconfig=/dev/null --registry=https://registry.npmjs.org ci --ignore-scripts --no-audit --no-fund", self.web)
        self.assertIn("npm_config_ignore_scripts: 'true'", self.web)
        self.assertIn("npm run build\n          npm test", self.web)
        self.assertIn("git diff --exit-code --", self.web)
        for output in ["MilkdownEditor.js", "MilkdownStyle.css", "MilkdownNotices.txt", "MilkdownAssets.json", "runtime-dependencies.json"]:
            self.assertIn(output, self.web)

    def test_rolling_release_requires_both_jobs_and_keeps_macos_artifact_identity(self):
        self.assertIn("needs: [macos, web-editor]", self.release)
        self.assertIn("name: ${{ needs.macos.outputs.artifact }}", self.release)
        self.assertIn("if: github.event_name == 'push' && github.ref == 'refs/heads/main'", self.release)
        self.assertIn("cancel-in-progress: false", self.release)
        self.assertIn("ref: ${{ github.sha }}", self.release)
        self.assertIn("persist-credentials: false", self.release)
