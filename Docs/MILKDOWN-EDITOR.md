# Milkdown Markdown editor

Normal Scribbit launch uses Milkdown/Crepe **7.23.0** for supported `.md` and
untitled notes, inside the existing AppDelegate, NoteModel, NoteSession,
coordinated WatchedNoteStore and NotchPresenter. Files remain Markdown, not JSON.
Production bundle ID, persistent bookmarks/preferences and Launch at Login
semantics are unchanged. Unsupported source, .txt and larger initial files stay
editable in the native Source editor. No automatic migration occurs.

## Builds and safe developer evaluation

`Scripts/build-app.sh` produces the normal signed app with rich Markdown enabled.
Building does not launch, touch real preferences/notes or register login items.
The separately marked developer helper remains available:

```sh
Scripts/build-milkdown-candidate.sh
```

Its default output is `build/milkdown-candidate/Scribbit Milkdown Candidate.app`,
with bundle identifier `com.stephenhe.Scribbit.candidate.milkdown` and
`ScribbitMilkdownCandidate=true`. It uses the real shell but RAM-only preferences,
no login registration and a blank untitled draft. It neither imports production
bookmarks nor grants access to real notes. The explicit `--milkdown-candidate`
flag has the same developer-isolation semantics. Native-only GUI harnesses remain
explicit native baselines; their tests do not exercise Milkdown GUI behavior.
The marker is a developer acceptance tool, not a user-facing opt-in requirement.

## Source and feature policy

The upstream empty-block placeholder feature is disabled: blank notes and empty
paragraphs show no “Please enter…” prompt. This uses Crepe's public feature flag,
not CSS that merely hides an active placeholder.

| Feature/input | Current behavior |
| --- | --- |
| `.md` / untitled initial source up to 1 MiB | Actual Milkdown rich Markdown if import/source checks succeed |
| `.txt`, other extensions, larger notes | Existing native source editor with a reason; native 64 MiB acceptance remains |
| Basic formatting, headings, bullet/ordered/nested lists, tasks, quotes, code, tables and ordinary links | Enabled with actual keyboard/edit/save/reopen regression fixtures |
| Used reference links | May normalize to inline links on actual edits, preserving resolved URL, title and link text |
| Unused/duplicate reference definitions | Native fallback; never silently remove them or apply incidental last-definition-wins behavior |
| Raw HTML, footnotes, possible frontmatter, mixed/legacy line endings | Native fallback; no destructive conversion |
| Exact no-attribute standalone `<br>`, `<br/>`, `<br />` | Admitted only in upstream empty-paragraph placeholder positions. Attributed/event-handler tags, inline HTML and other tags remain fallback |
| Images in existing source | Native fallback until authorized asset storage is integrated |
| Image/file paste/drop | Clearly rejected before inserting/writing bytes; not silently broken |
| Floating block drag/add handle | Disabled through the public block target filter; BlockEdit stays enabled so slash commands still work |
| Automatic heading DOM ids | Public `headingIdGenerator` configured to return empty ids; derived anchors are not part of this editor. Actual heading levels/text and Markdown link semantics stay checked |

### Separate admission, document and file limits

| Bound | Purpose / recovery |
| --- | --- |
| 1 MiB initial UTF-8 source | Admission only: larger existing files stay in editable native Source |
| 2 MiB canonical document JSON | Every prospective rich document-changing transaction is checked before application; oversized edits are rejected visibly without modifying the draft. Node-heavy initial imports are checked before DOM replacement |
| 64 MiB exported UTF-8 source | Same authoritative file cap as the native store. An already-loaded rich draft may grow past 1 MiB and still save or switch to Source without truncation; next open uses Source if above the initial threshold |

The document quota is not a total bridge-message or process-memory guarantee:
source and document are separate bounded fields, with temporary copies/DOM/history
and WebKit process overhead. BOM/CRLF restoration is checked against the file cap.
Do not reintroduce the former 1 MiB export restriction, which could strand a valid
rich draft. Native size/baseline encoding uses withoutEscapingSlashes, matching JavaScript
slash/control/Unicode byte budgets rather than accidentally doubling slash-heavy
text. Exact-boundary and unchanged-tree reuse tests cover the alignment.
The transaction admission gate measures canonical JSON, not Markdown;
it does not run full Markdown serialization on every keystroke.

