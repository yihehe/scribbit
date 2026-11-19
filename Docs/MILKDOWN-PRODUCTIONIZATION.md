# Milkdown integration and remaining productionization

Status: normal rich editing explicitly approved November 17, 2026. Supported
Markdown/untitled notes use Milkdown in the normal app; persistent preferences,
bookmarks, production bundle identity and login behavior are preserved. This is
not permission to migrate notes, publish, run real notes/preferences/login tests
or claim unperformed GUI/resource acceptance. The separate signed developer
build uses RAM preferences/no login solely for safe manual acceptance.

## Stage 1: integrated source-backed rich editing

| Boundary | Implementation contract |
| --- | --- |
| Storage | Existing Markdown source remains authoritative in NoteModel/NoteSession/coordinated WatchedNoteStore. No JSON file format or automatic migration |
| Scope | Initial `.md`/untitled rich admission up to 1 MiB, 2 MiB canonical-document transaction quota, grown rich export up to existing 64 MiB file cap; native `.txt`/large/unsupported fallback |
| Save lifecycle | One current generation/request/revision snapshot barrier for save/close/copy/Save As/switch/quit/reset/reload and dirty decisions; no hiding after a failure |
| Clean note | Native-owned canonical committed tree permits original source reuse before Markdown serialization. Native independently rejects missing source for changed content; Undo-to-baseline remains clean |
| Source fidelity | Preserve BOM and uniform CRLF; independent source AST inspection catches unsupported initial import. Compare actual edited document after serialization/reparse; no broad backslash/table/link rejection |
| Dialogs | Camera-safe parented native sheets for visible-note alerts/pickers; scoped dismissal holds and no editor focus theft |
| UI | Existing footer, pin, settings, hover, shortcuts, reset and native source fallback retained; one editable Rich/Source toggle replaces read-only preview; normal app uses existing persistent preferences/login semantics, developer build uses RAM settings/no login |
| Failure | Retain source/rich draft, conflict baseline and visibility; RAM checkpoint recovery on WebKit termination with explicit latest-unacknowledged-edit caveat |
| Security | Bundled pinned code/assets/notices; nonpersistent WKWebView; deny network/navigation/frames/fonts/remote images; typed bounded messages, nonce/origin/frame/generation/request verification |

The integration reuses editor-neutral app lifecycle boundaries and actual
Milkdown JSON node names, public ProseMirror transaction/update hooks and history
commands. No vendor fork or lexical blanket rejection replaces semantic checks.
The whitespace parity follow-up adds public text-node/remark/stringify extensions
and explicit must-save fixtures; see MARKDOWN-PARITY.md. Strict source/document
authority remains unchanged.

## Stage 2: authorized images, not implicit sibling access

The editor deliberately disables paste/drop/file image insertion and
falls back for existing image-containing source rather than silently altering
alt text or showing broken remote images. Crepe's image-block feature uses alt
text to serialize resize ratio, which is genuine semantic loss for arbitrary
existing alt text; investigate public inline-image features or a documented
schema extension, never vendor patch upstream unnoticed.

Production image support requires explicit chosen parent/asset-directory scope,
exact relative managed references, balanced scopes across switch/reset/quit,
PNG/JPEG byte/type/pixel/pending/per-note quota checks, no traversal/symlink or
arbitrary file/remote reads, mapped insertion cancellation on undo/generation,
immutable assets committed before source save, failed-note orphan handling, and
Save As/copy portability. No selected-file bookmark implies sibling permission.
This phase must not be described as complete just because prototype images work.

## Verification and acceptance gates

- Actual bundled editor tests: keyboard-created bullets/tasks/empty items,
  code fences/language/whitespace, nested lists, tables, ordinary and reference
  links, literal markers/backslashes, Unicode, CRLF/BOM, HTML/unknown nodes.
- Native authority: latest snapshot, missing/empty/mismatched/stale source,
  clean close/switch/no-write, save then clean close, Undo-to-baseline, conflicts,
  failure/cancellation/reentry, reset invalidation and source fallback.
- Resource integrity: pinned lock, complete notices, deterministic build, native
  source/bundle/notice hash tests without npm/network required in Swift CI.
- Build signed normal and distinct RAM-only developer apps without launching or screenshots.
- The opt-in native and rich GUI harnesses now have passing disposable-fixture
  evidence in Docs/VALIDATION.md. The rich harness uses actual WKWebView and native
  snapshots but synthetic paste/process-termination callbacks.
- Remaining release acceptance: separately authorized WebKit/IME/VoiceOver/keyboard/
  sheet/hover/reset/conflict/crash tests on disposable notes and whole-app+WebKit
  startup/open/hidden/idle CPU/RSS comparison against native. JavaScript bundle
  size and headless tests do not establish resource or interaction acceptance.
