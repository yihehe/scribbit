# Testing and acceptance

## Development-download automation

Run `python3 -m unittest discover -s Tests/CI -v` for the offline publisher tests.
They cover first publication, updates, stale runs, event/identity guards,
checksum mismatch, immutable releases, API failures and rollback. They do not
publish anything. Packaging verifies the extracted app's executable and signature.
See [development builds](DEVELOPMENT-BUILDS.md) for the workflow and live-publication
acceptance limits; no real-token publication is part of local testing.

## Native-editor gate

This gate explicitly exercises the native Source/fallback NSTextView and
NoteTextView Shift-Tab command. The normal app also includes Milkdown rich editing;
passing this native harness is not rich-editor GUI acceptance. Run tests/builds
without modifying the currently launched bundle; GUI execution requires explicit
authorization:

```sh
Scripts/test.sh
Scripts/build-app.sh
Scripts/gui-smoke.sh native "$PWD/build/smoke"
```

The GUI wrapper requires indentation, five composition contracts, native
composition history through the real Edit menu actions, Save/Close composition
persistence, and existing shell/controls/notch gates. It rejects runtime exceptions
and nonzero process status. Use `native` for this gate and `rich` for the separate
WebKit gate below; their required pass markers are not interchangeable.
See `NATIVE-EDITOR.md` for the event-boundary correction and scope.

The wrapper also requires `PRESENTER_LIFECYCLE_SMOKE_PASS`. The presenter
is exercised with a stock NSPanel and plain NSView, independently of notes.
The cases cover a superseded reveal, a superseded close followed immediately by
a new reveal, a waiter that follows replacement motion, multiple waiters and an
idle wait. The superseded-reveal case failed against the pre-refactor presenter;
it is not merely a new test of already-passing behavior.

`EDITOR_SELECTION_SMOKE_PASS` is also required. The real isolated shell verifies
native selection checkpoints, preview recreation, position surviving hidden
buffer release, explicit reopen focus, scrolling a late line into view, hover
focus and app-local typing at the restored caret without clicking, unpinned
deactivation before interaction, fresh externally shortened Unicode source, and
reset on file switch. Pure tests cover invalid/overflowing UTF-16 ranges, emoji, composed
characters and CRLF. Model tests cover fresh reads, failed open/save/reload,
position retention and revision behavior. These use disposable files/RAM settings,
not persisted cursor preferences or a user's note.

`EDITOR_VIEWPORT_SMOKE_PASS` checks that scrolling far from a caret does not move
it, that preview recreation and menu/hover reopening restore that viewport, that
native typing naturally reveals the offscreen caret, and that a same-length
external edit falls back to showing the caret. Model tests cover source
fingerprints after saves, empty hidden buffers, exact-byte Unicode
changes, failed reads/saves/reloads, file switches and fresh instances.

Isolated shell tests invoke the production deactivation handler explicitly,
including its pinned/unpinned gates, instead of observing ambient OS activation
changes. Otherwise switching focus on the desktop can initiate a legitimate
close during an unrelated test assertion. The non-isolated app still observes
the native notification; actual cross-app notification delivery is manual
acceptance, not established by this controller check.

## Automated suite

The settings task also requires `SETTINGS_POPUP_SMOKE_PASS`. It verifies that a
no-file editable untitled surface exposes a visible chevron anchor, Command-comma stays
wired through the application menu, interacting with the popup holds automatic
dismissal, and opening/closing it retains the same editor, source, selection and
native undo manager. Login mutations remain disabled in the isolated harness.
Unit tests cover untitled draft retention/discard, new-file adoption, existing-path
refusal, save failures and RAM-only popup snapshots.
Pure sheet-attachment tests cover notched/unnotched screens, negative/vertical
display origins, and preserving a lower native attachment. A window-level policy
test checks constants only; it does not create windows or establish live ordering.

```sh
/bin/bash Tests/Scripts/test-runner.sh
Scripts/test.sh
Scripts/build-app.sh
```

The shell regression test runs the actual wrapper with a fake compiler and
developer-directory lookup. It covers the empty optional-arguments path, the
explicit framework path with spaces, and propagation of a failing Swift exit
status. It uses `/bin/bash` deliberately: the system Bash 3.2 treats empty arrays
as unbound under `set -u`, unlike newer Bash versions. The wrapper therefore
builds optional arguments with positional parameters, retaining strict error
handling without requiring a shell upgrade. Fixtures stay under `.build`.

