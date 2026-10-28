#!/usr/bin/env python3
"""Candidate only: two offset photographic planes, native Icon Composer glass."""
from pathlib import Path
import importlib.util
import json
root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('icon_colors', root.parents[1] / 'modern_UI/Spektrafilm/Tools/make-icon.py')
colors = importlib.util.module_from_spec(spec)
spec.loader.exec_module(colors)
package = root / 'Silverphase-v2.icon'
assets = package / 'Assets'
assets.mkdir(parents=True, exist_ok=True)
shape = colors.rounded(-310, -210, 620, 420, 68)
def sheet(name, top, bottom, x, y):
    (assets / name).write_text(f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<title>Silverphase — {name[:-4]}</title>
<defs><linearGradient id="color" x1="0" y1="0" x2="0.7" y2="1">
<stop offset="0" stop-color="{colors.to_p3(top)}"/><stop offset="1" stop-color="{colors.to_p3(bottom)}"/>
</linearGradient></defs>
<path d="{shape}" fill="url(#color)" transform="matrix(.78 .36 -.56 .49 {x} {y})"/>
</svg>\n''')
sheet('01-silver.svg', '#DAE4EC', '#94A5B8', 466, 566)
sheet('02-amber.svg', '#FFC150', '#F18A28', 554, 434)
def group(name, asset, opacity, transmission, refraction, depth, shadow):
    return {'name': name, 'layers': [{'image-name': asset, 'name': name, 'fill': 'automatic', 'glass': True, 'opacity': opacity}],
            'lighting': 'individual', 'specular': True, 'specular-highlight-placement': 'outside',
            'translucency': {'enabled': True, 'value': transmission}, 'blur-material': .04,
            'refractivity': {'enabled': True, 'strength': refraction, 'depth': depth},
            'shadow': {'kind': 'layer-color', 'opacity': shadow}}
background = {'linear-gradient': ['srgb:0.98039,0.97647,0.95294,1', 'srgb:0.93333,0.95686,0.96078,1']}
doc = {'color-space-for-untagged-svg-colors': 'display-p3', 'features': ['refractivity'], 'fill': background,
       'fill-specializations': [{'value': background}, {'appearance': 'dark', 'value': {'linear-gradient': ['srgb:0.13,0.15,0.18,1', 'srgb:0.055,0.07,0.095,1']}}],
       'groups': [group('02 · Amber', '02-amber.svg', .86, .45, .5, .18, .16),
                  group('01 · Silver', '01-silver.svg', 1, .15, .2, .10, .26)],
       'supported-platforms': {'squares': 'shared'}}
(package / 'icon.json').write_text(json.dumps(doc, indent=2) + '\n')