Component-only gate timings on this arm64 macOS host, Node 22.19.0/JSDOM, with
30 samples after five warmups: median/p95 were 0.008/0.012 ms at 4 KiB,
0.113/0.119 ms at 64 KiB and 1.863/2.552 ms at 1 MiB. These are the actual bundled
prospective-transaction gate only, excluding DOM/layout/paint/IME and all WebKit
or whole-app costs. Reproduction is in the bundled-JS tests; ignored raw output
is build/milkdown-admission-benchmark.json. They do not prove interactive latency.

**Images are not enabled.** An owned test fixture folder is not a production
permission model. Selecting a note does not authorize
writing sibling assets. See the staged plan for explicit directory grants,
transaction/order/quotas/undo and Save As/copy portability work.

### Exact bytes versus edited Markdown semantics

Native retains the original source and canonical committed editor tree. Every
flush includes that native-owned generation/tree; exact unchanged equality
bypasses Markdown serialization. Swift independently verifies the returned tree
before accepting missing source. Browser hints/revisions alone cannot authorize
reuse or let an empty source replace nonempty content. This covers clean closes,
read-only opens, file switches and edit-then-Undo. Clean saves do not rewrite.
The session preserves original byte baselines, including UTF-8 BOM, for exact
conflict checks; uniform CRLF is restored on actual rich edits.

Before sending the loaded baseline, the bridge settles upstream appended
transactions under the loading/historyless gate. Milkdown can append a terminal
typing paragraph on a later selection transaction; ignoring this would make
mere focus appear dirty. Actual tests cover focus/no-op selection after loading
paragraphs, lists, code and tables without dirty notification or phantom undo.

Edited export checks retain actual text, significant code whitespace, node
structure, checkbox state, order, link targets/titles and other semantic attrs.
Only these inspected upstream presentation differences are normalized:

1. Noncontent `spread` flags on list/list-item nodes.
2. Recognized per-item `label` and `listType` rendering metadata, derived only
   under an actual bullet/ordered parent from its type, starting order and item
   index. Parent order, checkbox state, nesting, text, paragraph counts and all
   other/custom attrs remain strict. Unknown marker/type values are not normalized.
3. **One** terminal empty typing paragraph, which upstream `docSchema` explicitly
   omits. Never all empty paragraphs, nested empty items, nonempty terminal
   paragraphs or empty paragraphs between content blocks.

A concrete regression was lifting the nested ordered item in:

```markdown
- one
  1. two
```

Pressing Shift-Tab in `two` moves it into the actual bullet parent, but pinned
Milkdown retains that nonfirst item's old rendered marker `label=1.` and
`listType=ordered`. The serialized Markdown and reopened tree correctly contain
two bullet items. CommonMark/GFM list-item schemas and `sync-list-order-plugin`
show why: durable kind/start belong to the parent, while the order-sync plugin
does not reset this bullet sibling's marker. The comparison projection fixes the
false refusal without mutating editor transactions or vendor code. The upstream
visual marker can remain stale until reopen; this is not a visual-label fix.

Failed export now includes a bounded, content-free mismatch category and schema
path; it never echoes text, links or attribute values. A real different case stays
blocked: Tab before a soft line break can insert trailing spaces that upstream
serialization trims. The draft remains editable and unchanged, with a specific
remove-trailing-indentation or Undo hint. Source switching uses the same safe
snapshot and does not bypass genuine loss; explicit discard remains recovery-only.

Upstream represents additional intentional empty paragraphs using its existing
`<br />` Markdown placeholder. The editor permits that exact safe placeholder
and tests save/reopen and repeated clean cycles. It does not inject a custom HTML
serializer or patch vendor source. Whitespace/marker/reference syntax may still
normalize after an actual edit; this is not a byte-identical edited serializer.

Independent remark source-AST inspection catches unsupported initial-import
semantics before the ProseMirror roundtrip check can miss them. It resolves only
used link definitions, retaining unused definitions for rejection and rejecting
duplicates. Definitions, text and URLs are not blindly discarded. This finite
adapter/corpus is not a proof of losslessness for arbitrary Markdown.

## Block controls

