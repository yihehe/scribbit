# Editor configuration map

Verified against the installed Crepe/Milkdown 7.23.0 runtime/types and bundled
behavior tests. These are integration/build-time options, not automatically
user-visible settings in Scribbit.

## Crepe: ready-made editor UI

Crepe accepts `features` to include/exclude feature plugins and `featureConfigs`
to customize individual features. Disabling a UI plugin does not necessarily
remove its underlying Markdown syntax or formatting commands.

| Feature flag | Examples of feature options | Scribbit policy |
| --- | --- | --- |
| Toolbar | Selection toolbar buttons/groups, icons and labels | Off: no floating bold/italic popup |
| TopBar | Fixed toolbar items, heading options, icons | Off |
| BlockEdit | Slash-menu entries/groups and labels; block handle placement/icons | Slash menu kept; floating drag/add widget disabled through lower-level block target filter |
| LinkTooltip | Link popup icons, placeholder, copy callback | Enabled |
| CodeMirror | Code-block editor theme, language/CodeMirror component configuration | Enabled |
| ListItem | Bullet and checked/unchecked checkbox icons | Enabled |
| Table | Row/column, alignment and drag-handle icons | Enabled |
| Placeholder | Placeholder text; whole-document or per-block mode | Off |
| Cursor | Drop/gap/virtual insertion cursor color, width and virtual behavior | Enabled; not the mouse cursor style over list markers |
| ImageBlock | Image editing/upload component configuration | Off; app asset authorization/storage is not implemented |
| Latex | KaTeX options and edit-confirm icon | Off; enabling also needs compatible offline assets/CSP |
| AI | Optional AI feature/provider integration | Off; not configured or authorized by Scribbit |

The code/text styling is also configurable through theme CSS and variables, as
Scribbit does for fonts, colors, editor padding and state-dependent list-marker
cursors.

## Milkdown and ProseMirror: lower-level extension points

| Boundary | Configurable behavior | Existing Scribbit use |
| --- | --- | --- |
| Schema/presets | Nodes, marks, Markdown parse/serialize runners and DOM representation | Whitespace-preserving text serialization, without adding an editor document type |
| Remark/stringify plugins | Markdown AST transforms, escaping/encoding and handlers | Preserve marked/table boundary whitespace and whitespace before soft breaks |
| Editor view props | Copy text representation, paste/drop handlers and event behavior | Rich HTML copy/paste with readable text fallback and image/drop restrictions |
| Commands/keymaps | Formatting and structural commands, key bindings | Existing formatting/list commands remain available with the selection toolbar off |
| Block/slash plugin configuration | Eligible handle targets, menus, placement and visibility policy | Public blockConfig.filterNodes hides the floating handle without removing slash commands |
| Transactions/plugins | Read-only policy, filtering, history and lifecycle observation | Size/depth admission, native dirty/checkpoint notifications and snapshot settlement |

These hooks let an application adapt behavior; they are not all single boolean
flags. Our whitespace and clipboard adapters are small custom integration code,
whereas disabling the selection toolbar is just one built-in feature flag.

Some options declared in types have proven ineffective in the pinned behavior
(for example the block handle shouldShow callback), so verify the actual runtime
and a regression test rather than relying solely on a declaration or source file.

## Scribbit, not the editor library

The notch window, hover/dismiss timing, animation, pinning, native settings,
file chooser/bookmarks, file watching, save/conflict policy, launch at login,
security-scoped access and native/WebKit bridge are app responsibilities.
Crepe feature flags do not configure these.

In particular, an image feature flag is not permission to read/write arbitrary
files. Safe image support still requires the separate authorized storage and
transaction design described in MILKDOWN-PRODUCTIONIZATION.md.

## Selection toolbar setting

In WebEditor/Milkdown/editor.js:

```js
features: {
  [Crepe.Feature.Toolbar]: false,
}
```

This excludes the toolbar plugin rather than hiding it with CSS. The commonmark
formatting commands/keymaps are independent. The bundled test selects text,
applies bold and emphasis through real registered commands, verifies those marks
and a saveable snapshot, and checks that no milkdown-toolbar widget exists.
