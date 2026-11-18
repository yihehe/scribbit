# Validation record

## Mixed-list edit export guard — November 18, 2026

The reported list-edit serialization refusal was reproduced without user notes:
load a bullet item containing a nested ordered child, then Shift-Tab the child
into the nonfirst bullet sibling position. Only stale upstream list-item label
and listType presentation attrs differed after Markdown/reparse. The narrow
parent-aware comparison projection now accepts known markers while keeping
parent order, checkbox state, nesting, text, paragraph counts and other/custom
attrs exact. This does not mutate upstream transactions or fix its stale visual
marker; saved/reopened Markdown follows the actual parent list.

| Check | Result / boundary |
| --- | --- |
| Actual bundled JavaScript | **35 tests passed**, including ordered-to-bullet lifts/start3/task states, restarted numbering and exact save/reopen expectations |
| Public edit corpus | 32 keyboard/command/checkbox fixture cases plus 432 seeded short edit/flush steps; 343 source snapshots reimported, 89 guarded drafts retained, 238 public-key actions handled |
| Guard safety | Explicit negative order/checked/text/nesting/paragraph/custom marker and unknown-attr tests remain rejecting |
| Actual whitespace-loss case | Tab before a soft linebreak inside a list inserts spaces that upstream trims; guard still refuses, leaves editable draft unchanged and Undo recovers |
| Diagnostics | Bounded category/schema path only; no note text, URLs or attribute values; specific trailing-indentation recovery hint |
| Native/core/filesystem | **159 tests in 25 suites passed** with approved coordination; headless tests do not establish GUI acceptance |
| Helpers and builds | Three system-Bash runner scenarios and 19 offline publisher/workflow tests passed; separate normal/isolated signed list-fix apps built without launch |
| User data / app state / remote | No user note/DOM inspection, restart, real preferences/login/reset, commit or push |

Local ignored investigation and evidence live below build/milkdown-list-*. The
first 42 simple list-key cases did not reproduce; mixed-parent lifting did.
Normal item-end spaces that upstream safely encodes are not falsely rejected.
These deterministic stress-fixture counts are not a real-world failure rate or
proof that all list-edit failures are resolved. The prior commit remains intact;
this fix is separate working changes.


## Normal Milkdown integration and PR audit — November 17, 2026

Supersedes the earlier staged-only default and size-limit descriptions below.
The user explicitly approved Milkdown as the normal editor. Normal entrypoint
now enables it with the unchanged production identity/bookmarks/persistent
settings/login semantics; no running app, real preference or login item was
changed by these tests/builds. The separate developer marker still uses RAM-only
preferences and no login registration.

