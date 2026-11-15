# Scribbit

A lightweight macOS notepad tucked into your notch. Hover to capture a thought,
then get back to work. Plain-text files, Markdown preview, and no cloud required.

**Status:** Build from source (version 0.5.2). No notarized download or universal
binary is available yet. Editing uses Apple's NSTextView with a small
Shift-Tab command; there are no third-party runtime packages.

A small native macOS menu-bar app for one file-backed note, expanding directly
from the notch with a spring-animated black silhouette. Move the pointer to
the notch for 250 ms, click to write, and press **Done** or **Escape** to save and hide it.
On displays without a notch, use the top-center 120-point strip.

**Requirements:** macOS 14 or later; Swift 6 / modern Xcode Command Line Tools to
build. There are no third-party runtime packages, web views, network services, or account.
The app and supplied CLT test-framework fallback require macOS 14. Builds target the current architecture.

## Build and use

```sh
git clone https://github.com/yihehe/scribbit.git
cd scribbit
Scripts/test.sh
Scripts/build-app.sh
```

The result is `build/Scribbit.app`. Move it to `/Applications` (or
`~/Applications`), then open it in Finder. **Run the app bundle, not the raw Swift
executable:** Launch at Login needs a stable installed bundle path and signature.
The build script uses an ad-hoc signature for local use. For distribution, set
`SIGNING_IDENTITY` to a Developer ID identity, notarize, and staple yourself;
notarization and universal distribution are not included.

First launch asks for an existing file. Cancel if you prefer **Create Note File…**
in the menu-bar menu. The selection must be a regular UTF-8 text/Markdown file no
larger than **2 MiB**. Extensions are not enforced. RTF, Word, PDF, and non-UTF-8
encodings are deliberately unsupported. Selecting a symlink edits its resolved
target, not the symlink itself. Create does not truncate an existing file.

| Interaction | Result |
| --- | --- |
| Hover over notch/top-center strip for 250 ms | Fresh disk read, then editor opens below the camera |
| Menu bar → Open Note | Same behavior; keyboard/accessibility-friendly fallback |
| Choose Note File… / Cmd-O | Saves the current note first, then selects another file |
| Done / Cmd-Return / Escape / Cmd-W | Saves dirty content, then hides |
| Click outside / switch apps | Saves and hides, unless a dialog or save is already in progress |
| Normal Quit / system termination request | Attempts save; refuses termination if saving fails |
| System sleep notification | Best-effort save; OS may suspend before it completes |
| Cmd-S | Saves without hiding |
| Tab / Shift-Tab | Tab inserts a literal tab. Shift-Tab removes one leading tab or up to four leading spaces from current/selected lines, with atomic undo/redo |
| Cmd-F, Cmd-Z, Cmd-Shift-Z, clipboard shortcuts | Native find, undo, redo, cut/copy/paste |
| Pin button | Keep the working surface open across pointer exit/outside click/app switching |
| Bottom chevron / Cmd-, | Expand/collapse file, pin, preview, Done, status, and animation controls; collapsed on each open |
| Animation Speed menu / bottom slider | Persisted 0.5×–2× playback rate in 0.25× steps; 1× keeps the reference motion profile |
| Eye / pencil button | Read-only inline Markdown preview / plain source editing |
| Launch at Login | Enables/disables macOS Service Management registration |
| Show Frog in Left Notch Wing | Optional frog-and-pencil mark inside a black extension connected to the camera; off by default |

A hover-opened note collapses 180 ms after the pointer leaves; moving back cancels
that dismissal. Click the pin button to keep it open while writing. A menu-opened
note does not close merely because the pointer is elsewhere. Hover reveal does not
steal keyboard focus: click to edit. The top header is gone; file/actions/status
live in a bottom disclosure that starts closed, leaving only a 20-point chevron.
Save errors and recovery actions are never hidden by that disclosure. After explicitly closing over the notch, leave
the trigger region before reentering to reopen. The pinned surface also ignores
outside clicks/app deactivation, but Done/Escape and normal quit still save/close.

## Animation and resting wing

Use **Animation Speed** in the menu or the slider inside the bottom controls.
0.5× is half-speed, 2× is double-speed. Shape, content growth/fade, and completion
use one playback rate without changing the spring's bounce or overshoot. A change
during animation applies to the next transition. Hover entry/exit delays are not
changed. Reduce Motion retains its fixed 140 ms fade and no spring/growth.

The pencil's left wing shares one continuous contour with the camera cutout;
opening/collapse interpolate its left-shifted center as well as its size. It is
not a separate icon beside the notch. See `Docs/INDICATOR.md` for geometry/limits.

## Launch at login