The floating gutter block widget (drag grip and its attached add button) is not
shown for paragraphs, list items or other blocks. This uses the public
`@milkdown/kit/plugin/block` `blockConfig.filterNodes` callback, appended after
Crepe's default BlockEdit configuration so there are no eligible drag targets.
BlockEdit itself stays enabled: disabling it would also remove the slash menu.
Pinned 7.23.0 declares a blockHandle.shouldShow option but its provider does not
consume it, so the editor does not rely on that ineffective option, CSS-only
hiding, vendor edits or production DOM mutation.

The actual bundled headless regression supplies only geometric hit-testing,
then drives the real pointer handler/service/provider: configured targets keep
the handle hidden, a positive control permits the same handle to show, and the
production filter hides it again. A separate regression types slash queries and
runs the real Bullet List, Task List and Code actions. Existing keyboard-created
lists/tasks/fences and Tab/Shift-Tab regressions remain. These are not physical
macOS pointer/visual acceptance tests.

## Real application lifecycle

The concrete asynchronous editor settlement boundary is shared by Save, Close,
Save As and Copy. Dirty decisions before Choose/Quit/Reset inspect the current
composition-settled editor document without forcing export, so unsupported rich
content cannot make explicit Discard impossible. Reload/Reset/Discard invalidate
the generation; stale callbacks cannot intentionally restore old notes.

The browser freezes editor and toolbar-driven document transactions before the
final snapshot and remains frozen through store completion. Errors/timeouts keep
the draft and surface visible. Native exact-byte conflicts, atomic replacement,
file watching and new-file-only untitled Save As remain in their existing worker
path. No web code receives a note path or writes a selected note.

`NoteModel.close` retains the accepted source separately before clearing hidden
presentation, so the browser's committed baseline is finalized with actual saved
source, not an already-cleared empty model. A dedicated native regression covers
that close/finalization order.

The editor reuses the existing expanded-footer preview-button position for
**one Rich ↔ Source editor toggle**. Both modes are editable. The native-only GUI
harness retains its legacy read-only Markdown preview; normal rich editing does
not bind that preview flag to browser read-only state. There is no everyday duplicate
Use Source button or redundant editor status row.

Rich → Source owns the model busy gate, obtains one latest composition-settled
snapshot, accepts its Markdown into the model and only then deactivates/clears the
browser generation. It does not save, mark saved or change the actual file
baseline. Failed capture/export keeps Rich visible, editable and recoverable with
an error. Source → Rich commits native composition before taking the gate and
imports the newest source; the active mode changes only after success. Unsupported
Markdown, .txt and oversized sources remain editable Source with a reason.
Successful mode changes clear stale operation errors. Discard Rich Draft appears
only for recovery/error states, with explicit destructive confirmation; a normal
mode change never asks to discard. WebKit crash Restore remains available.

Rich selection and independent scroll metadata are checkpointed for unchanged
source/file. Native source retains independently remembered, UTF-16-clamped
selection and viewport metadata. There is no promise of DOM-to-source cursor
mapping: changed source does not reuse a stale rich position. Actual document
replacement starts that editor's new undo history; undo cannot cross documents.
Structural node selection restoration remains a later acceptance item.

Visible-note confirmations, Save As/Copy and errors use camera-safe attached
sheets at the real parent ordering band, under dismissal/focus holds. Hidden-note
Open/New pickers may still use app-modal panels, where the elevated note cannot
cover them. This avoids the earlier hidden Reload confirmation deadlock without
raising arbitrary global window levels or touching WebKit private views.

## Recovery, resources and security

- Finite cancellable checkpoint debounce retains a bounded native RAM mirror of
  committed browser transactions. WebKit termination keeps an error/recovery
  surface; Restore reloads the last acknowledged document. Latest unacknowledged
  edits/live preedit may be missing. No persistent recovery journal or zero-loss
  promise was added.
- Close releases source/history/RAM mirror after collapse, retaining only small
  position/fingerprint metadata. WebKit remains warm; whole-app plus helper-process
  memory/energy must be measured before selecting a production lifetime policy.
- Static HTML/JS/CSS and code grammars are bundled. Nonpersistent WebKit storage,
  deny-by-default CSP, no connections/CDN/fonts/analytics/remote images, exact
  resource routing, blocked navigation/new windows and main-frame/origin/nonce/
  generation/request/revision verification remain enforced.
