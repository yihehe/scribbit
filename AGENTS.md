# Scribbit — contributor and agent guide

## Start here

1. Read README.md, Docs/ARCHITECTURE.md, Docs/NATIVE-EDITOR.md,
   Docs/NOTCH-UX.md, Docs/TESTING.md and Docs/REFERENCE.md.
2. Inspect the actual source and tests; documentation is not proof of behavior.
3. Run Scripts/test.sh and Scripts/build-app.sh from the repository root.
4. Keep GUI/login/performance acceptance separate from unit and filesystem tests.

## Development privacy and safety

- Keep research, build outputs, fixtures and screenshots in ignored project-local
  directories. No external session logging, telemetry or automatic uploads.
- Do not read or write a real selected note, alter production preferences, register
  login items, install an app, or launch GUI tests without explicit permission.
- GUI tests must use the existing isolated settings and disposable-file harness.
- Do not commit signing credentials, local paths, generated artifacts, downloaded
  source checkouts, private notes or historical experiment logs.

## Design rules

- Prefer cohesive reusable components at demonstrated boundaries. Simplify when
  it removes coupling, duplicated ownership or a correctness risk—not merely
  lines. Do not introduce a protocol, package or general framework for an
  imagined future consumer. Preserve useful complexity that serves the UX.
- Swift native AppKit + SwiftUI, macOS 14 minimum; Swift 6 tools and Swift 5
  language mode. No third-party runtime dependencies. Do not add a dependency or
  editor fork without approval. Preserve bookmarks and settings.
- Preserve the `NoteStore` protocol boundary and UI-independent `NoteSession`.
- `SessionWorker` exclusively owns session access. Main-actor UI must not perform
  file coordination or reads/writes on the UI thread.
- Never hide or terminate normally after a failed save. Show errors and keep the
  buffer. Never substitute an empty file after read failure.
- A fresh disk read is required for every hidden-to-open transition. Do not
  silently reload a visible editor or discard its edits.
- Keep exact-byte conflict detection and atomic replacement inside coordinated
  access. Do not claim it prevents races with non-cooperating writers.
- Preserve the top-attached silhouette, fixed-window Core Animation mask, Reduce
  Motion fallback, top-anchored content arrival, and generation-guarded completions.
  Do not clear outgoing text before collapse or animate a failed save closed.
- `NotchPresenter` accepts an AppKit NSPanel and arbitrary NSView, not a
  note-specific panel/model. Keep storage and editor policy outside it. One
  cancellable transition task owns completion; phase/visibility settle in one
  place, never in superseded callers after an await. Preserve generation guards
  and replacement-aware waits. The lifecycle GUI regressions protect this.
- Keep file information/full selectable path, pin/preview, and the settings gear
  inside the bottom disclosure, collapsed per open. The collapsed footer contains
  only the chevron. Other preferences/file actions live in a native transient
  popup; do not recreate a menu-bar NSStatusItem. Command-comma uses the visible
  chevron as a fallback anchor when the gear is collapsed, not a hidden anchor or
  delayed layout retry. Keep native NSApp.mainMenu responder/keyboard actions.
  Error recovery stays visible outside the disclosure.
  Toggling information/settings must retain native selection and undo.
  Cmd-Return must work even while Done is hidden.
- Pin/Preview are togglable icon buttons, with selected appearance and accessible
  state—not preference checkboxes. About contains only the app icon, bundle name,
  version, and dismissal; do not put usage/help instructions in it.
- The popup must hold automatic dismissal while in use. Escape dismisses it
  before closing the note; explicit file/close/quit actions keep save-first
  behavior. The welcome surface must expose Choose/New and advertise expandable
  controls/Command-comma with no file open. Do not replace outgoing text with
  welcome before collapse. About is a native sheet parented at the panel's level;
  sheet attachment derives from camera-safe geometry, never a fixed screen point.
- Preserve the left resting wing shared contour and its asymmetric animation
  endpoints. Animation speed scales one whole transition clock, never hover
  deadlines or the fixed Reduce Motion fade. Validate persisted rates.
- `NoteTextView.insertBacktab` is the only custom editing command. It uses the
  pure UTF-16 outdent plan, AppKit's public range-edit permission API, one storage
  replacement, a scoped native undo group and didChangeText. Preserve no-op focus,
  delegate veto, read-only, multi-selection and live-composition guards. Do not
  replace text by assigning editor.string for commands or manage AppKit's event
  groups manually. Ordinary Tab and input methods remain AppKit-owned.
- Preserve the coordinator's exact-byte model snapshots: chrome updates must not
  overwrite live preedit, and external replacements must clamp selection/reset
  history. Save/Close accept pending composition via public unmarkText. Do not
  swizzle, reconstruct compositions or access private input-method state.
- Edit menu history actions must target the active editable native responder's
  undo manager. Keep the public undo/redo completion observers so SwiftUI/model
  source follows history changes. Filter by manager identity, capture weakly and
  remove observers on teardown/deinit. This is synchronization, not a custom
  undo engine.
