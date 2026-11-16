# Native editor and simple Shift-Tab

Current native-editor design, version 0.5.2.

## Decision and scope

Scribbit uses Apple's NSTextView with a small adapter, not a from-scratch text
layout/input engine or a third-party editor fork. macOS 14 is the minimum.

The only custom editing command is `NoteTextView.insertBacktab`. Normal Tab,
composition, selection, clipboard, find and ordinary typing remain AppKit-owned.
The outdent command is a separate non-typing edit transaction, implemented using
public AppKit APIs.

## Behavior

| Input/state | Result |
| --- | --- |
| Tab | Existing AppKit behavior: inserts a literal tab |
| Shift-Tab, caret anywhere in a line | Remove one leading tab or up to four leading ASCII spaces |
| Shift-Tab, selected lines | Apply the same rule to each touched line in one undoable action |
| Selection ends at the following line's start | Do not outdent that following line |
| Internal tabs, unindented line, empty EOF line | No change and no focus navigation |
| Read-only, active preedit, multiple selections | No custom edit |
| Delegate veto | No edit |
| Undo / Redo | Restore/reapply the whole outdent; preceding typing remains a separate action |

Only leading indentation is changed. This is not a shortcut for deleting a tab
in the middle of text. Newline bytes, combining sequences and surrogate pairs
are preserved. The pure planner uses NSString/UTF-16 offsets to match AppKit.

## Implementation

```mermaid
flowchart LR
    Key[AppKit insertBacktab command] --> Guard[Editable / no preedit / one selection]
    Guard --> Plan[Pure UTF-16 outdent plan]
    Plan --> Permission[shouldChangeText inRanges / delegate veto]
    Permission --> Edit[One text-storage replacement]
    Edit --> Notify[Restore mapped selection / didChangeText]
    Notify --> Undo[Scoped native undo action named Unindent]
```

- `Sources/ScribbitCore/TextIndentation.swift` computes one replacement and
  mapped selection; it has no UI, preferences or I/O.
- `Sources/Scribbit/NoteTextView.swift` applies that plan. Native typing
  coalescing is broken at command boundaries. A balanced undo group makes the
  command one action, and the standard change notifications update the model.
- `Sources/Scribbit/EditorView.swift` supplies the plain-source configuration
  and SwiftUI binding. Exact-byte snapshots distinguish external source changes
  from chrome updates. Chrome updates do not overwrite live native preedit.
  External replacement clamps selection and clears undo; editing commands never
  reset the whole editor string.
- `AppDelegate` uses public `unmarkText` before Save/Close so pending composition
  is accepted before persistence. It does not implement or reconstruct an IME.
- Edit menu actions forward to the active editable NSTextView's undo manager.
  Public undo/redo-completion notifications keep the SwiftUI source in sync even
  when native history does not deliver `textDidChange`. Observers are filtered to
  that editor's manager, capture views weakly, and are removed on teardown/deinit.
- Native undo, TextKit, clipboard and input handling are not forked or swizzled.

## Restoring editing position

### Cursor and focus

`NoteModel` keeps one native UTF-16 selection range for the last successfully
opened file, separate from source text. Close can release its outgoing buffer
without erasing that range. It is RAM-only: quitting loses the position, and
successfully selecting another URL resets it. Failed opens/saves/reloads do not
erase it. Successful opens still read disk first; explicit reload also clamps
the current position against its newly loaded source.

The coordinator checkpoints selection notifications and completed text/history
changes. These checkpoints do not publish SwiftUI changes or scan the document.
Synchronization and live marked-text notifications do not replace the checkpoint;
Save/Close accept composition through `unmarkText` before checkpointing its final
selection. A monotonically advancing open/reload revision distinguishes a restore
request from a chrome update, even when source bytes happen to be unchanged.
Recreating the editor after preview also restores the selection.

`TextSelection.clamped` bounds offsets without overflowing, floors a caret inside
a composed character to its beginning, and expands a partial selection to whole
characters. It does not diff/remap offsets through external edits. Only actual
source replacement clears native history; restoring a selection alone does not.
After reveal/layout the controller preserves a restored viewport, or shows the
native selection if no valid viewport is available.
Both menu-open and completed hover-open activate the panel and make the editor
first responder at its restored selection. This lets typing resume without a
click that would otherwise relocate the caret. Hover entry still requires its
configured dwell (100 ms by default) and a fresh eligibility check after reading
disk. Losing activation closes an unpinned note even if no typing/click occurred
after hovering.
There is no delayed focus timer or custom mouse handling.

