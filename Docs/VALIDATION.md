# Validation record

## Notch settings popup — November 15, 2026

Replaced the persistent menu-bar item with a native settings popover. The bottom
section keeps the selectable file path, Pin/Preview icon buttons, and settings
gear; collapsed Command-comma uses the visible chevron as its native anchor.
The popup holds automatic dismissal and Escape dismisses settings before the
note. No-file startup has safe Choose/New/settings access. Native editing menu
shortcuts and save-before-close protections remain.

About is a minimal native sheet with the app icon, name, version and Close. It
is parented to the note panel and attached below the geometry's camera-safe
boundary, rather than using an unparented alert below the panel's window level.

| Check | Result / ignored local evidence |
| --- | --- |
| Unit/filesystem/resource suite | **104 tests in 13 suites passed**; `build/settings-popup-polish/tests.log` |
| Fresh release build and strict signature | Passed; `build/settings-popup-polish/build.log` |
| Focused regressions | Welcome/outgoing-buffer safety, RAM popup state, About metadata, sheet geometry across screen origins and window-level policy |
| Full GUI suite | **Not passed for this feature**: earlier attempts stopped in native Tab/Shift-Tab checks before reaching popup checks |
| Visual/physical acceptance | Candidate launched with user approval; full live ordering, camera/display and input-method matrix not independently verified |

Candidate: `build/settings-popup-polish/Scribbit.app`. The branch is based on
main revision `3bc5e8e025a8dbf8eea5f55e59ea39c00c690e86`, including merged
cursor/scroll and configurable-hover changes. The 0–1000 ms hover setting is
preserved in settings. No new third-party package was added. Tests use project
fixtures and RAM-only settings, not production preferences or login registration.

Manual checks include selected-state Pin/Preview buttons, full selectable path,
collapsed Command-comma, minimal About content/Close below the camera, popup
hover hold/Escape behavior, and retained native selection, scrolling and history.
Generic error/reload dialogs were not broadly converted to sheets by this change.

## Configurable hover opening delay — November 15, 2026

Entry dwell defaults to **100 ms**, down from 250 ms. The bottom disclosure's
**Hover to open** slider selects **0–1000 ms in 50 ms steps**, persisted through
`AppSettings.hoverDelay`. Zero removes the wait, not file loading, animation or
pointer eligibility checks. Nonfinite values fall back to the default; finite
values are bounded and rounded. No third-party dependency or runtime service
was added.

| Check | Result / ignored local evidence |
| --- | --- |
| Final PR-base unit/filesystem/resource suite | **97 tests in 12 suites passed**; `build/hover-pr-prep/tests.log` |
| Final PR-base release build and strict signature | Passed; `build/hover-pr-prep/build.log` |
| Earlier zero-option unit suite | **97 tests in 12 suites passed**; `build/hover-settings-zero/tests.log` |
| Earlier isolated GUI with 50 ms minimum | **GUI_SMOKE_PASS**, including `HOVER_SETTINGS_SMOKE_PASS`; `build/hover-settings/gui.log` |
| Zero-option GUI attempt | Stopped at the existing native Tab assertion before hover checks; **not passed**; `build/hover-settings-zero/gui.log` |
| Added zero-delay GUI cases | Opening, cancellation before queued work runs, and explicit-close suppression; compiled but not reached in the interrupted run |
| Physical timing and actual preference quit/relaunch cycle | Manual acceptance not independently recorded |

The PR is based on the merged cursor/focus/scroll implementation; only hover
configuration is changed. The settings-popup feature is excluded. Changing a
pending delay cancels and restarts only eligible work, without resetting
`HoverGate` or bypassing close-until-exit suppression. Exit delay and animation
clocks are unchanged.

Tests use disposable files, RAM-only settings and app-local events. The zero-delay
candidate was launched with user approval. No further GUI run is included during
PR preparation, while the separate settings-popup candidate is under manual
evaluation.

Reproduce with host file-coordination and GUI permissions where required:

```sh
Scripts/test.sh
APP_PATH="$PWD/build/hover-pr-prep/Scribbit.app" Scripts/build-app.sh
APP_PATH="$PWD/build/hover-pr-prep/Scribbit.app" Scripts/gui-smoke.sh native "$PWD/build/hover-pr-prep/smoke"
git diff --check
```

## Restore editing position — November 15, 2026

Reopening restores the last file's caret/selection and focuses the native editor
for both menu and hover opens. Unchanged source also restores its independent
viewport, including an intentionally offscreen caret. External byte changes fall
back to showing the safely clamped caret. State remains RAM-only for the last
successfully opened file; source is still read fresh and released after close.

| Check | Result / ignored local evidence |
| --- | --- |
| Unit/filesystem/resource suite | **89 tests in 10 suites passed**; `build/restore-caret-scroll/tests.log` |
| Separate release build and strict signature | Passed; `build/restore-caret-scroll/build.log` |
| Isolated native GUI suite | **GUI_SMOKE_PASS**; `build/restore-caret-scroll/gui.log` |
| Selection gate | **EDITOR_SELECTION_SMOKE_PASS**: caret/selection, preview recreation, hidden source release, keyboard focus, click-free typing, deactivation, Unicode clamp and file switch |
| Viewport gate | **EDITOR_VIEWPORT_SMOKE_PASS**: offscreen caret, preview, menu/hover reopen, native typing reveal and same-length external-change fallback |
| Existing GUI regressions | Presenter lifecycle, all five composition contracts, native history, Shift-Tab, controls, motion, hover and save/conflict checks passed |
| Clean-source PR check | Fresh export with no reused build cache: **89 tests in 10 suites passed**, signed release build and strict signature passed; `build/restore-caret-pr/clean-tests.log` and `clean-build.log` |
| Publication hygiene | 67 intended files, 62 UTF-8 files screened, 17 local Markdown links resolved; no findings in the bounded local-path/retired-reference/credential-pattern check; `build/restore-caret-pr/audit.json` |
| Shell/plist/coverage checks | Bash 3.2 runner regressions, script syntax, plist and whitespace checks passed; unit-only coverage report generated separately from GUI checks |
| Manual smoke feedback | Positive user feedback after launching the candidate; not a claim that every manual-matrix case was exercised |
| Remaining manual checks | Physical input-method candidate UI, full display/keyboard matrix, login cycle and long-running/large-file performance remain unverified |

Candidate: `build/restore-caret-scroll/Scribbit.app`. This change includes no
settings-popup or configurable-hover work. No production preference or login
configuration was changed by tests; isolated GUI fixtures use disposable files
and RAM-only settings. The candidate was later launched with user approval.

Apple's CryptoKit computes a 32-byte source fingerprint on the serial file worker;
there is no third-party package, hidden text cache, scroll observer or polling.
Native layout applies a pending viewport once and constrains it to current bounds.
Offsets do not track semantic text through external insertions or reflow.

Desktop deactivation initially raced controlled GUI assertions. Isolated tests
now invoke the shared controller handler directly; production still observes the
native notification. Pin, dialog and save-failure protections remain in place.
No retry timer or event-group workaround was added to production editing.

Reproduce from the repository root, with host file-coordination access and GUI
launch permission where required:

```sh
/bin/bash Tests/Scripts/test-runner.sh
Scripts/test.sh
APP_PATH="$PWD/build/restore-caret-scroll/Scribbit.app" Scripts/build-app.sh
APP_PATH="$PWD/build/restore-caret-scroll/Scribbit.app" Scripts/gui-smoke.sh native "$PWD/build/restore-caret-scroll/smoke"
git diff --check
```

## Branding pre-commit review — November 15, 2026

Reviewed the complete branding diff and exports. No blocking correctness or
privacy findings remained. Added an ImageIO regression test that decodes the
ICNS export and checks the required 16–1024-pixel representations.

