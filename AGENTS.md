# Scribbit — contributor and agent guide

## Milkdown editing integration

Read `Docs/MILKDOWN-EDITOR.md` and `Docs/MILKDOWN-PRODUCTIONIZATION.md`.
Normal launch uses Milkdown for supported Markdown and untitled notes, with the
existing persistent preferences, bookmarks, bundle identity and login behavior.
Native source remains the fallback for .txt, unsupported constructs and large
notes. The separate marked developer build still uses RAM preferences/no login;
native GUI harnesses explicitly retain their native baseline, not rich coverage.
Dependencies are pinned under WebEditor/Milkdown with complete notices/offline
routing. No JSON note format, automatic migration or clean-note rewrite exists.
Preserve native-owned unchanged-tree authority before serialization, exact-byte
conflicts, async settlement/discard distinction and camera-safe native sheets.
Never broadly strip blank paragraphs/attrs to force exports through. Only known
list-item marker metadata may be projected from an actual bullet/ordered parent;
parent order, checked state, nesting/text/paragraphs and unknown/custom attrs stay
strict. Keep export diagnostics content-free: bounded schema paths/categories,
never note text, URLs or attribute values. Images are
explicitly deferred pending safe authorized storage. One editable Rich/Source
toggle occupies the old preview position; do not bind it to read-only state.
Switching settles current unsaved source under the model busy gate without saving
or moving the file baseline. Failed conversion retains the originating editable
mode. Explicit rich discard is recovery-only. Keep the native harness's preview
behavior independent. Only one explicitly armed exact native page load may
navigate WebKit; links/reloads must not replace a live draft. Each native boot
rotates its page nonce; note generations change only for explicit note actions.
Initial rich admission is
1 MiB, canonical-document quota is 2 MiB and source persistence uses the existing
64 MiB core cap. Reject over-quota document transactions before application;
never strand an admitted draft by applying the admission threshold to exports.
Keep the floating block grip/add widget disabled through the public blockConfig
filter after Crepe's defaults. Do not disable the entire BlockEdit feature: slash
commands must remain available. Pinned 7.23.0 does not consume its declared
blockHandle.shouldShow option; verify actual provider behavior, not just config.
Do not claim headless tests prove physical IME, WebKit, accessibility or whole-app
performance. No launch, real notes/preferences/login/reset, commit or push without
authorization. Incognito: no external session/vault logging or activity uploads.

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
  language mode. Pinned Milkdown runtime dependencies are approved. Do not add another dependency
  or editor fork without approval. Preserve bookmarks and settings.
- Preserve the `NoteStore` protocol boundary and UI-independent `NoteSession`.
- `SessionWorker` exclusively owns session access. Main-actor UI must not perform
  file coordination or reads/writes on the UI thread.
- Never hide or terminate normally after a failed save. Show errors and keep the
  buffer. Never substitute an empty file after read failure.
- Reopening uses the selected-note RAM snapshot only while native file/parent
  observation and worker-side identity/size/mtime/ctime checks permit it. Invalidate
  on events, explicit reload and save; reread conservatively on uncertainty. Never
  silently reload a visible editor or discard edits. The UTF-8 source/cache limit
  is 64 MiB, allocated on demand, not a process-memory or responsiveness promise.
  Confirmed Reset App must clear the cache and cancel its observations on the
  worker before the controller releases selected-file security-scoped access.
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
  inside the bottom disclosure, collapsed per open. The always-visible footer keeps
  a small, noninteractive frog-and-Scribbit brand at left and the native chevron
  centered in a 20-point row with 8 points of breathing room above it.
  Other preferences/file actions live in a native transient
  popup; do not recreate a menu-bar NSStatusItem. Command-comma uses the visible
  chevron as a fallback anchor when the gear is collapsed, not a hidden anchor or
  delayed layout retry. Keep native NSApp.mainMenu responder/keyboard actions.
  Error recovery stays visible outside the disclosure.
  Toggling information/settings must retain native selection and undo.
  Cmd-Return must work even while Done is hidden.
- Pin/Preview are togglable icon buttons, with selected appearance and accessible
  state—not preference checkboxes. About contains only the app icon, bundle name,
  version, dismissal, and the secondary Reset App action; do not put usage/help
  instructions in it. Reset requires explicit confirmation and save/discard/cancel
  for dirty text. Remove only app-owned preference keys, never an entire defaults
  domain or user files; isolated tests must not mutate login registration.
- The popup must hold automatic dismissal while in use. Escape dismisses it
  before closing the note; explicit file/close/quit actions keep save-first
  behavior. With no selected file, reveal the regular editable untitled notepad
  with Open/Save As and a visible unsaved-loss warning. Retain its RAM-only draft
  through hover dismissal; require Save/Discard/Cancel before replacement or quit.
  Save As never overwrites an unopened existing file. Do not replace outgoing
  content before collapse. About is a native sheet parented at the panel's level;
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
- Markdown files remain authoritative. Rich edits serialize only after safety
  checks; unchanged rich documents reuse the original bytes. Native-harness
  preview is read-only and intentionally limited.
- Keep the last file's caret/selection separate from hidden source release.
  Position is RAM-only, resets on successful file switch, and clamps to composed
  UTF-16 character boundaries after fresh reads. Selection checkpoints must not
  publish per-keystroke SwiftUI invalidations; open/reload revisions request
  restoration even for identical source. Both menu and completed hover opens
  must focus the native editor at the restored selection without a click.
- Preserve cursor and viewport independently. Capture scroll position before
  close and preview teardown; restore it once during native layout only for the
  same source/file. Compare worker-computed SHA-256 fingerprints independently of the
  bounded hidden store cache. Changed source falls back to showing the clamped cursor.
  Focus must not undo viewport restoration; do not add a scroll lock or polling.
- No polling timers, networking, global keyboard monitors, Accessibility prompts,
  or watchers just to implement notch hover. Preserve cancellation/reentry logic.
- Open-note hover dismissal uses the separate display-clamped retention region,
  not the exact contour. Keep both its initial decision and delayed recheck in
  sync. Never reuse the grace region for closed entry or outside-click hit testing.
- Entry dwell uses validated `HoverDelay`, default 100 ms, range 0–1000 ms in
  50 ms steps. Zero removes the wait, not queued-work eligibility checks.
  Keep it independent of exit/animation clocks. Delay changes may restart pending
  work but must not reset `HoverGate` or close-until-exit suppression.
  The slider lives in the settings popup. Isolated settings remain RAM-only.
- File pickers and alerts inhibit automatic close. Retain selected-file scoped
  access while hidden for observation; balance it on successful switch/termination.
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
