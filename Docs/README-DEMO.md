# README workflow preview

The README embeds `Images/scribbit-demo.gif`, with
`Images/scribbit-demo.png` as a still-image alternative.

This is an **illustrative offscreen rendering, not a screen recording**. The
notch contour, screen-safe geometry, default hover delay, spring samples, arrival
scale/easing and departure timing follow the current app sources. Font drawing,
the sample note, caret, chevron and pointer are a documentation fixture; no live
NSTextView, user note, desktop or OS pointer is captured. The open footer uses
the existing committed frog-and-pencil PNG and the proposed footer-branding
layout: a 14-point frog, 5-point gap and 11-point medium Scribbit wordmark,
inset 16 points from the leading edge. The optional resting-notch indicator is
enabled for this demo, though off by default in the app. Its left wing and
14-point frog use the shared indicator geometry; opening/collapse use the shared
asymmetric endpoints and horizontal spring offset, with the resting icon hidden
during the transition as in production. It does not establish
native input, actual saving, physical-notch delivery or GUI acceptance.

## Reproduce

On macOS with compatible Swift Command Line Tools:

```sh
Scripts/export-readme-demo.sh
```

Or keep an experiment out of the committed asset directory:

```sh
Scripts/export-readme-demo.sh "$PWD/build/readme-demo/experiment.gif"
```

The command writes the GIF and a same-basename PNG poster. Its exporter binary
and module cache live only under ignored `build/readme-demo/`. It does not build
or launch Scribbit, create a window/application, post events, access a selected
file, write preferences, register login items, use the clipboard, capture a
screen, or make network requests. No additional package/runtime is required.

`Scripts/ReadmeDemo.swift` is a documentation-only command-line renderer using
Core Graphics, Core Text and ImageIO. The wrapper compiles it directly with the
committed `NotchMotion.swift`, `NotchGeometry.swift` and `HoverDelay.swift`, so
geometry/motion policy is not copied into a separate fixture implementation.
Only the production presenter's content-easing control points are repeated
locally; changing that profile should update the exporter too.

## Timeline and acceptance

The quiet loop shows a pointer approaching the trigger, the default entry wait,
opening, disposable plain-text typing, a reading hold, pointer exit, close delay,
and collapse. It intentionally does not demonstrate richer Markdown editing,
image pasting, settings controls, or unimplemented features.

The export validates decoded GIF frame count and dimensions and rejects output
at or above 4 MiB. The animation is 800×560 at 20 frames/second, with a fixed
background and no full-frame flash/cut. A still-image link is provided for
readers who do not want animation.

The asset previews the independently developed footer-branding change; it does
not imply that change is merged or demonstrate the no-file draft feature.
If the footer, typography, geometry or timing changes, regenerate and
review it rather than claiming it automatically tracks every native UI detail.
