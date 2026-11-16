# Frog-and-pencil identity

| Surface | Artwork | Delivery |
| --- | --- | --- |
| Application | Curious Tilt: sage frog, ochre pencil, forest-green layered paper | Resources/AppIcon.icns |
| Left notch wing | Chest Cross: pencil across the frog's body, smooth face | 14-point template, 1x/2x PNGs |
| Open note footer | Same Chest Cross mark, with subtle Scribbit wordmark | Reuses cached 14-point template; always visible at bottom-left |
| Reserved 18-point export | Same Chest Cross mark | 1x/2x PNGs retained as artwork; no current menu-bar item |

Editable originals are `Resources/Branding/AppIcon.svg` and
`Resources/Branding/FrogPencil.svg`. They contain vector paths, not embedded images.
The app artwork uses procedural SVG paper grain. Pre-rendering preserves that
texture across renderers; the small monochrome marks are deliberately untextured.
These original vector designs were created with AI assistance and selected by
the project owner.

`BrandAssets` loads and caches two template NSImages using SwiftPM's resource
bundle. Each contains separate 1x and 2x representations at the correct logical
size. The notch view explicitly tints white. The 18-point resource remains
available, but the app no longer creates a persistent menu-bar status item.
There is no runtime SVG parser or new runtime dependency.

The popup label is “Show frog beside notch”. The existing preference key
and default-off behavior are unchanged. That preference controls only the closed
notch wing, not the footer. The wing geometry, hover target, animation, editor
and file behavior are unchanged.

## Open-surface identity

`NoteFooter` keeps the frog/pencil plus “Scribbit” in secondary monochrome at the
bottom-left, even when information is collapsed. The mark identifies the app
without a large watermark or another action button. It reuses the existing
20-point footer row with 8 points of padding above the entire row, reserving
28 points overall. This separates the logo from the editor/preview without
making the controls themselves oversized. The centered native chevron retains
its full-width target and settings anchor.
The branding does not intercept pointer events or accept keyboard focus.
It is present in editing, preview and welcome modes, outside their conditional
content. No new asset, resource load, preference, timer or dependency is needed.

## Regenerating artwork

Normal builds use committed exports and need only the existing Swift toolchain.
Only artwork maintainers need Node.js and Sharp with librsvg filter support:

```sh
node Scripts/export-branding.cjs
```

Use an existing installation of Sharp, or provide it via NODE_PATH. The script
uses macOS iconutil and writes intermediates under ignored build/branding-export.
The reviewed exports used Sharp 0.35.5, libvips 8.18.7 and librsvg 2.63.2.
Review the paper grain again when changing renderer versions; normal app builds
remain independent of those tools because the exports are committed.
It exports all ten standard iconset representations into AppIcon.icns and four
transparent template PNGs into Sources/Scribbit/Resources. Commit source SVGs and
exports together after visual review. Never substitute a flattened screenshot
of a concept board for these source assets.

The app assembly copies the SwiftPM resource bundle into Contents/Resources,
where BrandAssets loads it explicitly. CLI builds/tests use Bundle.module.
This avoids SwiftPM's default app-root lookup, which conflicts with strict bundle
signing, and prevents packaged apps silently falling back to build caches.
Tests exercise resource lookup,
template flags, logical/pixel sizes and nonempty transparency. The isolated GUI
gate checks packaged resource lookup and the notch template. Physical-notch
optical acceptance still requires a live user review.