| Check / finding | Evidence / result |
| --- | --- |
| Actual bundled JavaScript | **29 tests passed**; complete no-edit/edited corpus, mode replacement, placeholder removal, navigation-link sanitization, >1 MiB growth/export, rejected over-quota paste and exact Unicode/control/slash JSON budget |
| Native/core/coordinated filesystem | **159 tests in 25 suites passed**, including both no-save mode directions, grown source persistence, navigation admission and canonical quota/baseline alignment |
| Page replacement safety fix | One exact nonce-bearing programmatic main-frame native boot/recovery is admitted once; same-path links/reloads/changed query/frames/replay are denied. Page nonce rotates after crash without discarding native source/mirror. Policy tests are not actual WebKit delivery tests |
| Size recovery fix | 1 MiB initial admission is distinct from 2 MiB live canonical-document quota and existing 64 MiB exported-source cap; over-quota transactions reject before mutation, grown admitted drafts can still save/switch Source |
| Canonical quota consistency fix | Native document size and baseline encoding uses withoutEscapingSlashes, matching JavaScript for slash/control/Unicode. Exact 2 MiB passes, one-byte-over rejects, slash-heavy grown source exports without truncation and unchanged source reuse remains valid |
| Authored source and dependencies | WebEditor/Milkdown, package scribbit-milkdown-editor; exact locked public-registry dependencies, preserved full licenses; fresh no-lifecycle-script npm ci completed |
| Regeneration reproducibility | Repeat JS/CSS/notices/runtime-inventory/manifest generation was byte-identical; Swift manifest hashes passed |
| CI release gate | New read-only pinned-Node web-editor job tests/regenerates/checks committed output; development release requires both macOS and web-editor success, keeping the macOS artifact identity. Remote CI not run |
| Local helper suites | Three system-Bash runner scenarios and **19 offline publisher/workflow contract tests passed** |
| Signed normal app | build/milkdown-audit/Scribbit.app built, production ID com.stephenhe.Scribbit confirmed, strict deep signature passed, all five Milkdown resources packaged |
| Signed isolated developer app | build/milkdown-audit-isolated/Scribbit Milkdown Candidate.app built, RAM-only marker confirmed, strict deep signature passed |
| Native builds | Consume committed resources without npm/network; native GUI harness remains explicitly native-only, not Milkdown coverage |
| Actual GUI / IME / VoiceOver / menu-focus / crash injection / app-plus-WebKit resources | Not run or measured; remaining acceptance gates |
| Images | Still deferred; source fallback and visible paste/drop rejection, no unapproved asset writes |
| Real notes / production preferences / login / launch / reset / commit / push | Not performed |

Transaction-admission component benchmark: Node 22.19.0, darwin arm64/JSDOM,
30 samples after five warmups. Actual JSON gate median/p95: 4 KiB
0.008/0.012 ms, 64 KiB 0.113/0.119 ms, 1 MiB 1.863/2.552 ms. Excludes DOM,
layout, paint, physical IME and all WebKit/whole-app work; no interactive latency,
whole-app memory or resource-budget claim follows. No per-key Markdown export.

Ignored evidence: build/milkdown-audit-js-tests.log,
build/milkdown-audit-tests.log, build/milkdown-audit-build.log,
build/milkdown-audit-isolated-build.log, build/milkdown-audit-shell-tests.log,
build/milkdown-audit-publisher-tests.log and
build/milkdown-admission-benchmark.json. Initial test-macro compilation failures
were corrected and complete suites rerun; no filesystem-coordination bypass.


## Milkdown editable Rich and Source modes — November 17, 2026

One toolbar mode action replaces the candidate read-only preview and duplicate
Use Source/status controls. Mode switches accept current unsaved content without
saving or changing the file baseline. Failure retains the originating editable
mode. No GUI was launched; the existing no-placeholder build was left running.

| Check | Result |
| --- | --- |
| Actual bundled JavaScript | **25 passed**, including the retained placeholder regression and mode replacement/history/generation case |
| Native/core/coordinated filesystem | **153 tests in 21 suites passed**, including seven mode-transition regressions |
| System Bash / offline publisher | **3 scenarios / 16 tests passed** |
| Fresh separate candidate | build/milkdown-modes/Scribbit Milkdown Candidate.app built and strict deep signature verified |
| GUI / physical IME / accessibility / crash / performance | Not run; remaining acceptance gates, not unit-test claims |


## Milkdown empty-editor placeholder — November 17, 2026

Disabled Crepe's public Placeholder feature so blank notes and empty paragraphs
remain visually blank. No serializer, note-storage, or newline behavior changed.

| Check | Result |
| --- | --- |
| Bundled editor tests | **24 passed**, including absence of placeholder plugin/decorations in empty notes and new empty paragraphs, with typing still functional |
| Native/core/filesystem tests | **146 tests in 20 suites passed** with approved host coordination |
| Separate signed release | Passed; `build/milkdown-no-placeholder/Scribbit Milkdown No Placeholder.app` |
| Live GUI | Not run; the running candidate was not restarted |

## Untitled drafts and first-time setup reset — PR preparation, November 16, 2026

