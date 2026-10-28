#!/usr/bin/env python3
"""Generate the shared macOS/iOS Silverphase Icon Composer document.

Two Layerlight-family planes: orange film below a silver photographic print.
Only vector geometry and material gradients are authored; Apple's renderer owns
lighting, refraction, shadows, masks and appearance variants. SVG colours are
converted from design sRGB to the document's declared Display P3 space.
"""
from pathlib import Path
import json

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



def main():
    package = Path(__file__).resolve().parents[1] / 'Spektrafilm/Silverphase.icon'
    assets = package / 'Assets'
    assets.mkdir(parents=True, exist_ok=True)
    shape = ("M512 220 C478 220 460 230 432 247 L244 356 "
             "C192 386 192 424 244 454 L432 563 C480 591 544 591 592 563 "
             "L780 454 C832 424 832 386 780 356 L592 247 C564 230 546 220 512 220Z")

    def sheet(name, top, bottom, x, y):
        (assets / name).write_text(f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
    <title>Silverphase — {name[:-4]}</title>
    <defs><linearGradient id="color" x1="0" y1="0" x2="0.7" y2="1">
    <stop offset="0" stop-color="{to_p3(top)}"/><stop offset="1" stop-color="{to_p3(bottom)}"/>
    </linearGradient></defs>
    <path d="{shape}" fill="url(#color)" transform="translate(0 {y})"/>
    </svg>\n''')
    sheet('01-film.svg', '#FFAD19', '#F0780C', 512, 180)
    sheet('02-paper.svg', '#E8EFF5', '#A7B8C9', 512, 32)
    def group(name, asset, opacity, transmission, refraction, depth, shadow):
        return {'name': name, 'layers': [{'image-name': asset, 'name': name, 'fill': 'automatic', 'glass': True, 'opacity': opacity}],
                'lighting': 'individual', 'specular': True, 'specular-highlight-placement': 'outside',
                'translucency': {'enabled': True, 'value': transmission}, 'blur-material': .08 if name.startswith('02') else .025,
                'refractivity': {'enabled': True, 'strength': refraction, 'depth': depth},
                'shadow': {'kind': 'layer-color', 'opacity': shadow}}
    background = {'linear-gradient': ['srgb:0.98039,0.97647,0.95294,1', 'srgb:0.93333,0.95686,0.96078,1']}
    doc = {'color-space-for-untagged-svg-colors': 'display-p3', 'features': ['refractivity'], 'fill': background,
           'fill-specializations': [{'value': background}, {'appearance': 'dark', 'value': {'linear-gradient': ['srgb:0.13,0.15,0.18,1', 'srgb:0.055,0.07,0.095,1']}}],
           'groups': [group('02 · Silver print', '02-paper.svg', .84, .45, .5, .18, .12),
                      group('01 · Orange film', '01-film.svg', 1, .06, .18, .10, .28)],
           'supported-platforms': {'squares': 'shared'}}
    (package / 'icon.json').write_text(json.dumps(doc, indent=2) + '\n')

    import os
    os.utime(package, None)
    for name in ['01-silver.svg', '02-emulsion.svg', '03-negative.svg',
                 '1-silver-strip.svg', '2-orange-strip.svg', '2-orange-strip-base.svg']:
        (assets / name).unlink(missing_ok=True)


if __name__ == '__main__':
    main()