`HoverDelayTests` covers the 100 ms default, 0–1000 ms bounds, 50 ms
quantization, invalid/nonfinite inputs, labels and independence from exit/motion
timing. `HoverSettingsTests` uses RAM-only settings for write normalization,
preference independence and lifecycle retention. The native harness requires
`HOVER_SETTINGS_SMOKE_PASS`: configured delayed opening, pending-work replacement,
pointer-exit cancellation and preserving explicit-close suppression, including
zero-delay opening and cancellation before queued zero-delay work runs.

Swift Testing covers lifecycle and model boundaries, actual coordinated temporary
files, and pure hover/geometry logic. Fixtures and coverage outputs live under
`.build`. Tests do not register login items or open a real selected user file.
The native model tests exercise the actual serial I/O worker, including deterministic
semaphore-controlled busy state without timing-dependent sleeps.

| Layer | Behaviors covered |
| --- | --- |
| NoteSession | Fresh reread on every reopening, no reload while open, save-on-close, retry after failure, byte conflicts, clean no-op close, baseline advancement, invalid UTF-8, failed/discard reload, dirty-state changes, buffer release on close |
| DiskNoteStore | Actual Unicode/CRLF roundtrip, empty file, exact size boundary, oversized read/write, same-length external edits, atomic external replacement, deletion, missing paths, directories, file-to-directory replacement, safe creation, symlink handling |
| Geometry / HoverGate | Physical notch, unnotched fallback, negative display origins, small screens, invalid insets, entry/exit/reentry, old-display dwell invalidation |
| NoteModel | Main-actor observable state, successful/error save, editable buffer retention, reload, preview reset, no destructive double-open, off-main I/O, duplicate-action busy gating |
| App metadata | Display/executable names, bundle identifier, accessory mode, minimum supported macOS |
| Branding | App-icon ICNS decoding at required sizes; template flags, logical sizes, 1x/2x pixels, and nonempty transparency |

`NoteFooterTests` hosts the footer offscreen, without creating a window. It checks
the native disclosure's centered placement, 20-point control height within a
28-point footer, accessible labels and action in both expansion states. A native
editor layout fixture verifies the 8-point clearance and resulting viewport
height. These tests create no windows or image captures. Existing control/editor smoke gates remain
the checks for selection, undo and popup anchoring in a live shell.

Animation-specific checks and the rendered fixture GIF are documented in `NOTCH-UX.md`.

Hover-retention geometry tests cover both side margins, bottom/top boundaries,
unchanged closed trigger, small-display clipping and negative/vertical origins.
The opt-in `HOVER_RETENTION_SMOKE_PASS` gate additionally checks that resting
outside the visible contour stays open, returning to that grace region cancels
a pending close, and an intentional outside click there still saves/closes.

The command sandbox can prevent `NSFileCoordinator` from contacting macOS's
coordination service. In that environment, real disk tests return Cocoa error
256 even though fixtures exist. **Do not remove coordination or silently bypass
it to make tests pass.** Run the same suite with approved host access. Fake-store
unit tests passing alone do not establish actual disk behavior.

The installed CLT's Swift Testing framework is built for macOS 14; its custom
runner can emit a deployment-target warning on older package versions that targeted macOS 13. The current package targets macOS 14. The app release does not link Testing. A full supported Xcode install
is recommended for cross-version and distribution validation.

## Opt-in native GUI harness

After building, with GUI launch approval:

```sh
'build/Scribbit.app/Contents/MacOS/Scribbit' --smoke-test "$PWD/build/smoke"
```

It opens sample UI and exits automatically. It tests actual NSTextView insertion
and binding, saves on model close, reopens an externally changed file, retains a
conflicting buffer, and renders editor/preview/conflict PNGs. It also initializes
the actual AppDelegate shell with **RAM-only settings and all login mutations
disabled**, checking bookmark creation/resolution, panel open/save/hide, disk
refresh, failed-save visibility, and indicator creation/removal for current screens.
It installs/removes the actual event monitors. The newer harness also injects
pointer coordinates into the isolated controller to test dwell, exit/reentry,
pin, save conflicts, and close-during-open without moving the real cursor. It does
not synthesize physical OS pointer events or system login. No production preference writes or real user notes.

