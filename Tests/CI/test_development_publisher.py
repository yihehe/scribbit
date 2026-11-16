import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import urllib.error

SCRIPT = Path(__file__).resolve().parents[2] / "Scripts/publish-development.py"
spec = importlib.util.spec_from_file_location("publisher", SCRIPT)
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
BASE = "/repos/example/scribbit"
SHA = "a" * 40
OLD_SHA = "b" * 40


class FakeGitHub:
    """Stateful API contract double: no HTTP, token, account or release writes."""
    def __init__(self, existing=True, draft_creates_tag=False):
        self.release = ({"id": 1, "prerelease": True, "draft": False, "immutable": False,
                         "body": "<!-- scribbit-development-run: 10 -->"} if existing else None)
        self.tag = OLD_SHA if existing else None
        self.tag_type = "commit"
        self.assets = ({2: {"id": 2, "name": publisher.ASSET, "content": b"old"}} if existing else {})
        self.calls = []
        self.fail = lambda method, path, payload: False
        self.bad_upload = False
        self.draft_creates_tag = draft_creates_tag

    def request(self, method, path, payload=None, *, missing=False, upload=None):
        self.calls.append((method, path, copy.deepcopy(payload)))
        if self.fail(method, path, payload):
            raise RuntimeError("Injected API failure")
        if method == "GET" and path == BASE + "/releases/tags/development":
            return copy.deepcopy(self.release)
        if method == "GET" and path == BASE + "/git/ref/tags/development":
            return {"object": {"type": self.tag_type, "sha": self.tag}} if self.tag else None
        if method == "POST" and path == BASE + "/releases":
            self.release = {"id": 1, "immutable": False, **payload}
            if self.draft_creates_tag:
                self.tag = payload["target_commitish"]
            return copy.deepcopy(self.release)
        if method == "GET" and path == BASE + "/releases/1/assets?per_page=100":
            return [copy.deepcopy(asset) for asset in self.assets.values()]
        if method == "POST" and path.startswith(BASE + "/releases/1/assets?"):
            from urllib.parse import parse_qs, urlsplit
            asset = {"id": 3, "name": parse_qs(urlsplit(path).query)["name"][0],
                     "state": "uploaded", "size": len(upload), "content": upload,
                     "digest": "sha256:" + hashlib.sha256(upload).hexdigest()}
            if self.bad_upload:
                asset["digest"] = "sha256:wrong"
            self.assets[3] = asset
            return copy.deepcopy(asset)
        if method == "POST" and path == BASE + "/git/refs":
            if self.tag:
                raise RuntimeError("Tag already exists")
            self.tag = payload["sha"]
            return {}
        if method == "PATCH" and path == BASE + "/git/refs/tags/development":
            self.tag = payload["sha"]
            return {}
        if method == "DELETE" and path == BASE + "/git/refs/tags/development":
            self.tag = None
            return None
        if path.startswith(BASE + "/releases/assets/"):
            asset_id = int(path.rsplit("/", 1)[1])
            if method == "DELETE":
                del self.assets[asset_id]
                return None
            if method == "PATCH":
                if any(a["id"] != asset_id and a["name"] == payload["name"] for a in self.assets.values()):
                    raise RuntimeError("Duplicate asset name")
                self.assets[asset_id].update(payload)
                return copy.deepcopy(self.assets[asset_id])
        if method == "PATCH" and path == BASE + "/releases/1":
            self.release.update(payload)
            return copy.deepcopy(self.release)
        raise AssertionError(f"Unexpected API operation: {method} {path}")