| Check | Result / ignored local evidence |
| --- | --- |
| Exact staged-source export, without reused caches/research | **77 tests in 9 suites passed**; `build/branding-review/tests.log` |
| Fresh separate release build | Passed; `build/branding-review/build.log` |
| Package integrity and signature | Icon, four glyph exports and MIT license match the sources; identity unchanged; strict signature passed; no Testing framework linked |
| Isolated GUI gate | **GUI_SMOKE_PASS**, including packaged-resource lookup and menu template; `build/branding-review/gui.log` |
| Shell runner regressions, script/plist syntax, whitespace | Passed |
| Public index audit | 65 intended files, five intended binaries, 17 local Markdown links; no findings in the bounded path/credential screen; vector SVGs have no embedded images/scripts/external references |
| Hosted CI and daily-use optical acceptance | Not established by this review |

The selected SVGs exactly match the approved Curious Tilt and Chest Cross
masters. Source/export consistency, Retina image sizing, template tint behavior,
bundle lookup/signing and unchanged indicator preference were reviewed.
This does not replace a legal/security audit or physical-notch acceptance.

Review candidate: `build/branding-review/Scribbit.app`. The running app was not
replaced, and no production note, preferences or login registration were changed.

## Frog branding — November 14, 2026

Integrated the selected Curious Tilt paper-style app icon and Chest Cross
frog/pencil mark. The menu bar uses an 18-point template and the notch a 14-point
template, each with explicit 1x/2x PNG representations. SVGs remain the editable
source; exports are committed so normal builds need no new tools/dependencies.
The existing indicator preference and geometry are unchanged.

| Check | Result |
| --- | --- |
| Unit/filesystem/resource suite | **76 tests in 9 suites passed**; `build/frog-branding/tests.log` |
| Separate signed candidate | Passed strict signature verification; `build/frog-branding/build.log` |
| Packaged resource integrity | Icon and four glyph exports byte-identical to source exports; correct icon plist key |
| Native GUI smoke | **GUI_SMOKE_PASS**, including menu template identity and packaged-bundle lookup; `build/frog-branding/gui.log` |
| Visual review | Export preview and `build/frog-branding/smoke/left-wing.png` inspected; actual tiny notch mark visible |
| Shell regression and syntax, plist, diff whitespace | Passed |
| Actual daily-use menu contrast/physical-notch optical acceptance | Pending user review; running app not replaced |

Candidate: `build/frog-branding/Scribbit.app`. No production note, preferences,
login registration or running app were changed. No commit or push performed.

During validation, the initial image-loader initializer failed compilation and
was corrected to decode PNG Data. The first SwiftPM bundle placement at the app
root failed strict signing; it now lives in Contents/Resources with explicit
lookup and a GUI assertion preventing fallback to a local build cache. The final
results above are after these corrections. macOS iconutil required approved host
access for the SVG-export packaging step.

## CI shell compatibility — November 14, 2026

The hosted runner failed before Swift started: expanding an empty optional-flag
array under `set -u` raised an unbound-variable error in macOS Bash 3.2. The local
CLT installation supplied framework arguments, so the previously tested path
did not exercise that empty expansion.

`Scripts/test.sh` now builds optional flags with positional parameters and
`"$@"`, preserving strict error handling and all compiler/linker arguments.
No application source or SDK was changed. CI now runs shell regression tests
before the Swift suite and syntax-checks each shell script individually.

| Check | Result / local evidence |
| --- | --- |
| Regression against the original wrapper | Failed with the same unbound-variable error, as expected; `build/ci-fix/before.log` |
| `/bin/bash Tests/Scripts/test-runner.sh` | Three checks passed: no framework flags, exact framework arguments with spaces, Swift failure-status propagation; `build/ci-fix/shell-tests.log` |
| `Scripts/test.sh` with approved filesystem coordination | **75 tests in 8 suites passed**; `build/ci-fix/swift-tests.log` |
| Separate signed release candidate | Passed; `build/ci-fix/build.log`, output `build/ci-fix/Scribbit.app` |
| Per-file Bash syntax, workflow YAML, diff whitespace | Passed |
| Hosted rerun | Not run yet; local results do not establish GitHub CI success |

The running app, selected note, production preferences and login registration
were not changed. GUI smoke was not rerun for this shell-only change.