Artifacts: `build/smoke/editor.png`, `preview.png`, `conflict.png`, sample `.md`
fixtures, and `resources.txt`. The short hidden-harness CPU interval is not a
full live-monitor performance benchmark. Its peak memory also includes GIF
encoding/raster allocation from the fixture animation exporter. The harness exits after reporting
`CONTROLS_SMOKE_PASS`, `ANIMATION_SMOKE_PASS`, `HOVER_SMOKE_PASS`, `SHELL_SMOKE_PASS`, and
`GUI_SMOKE_PASS`. It is excluded from normal startup unless
the exact command-line option and output path are supplied.

## Manual acceptance matrix — use a disposable file

These are not claimed as passed by unit tests or screenshots.

| Check | Steps | Expected result |
| --- | --- | --- |
| Actual notch hover | Move into notch from another app, linger for configured delay | Editor opens below camera; default 100 ms; no permission prompt |
| Hover delay preference | Set Hover to open to 0 ms, 50 ms, 500 ms and 1000 ms; close/reenter; quit/relaunch | Entry wait changes and persists; animation and 180 ms exit behavior do not change |
| Accidental entry | At a nonzero delay, cross the trigger before its dwell completes | No editor; 0 ms intentionally skips the dwell filter |
| Reentry suppression | Open, Escape with pointer still in trigger | Stays hidden until leave and reenter |
| Alternative open | Reopen running Scribbit from Finder/Spotlight; expand chevron/use VoiceOver on gear | Surface opens with the same file or RAM-only untitled draft; no menu-bar status icon |
| Bottom disclosure | Toggle chevron; inspect/copy path; click pin/preview; edit/undo/select before/after | Icon buttons, not checkboxes; selected appearance/accessible On/Off state; full path and gear inside section only; same native editor/source/history |
| Footer branding | Inspect source/preview/untitled with disclosure collapsed/expanded, and closed-wing preference on/off | Small frog/Scribbit mark stays at bottom-left of open surface; centered chevron and Cmd-comma still work; 8-point gap above logo/control row; optional closed wing remains independent |
| Settings popup | Gear when expanded; Cmd-comma when collapsed; move into popup, Escape, click outside | Popup has other preferences/actions but no pin/preview; visible chevron anchors collapsed keyboard path; Escape dismisses popup first |
| About | Settings → About on current display; inspect icon/content and close | App icon, name/version and reachable Close only; sheet remains above note surface and below camera-safe top |
| No-file settings | First launch/cancel selection, expand chevron or Cmd-comma | Choose/New, preferences and Quit reachable; no empty writable file substituted |
| Animation speed | Use popup slider at 0.5×, 1×, 2×; quit/reopen; try Reduce Motion | Rate persists, shape/content stay synchronized, Reduce Motion remains short fade |
| Native editing | Select, undo/redo, Cmd-F, paste, non-Latin IME, emoji | Correct source and focus, find bar usable |
| Hover exit / pin | Open via hover, leave, reenter within 180 ms, then pin and leave | Reentry cancels; unpinned exit saves/collapses; pin holds surface |
| Close paths | Edit distinct marker and try Done, Escape, Cmd-W, outside click, switch app, normal Quit separately | Marker saved on every path |
| No stale reopen | Close, edit file in another editor, reopen | External version is loaded |
| Last edit position | Place caret/select text near end of long note; close/reopen by menu and hover; type without clicking; toggle preview | Position restored; unchanged source preserves viewport independently, changed source shows the caret; both open paths focus the editor and typing inserts/replaces at the restored position |
| Independent scroll | Leave caret near the start, scroll far down to read, close/reopen without changing the file; repeat after an external edit | Unchanged source restores the reading viewport without moving the caret; changed source shows the clamped caret instead |
| Conflict | Edit here, change same file in another editor, Done | Editor stays open; external bytes are intact |
| Recovery | Save a Copy to another path; cancel reload, then confirm reload | Copy preserves buffer; cancel retains; confirmation reloads |
| Save failure | Remove write permission from disposable parent folder, edit and close | Error and open buffer; retry after restoring access |
| Normal quit failure | Repeat above, then Quit | Quit is refused; buffer remains |
| File pickers | Edit, choose other file, cancel picker, reopen | Original edits saved; cancellation does not truncate anything |
| New file | Create fresh `.md`; also choose existing path | Fresh empty file created; existing content is opened, not truncated |
| Rename/move | Close, move selected file, reopen | Bookmark resolves move or actionable error, never empty replacement |
| Display changes | Move across displays; disconnect display while editing | Panel stays reachable; edits retained |
| Spaces/full screen | Hover in another Space/full-screen app | Panel visible and correctly placed; no overlay over camera |
| Indicator | Toggle left wing on/off, try crowded menu bar, both display types | Pencil joins the camera on the left with no gap; morph starts/ends at the wing; clicks pass through |
| Login | Install stable signed bundle, enable, approve System Settings, log out/in | App starts with selected file remembered and editor closed |
| Disabled login | Disable in System Settings, relaunch app | App does not re-enable automatically |
| Sleep/wake | Edit, sleep/wake, reopen | Best-effort save; verify actual bytes before trusting this path |

