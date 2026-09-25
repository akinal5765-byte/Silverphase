# Visual iteration — the snapshot harness

> **The interface spec is [`UI-SPEC.md`](UI-SPEC.md).** It is the only one: the
> token-translation documents, the frontend architecture record, the SwiftUI
> guideline and the Chinese copy guide were merged into it and deleted on
> 2026-09-26. Read that before changing anything the interface draws.

| | |
|---|---|
| **What this is** | The harness that lets the interface be checked without a human looking at it — and the record of what it cannot see. |
| **One command** | `design/snapshot.sh [image]` → `design/snapshots/window-*.png` |
| **The live window** | `Spektrafilm/Tools/capture-live.sh [image.NEF]` → `snapshots/live-window.png` |
| **The frame** | `_DSC0897.NEF` — see below |
| **Date** | 2026-09-26 |

## The frame the captures use

Every committed capture is of **`_DSC0897.NEF`** (the Nikon Z7ii folder in the
`spektrafilm` reference tree, which the repository-root `tests` symlink reaches
in a checkout that has it — see `AGENTS.md` trap 26). It is not arbitrary and
it should not be swapped casually: a capture is read by diffing it against the
last one, and changing the photograph changes every pixel of the canvas, the
histogram, the curve and four thumbnails at once. A real regression is then a
needle in a frame-sized haystack.

The export page's capture is the same frame:

```
Silverphase --snapshot 1490x990 out.png --export --open <frame> --wait 120
```

## How it works

The app itself has a snapshot mode:

```
Silverphase --snapshot 1920x1080 out.png [--open file.NEF --wait 90]
```

It opens its own `NSWindow` at that size, hosts the real `EditorWindow`, and in
`--open` mode runs the whole pipeline (Core Image decode → linear TIFF →
engine `open` → `reprint` → texture) and waits for the print to land before
capturing. The Metal canvas is replaced by an offscreen render through the
same `Renderer` (`SnapshotCanvas`), so the capture shows the real render path
including Layer 2 and the histogram. `Tools/snapshot.sh` runs it at the three
shapes that matter: MacBook Pro 14" (1512×982), 16:9 (1920×1080) and the 21:9
display (3360×1418).

`Tools/snapshot.sh` also takes a fourth shot, `window-folded-both.png`, with
both rails folded (`--folded left|right|both`). That is the one state the
harness otherwise goes out of its way to reset, and the PRD makes a
requirement about it: the two `sidebar` buttons have to be on screen "at any
given time", so when a rail folds its button moves onto the bar, along with the
window buttons' clearance. Nothing but a capture shows that.

### Flags that exist because a test cannot see the thing

`--zoom`, `--geometry`, `--mask`, `--compare`, `--original`, `--print S`,
`--stage <inspector stage>`, `--settings`, `--boot [--boot-phase …]`,
`--export [--export-grid]`. The list is in `SnapshotRequest.parse`
(`SpektrafilmApp.swift`), with the reason each one needs a flag on the struct.

## What it cannot capture — and the harness that can

Hover, focus and drag: no pointer exists. Menus and sheets are not opened.

**The canvas.** `cacheDisplay` cannot see a `CAMetalLayer`, so snapshot mode
substitutes an offscreen render through the same `Renderer`. That covers the
render path and misses everything between it and the screen — which is where
two shipped defects lived at once: a drawable pixel format `CAMetalLayer`
rejects (the app crashed on launch) and a redraw that never reached the view
(the canvas stayed blank while every number behind it was right).

```
Spektrafilm/Tools/capture-live.sh [image.NEF]   # → design/snapshots/live-window.png
```

launches the real app, opens a frame, waits for the print, and asks the window
server for the pixels. It needs Screen Recording permission. **It is the only
capture that proves the canvas draws** — run it before believing it does. If
`CGWindowListCopyWindowInfo` reports almost no on-screen windows, the failure is
environmental rather than a regression.

**A colour literal in the canvas.** `--snapshot` cannot referee the working-space
rule in UI-SPEC §11.4: `cacheDisplay` applies a window-level conversion that
follows the layer's tag, so an offscreen A/B compares two conversions rather
than two renderings and *everything* differs, including regions nothing touched.
The check that needs no "before" image is a **live** capture — the window's
outer margin and the canvas letterbox are two routes to the same grey and must
land on the same pixel.

## Two things the harness itself got wrong

Both are worth remembering because each one produced a confident wrong answer.

- **A titled window is clamped to the screen.** Asking for 1920×1080 on a
  smaller display quietly produced an 1800-point-wide capture, and every
  measurement against it was wrong by that ratio. The snapshot window is now
  borderless and never centred, so the capture does not depend on which display
  is attached.
- **A capture inherited persisted UI state.** A filmstrip collapsed in an
  earlier session removed a whole region. Snapshot mode now resets the collapse
  flags **and** pins both rails to `standard`, so a rail someone dragged wide
  days ago cannot silently become what every measurement measures.

## Measuring a capture

**A control's ink is not its frame.** The run-detector in a capture stops at a
bright glyph — a pill's chevron, a slider's knob — so the measured "gap" between
two controls includes that ink and reads wider than the layout gap. Measured
on 2026-09-26: a row whose controls are 8 pt apart by construction reports
**17** because the pill's chevron is 8 pt of bright ink plus its trailing
inset. Compare runs *within* one row, and check a layout gap in the source.


There is no committed measuring tool any more. `measure-layout.swift`,
`compare-design.swift` and `compare-layout.py` were deleted on 2026-09-26 with
the drawings they were pointed at: two took `main_page.png` as their reference
and could not run at all, and the third asserted the previous floating-bar
layout. Their replacement is **`ModernCalibrationTests` + `LayoutTests`**, which
check the rules at the source and the geometry in a hosted window, and never
depend on a raster of a drawing.

When you do need a number off a capture, measure it directly — the tokens are in
`Theme.swift` and the former Traditional layout is recorded in
UI-SPEC §10.3. Both tools are recoverable from git history if a pixel-level
comparison against a *new* drawing is ever wanted; re-point them at that drawing
before trusting a run, and prefer an assertion in `LayoutTests` to a script that
grades a picture.
