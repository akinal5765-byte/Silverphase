#!/usr/bin/env python3
"""make-icon.py — the two artwork layers of Silverphase.icon, drawn from numbers.

    python3 Tools/make-icon.py            # writes the SVGs into the .icon package

Why a generator and not two hand-written SVGs: the layers are one shape in two
materials — a strip with sprocket holes punched through it and three frame
windows on top — and every number in it (hole pitch, window gap, the margin the
artwork keeps from the canvas edge) is a proportion of the strip that has to
move together. Twelve hex digit pairs per file is where a design stops being
editable and starts being archaeology.

**The colours are written in Display P3, and that is not decoration.**
`icon.json` declares `color-space-for-untagged-svg-colors: display-p3`, which is
the only value this Icon Composer build accepts, so an untagged hex in the SVG
is read as a P3 number. Designing in sRGB and dropping the hex in would have
made every colour more saturated on screen than it was chosen to be, so the
sRGB values below are converted — linear light, the CSS Color 4 matrices, back
through the P3 transfer function — and what the icon shows is what was designed.
`sRGB #FF9F0A` (the app's accent) lands on `#F2A33C` in P3, which is the same
orange.

Nothing here draws the glass. Icon Composer composes the specular edge, the
refraction and the shadow; a baked highlight would be a second one.
"""

import io
import json
import os
import re

# ---- the sRGB → Display-P3 conversion (CSS Color 4 matrices) ---------------

SRGB_TO_XYZ = [[0.41239079926595934, 0.357584339383878, 0.1804807884018343],
               [0.21263900587151027, 0.715168678767756, 0.07219231536073371],
               [0.01933081871559182, 0.11919477979462598, 0.9505321522496607]]
XYZ_TO_P3 = [[2.493496911941425, -0.9313836179191239, -0.40271078445071684],
             [-0.8294889695615747, 1.7626640603183463, 0.023624685841943577],
             [0.03584583024378447, -0.07617238926804182, 0.9568845240076872]]


def _linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _gamma(c):
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def to_p3(hex6):
    """The Display-P3 encoding of an sRGB colour: same colour, P3 numbers."""
    v = [_linear(int(hex6[i:i + 2], 16) / 255) for i in (1, 3, 5)]
    xyz = [sum(SRGB_TO_XYZ[i][j] * v[j] for j in range(3)) for i in range(3)]
    return "#" + "".join(
        f"{round(_gamma(sum(XYZ_TO_P3[i][j] * xyz[j] for j in range(3))) * 255):02X}"
        for i in range(3))


# ---- the strip, in 1024-point canvas units ---------------------------------

# How far the two strips are pulled apart, in canvas points: the front one down
# and to the right, the back one up and to the left. **Nearly a full frame
# vertically** (the pitch is WIN_H + WIN_GAP): aligned windows cancel — light on
# light shows nothing — and the offset is what makes one strip legible through
# the other. `icon.json` carries the same two numbers.
OFFSET_FRONT = (84, 78)
OFFSET_BACK = (-84, -78)

CANVAS = 1024
W, H, R = 400, 580, 46          # the strip: its own size and corner radius

HOLES = 6                       # per side. Six, not the nine a 35 mm strip has:
HOLE_W, HOLE_H, HOLE_R = 52, 38, 10   # at 16 pt an icon shows a dotted edge
HOLE_INSET = 32                 # from the strip's side edge
HOLE_PITCH = 88

WIN_W, WIN_H, WIN_R = 200, 146, 16
WIN_GAP = 28

# sRGB, as designed. `top`/`bottom` are the two ends of the strip's gradient —
# a material, not a light: silver is a gradient because a flat grey at this size
# reads as paper, and the system's glass is what adds the shine.
#
# `body_alpha`/`window_alpha` are what make two strips read as *stacked film*
# rather than as one sticker on another: the front strip has to let the one
# behind it show through, and the frame window — the clear base the image sits
# on — is the most transparent part of all. Without this the orange simply
# covers the silver, which is what the user saw: "上面黄的把下面灰的覆盖了".
SILVER = {"top": "#C2CAD6", "bottom": "#7C8797", "rim": "#6D7889", "window": "#B4BFCB",
          "body_alpha": 0.94, "window_alpha": 0.94, "windows_are_holes": False}
# **The strip's edges are opaque Apple orange; its frame windows are clear.**
# That is also what a strip of film is: the image area is bare base, and the
# margins carry the perforations. Tinting the *whole* strip (alpha everywhere)
# was what turned the orange to cream and made the layering read as nothing —
# the see-through has to happen where the geometry makes it legible, and the
# colour has to stay the colour.
# **Deeper than Apple orange on purpose.** The strip is translucent (0.78), so
# what lands on screen is `0.78 · this + 0.22 · what is behind` — which over the
# white ground was reading as a pale amber, not as Apple orange. These values are
# pre-compensated so the *result* over white is #FF9F0A; over the silver strip it
# is greyer, which is what transparency means.
# The strip's **frame** is opaque Apple orange; its **frame windows** are the
# clear base, and they are where the strip behind reads through. Tinting the whole
# strip instead (alpha 0.78 everywhere) showed the layering but cost the colour:
# measured #F38C36 where #FF9F0A was wanted, because 22 % of the white ground came
# through everywhere. Confining the transparency to the windows keeps both.
ORANGE = {"top": "#FF9F0A", "bottom": "#F58C00", "rim": "#D2730A", "window": "#FFC24D",
          "body_alpha": 1.0, "window_alpha": 1.0, "windows_are_holes": True,
          "base": "#FFB84D", "base_alpha": 0.90}