## Performance checks

Use a **release** bundle, a small local file, and Activity Monitor or Instruments.
Observe hidden idle for at least 60 seconds, ordinary pointer movement away from
the notch, repeated open/close, preview, and the 64 MiB boundary file. Record Mac
model/CPU, OS, build, idle CPU, resident memory, energy impact, and any growth over
100 open/close cycles. Distinguish warm SwiftUI baseline from leaks. No recurring
timer or idle I/O is expected, but numerical CPU/RAM budgets require actual
measurements on the target Mac. The 3-second smoke interval alone is insufficient.

## Untitled draft acceptance

| Action | Expected result |
| --- | --- |
| Open with no selected file | Native editor is focused; Open/Save As and unsaved-loss warning are visible; no picker opens automatically |
| Type, dismiss, hover open again | Draft, caret and viewport remain in RAM |
| Cmd-S or Save As | Camera-safe native sheet asks for a new path; success adopts a file-backed note |
| Save to existing path or inaccessible directory | Existing file is untouched; draft and visible error remain |
| Open another file or quit with draft | Save As / Cancel / Discard sheet; Cancel preserves draft, including after cancelled Save As |
| Quit with hidden draft | Surface is revealed before confirmation; no silent loss |
| Force Quit / crash | RAM-only draft is not recoverable, as the visible warning states |

These sheet ordering, focus and confirmation flows require opt-in manual GUI
validation. Model/filesystem tests do not establish physical-notch usability.

## First-time setup reset acceptance

Focused RAM-only tests cover all five reset preference values, idempotence,
file/draft identity and selection/viewport clearing, worker session clearing,
refusal during an existing transaction, and no disk I/O in confirmed discard.
Tests never reset standard defaults or register/unregister a real login item.

| Manual action | Expected |
| --- | --- |
| About → Reset App → Cancel | Note, preferences and login unchanged |
| Continue with dirty file or draft → Cancel | Text and current file selection remain |
| Save / Save As fails or conflicts | Reset aborts, buffer/error remain visible |
| Discard and confirm reset | Existing note file untouched; blank focused notepad, default settings and no selected file |
| Reset from preview or with native undo history | Editor appears focused with empty history; Undo/Redo cannot restore discarded text |
| Login unregister fails | Reset aborts without discarding unsaved text or preferences |
| Reset with login enabled | Login disabled now; confirmation explains that the next real launch repeats first-launch registration |

These flows are not simulated by the unit suite. Native sheet ordering, default
button cancellation, login removal and actual first-launch behavior require
explicitly approved manual validation with disposable preferences/notes.

## Watched selected-note cache

WatchedNoteStoreTests covers unchanged reopen reuse, clearing the session text,
explicit reload bypass, same-length edits, atomic replacement, deletion/recreation,
file switching, explicit invalidation and save conflicts despite a populated cache.
The reset regression clears a hidden snapshot without reading, writing or deleting
the note, then verifies an unchanged reopen must read again after reset.
The actual directory-event regression creates a sibling file without changing the
note metadata and waits up to three seconds for invalidation; it does not assert
an exact delivery deadline or use a production polling timer. Existing
DiskNoteStore boundary and oversized-save regressions exercise the 64 MiB limit.

