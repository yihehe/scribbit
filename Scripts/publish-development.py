#!/usr/bin/env python3
"""Publish one mutable prerelease. Run only in the trusted main-push CI job."""
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

TAG = "development"
ASSET = "Scribbit-macOS.zip"
MARKER = r"<!-- scribbit-development-run: (\d+) -->"


class GitHub:
    def __init__(self, token):
        self.token = token

    def request(self, method, path, payload=None, *, missing=False, upload=None):
        host = "https://uploads.github.com" if upload is not None else "https://api.github.com"
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "scribbit-development-publisher",
        }
        data = None
        if upload is not None:
            data = upload
            headers["Content-Type"] = "application/zip"
        elif payload is not None:
            data = json.dumps(payload).encode()
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(host + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                body = response.read()
                return json.loads(body) if body else None
        except urllib.error.HTTPError as error:
            if missing and error.code == 404:
                return None
            # Never print request headers or the token.
            raise RuntimeError(f"GitHub {method} {path} failed: HTTP {error.code}") from error


def publish(api, env, directory):
    # Defense in depth: PRs, tags and manual branch runs never publish.
    if env.get("GITHUB_EVENT_NAME") != "push" or env.get("GITHUB_REF") != "refs/heads/main":
        raise ValueError("Development publication is allowed only for a main-branch push")
    repo = env["GITHUB_REPOSITORY"]
    sha = env["GITHUB_SHA"]
    run = int(env["GITHUB_RUN_NUMBER"])
    run_id = env["GITHUB_RUN_ID"]
    if (not re.fullmatch(r"[\w.-]+/[\w.-]+", repo) or any(p in (".", "..") for p in repo.split("/"))
            or not re.fullmatch(r"[0-9a-f]{40}", sha)
            or not re.fullmatch(r"\d+", run_id) or run < 1):
        raise ValueError("Invalid workflow identity")
    archive = (directory / ASSET).read_bytes()
    metadata = json.loads((directory / "build-metadata.json").read_text())
    digest = hashlib.sha256(archive).hexdigest()
    if not archive or metadata["commit"] != sha or metadata["sha256"] != digest:
        raise ValueError("Downloaded artifact does not match this workflow commit/checksum")
    base = f"/repos/{repo}"
    release = api.request("GET", f"{base}/releases/tags/{TAG}", missing=True)
    if release and (release.get("immutable") or not release["prerelease"]):
        raise ValueError("The development release must be mutable and marked as a prerelease")
    previous_run = re.search(MARKER, (release or {}).get("body") or "")
    if previous_run and int(previous_run[1]) > run:
        print("Skipping an older run: a newer successful build is already published")
        return False
    old_tag = api.request("GET", f"{base}/git/ref/tags/{TAG}", missing=True)
    if old_tag and old_tag["object"]["type"] != "commit":
        raise ValueError("The reserved development tag must be a lightweight commit tag")
    if not release:
        release = api.request("POST", f"{base}/releases", {
            "tag_name": TAG, "target_commitish": sha, "name": "Development build",
            "draft": True, "prerelease": True, "make_latest": "false",
        })
    release_path = f"{base}/releases/{release['id']}"
    assets = api.request("GET", release_path + "/assets?per_page=100")
    # Bounded by this publisher (one active ZIP + occasional failed-run backups).
    # Refuse an unexpected full page rather than risk missing the active asset.
    if len(assets) >= 100:
        raise ValueError("Too many development assets; inspect and clean up old backups")
    old_asset = next((asset for asset in assets if asset["name"] == ASSET), None)
    suffix = uuid.uuid4().hex
    pending = f"pending-{suffix}-{ASSET}"
    backup = f"previous-{suffix}-{ASSET}"
    uploaded = None
    renamed_old = False
    promoted = False
    tag_changed = False
    try:
        uploaded = api.request("POST", release_path + "/assets?name=" + urllib.parse.quote(pending),
                               upload=archive)
        if (uploaded["state"] != "uploaded" or uploaded["size"] != len(archive)
                or uploaded.get("digest") != "sha256:" + digest):
            raise ValueError("GitHub did not confirm the complete archive checksum")
        # Do not move the source tag or replace the working download until the
        # new upload has succeeded and its checksum has been verified.
        # Creating a draft may already have created its tag. Re-read rather
        # than assuming the API's draft/tag behavior.
        current_tag = api.request("GET", f"{base}/git/ref/tags/{TAG}", missing=True)
        if current_tag and current_tag["object"]["type"] != "commit":
            raise ValueError("The development tag changed to an annotated tag during publication")
        if current_tag:
            api.request("PATCH", f"{base}/git/refs/tags/{TAG}", {"sha": sha, "force": True})
        else:
            api.request("POST", f"{base}/git/refs", {"ref": f"refs/tags/{TAG}", "sha": sha})
        tag_changed = True
        if old_asset:
            api.request("PATCH", f"{base}/releases/assets/{old_asset['id']}", {"name": backup})
            renamed_old = True
        api.request("PATCH", f"{base}/releases/assets/{uploaded['id']}", {"name": ASSET})
        promoted = True
        body = (
            f"Latest successful development build from `main`.\n\n"
            f"- Commit: `{sha}`\n- Architecture: `{metadata['architecture']}` (not universal)\n"
            f"- SHA-256: `{digest}`\n"
            f"- Build: https://github.com/{repo}/actions/runs/{run_id}\n\n"
            "Ad-hoc signed, not notarized. This ZIP is replaced by the next successful build. "
            "Historical builds remain in Actions for the repository's default retention period.\n\n"
            f"<!-- scribbit-development-run: {run} -->"
        )
        api.request("PATCH", release_path, {
            "name": "Development build", "body": body, "draft": False,
            "prerelease": True, "make_latest": "false",
        })
    except Exception:
        # The API has no transaction spanning tags, assets and release metadata.
        # Best-effort rollback retains the previous ZIP if publication fails.
        try:
            if promoted:
                api.request("PATCH", f"{base}/releases/assets/{uploaded['id']}", {"name": pending})
            if renamed_old:
                api.request("PATCH", f"{base}/releases/assets/{old_asset['id']}", {"name": ASSET})
            if tag_changed:
                if old_tag:
                    api.request("PATCH", f"{base}/git/refs/tags/{TAG}",
                                {"sha": old_tag["object"]["sha"], "force": True})
                else:
                    api.request("DELETE", f"{base}/git/refs/tags/{TAG}")
            if uploaded:
                api.request("DELETE", f"{base}/releases/assets/{uploaded['id']}")
        except Exception as rollback_error:
            print(f"Rollback incomplete; inspect development assets/tag: {rollback_error}", file=sys.stderr)
        raise
    if old_asset:
        try:
            api.request("DELETE", f"{base}/releases/assets/{old_asset['id']}")
        except Exception:
            print("Published successfully; previous ZIP backup needs manual cleanup", file=sys.stderr)
    return True


if __name__ == "__main__":
    try:
        token = os.environ["GH_TOKEN"]
        publish(GitHub(token), os.environ, Path(sys.argv[1]))
    except Exception as error:
        print(f"Development publication failed: {error}", file=sys.stderr)
        sys.exit(1)