class PublisherTests(unittest.TestCase):
    def setUp(self):
        build = Path(__file__).resolve().parents[2] / "build"
        build.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=build)
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.archive = b"a disposable signed-app ZIP fixture"
        (self.directory / publisher.ASSET).write_bytes(self.archive)
        self.metadata = {"commit": SHA, "architecture": "arm64",
                         "sha256": hashlib.sha256(self.archive).hexdigest()}
        self.write_metadata()
        self.env = {"GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/heads/main",
                    "GITHUB_REPOSITORY": "example/scribbit", "GITHUB_SHA": SHA,
                    "GITHUB_RUN_NUMBER": "11", "GITHUB_RUN_ID": "123"}

    def write_metadata(self):
        (self.directory / "build-metadata.json").write_text(json.dumps(self.metadata))

    def publish(self, api):
        return publisher.publish(api, self.env, self.directory)

    def assert_old_download(self, api):
        active = [a for a in api.assets.values() if a["name"] == publisher.ASSET]
        self.assertEqual([a["content"] for a in active], [b"old"])
        self.assertEqual(api.tag, OLD_SHA)

    def test_first_publication_with_either_draft_tag_behavior(self):
        for auto_tag in [False, True]:
            with self.subTest(draft_creates_tag=auto_tag):
                api = FakeGitHub(existing=False, draft_creates_tag=auto_tag)
                self.assertTrue(self.publish(api))
                self.assertEqual(api.tag, SHA)
                self.assertTrue(api.release["prerelease"])
                self.assertFalse(api.release["draft"])
                self.assertEqual(api.release["make_latest"], "false")
                self.assertEqual(api.assets[3]["name"], publisher.ASSET)

    def test_update_uploads_before_replacing_old_and_reports_source(self):
        api = FakeGitHub()
        self.assertTrue(self.publish(api))
        self.assertEqual(list(api.assets), [3])
        self.assertEqual(api.assets[3]["name"], publisher.ASSET)
        self.assertEqual(api.tag, SHA)
        self.assertIn(SHA, api.release["body"])
        self.assertIn("arm64", api.release["body"])
        self.assertIn("run: 11", api.release["body"])
        upload = next(i for i, call in enumerate(api.calls) if call[0] == "POST")
        rename = next(i for i, call in enumerate(api.calls) if call[0] == "PATCH")
        self.assertLess(upload, rename)

    def test_older_run_cannot_replace_a_newer_success(self):
        api = FakeGitHub()
        self.env["GITHUB_RUN_NUMBER"] = "9"
        self.assertFalse(self.publish(api))
        self.assertEqual(len(api.calls), 1)
        self.assert_old_download(api)

    def test_retry_of_same_run_can_repair_publication(self):
        api = FakeGitHub()
        self.env["GITHUB_RUN_NUMBER"] = "10"
        self.assertTrue(self.publish(api))

    def test_untrusted_events_never_call_api(self):
        for event, ref in [("pull_request", "refs/pull/1/merge"), ("push", "refs/heads/feature"),
                           ("push", "refs/tags/development"), ("workflow_dispatch", "refs/heads/main")]:
            with self.subTest(event=event, ref=ref):
                self.env.update(GITHUB_EVENT_NAME=event, GITHUB_REF=ref)
                api = FakeGitHub()
                with self.assertRaises(ValueError):
                    self.publish(api)
                self.assertEqual(api.calls, [])

    def test_wrong_commit_or_checksum_never_mutates_release(self):
        for key in ["commit", "sha256"]:
            with self.subTest(key=key):
                self.metadata[key] = "wrong"
                self.write_metadata()
                api = FakeGitHub()
                with self.assertRaises(ValueError):
                    self.publish(api)
                self.assertEqual(api.calls, [])
                self.metadata[key] = SHA if key == "commit" else hashlib.sha256(self.archive).hexdigest()

    def test_invalid_workflow_identity_is_rejected_before_api_calls(self):
        for key, value in [("GITHUB_REPOSITORY", "../scribbit"), ("GITHUB_SHA", "not-a-sha"),
                           ("GITHUB_RUN_NUMBER", "0"), ("GITHUB_RUN_ID", "not-a-run")]:
            with self.subTest(key=key):
                before = self.env[key]
                self.env[key] = value
                api = FakeGitHub()
                with self.assertRaises(ValueError):
                    self.publish(api)
                self.assertEqual(api.calls, [])
                self.env[key] = before

    def test_immutable_or_stable_release_is_not_overwritten(self):
        for field, value in [("immutable", True), ("prerelease", False)]:
            with self.subTest(field=field):
                api = FakeGitHub()
                api.release[field] = value
                with self.assertRaises(ValueError):
                    self.publish(api)
                self.assert_old_download(api)

    def test_upload_failure_or_bad_digest_keeps_previous_download(self):
        for bad_digest in [False, True]:
            with self.subTest(bad_digest=bad_digest):
                api = FakeGitHub()
                api.bad_upload = bad_digest
                if not bad_digest:
                    api.fail = lambda m, p, _: m == "POST" and "/assets?" in p
                with self.assertRaises((RuntimeError, ValueError)):
                    self.publish(api)
                self.assert_old_download(api)

    def test_failed_asset_promotion_or_release_edit_rolls_back(self):
        for release_edit in [False, True]:
            with self.subTest(release_edit=release_edit):
                api = FakeGitHub()
                api.fail = lambda m, p, data: m == "PATCH" and (
                    p == BASE + "/releases/1" if release_edit else
                    p == BASE + "/releases/assets/3" and data["name"] == publisher.ASSET)
                with self.assertRaises(RuntimeError):
                    self.publish(api)
                self.assert_old_download(api)
                self.assertNotIn(3, api.assets)

    def test_protected_tag_failure_does_not_replace_download(self):
        api = FakeGitHub()
        api.fail = lambda m, p, _: m == "PATCH" and "/git/refs/" in p
        with self.assertRaises(RuntimeError):
            self.publish(api)
        self.assert_old_download(api)

    def test_failed_first_publication_leaves_no_public_release_and_can_retry(self):
        api = FakeGitHub(existing=False)
        api.fail = lambda m, p, _: m == "PATCH" and p == BASE + "/releases/1"
        with self.assertRaises(RuntimeError):
            self.publish(api)
        self.assertTrue(api.release["draft"])
        self.assertIsNone(api.tag)
        self.assertEqual(api.assets, {})
        api.fail = lambda *args: False
        self.assertTrue(self.publish(api))
        self.assertFalse(api.release["draft"])

    def test_backup_cleanup_failure_does_not_undo_successful_publication(self):
        api = FakeGitHub()
        api.fail = lambda m, p, _: m == "DELETE" and p == BASE + "/releases/assets/2"
        self.assertTrue(self.publish(api))
        self.assertEqual(api.assets[3]["name"], publisher.ASSET)
        self.assertTrue(api.assets[2]["name"].startswith("previous-"))
        self.assertEqual(api.tag, SHA)

    def test_excess_assets_and_annotated_tag_fail_closed(self):
        api = FakeGitHub()
        api.tag_type = "tag"
        with self.assertRaises(ValueError):
            self.publish(api)
        self.assert_old_download(api)
        api = FakeGitHub()
        api.assets.update({i: {"id": i, "name": f"unexpected-{i}"} for i in range(10, 110)})
        with self.assertRaises(ValueError):
            self.publish(api)
        self.assert_old_download(api)