Rebased the local feature onto fetched main at `1308509`, preserving the shared
NoteFooter's 20-point native row and 8-point top padding, forgiving hover retention,
README demo and all prior validation records. The independent file-watching /
64 MiB proposal is not included; the existing 2 MiB selected-file limit remains.
README first-use and recovery instructions now describe the actual untitled mode.

| Check | Result / ignored project-local evidence |
| --- | --- |
| Rebase | Clean onto `1308509`; feature remains a single author-scoped local branch |
| Full unit/filesystem/resource suite, approved coordination access | **115 tests in 14 suites passed**; `build/untitled-pr/tests.log` |
| Shell runner regressions | **3 scenarios passed** under system Bash; `build/untitled-pr/script-tests.log` |
| Offline development-publisher suite | **16 tests passed**; `build/untitled-pr/publisher-tests.log` |
| Fresh ad-hoc-signed release candidate | Passed; `build/untitled-pr/Scribbit.app`, build log alongside it |
| Script syntax / plist / whitespace | Bash syntax, Info.plist lint and diff whitespace passed |
| User-file, production preferences, reset, login or GUI execution | **Not performed** during this preparation |

Manual acceptance remains required for no-file focus, draft reopen position,
Save As cancellation/errors, hidden-draft quit, reset-from-preview native focus,
undo clearing, camera-safe sheet sequencing and actual login unregister/relaunch.
The unit suite is not evidence for these native GUI / operating-system flows.
No existing running or installed app was replaced or launched.

## Open-note footer identity — November 16, 2026

Added a subtle frog/pencil plus Scribbit wordmark to the bottom-left of the open
surface. It reuses the cached 14-point asset. Following user feedback, the
20-point footer row now has 8 points of breathing room above it, reserving
28 points total. The native centered disclosure/settings anchor and optional
closed-wing setting are unchanged. No editor command, note lifecycle or
preference was changed.

| Check | Result / ignored local evidence |
| --- | --- |
| Rebased source | Based on latest fetched main `a549ca2`, including README demo and forgiving hover dismissal |
| Final unit/filesystem/resource suite with approved coordination access | **109 tests in 14 suites passed**; `build/footer-branding-pr/tests.log` |
| Windowless footer tests | Both expansion states preserve centered native disclosure, 20-point control height, 28-point total footer, accessible labels and working action; native editor layout verifies 8-point clearance with native pixel-rounding tolerance |
| Separate signed release build | Passed; `build/footer-branding-pr/build.log`; candidate `build/footer-branding-pr/Scribbit.app` |
| Initial pre-rebase candidate | **106 tests in 14 suites passed** and signed build; `build/footer-branding/tests-host.log` and `build/footer-branding/build.log` |
| Initial fixture-only optical preview | `build/footer-branding/footer.png` and `editor-footer.png`; generated offscreen before the padding change, not current-spacing acceptance |
| User review — November 16, 2026 | Earlier candidate launched at user's request; user requested more separation between logo and text view |
| Updated spacing manual review — November 16, 2026 | Updated candidate launched at the user's request before PR preparation; automated GUI/physical-notch assertions were not executed |

The sandboxed suite encountered the documented NSFileCoordinator access failure;
the same suite passed with approved host access without bypassing coordination.
Tests now use windowless geometry fixtures without generating image captures.
Implementation and automated tests did not access real notes, mutate production
preferences or install/restart the app. The updated candidate was subsequently
launched at the user's request for manual review. The README's existing
rendered demo remains illustrative and was not re-exported for this adjustment.

## README rendered demo — November 16, 2026

Added a README GIF and still-image alternative, generated offscreen from current
shared geometry/motion/default-hover sources and disposable sample text.

