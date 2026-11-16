# Development builds

The existing **Build and test** workflow tests/builds on pushes, pull requests,
and manual dispatches. This means each workflow run's checked-out commit—not
each intermediate local commit bundled into one push.

| Output | Trigger | Lifetime |
| --- | --- | --- |
| Actions artifact | Every successful tested/packaged build | Repository-default artifact retention; no `retention-days` override |
| Development prerelease | Successful `main` push only | One rolling ZIP, until replaced/deleted; no artifact-expiry timer |

## Download

Use the README's **Download the latest development build** link for the latest
published `main` ZIP. Before the first successful publication it returns not found.
The `development` tag, notes and checksum are updated with the build; this is a
deliberately mutable development tag, not a stable version tag.

For a historical/branch/PR build, sign into GitHub and open **Actions → Build and
test → run → Artifacts**. Artifact names include OS, architecture, checked-out
commit, run ID and attempt. Each contains `Scribbit-macOS.zip` and
`build-metadata.json`. Retention changes in repository settings apply without a
workflow edit. Expired artifacts cannot be treated as a permanent archive.

The app is ad-hoc signed and **not notarized**. Archive construction preserves
the signed bundle, executable modes and macOS metadata using `ditto`; uploading
the raw bundle would lose executable modes. The build is runner-native, not
universal. Release notes report its architecture. No Developer ID certificate,
Apple credential or new signing secret is required/provisioned by this change.

## Publication and safety

1. The macOS build job has `contents: read`. It runs app and offline publisher
   tests, builds/signs the app, packages it, then uploads the artifact.
2. A separate job gets `contents: write` only on a `push` to `main`. PRs, feature
   branches, tag pushes and manual dispatches cannot publish releases.
3. It downloads the exact artifact from this run and checks commit/checksum
   metadata before any release mutation. No app is rebuilt in the publisher.
4. Publication jobs are serialized without canceling a running publisher. A
   run-number marker prevents an older job/rerun overwriting a newer success.
   The workflow run-number sequence must not be reset without reviewing this marker.
5. A new ZIP is uploaded under a unique temporary name and its server checksum
   verified **before** touching the existing download. The old ZIP is temporarily
   renamed as a backup after updating the source tag; the new one takes its fixed
   name and notes record SHA/architecture/checksum/run. Successful publication removes
   the backup. The release remains a prerelease, not the stable Latest release.

Failed tests/builds/packaging/artifact upload skip publication altogether.
Publication failures attempt to restore the previous ZIP and tag. GitHub has no
transaction covering these APIs: interruption, transport ambiguity or a rollback
failure can require manual recovery. A short replacement window is not an
atomic/zero-downtime guarantee. The tested Actions artifact is still available
even when publication fails.

The normal `GITHUB_TOKEN` supplies job-scoped permissions. No PAT is stored.
The reserved tag is updated through the API; token-generated events do not
recursively launch ordinary workflows.

## Prerequisites and recovery

- Actions must be allowed to upload artifacts and use the job's `contents: write`
  permission. No repository setting is changed by these scripts.
- **Immutable releases must be disabled for this rolling-release setup.** Do not
  enable repository-wide immutability and expect an exception for this release.
  An existing immutable or non-prerelease `development` release is refused.
  Stable/versioned publication is a separate workflow/policy.
- Tag rules must allow the workflow to create/update its reserved lightweight
  `development` tag. A protected or annotated tag fails closed; the workflow
  does not weaken protection or change other tags.
- If publication fails, download the per-run Actions artifact first. Inspect the
  development release's `pending-*`/`previous-*` assets and workflow error.
  Restore the intended ZIP name/tag/notes before deleting backups. A later
  successful run normally repairs publication; unexpected asset accumulation is
  bounded and stops for manual inspection rather than deleting unknown assets.
- Deleting a workflow and recreating its run-number sequence may require
  deliberately resetting the release's run marker before publishing again.

## Local validation

```sh
python3 -m unittest discover -s Tests/CI -v
Scripts/build-app.sh
Scripts/package-app.sh
ditto -x -k build/development/Scribbit-macOS.zip build/archive-check
codesign --verify --strict build/archive-check/Scribbit.app
```

The publisher tests are fully offline and use disposable project-local files.
Do not run the real publisher as a local smoke test: it mutates a release/tag.
First hosted publication, policy compatibility and downloading on another Mac
remain integration/manual checks until the workflow runs on GitHub.

## Platform references

- [Workflow artifacts and retention](https://docs.github.com/en/actions/tutorials/store-and-share-data)
- [Artifact upload and permission limitations](https://github.com/actions/upload-artifact)
- [Managing releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
- [Immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
