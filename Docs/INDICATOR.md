# Closed-state left notch wing

The optional frog-and-pencil mark sits inside **one continuous black notch silhouette**, not
a separate floating icon. Enable **Show frog beside notch** in the gear's
settings popup. This preference is off by default.

| Property | Behavior |
| --- | --- |
| Placement | 36-point left extension beside the camera; white frog-and-pencil mark centered in the extension |
| Outline | Same attached shoulders and rounded lower corners as the note surface |
| Connection | Black contour spans the wing and cutout with no gap; the right edge stays aligned with the original closed notch |
| Hit region | Hovering the mark, wing, or camera trigger opens the note; transparent corners are excluded |
| Click handling | Nonactivating, click-through status-level window; no menu-bar clicks are consumed |
| Transition | Expands from the wing's left-shifted center into the centered editor; collapse ends at the same resting shape |
| Unnotched display | Connected wing on the simulated top-center notch, at 24-point resting height |
| Displays | Rebuilt on display changes; each display uses its own global coordinates |

`RestingNotchView` and the expanded host share `NotchContour`. The closed wing's
size and horizontal offset come from `NotchGeometry`; Core Animation carries the
offset with the width spring while the native window stays fixed. The small pencil
itself hides as opening starts and reappears once collapse finishes.

No persistent menu-bar status item is created. Reopen the running app through
Finder/Spotlight as an alternative to hover; the gear is an accessible native
button once the surface is open. A crowded system menu bar may still overlap
the wing; no third-party menu measurements or new permissions are requested.
A physical-notch/full-screen/crowded-menu visual check remains manual.

Native fixture output: `build/smoke/left-wing.png`. It demonstrates the
rendered contour and glyph, not their alignment with the user's physical camera.
The earlier `indicator-concepts.svg` contains historical right-tab/dot/underline
ideas; it no longer represents the implemented default design.