### Independent viewport restoration

Cursor and viewport are separate state: scrolling to read need not move a caret.
Before Save/Close the controller captures the clip-view origin before accepting
composition; editor teardown also captures it when entering preview. There is no
scroll observer, per-scroll document scan, polling, or published SwiftUI update.

On successful close the existing serial file worker computes a SHA-256 fingerprint
of the displayed/saved UTF-8 source using Apple's CryptoKit. Only this 32-byte
fingerprint, selection and scroll origin survive session/UI source release.
The production store separately retains its bounded watcher-validated snapshot. Each open
fingerprints the validated store snapshot on the worker; explicit reload bypasses
the store cache. Matching file
URL and fingerprint permit viewport restoration; changed bytes, a different file,
or a new app instance discard it. Same-length external edits and canonically equal
but byte-different Unicode also invalidate it. Failed operations keep the existing
position. Explicit reload preserves the viewport only for identical source.

`NoteTextView` owns a one-shot pending origin applied during native layout, after
TextKit lays out the document and AppKit constrains the origin to valid bounds.
This also supports preview recreation. Focus preserves the current viewport rather
than unconditionally scrolling the caret into view again. No repeating callback
locks the scroll position: subsequent editing and scrolling remain AppKit-owned.
Resized displays/viewports may clamp the remembered pixel offset; this is not a
semantic line anchor. Read-only Markdown preview has no separate saved viewport.

```mermaid
flowchart LR
    Native[Native selection / committed edit] --> Position[One RAM range in model]
    Close[Successful close] --> Release[Release hidden source only]
    Open[Open / explicit reload] --> Disk[Validated store snapshot / explicit disk reload]
    Disk --> Clamp[Clamp range to UTF-16 character boundaries]
    Position --> Clamp
    Clamp --> Restore[Restore native selection]
    Disk --> Match{Same file and source fingerprint}
    Match -->|yes| Viewport[Restore saved viewport within current bounds]
    Match -->|no| Caret[Scroll restored caret into view]
```

## Regression tests and the event-boundary finding

Pure tests cover tabs/spaces/mixed indentation, line boundaries, no-ops,
whitespace-only lines, malformed ranges, CRLF/CR/LF/Unicode separators,
combining characters and UTF-16 selection mapping.

The opt-in GUI harness checks an app-local Shift-Tab event, caret and multiline
selection, atomic undo/redo, binding, preceding-typing isolation, read-only and
delegate-veto guards. It also checks composition acceptance/replacement/cancel,
outdent during preedit, chrome changes during preedit and Save/Close persistence.

The initial direct-insertion fixture left an AppKit undo event open at grouping
level one. The next command therefore shared that event, causing Undo to remove
both fixture typing and outdent. A harmless app-local key-up now ends the
synthetic typing event, and the harness asserts grouping level zero before the
next command. Production does **not** inspect grouping levels, close AppKit's
event groups, change groupsByEvent or manufacture keyboard events.

This distinction is important: do not reintroduce event-group manipulation into
the editor to accommodate an inaccurate test driver. The regression still checks
the source, selection and model after Undo/Redo, not merely command dispatch.

The shell test dispatches actual Edit menu actions and verifies Undo/Redo of
committed caret composition in both source and model. This is not proof of every
selected-source history or physical input-method workflow. Physical candidate
UI, dead keys, dictation, keyboard-layout variants, accessibility and real notch
interaction still need manual acceptance.

See `VALIDATION.md` for current commands, results and acceptance limits.
Component benchmark output does not establish whole-app resource costs.

## Build and run tests without changing the current app

```sh
Scripts/test.sh
Scripts/build-app.sh
Scripts/gui-smoke.sh native "$PWD/build/smoke"
```

GUI launch and actual filesystem coordination may require approved host access.
Tests use project-local disposable files and do not change production preferences,
login registration, the general clipboard or the selected user note.

The build script assembles a fresh signed bundle without retired notices.
An existing destination bundle is preserved in the package staging directory.
Building does not quit, launch, install or change login registration.
