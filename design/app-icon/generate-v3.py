#!/usr/bin/env python3
"""Candidate v3: two centered, rounded glass phases."""
from pathlib import Path
import importlib.util
import json
root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('icon_colors', root.parents[1] / 'modern_UI/Spektrafilm/Tools/make-icon.py')
colors = importlib.util.module_from_spec(spec)
spec.loader.exec_module(colors)
package = root / 'Silverphase-v3.icon'
assets = package / 'Assets'
assets.mkdir(parents=True, exist_ok=True)
shape = ("M512 228 C478 228 456 238 428 254 L242 366 "
         "C190 398 190 438 242 470 L428 582 C477 612 547 612 596 582 "
         "L782 470 C834 438 834 398 782 366 L596 254 C568 238 546 228 512 228Z")
def sheet(name, top, bottom, x, y):
    (assets / name).write_text(f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<title>Silverphase — {name[:-4]}</title>
<defs><linearGradient id="color" x1="0" y1="0" x2="0.7" y2="1">
<stop offset="0" stop-color="{colors.to_p3(top)}"/><stop offset="1" stop-color="{colors.to_p3(bottom)}"/>
</linearGradient></defs>
<path d="{shape}" fill="url(#color)" transform="translate(0 {y})"/>
</svg>\n''')
sheet('01-silver.svg', '#B4BDC6', '#64717E', 512, 156)
sheet('02-amber.svg', '#FFE2A0', '#FFBE61', 512, 12)
def group(name, asset, opacity, transmission, refraction, depth, shadow):
    return {'name': name, 'layers': [{'image-name': asset, 'name': name, 'fill': 'automatic', 'glass': True, 'opacity': opacity}],
            'lighting': 'individual', 'specular': True, 'specular-highlight-placement': 'outside',
            'translucency': {'enabled': True, 'value': transmission}, 'blur-material': .08 if name.startswith('02') else .025,
            'refractivity': {'enabled': True, 'strength': refraction, 'depth': depth},
            'shadow': {'kind': 'layer-color', 'opacity': shadow}}
background = {'linear-gradient': ['srgb:0.98039,0.97647,0.95294,1', 'srgb:0.93333,0.95686,0.96078,1']}
doc = {'color-space-for-untagged-svg-colors': 'display-p3', 'features': ['refractivity'], 'fill': background,
       'fill-specializations': [{'value': background}, {'appearance': 'dark', 'value': {'linear-gradient': ['srgb:0.13,0.15,0.18,1', 'srgb:0.055,0.07,0.095,1']}}],
       'groups': [group('02 · Amber', '02-amber.svg', .78, .55, .5, .18, .12),
                  group('01 · Silver', '01-silver.svg', 1, .12, .18, .10, .28)],
       'supported-platforms': {'squares': 'shared'}}
(package / 'icon.json').write_text(json.dumps(doc, indent=2) + '\n')