| Check | Result |
| --- | --- |
| Renderer execution / reproduction | Passed twice with byte-identical GIF and PNG outputs on this host |
| GIF contract | 138 frames, 800×560, 6.90 seconds, 20 FPS, infinite loop, 66,985 bytes; decoded timing/dimensions/loop and 4 MiB cap verified |
| Script syntax / diff whitespace | Bash syntax and `git diff --check` passed |
| Static visual inspection | Regenerated open poster and decoded first GIF frame inspected: actual frog-and-pencil asset in resting left wing and proposed open footer, wordmark, chevron, attached silhouette and caption |
| Existing app suite | **104 tests in 13 suites passed**; `build/readme-demo/tests.log` |
| Fresh signed release build | Passed; `build/readme-demo/build.log`; candidate built but not launched |
| Live UI / physical-notched display | Not exercised or claimed; this is a rendered fixture, not a recording |

Reproduction and privacy boundaries are documented in [README demo](README-DEMO.md).
No app source/runtime behavior or dependencies were changed.
The footer-branding layout is explicitly marked proposed in the README caption;
the independent no-file draft feature is not described as shipped. The optional
resting-notch indicator is explicitly enabled in this demo, not claimed as the
app default. Its shared geometry and asymmetric spring offset are used.
Re-exported GIF and PNG were byte-identical across two runs after adding the frog; the PNG
poster is 27,525 bytes.

## Forgiving hover dismissal — November 15, 2026

Hover-opened notes now retain the pointer within a display-clamped region
extending 48 points beyond each side and 24 points below the expanded surface.
The visible contour, native panel, closed entry target and outside-click hit
testing are unchanged. The existing 180 ms exit delay, reentry cancellation,
pin/dialog/settings/drag holds and save-before-close policy remain.

| Check | Result / ignored local evidence |
| --- | --- |
| Unit/filesystem suite with approved host coordination access | **107 tests in 13 suites passed**; `build/hover-retention/tests.log` |
| Fresh release build and strict signature | Passed; `build/hover-retention/build.log` |
| Focused geometry regressions | Side and bottom thresholds including exact boundaries, physical screen top, unchanged closed trigger, display clipping and translated display origins |
| Whitespace and GUI script syntax | Passed; `git diff --check` and `bash -n Scripts/gui-smoke.sh` |
| New opt-in GUI acceptance | Compiled assertions cover staying in grace, canceling a pending exit on reentry, and strict outside-click dismissal; **not executed** |
| Manual acceptance — November 16, 2026 | Candidate launched at the user's request; user reported “looks good” and approved PR preparation. This does not establish execution of every GUI assertion |

Automated validation did not launch the GUI or access production notes/preferences.
The standalone candidate, `build/hover-retention/Scribbit.app`, was subsequently
launched at the user's request for manual review. No installed bundle was replaced
or login registration changed. No new runtime dependency or event monitor was added.

## Automatic development downloads — November 15, 2026

Added default-retention Actions artifacts for successful builds and a separate,
main-push-only publisher for one rolling development prerelease. App runtime,
signing identity and launch/login behavior are unchanged.

| Check | Result / ignored local evidence |
| --- | --- |
| Offline publisher suite | **16 tests passed**; `build/downloads-validation/publisher-tests.log` |
| Existing app suite | **104 tests in 13 suites passed**; `build/downloads-validation/tests.log` |
| Fresh signed release build | Passed; `build/downloads-validation/build.log` |
| ZIP roundtrip | Extracted bundle strict signature, executable bytes/mode and commit/checksum metadata verified; `build/downloads-validation/package.log` |
| Workflow checks | YAML syntax, write-job event/dependency guards, read-only build permissions, no artifact-retention override, and shell/whitespace checks passed |
| Hosted Actions/publication | **Not run**; no release/tag or repository setting was mutated during development |

Publisher tests use an in-memory API double and disposable project-local files.
The rolling release requires mutable releases and permission to update the
reserved `development` tag. The first hosted run and actual download on another
Mac remain integration/manual acceptance. No GUI was launched or running app
replaced by this change.

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

## Untitled notepad candidate

The no-file welcome has been replaced by the regular native editor with a RAM-only
draft, explicit Open/Save As and a visible loss warning. File-backed behavior is
unchanged. See the untitled acceptance matrix in TESTING.md. GUI validation,
including modal cancellation and hidden-draft quit, has not been run for this
candidate. The running user app and production preferences have not been touched.