def rounded(x, y, w, h, r):
    return (f"M{x + r} {y}h{w - 2 * r}a{r} {r} 0 0 1 {r} {r}v{h - 2 * r}"
            f"a{r} {r} 0 0 1 -{r} {r}h-{w - 2 * r}a{r} {r} 0 0 1 -{r} -{r}"
            f"v-{h - 2 * r}a{r} {r} 0 0 1 {r} -{r}Z")


def base_svg(material, title):
    """The three frame windows as a *tint*: the clear base of the film."""
    c = to_p3(material["base"])
    panels = "".join(
        f'<path d="{rounded((W - WIN_W) / 2, y, WIN_W, WIN_H, WIN_R)}"/>'
        for y in top_windows())
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<!-- Drawn by Tools/make-icon.py. The clear base under the frame windows. -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}"
     width="{CANVAS}" height="{CANVAS}">
  <title>{title}</title>
  <g transform="translate({(CANVAS - W) // 2} {(CANVAS - H) // 2})"
     fill="{c}" opacity="{material['base_alpha']}">{panels}</g>
</svg>
'''


def strip_svg(material, title):
    body = rounded(0, 0, W, H, R)
    holes = []
    run = (HOLES - 1) * HOLE_PITCH
    top = (H - (run + HOLE_H)) / 2
    for i in range(HOLES):
        y = top + i * HOLE_PITCH
        holes.append(rounded(HOLE_INSET, y, HOLE_W, HOLE_H, HOLE_R))
        holes.append(rounded(W - HOLE_INSET - HOLE_W, y, HOLE_W, HOLE_H, HOLE_R))
    windows = [rounded((W - WIN_W) / 2, y, WIN_W, WIN_H, WIN_R)
               for y in (top_windows())]
    openings = windows if material.get("windows_are_holes") else []
    # One path with `evenodd` and the holes as subpaths: the perforations are
    # **holes**, so the ground and the glass read through them. The windows are
    # panels — the clear base the image sits on — so they are drawn on top.
    path = " ".join([body] + holes + openings)
    c = {k: to_p3(v) for k, v in material.items() if k.endswith(("top", "bottom", "rim", "window"))}
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<!-- Drawn by Tools/make-icon.py. Untagged colours are Display P3. -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}"
     width="{CANVAS}" height="{CANVAS}">
  <title>{title}</title>
  <defs>
    <linearGradient id="body" x1="0.08" y1="0" x2="0.92" y2="1">
      <stop offset="0" stop-color="{c['top']}"/>
      <stop offset="1" stop-color="{c['bottom']}"/>
    </linearGradient>
  </defs>
  <g transform="translate({(CANVAS - W) // 2} {(CANVAS - H) // 2})"
     opacity="{material['body_alpha']}">
    <path fill="url(#body)" fill-rule="evenodd" d="{path}"/>
    <path fill="none" stroke="{c['rim']}" stroke-opacity="{material['body_alpha']}"
          stroke-width="2.5" fill-rule="evenodd" d="{path}"/>
    <g fill="{c['window']}" opacity="{material['window_alpha']}">{''.join(f'<path d="{p}"/>' for p in ([] if material.get("windows_are_holes") else windows))}</g>
  </g>
</svg>
'''


def top_windows():
    span = 3 * WIN_H + 2 * WIN_GAP
    first = (H - span) / 2
    return [first + i * (WIN_H + WIN_GAP) for i in range(3)]


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    assets = os.path.join(here, "..", "Spektrafilm", "Silverphase.icon", "Assets")
    assets = os.path.normpath(assets)
    for name, material, title in (("1-silver-strip.svg", SILVER, "Silver strip"),
                                  ("2-orange-strip.svg", ORANGE, "Orange strip")):
        with io.open(os.path.join(assets, name), "w", encoding="utf-8") as f:
            f.write(strip_svg(material, title))
        if material.get("base_alpha"):
            base = name.replace(".svg", "-base.svg")
            with io.open(os.path.join(assets, base), "w", encoding="utf-8") as f:
                f.write(base_svg(material, title + " base"))
        print("wrote", os.path.relpath(os.path.join(assets, name), here))
    # **Touch the package directory.** Xcode tracks the `.icon` as an input, and
    # rewriting a file *inside* a directory does not change that directory's
    # mtime — so the asset catalog was re-run, the icon was not, and the app went
    # on shipping the previous artwork. One `utime` is the whole fix.
    os.utime(os.path.dirname(assets), None)
    print("check: sRGB #FF9F0A (the accent) is", to_p3("#FF9F0A"), "in P3")


if __name__ == "__main__":
    main()