## Public-source preparation — November 14, 2026

Version: **0.5.2**, build **8**. Package/executable: Scribbit; core: ScribbitCore.
Bundle identifier: `com.stephenhe.Scribbit`.

This identity starts with fresh preferences. Selected-file bookmarks and login
registration from differently identified development builds are not migrated.
No existing note, production settings, installed/running app or login registration
was modified during preparation.

### Reproduce

```sh
Scripts/test.sh
Scripts/build-app.sh
Scripts/coverage.sh
bash -n Scripts/*.sh
plutil -lint Resources/Info.plist
codesign --verify --strict build/Scribbit.app
```

With explicit permission to open disposable test windows:

```sh
Scripts/gui-smoke.sh native "$PWD/build/smoke"
```

### Current checks

| Check | Result |
| --- | --- |
| Clean-source export: unit/filesystem tests | **75 tests in 8 suites passed** |
| Clean-source export: signed release build | **Passed**; produced build/Scribbit.app with no ignored source/build inputs |
| Metadata, executable, bundled license and signature | **Passed**; Scribbit identity/version, one Scribbit executable, byte-identical MIT license, strict signature; no retired editor packages or Testing framework linked |
| Native GUI smoke on renamed app | **Passed**, exit 0 / GUI_SMOKE_PASS; all five composition contracts, indentation/history, presenter lifecycle, controls/speed/motion, hover and save/conflict gates |
| Public-file inventory, branding/local-path/secret-pattern screen, links | **53 UTF-8 files screened**, no findings; 16 local Markdown links resolve after the platform-reference cleanup; no public symlinks or files over 1 MiB |
| Script/plist/workflow syntax | **Passed**; bash -n, plutil and YAML parser |
| Coverage command | **Passed**; unit-only line coverage 15.52% overall, including UI/harness code not run by the unit suite; core files 87.01–100% line coverage; separate GUI results are not merged |
| Reference text screen | No matches in five consecutive whitespace-normalized, nonblank/noncomment lines totaling at least 100 characters, against the inspected local reference checkouts; not a legal/provenance determination |
| Reference license review | GPL-3.0-or-later and separate trademark/trade-dress policy checked; no MIT exception identified for the referenced implementation; publication licensing boundary remains unadjudicated |
| Platform-reference cleanup | Public named-reference sweep passed; documentation and one source comment changed, executable code unchanged; full tests were not rerun for this documentation-only follow-up |
| GitHub Actions | Workflow added; not run on GitHub |
| Real notch, physical IME candidate UI, login cycle, notarization, long-running resource use | Manual/not run for this change |

The local environment is Apple silicon, macOS 26.7.3 and Apple Swift 6.3.3.
The CLT manifest-interface workaround is local to ignored build output. Filesystem
tests use actual NSFileCoordinator and require approved host access when a command
sandbox blocks the macOS coordination service.

Two metadata regression tests cover the display/executable names, bundle identity,
accessory mode and minimum macOS version. Core/editor behavior was not rewritten.
Historical experiments, naming research, old logs, downloaded source and retired
dependency notices are not part of the public source tree or current bundle.

Local evidence is intentionally ignored under `build/public-prep/`: clean-tests.log,
clean-build.log, clean-coverage.log, gui.log, audit.json, linked-libraries.txt,
reference-similarity.json and editor-similarity.json. Historical originals are
preserved there rather than rewritten as evidence for the current app. The
clean-source export contains only the files Git would include, without Git
metadata, downloaded source or reused build caches.

### Limits

Source publication is not a notarized app release. Local ad-hoc signing does not
establish Gatekeeper acceptance or login approval on another Mac. Automated GUI
tests use app-local events and API-driven composition, not every keyboard layout,
physical input method or physical-notch interaction.

The repository screen is a bounded text/path/packaging check, not a guarantee that
no secret exists, a vulnerability audit, a trademark clearance or legal clearance.
The [platform reference catalog](REFERENCE.md) documents the Apple APIs used;
it does not establish source independence or resolve licensing obligations.