class HTTPClientTests(unittest.TestCase):
    def test_upload_uses_upload_host_and_binary_body(self):
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = b'{"id": 1}'
        with mock.patch.object(publisher.urllib.request, "urlopen", return_value=response) as open_url:
            result = publisher.GitHub("test-only-token").request(
                "POST", "/repos/example/scribbit/releases/1/assets?name=test.zip", upload=b"ZIP")
        request = open_url.call_args.args[0]
        self.assertTrue(request.full_url.startswith("https://uploads.github.com/"))
        self.assertEqual(request.data, b"ZIP")
        self.assertEqual(request.get_header("Content-type"), "application/zip")
        self.assertEqual(result, {"id": 1})

    def test_only_explicit_404_is_missing_and_error_does_not_log_token(self):
        for status in [404, 403, 500]:
            with self.subTest(status=status):
                error = urllib.error.HTTPError("https://api.github.com/test", status, "failure", {}, None)
                with mock.patch.object(publisher.urllib.request, "urlopen", side_effect=error):
                    client = publisher.GitHub("test-only-token")
                    if status == 404:
                        self.assertIsNone(client.request("GET", "/test", missing=True))
                    else:
                        with self.assertRaises(RuntimeError) as result:
                            client.request("GET", "/test", missing=True)
                        self.assertNotIn("test-only-token", str(result.exception))


if __name__ == "__main__":
    unittest.main()
