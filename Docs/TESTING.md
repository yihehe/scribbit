# Testing and acceptance

## Native-editor gate

The only editor is NSTextView plus NoteTextView's Shift-Tab command. There are
no third-party runtime packages or editor switches. Run the signed candidate
without modifying the currently launched bundle:

```sh
Scripts/test.sh
Scripts/build-app.sh
Scripts/gui-smoke.sh native "$PWD/build/smoke"
```

The GUI wrapper requires indentation, five composition contracts, native
composition history through the real Edit menu actions, Save/Close composition
persistence, and existing shell/controls/notch gates. It rejects runtime exceptions
and nonzero process status. Only the native editor argument is accepted.
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

Animation-specific checks and the rendered fixture GIF are documented in `NOTCH-UX.md`.

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
| Actual notch hover | Move into notch from another app, linger 250 ms | Editor opens below camera; no permission prompt |
| Accidental entry | Cross trigger quickly and leave | No editor |
| Reentry suppression | Open, Escape with pointer still in trigger | Stays hidden until leave and reenter |
| Alternative open | Use menu-bar Open Note / VoiceOver | Same selected file opens |
| Bottom disclosure | Toggle using chevron and Cmd-,; edit/undo/select before and after | Default collapsed, no top header, same source/selection/undo, viewport restored on collapse |
| Animation speed | Use slider/menu at 0.5×, 1×, 2×; quit/reopen; try Reduce Motion | Rate persists, shape/content stay synchronized, Reduce Motion remains short fade |
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
the notch, repeated open/close, preview, and the 2 MiB boundary file. Record Mac
model/CPU, OS, build, idle CPU, resident memory, energy impact, and any growth over
100 open/close cycles. Distinguish warm SwiftUI baseline from leaks. No recurring
timer or idle I/O is expected, but numerical CPU/RAM budgets require actual
measurements on the target Mac. The 3-second smoke interval alone is insufficient.