First launch requests registration using `SMAppService.mainApp`. macOS may require
approval in **System Settings → General → Login Items**. The menu refreshes registration
state each time it opens; selecting a pending-approval item opens System Settings.
Later user changes in System Settings are not automatically undone on launch.
If registration fails, use the menu to retry after installing the bundle.

Registration is implemented, but only an actual approved login cycle on your Mac
can validate automatic startup. Rebuilding/replacing an ad-hoc-signed app may
invalidate macOS login approval. Use a stable signing identity for everyday use.
To uninstall, disable Launch at Login first, quit, and delete the app.

## Saving and recovery

- Each hidden-to-open transition rereads the selected file; an already-visible
  editor is never silently reloaded. The editor remains unavailable until read
  succeeds; failed reads never expose an empty writable substitute.
- Dirty content is compared with the exact bytes read at open/last save, inside
  `NSFileCoordinator`, then written atomically. Read and write transactions use
  a dedicated serial worker, not the UI thread. Controls freeze during I/O.
- If another editor changes/deletes the file, **your buffer stays open** with a
  visible error. Use **Save a Copy…** to preserve your version, or **Reload from
  Disk…** to explicitly discard it after confirmation. A clean close never writes.
- Save a Copy exports the current buffer; it does not switch files, resolve the
  original conflict, or hide the editor. A failed reload preserves your edits.
- There is **no autosave journal or hidden note database**. Force Quit, a crash,
  power loss, and forced shutdown can lose unsaved edits. Use Cmd-S for long edits.
- Coordination protects against participating macOS apps, not all possible
  external writers. A non-cooperating process can still write in the final
  compare/replace window. Cloud conflicts and remote-file availability are not
  solved. Prefer a local file; keep normal backups for valuable notes.
- Atomic replacement changes the file inode; hard links are not kept in sync.
  Extended attributes/ACLs and file-provider-specific semantics are not guaranteed.

## Markdown and resources

Source text is authoritative and is never regenerated from formatted text.
The preview uses Foundation's **inline-only, whitespace-preserving Markdown**:
emphasis, strong text, code spans, and links. It is not a full Markdown renderer:
headings, task lists, tables, images, HTML, and fenced code blocks have no special
layout. No remote images are fetched. Switching preview modes recreates the text
view and resets its native undo history; saving does not reset it.

Idle behavior is event-driven: no recurring timers, disk watchers, polling loops,
network requests, or Markdown parsing while hidden. Finite cancellable work items
exist only during hover entry/exit and a transition. Core Animation morphs a mask
inside a fixed window; the editor is not relaid out on every frame. Screen layouts
update on display-change
notifications. Rendering is native AppKit/SwiftUI. Resource claims are design
properties, not a universal measured CPU/RAM guarantee; see the test report and
manual profiling instructions.

## Privacy

The app has no analytics, telemetry, cloud service, or automatic uploads.
Development outputs and test fixtures stay inside the project directory.
At runtime the installed app stores **only a file-location
bookmark, login-offer flag, indicator preference, and animation speed** in macOS UserDefaults
under `com.stephenhe.Scribbit`; note contents live in the selected file and RAM,
plus any explicit Save a Copy destination. macOS also owns login registration.
No Accessibility, Input Monitoring, or Screen Recording permission is requested:
global monitors observe **mouse events only**; keyboard events are local to the app.
Protected folders may require normal macOS Files and Folders access.

This app identity starts with its own preferences. When switching from a
differently identified development build, choose your note again and explicitly
configure launch at login. Existing note files and other apps' settings are not
migrated, deleted or rewritten. Quit any other build before opening this one.

## Project guide

- [Frog branding and editable SVG sources](Docs/BRANDING.md)
- [Native editor and Shift-Tab design](Docs/NATIVE-EDITOR.md)
- [Notch UX, matching profile, and animation limitations](Docs/NOTCH-UX.md)
- [Architecture and invariants](Docs/ARCHITECTURE.md)
- [Testing and acceptance checklist](Docs/TESTING.md)
- [Validation results](Docs/VALIDATION.md)
- [P2 indicator ideas](Docs/INDICATOR.md)
- [Apple platform API references](Docs/REFERENCE.md)
- [Next-agent instructions](AGENTS.md)
- [Contributing](CONTRIBUTING.md)

The build scripts include a **project-local** workaround for a CLT installation
where PackageDescription's private interface is older than its public interface
and dylib. No SDK or global toolchain file is edited. A normal Xcode installation
does not need this path. `Scripts/test.sh` also locates CLT's bundled Swift Testing
framework when SwiftPM does not add its framework search path automatically.

## License

Scribbit is licensed under the [MIT License](LICENSE).
