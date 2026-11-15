# Contributing to Scribbit

Scribbit is an early native macOS app. Keep changes focused and include regression
tests for observable behavior. Read [AGENTS.md](AGENTS.md) for design invariants.

## Prerequisites

- macOS 14 or later.
- Swift 6 tools, supplied by a compatible Xcode or Command Line Tools installation.
- No third-party runtime packages are required.

## Local checks

Run from the repository root:

```sh
/bin/bash Tests/Scripts/test-runner.sh
Scripts/test.sh
Scripts/build-app.sh
Scripts/coverage.sh
for script in Scripts/*.sh Tests/Scripts/*.sh; do /bin/bash -n "$script"; done
plutil -lint Resources/Info.plist
git diff --check
```

The build produces `build/Scribbit.app`, signed ad hoc for local use. Building does
not launch/install the app, register login items or modify a selected note.
See [testing](Docs/TESTING.md) for limitations and the manual acceptance matrix.

With permission to open disposable test windows in your graphical session:

```sh
Scripts/gui-smoke.sh native "$PWD/build/smoke"
```

This harness uses isolated in-memory settings and project-local fixtures, not
production notes or preferences. Do not run its event-loop tests in a headless
environment or substitute them for real hardware/input-method acceptance.

GitHub Actions runs unit/filesystem tests and a signed build on macOS. It does
not run interactive GUI tests, a login cycle, notarization or performance acceptance.

## Scope and safety

- Native source editing, explicit read-only Markdown preview and file-backed notes
  are intentional. Discuss cloud services, new packages or richer editor engines
  before implementing them.
- Never discard an unsaved buffer after a read/save failure. Protect fresh reads,
  coordinated byte-conflict detection and save-before-hide behavior.
- Keep signing keys, personal notes, local paths and generated artifacts out of
  commits. Build output, fixtures, caches and research belong in ignored folders.
- Preserve source provenance. Do not copy code from a differently licensed
  project without reviewing compatibility and retaining required notices.
- Document behavior changes and distinguish automated results from manual checks.
- Publishing source is not a notarized application release. Developer ID signing,
  notarization and user-approved login setup are separate steps.