- Pinned Milkdown 7.23.0 already sanitizes rendered anchor destinations with its
  upstream `sanitizeLinkHref` sink. It neutralizes javascript, vbscript, data,
  file and unknown explicit schemes, including mixed-case/control/zero-width/BOM
  obfuscation. The stored destination and Markdown are not stripped or rewritten;
  no-edit settlement still reuses original bytes. Markdown entity-encoded schemes
  decode before rendering and are neutralized too. Percent-encoded protocol text
  is a relative URL, not an executable scheme. Tests exercise these distinctions
  against the actual bundled editor, including literal URLs inside code. Upstream
  also allows tel/ftp, but the editor does not navigate any external link:
  native navigation allows only its exact bundled document route. CSP and the
  static resource handler remain independent barriers. No duplicate custom scheme
  parser or content-stripping import rule was added.
- AI, LaTeX and Crepe image-block features are disabled. No upstream fork or
  private OS APIs/swizzling are used. Public heading-id configuration avoids
  weakening all attribute comparisons.
- Exact lock, runtime inventory and complete license texts are bundled. Native
  hash verification runs with Swift tests without npm/network. Most dependencies
  are MIT/BSD/ISC; one declares `(MPL-2.0 OR Apache-2.0)`. Notices include the
  complete texts; this is not legal-clearance advice.
- The normal Swift build does not invoke Node. The read-only CI web-editor job
  installs exact locked public packages without lifecycle scripts, rebuilds/tests
  the actual bundle and rejects generated drift. A main-push development release
  requires both macOS and web-editor jobs. Node 22.23.5 and the official setup-node
  v6 commit 249970729cb0ef3589644e2896645e5dc5ba9c38 are pinned; that SHA was verified
  from the official GitHub ref API and its action metadata. Deliberate regeneration:

```sh
cd WebEditor/Milkdown
npm_config_cache="$PWD/../../build/npm-cache" npm --userconfig=/dev/null \
  --registry=https://registry.npmjs.org ci --ignore-scripts --no-audit --no-fund
npm run build
npm test
```

The source formatter used during development was an ephemeral project-cache tool,
not a runtime/build dependency. Generated JS grammars contain significant
trailing template-literal whitespace; `.gitattributes` exempts only that file.
`remark-math`'s tarball omits a license file; its upstream MIT license is retained
under `WebEditor/Milkdown/licenses/remark-math-LICENSE` and included in notices.

## Evidence and remaining gates

| Check | Evidence / result |
| --- | --- |
| Actual bundled editor tests | 37 tests; real keyboard transactions, no-edit/Undo, source/edited corpus, task toggle, list Tab/Shift-Tab, code whitespace, tables/empty cells, links/references/orphans, plain multiline paste, composition DOM events, state locks, history, generation clears, first-focus caret settlement and upstream unsafe-link DOM neutralization, empty-placeholder removal and mode replacement/generation isolation |
| Native/core/filesystem suite | 159 tests in 25 suites with approved host coordination; includes resource hashes, source authority, settlement/failure/conflict/reset and close-before-clear and bidirectional no-save mode-switch regressions |
| Signed app builds | Fresh normal app and separate RAM-only developer app; strict signature verification |
| CI helpers | Three system-Bash scenarios and 19 offline publisher/workflow contract tests; no hosted publication |
| Actual GUI/WebKit/physical IME/VoiceOver/clipboard/process-crash injection | Not run; headless DOM events do not establish OS-level acceptance |
| Whole-app startup/open/close/idle/hidden CPU and app-plus-WebKit RSS | Not measured; no resource budget or lightweight-performance claim |
| Real notes/preferences/login/install/restart/commit/push | Not performed; only normal entrypoint enablement changed by explicit authorization |

Local logs live in ignored `build/milkdown-no-block-handle-js-tests.log`,
`build/milkdown-no-block-handle-tests.log`, `build/milkdown-no-block-handle-build.log` and related
synthetic corpus/characterization JSON files. Initial sandboxed coordination
failures were rerun with approved host access; coordination was not bypassed.

Remaining release-acceptance gates: actual disposable-note GUI acceptance, broader
source/property corpus, resource comparison, production image authorization and
transactions, and final review/rebase/explicit user approval are still required.
Normal default enablement is explicitly authorized; it is not evidence that
these acceptance gates have passed.