| Candidate check | Result |
| --- | --- |
| Scripts/test.sh with approved host coordination | 107 tests in 13 suites passed |
| Sandboxed initial run | Existing NSFileCoordinator fixtures and new read-back fixture blocked with Cocoa 256; not treated as behavior failures |
| Scripts/build-app.sh | Ad-hoc-signed build succeeded; no launch/install |
| git diff --check | Passed |
| GUI sheets, cancellation, hidden-draft quit and physical notch | Not run; manual validation required |

### About reset follow-up

Reset App is a secondary About action with explicit reset scope and separate
Save or Save As / Cancel / Discard handling. Only known app preference keys and
RAM state are cleared; no note file is deleted. ServiceManagement unregistering
is production-only and occurs only after explicit confirmation. The confirmation
explains that the next real launch repeats first-launch automatic registration.

| Check | Result |
| --- | --- |
| Updated host-coordinated unit/filesystem suite | 110 tests in 13 suites passed |
| Reset-specific tests | RAM preference defaults/idempotence, worker/model file and hidden-draft reset, selection/viewport clear, busy refusal and no store I/O on discard |
| Production reset, real defaults or login mutation | Not run |
| GUI confirmation/cancel/failure ordering and focus | Not run; manual acceptance remains required |

## Selected-file watching and 64 MiB source acceptance

Supersedes earlier statements about fresh reads on every reopen and no hidden
cache. Production now uses one on-demand RAM snapshot, invalidated by native
file/parent observation, saves and explicit reload, with worker-side metadata
fallback. Session/UI closed buffers still clear. The source acceptance limit is
64 MiB, not total process memory. See ARCHITECTURE.md for consistency tradeoffs.

- Initial sandboxed test run: filesystem coordination failed with Cocoa error
  256 in existing and new tests. Coordination was not bypassed.
- Approved host-access Scripts/test.sh: final **111 tests in 14 suites passed**, including
  native directory notification, external replacement/deletion/recreation, cache
  reuse/reload, successful-save invalidation, preservation of visible unsaved
  edits, conflict safety, and actual 64 MiB read/successful-save/oversized-save
  bounds. Log: build/file-watching-tests-final.log.
- Scripts/build-app.sh: fresh release build and ad-hoc signature succeeded.
  Log: build/file-watching-build-final.log. An earlier build correctly rejected
  a concurrent source edit; this result is from a separate completed rerun.
- Git diff whitespace validation passed.
- No app launch, GUI tests, preferences, real notes, login, install, commit or push.
- Native editor/undo/preview latency and whole-app memory at 64 MiB remain manual
  and unverified. No claim of smooth editing at the source limit.

### Rebase onto remote main — November 16, 2026

| Check | Evidence / result |
| --- | --- |
| Latest fetched origin/main | aee065a, including README demo, dismissal tuning, persistent footer frog, untitled drafts and first-time reset |
| Rebase integration | Preserved merged features and documentation; production model still uses the watched store while untitled drafts remain separate |
| Reset lifecycle | Clears hidden store snapshot and cancels file/parent observation on worker before controller releases scoped access; no note read/write/delete |
| Untitled Save As | Opens through normal store path; balances any previously retained selected-file scope on success |
| Approved host filesystem/unit suite | **123 tests in 15 suites passed**; build/file-watching-rebased-tests.log |
| Fresh signed candidate | **Build and strict signature verification passed**; build/file-watching-rebased/Scribbit.app and build/file-watching-rebased-build.log |
| Whitespace | git diff --check passed |
| GUI / launch | No GUI tests or reset exercised; candidate handed to parent for authorized normal app relaunch |
| Remote mutation | No push or release publication |

64 MiB native editing/undo/preview responsiveness and whole-app memory remain
unverified; passing storage boundaries is not a GUI performance measurement.