- Source text is authoritative. Preview is read-only and intentionally limited.
- Keep the last file's caret/selection separate from hidden source release.
  Position is RAM-only, resets on successful file switch, and clamps to composed
  UTF-16 character boundaries after fresh reads. Selection checkpoints must not
  publish per-keystroke SwiftUI invalidations; open/reload revisions request
  restoration even for identical source. Both menu and completed hover opens
  must focus the native editor at the restored selection without a click.
- Preserve cursor and viewport independently. Capture scroll position before
  close and preview teardown; restore it once during native layout only for the
  same source/file. Compare worker-computed SHA-256 fingerprints without retaining
  hidden note text. Changed source falls back to showing the clamped cursor.
  Focus must not undo viewport restoration; do not add a scroll lock or polling.
- No polling timers, networking, global keyboard monitors, Accessibility prompts,
  or watchers just to implement notch hover. Preserve cancellation/reentry logic.
- Entry dwell uses validated `HoverDelay`, default 100 ms, range 0–1000 ms in
  50 ms steps. Zero removes the wait, not queued-work eligibility checks.
  Keep it independent of exit/animation clocks. Delay changes may restart pending
  work but must not reset `HoverGate` or close-until-exit suppression.
  The slider lives in the settings popup. Isolated settings remain RAM-only.
- File pickers and alerts inhibit automatic close. Always balance scoped access.
- Prefer changes with deterministic unit/integration tests for credible behavior.
  Keep GUI/login acceptance separate from mocked or core test results.
- Use author-scoped branch names when creating branches.
- Review licensing before reusing any third-party implementation or assets;
  preserve required notices and do not assume compatibility with MIT.
  Read `Docs/REFERENCE.md` for the Apple APIs used by the current implementation.

## Repository map

| Path | Purpose |
| --- | --- |
| Sources/ScribbitCore/ | Storage, session, indentation, geometry and motion |
| Sources/Scribbit/ | Native editor, app shell, presenter and opt-in GUI harness |
| Tests/ | Swift/app, actual-filesystem and offline CI-publisher regression suites |
| Resources/Info.plist | App identity, version and accessory-app metadata |
| Resources/Branding/ | Editable app-icon and frog-mark SVGs; see Docs/BRANDING.md |
| Sources/Scribbit/Resources/ | Committed 1x/2x template exports loaded by BrandAssets |
| Scripts/ | Build, test, coverage and opt-in GUI smoke commands |
| Docs/ | Current design, testing, platform API references and validation |

The package/executable is Scribbit; the core module is ScribbitCore. Bundle ID:
`com.stephenhe.Scribbit`. Changes to this ID create a new preferences/login
identity; do not silently change it or introduce migration code as a cleanup.

Keep artwork sources and exports in sync. Normal builds must not require Node,
Sharp or network access. BrandAssets loads the nested SwiftPM bundle explicitly
from Contents/Resources in packaged apps; do not rely on a local build-cache
fallback. Preserve strict signing and test the packaged resource lookup.

The toolchain workaround copies public manifest interfaces and a matching dylib
into ignored .build only for the known CLT private/public interface mismatch.
Never patch system SDK files or generalize it into arbitrary interface rewriting.

## Validation and completion

- Scripts/test.sh: unit/filesystem tests with coverage. NSFileCoordinator tests
  may need approved host access; do not bypass coordination to make them pass.
- Scripts/build-app.sh: fresh ad-hoc-signed build/Scribbit.app. APP_PATH may select
  a different output. Existing destination bundles are preserved, not deleted.
- Scripts/coverage.sh: report the most recent unit-test coverage, including UI
  code not exercised by that suite. GUI results do not inflate this report.
- Scripts/gui-smoke.sh native OUTPUT: opt-in native editor/composition/history,
  controls, hover, animation, presenter lifecycle and save/conflict gate.
- Release executable --benchmark-editor native OUTPUT: component-only screen,
  not proof of whole-app CPU or memory costs.
- Update current docs and Docs/VALIDATION.md when behavior or evidence changes.
  Report blocked/skipped/manual-only checks distinctly. Do not claim login startup
  without an approved login cycle, or physical-notch delivery from a screenshot.
- GUI tests post app-local events only. Synthetic typing must finish its event
  before the next command. Never move harness event-group mechanics into the
  production editor to accommodate an inaccurate test driver.
- Isolated shell checks drive the shared deactivation handler explicitly; do not
  reintroduce ambient desktop deactivation notifications into controlled test
  sequences. Production still observes the real application notification.
- Never push, publish a release, install or restart an app without authorization.
- CI retains each successful build as an artifact with repository-default
  retention. Only the separate trusted main-push job may write the mutable
  development prerelease/tag. Keep PR build jobs read-only, the stale-run guard,
  upload/checksum-before-replacement and recovery behavior. Publisher tests must
  remain offline; do not mutate a real release to validate them.