64 MiB is a supported source acceptance bound, not a UI performance benchmark.
Manual editor/undo/preview latency and whole-app RSS at that size remain unverified;
use disposable data only and do not infer interactive smoothness from store tests.

## File-watching benchmark harness

Scripts/benchmark-file-watching.sh builds an isolated release-optimized CLI from
the production storage/session sources; it does not launch Scribbit. Use --quick
for smoke validation, no flags for ordinary sizes, or --stress to add 8/64 MiB.
The executable self-test checks percentile computation, fixtures and read/cache
contracts. The driver checks result schemas and backing read counts without
timing assertions. Fixtures are private per subprocess and removed automatically.
Host access may be needed for NSFileCoordinator. Measurements and limitations are
in [FILE-WATCHING-PERFORMANCE.md](FILE-WATCHING-PERFORMANCE.md). This is not a GUI,
physical-disk, energy or whole-app memory benchmark.


## Milkdown rich editor and developer acceptance build

### Actual WebKit/native bridge gate

After building, with GUI execution approval:

```sh
APP_PATH="$PWD/build/Scribbit.app" Scripts/gui-smoke.sh rich "$PWD/build/smoke-rich"
```

This opens one disposable panel with the packaged WKWebView and real bridge,
not JSDOM. It does not construct the normal AppDelegate, read settings/bookmarks,
register login, use the system clipboard or inspect user notes. Tests use a
uniquely named project-local file, removed on completion. The harness has a
60-second overall deadline. The wrapper rejects process failures, missing markers
and Swift continuation-leak diagnostics even when other pass markers appear.

It covers unchanged byte preservation, edited save, unsaved Rich/Source mode
switching, coordinated conflict retention, explicit reload, closed-document
cleanup, Source fallback, invalid snapshot errors/retry, inactive WebKit
termination, double Restore and restore acknowledgement timeout/retry.
Termination callbacks are deliberately simulated while page recreation and
restoration use real WebKit. This is not actual OS crash delivery, physical
IME, accessibility or cross-app clipboard acceptance.

Malformed app-owned smoke/benchmark CLI arguments exit 64 before constructing
NSApplication; they never launch the normal app. Explicit harness arguments also
take precedence over a candidate bundle marker. `LaunchModeTests` exercises this
without launching a GUI. Python smoke-wrapper tests use a fake executable, not
an application, and protect the runner's success/failure reporting.

### Headless and native authority suites

Normal launch explicitly enables Milkdown with persistent app settings. Existing
native GUI smoke/benchmark constructors remain native-only; their coverage must
not be presented as rich WebKit/physical IME acceptance. No test changes real
bookmarks/preferences/login or reads user notes.

`WebEditor/Milkdown` contains exact locked web dependencies, authored editor and
actual bundled-JS headless regressions. `npm test` there runs separately from
Swift tests; it is not silently counted as GUI acceptance. Native tests verify
source/lock/bundle/notices hashes without requiring Node/network, source snapshot
authority and settlement ordering, failed captures/saves, original-byte no-write
paths, and retaining final source before closed presentation is cleared. Mode
regressions cover latest unsaved source in both directions without file writes or
baseline changes, failed capture/import retention, busy/reentry/closed/reset
guards, untitled drafts and .txt/large fallback. Actual bundled-JS tests cover
mode replacement, editing after import, no cross-replacement undo and stale clears.
Toolbar appearance/accessibility and physical composition focus remain GUI gates.

`Scripts/build-milkdown-candidate.sh` builds/signs a separate marked candidate,
never launches it. See [MILKDOWN-EDITOR.md](MILKDOWN-EDITOR.md) for exact
reproduction, normalization scope, supported/fallback inputs and remaining
physical IME, GUI, accessibility, crash and whole-app resource acceptance.

The read-only Ubuntu web-editor CI job uses pinned Node 22.23.5 and official
setup-node v6 at a verified commit SHA. It installs the lockfile from the public
registry with no lifecycle scripts/user npm config/audit, regenerates committed
assets/notices/inventory/manifest, runs actual bundle tests and checks drift.
The trusted development publisher requires both web-editor and macOS success;
its macOS artifact identity, permissions and freshness/rollback checks remain.
Normal Swift builds still require neither Node nor network. Offline workflow
contracts are tested alongside the existing publisher suite.