### Selected-file cache core benchmark — November 16, 2026

The [performance report](FILE-WATCHING-PERFORMANCE.md) records reproduction,
environment, complete paired timing tables, backing read counts, process CPU/RSS
and important limitations. Production storage/cache/save code was unchanged.

| Check | Result |
| --- | --- |
| Optimized harness | swiftc -O against production core sources; no GUI/app launch |
| Deterministic self-test | Percentile math, fixture bytes, cache reuse, save and external replacement contracts passed |
| Completed measurement | 96 unique cells across six sizes, two layers, four workloads and two store modes |
| Result checks | Sample/result shape and backing read-count bounds passed; all measured source SHA-256 hashes match current files |
| Fixture cleanup | Final-run private per-cell temporary directories were removed automatically |
| Static checks | Shell syntax, Python AST and git diff --check passed |
| Production source diff | Empty; no cache/save optimization added during benchmarking |
| Whole-app GUI / energy / cold disk | Not measured; existing app was left untouched |
| Commit / push | Not requested or performed for the benchmark work |

Raw final artifacts remain ignored below build/file-watching-benchmarks-final;
the durable report contains the results without committing generated outputs.

## Staged Milkdown full-shell candidate — November 17, 2026

This is a separately marked, opt-in evaluation build based on remote main
`cb340bd`, not a default-editor switch or note-format migration. It uses the real
notch/session/storage shell with RAM-only preferences and no login registration.
See MILKDOWN-EDITOR.md for contracts, limits, corpus and remaining gates.

| Check | Result / boundary |
| --- | --- |
| Actual bundled Milkdown JavaScript | **25 tests passed** in headless JSDOM against the committed bundle, not a reimplementation |
| Keyboard / Markdown fixtures | List Tab/Shift-Tab, tasks, code whitespace, tables/empty cells, links/references, literal escapes, multiline plain paste and edited export/reopen passed |
| No-edit and Undo authority | Native committed tree is supplied before serialization, Swift verifies equality independently, and original source bytes are reused; upstream caret append is settled before baseline |
| Unsafe links | Actual upstream DOM sanitizer neutralizes unsafe/obfuscated explicit schemes while stored destinations and original Markdown survive; literal code URLs remain code; native external navigation remains denied |
| Native / core / coordinated filesystem | **153 tests in 21 suites passed** with approved host coordination, including close-before-clear, snapshot authority, failed settlement/conflict/reset and bundled resource hashes |
| Signed candidate | Fresh release build and strict signature verification passed; separately marked bundle ID com.stephenhe.Scribbit.candidate.milkdown |
| CI helper regressions | Three system-Bash runner scenarios and 16 offline publisher tests passed; no remote release mutation |
| Single editable mode toggle | Both directions accept newest unsaved source without save/baseline changes; failures retain source/draft, busy/reentry blocks file switches, .txt/large fallback remains native; bundle tests cover generations/history and placeholder removal |
| Rich limits | 1 MiB source and 2 MiB JSON bridge bounds; native source fallback remains 64 MiB; none is a total-memory guarantee |
| Images | Intentionally deferred: source falls back, image/file paste/drop is visibly rejected without any asset write |
| GUI / WebKit / physical IME / VoiceOver / crash / performance | Not run or measured; headless DOM tests do not establish these outcomes |
| Real notes / production preferences / login / install / restart / commit / push | Not performed |

Ignored local logs: build/milkdown-mode-js-tests.log,
build/milkdown-mode-tests.log, build/milkdown-mode-build.log,
build/milkdown-shell-tests.log and build/milkdown-publisher-tests.log.
Initial sandboxed filesystem coordination failures were rerun with approved host
access; no coordination bypass was used. Candidate output is
build/milkdown-modes/Scribbit Milkdown Candidate.app. The normal unmarked app
entrypoint remains native. Image authorization/storage, actual disposable-note
GUI acceptance, app-plus-WebKit resource measurements and explicit rollout
approval remain required before any default enablement.
