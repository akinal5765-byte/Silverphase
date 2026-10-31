#!/usr/bin/env python3
"""Check source-release notices and provenance; does not certify asset rights."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = Path('modern_UI/Spektrafilm/Spektrafilm/Resources/Licenses')
errors = []


def require(condition, message):
    if not condition:
        errors.append(message)


for source, destination in [
    ('license/LICENSE', 'COPYING'),
    ('license/LICENSE', BUNDLE / 'Silverphase-GPL-3.0.txt'),
    ('license/SPEKTRAFILM_LICENSE.txt', BUNDLE / 'Profiles-and-LUTs-CC-BY-SA-4.0.txt'),
    ('engine/third_party/metal-cpp/LICENSE.txt', BUNDLE / 'metal-cpp-Apache-2.0.txt'),
    ('engine/resources_product/NOTICE.md', BUNDLE / 'SpektraLab-BW-PROFILES-NOTICE.md'),
    ('license/Colour-BSD-3-Clause.txt', BUNDLE / 'Colour-BSD-3-Clause.txt'),
    ('license/CC-BY-SA-4.0.txt', BUNDLE / 'Silverphase-Artwork-CC-BY-SA-4.0.txt'),
    ('license/ARTWORK.md', BUNDLE / 'Silverphase-Artwork-NOTICE.md'),
    ('license/DATA-SOURCES.md', BUNDLE / 'Runtime-Data-SOURCES.md'),
]:
    a, b = ROOT / source, ROOT / destination
    require(a.is_file() and b.is_file() and a.read_bytes() == b.read_bytes(),
            f'Licence/notice missing or different: {destination}')

subprocess.run([sys.executable, str(ROOT / 'tools/inventory-release-data.py'), '--check'], check=True)
subprocess.run([sys.executable, str(ROOT / 'tools/inventory-release-media.py'), '--check'], check=True)

product = ROOT / 'engine/resources_product'
provenance = json.loads((product / 'UPSTREAM.json').read_text())
for name, expected in provenance['sha256'].items():
    path = product / name
    require(path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == expected,
            f'Product provenance mismatch: engine/resources_product/{name}')

# Follow Stock.packagingArtworkURL, including existing aliases and v2 Portra.
resources = ROOT / 'modern_UI/Spektrafilm/Spektrafilm/Resources'
stocks = json.loads((resources / 'StockCatalog.json').read_text())['stocks']
require(not list((ROOT / 'engine/resources/profiles').glob('*_experimental.json')), 'Retired experimental profile data is present')
require(all(not stock['id'].endswith('_experimental') for stock in stocks), 'Retired experimental stock is in the catalog')
aliases = {'kodak_portra_800_push1': 'kodak_portra_800',
           'kodak_portra_800_push2': 'kodak_portra_800'}
for stock in stocks:
    sid = aliases.get(stock['id'], stock['id'])
    version = 'v2' if sid == 'kodak_portra_400' else 'v1'
    cover = resources / 'FilmCovers' / f'{sid}-packaging-{version}.png'
    require(cover.is_file(), f'Missing packaging cover: {stock["id"]}')
for name in ('workflow_film_scan-v1.png', 'workflow_digital_intermediate-v1.png'):
    require((resources / 'FilmCovers' / name).is_file(), f'Missing workflow cover: {name}')
for manifest in (ROOT / 'modern_UI/design/film-artwork').glob('generated-*-manifest.json'):
    for item in json.loads(manifest.read_text()).get('items', []):
        if 'file' in item:
            require((resources / 'FilmCovers' / item['file']).is_file(),
                    f'Missing generated artwork: {item["file"]}')

readme = (ROOT / BUNDLE / 'README.txt').read_text()
for phrase in ('Hanze Qiu', 'Andrea Volpato',
               'https://github.com/akinal5765-byte/Silverphase',
               'https://github.com/JamesQiu2005/SpektraLab',
               'https://github.com/andreavolpato/spektrafilm'):
    require(phrase in readme, f'Bundled credit/source link missing: {phrase}')

# Include new candidate source files, but never ignored private/build files.
result = subprocess.run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
                        cwd=ROOT, check=True, capture_output=True)
paths = set(result.stdout.decode().rstrip('\0').split('\0'))
retired = re.compile('fotu' + r'[-_ ]?film', re.IGNORECASE)
private_suffixes = {'.p12', '.pfx', '.pem', '.key', '.mobileprovision', '.arw', '.nef', '.dng', '.spektrapair'}
text_suffixes = {'.md', '.txt', '.json', '.py', '.swift', '.cpp', '.hpp', '.h', '.metal',
                 '.sh', '.pbxproj', '.plist', '.cff', '.yml', '.yaml', '.toml', '.xml'}
for name in sorted(paths):
    path = ROOT / name
    require(not retired.search(name), f'Retired research filename: {name}')
    require(path.suffix.lower() not in private_suffixes and path.name != '.env',
            f'Private input/signing file needs review: {name}')
    if path.is_file() and not path.is_symlink() and path.suffix.lower() in text_suffixes:
        body = path.read_text(errors='replace')
        require(not retired.search(body), f'Retired research reference: {name}')

if errors:
    print('\n'.join(f'FAIL: {error}' for error in errors))
    sys.exit(1)
print(f'PASS: notices, product hashes, credits, {len(stocks)} material covers and {len(paths)} candidate source paths checked.')
print('Asset rights and historical secret scanning remain separate release reviews.')
