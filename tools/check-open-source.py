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
product = ROOT / 'engine/resources_product'
provenance = json.loads((product / 'UPSTREAM.json').read_text())
adoption = provenance['experimental_film_adoption']
notice = adoption['notice']


def require(condition, message):
    if not condition:
        errors.append(message)


for source, destination in [
    ('license/LICENSE', 'COPYING'),
    ('license/LICENSE', BUNDLE / 'Silverphase-GPL-3.0.txt'),
    ('license/SPEKTRAFILM_LICENSE.txt', BUNDLE / 'Profiles-and-LUTs-CC-BY-SA-4.0.txt'),
    ('engine/third_party/metal-cpp/LICENSE.txt', BUNDLE / 'metal-cpp-Apache-2.0.txt'),
    ('engine/resources_product/NOTICE.md', BUNDLE / 'SpektraLab-BW-PROFILES-NOTICE.md'),
    ('engine/resources_product/CINESTILL_NOTICE.md', BUNDLE / 'SpektraLab-CINESTILL-NOTICE.md'),
    (product / notice, BUNDLE / notice),
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

subprocess.run([sys.executable, str(ROOT / 'tools/stock-artwork.py'), '--web'], check=True)

for name, expected in provenance['sha256'].items():
    path = product / name
    require(path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == expected,
            f'Product provenance mismatch: engine/resources_product/{name}')

# Follow the shared runtime artwork lookup, including public profile aliases.
resources = ROOT / 'modern_UI/Spektrafilm/Spektrafilm/Resources'
stocks = json.loads((resources / 'StockCatalog.json').read_text())['stocks']
require(not list((ROOT / 'engine/resources/profiles').glob('*_experimental.json')), 'Retired experimental profile data is present')
require(all(not stock['id'].endswith('_experimental') for stock in stocks), 'Retired experimental stock is in the catalog')
adopted = set(adoption['profiles'])
adopted_ids = {Path(name).stem for name in adopted}
require(len(adopted_ids) == 29 and adopted_ids == {s['id'] for s in stocks if s['id'].endswith(adoption['id_suffix'])},
        'Experimental imports and catalog differ')
cover_directory = resources / 'FilmCovers'
artwork_files = json.loads((cover_directory / 'StockArtwork.json').read_text())['files']
adopted_covers = {str((cover_directory / artwork_files[sid]).relative_to(ROOT)) for sid in adopted_ids}
workflow_manifest = ROOT / 'modern_UI/design/film-artwork/generated-workflow-manifest.json'
for item in json.loads(workflow_manifest.read_text()).get('items', []):
    if 'file' in item:
        require((cover_directory / item['file']).is_file(), f'Missing generated workflow artwork: {item["file"]}')

readme = (ROOT / BUNDLE / 'README.txt').read_text()
for phrase in ('Hanze Qiu', 'Andrea Volpato',
               'https://github.com/akinal5765-byte/Silverphase',
               'https://github.com/JamesQiu2005/SpektraLab',
               'https://github.com/andreavolpato/spektrafilm'):
    require(phrase in readme, f'Bundled credit/source link missing: {phrase}')

# Include new candidate source files, but never ignored private/build files.
result = subprocess.run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
                        cwd=ROOT, check=True, capture_output=True)
# A checkout may contain intentional deletions not yet marked in the index.
paths = {name for name in result.stdout.decode().rstrip('\0').split('\0')
         if (ROOT / name).exists() or (ROOT / name).is_symlink()}
retired = re.compile('fotu' + r'[-_ ]?film', re.IGNORECASE)
private_suffixes = {'.p12', '.pfx', '.pem', '.key', '.mobileprovision', '.arw', '.nef', '.dng', '.spektrapair'}
text_suffixes = {'.md', '.txt', '.json', '.py', '.swift', '.cpp', '.hpp', '.h', '.metal',
                 '.sh', '.pbxproj', '.plist', '.cff', '.yml', '.yaml', '.toml', '.xml'}
# Allow the reviewed, hash-checked import while retaining the guard against
# reintroducing historical research files or private source assets.
approved_import = {f'engine/resources_product/{name}' for name in adopted} | adopted_covers | {
    str((product / notice).relative_to(ROOT)),
    'engine/resources_product/UPSTREAM.json',
    'engine/resources_product/neutral_print_filters.json',
    'license/DATA-SOURCES.md',
    'license/media-inventory.json',
    'tools/check-open-source.py',
    'tools/stock-artwork.py',
    'modern_UI/design/film-artwork/generated-stock-covers-v2-manifest.json',
    'modern_UI/Spektrafilm/Spektrafilm/Resources/FilmCovers/StockArtwork.json',
    'README.md', 'README.en.md', 'AGENTS.md', 'ARCHITECTURE.md', 'LICENSES.md',
    'docs/README.md', 'docs/LOCAL-MATERIALS.md', 'docs/showcase/README.md',
    'modern_UI/Spektrafilm/releases/1.3.0.md',
    'modern_UI/Spektrafilm/releases/1.3.1.md',
    'modern_UI/Spektrafilm/README.md',
    'modern_UI/Spektrafilm/VALIDATION.md',
    'ios/releases/1.3.0.md',
    'ios/releases/1.3.1.md',
    'ios/Silverphase/Sources/EditorDesign.swift',
    'ios/Silverphase/Sources/MaterialChooser.swift',
    'ios/Silverphase/Sources/MobileCamera.swift',
    'ios/Silverphase/Sources/SilverphaseApp.swift',
    'engine/src/core/curves.cpp', 'engine/src/core/curves.hpp', 'engine/src/core/params.cpp',
    'engine/src/pipeline/pipeline.cpp',
    'engine/tests/fotufilm_dir_edges.py',
    'modern_UI/design/film-artwork/generated-fotufilm-packaging-manifest.json',
    str(BUNDLE / notice),
    str(BUNDLE / 'Runtime-Data-SOURCES.md'),
    'modern_UI/Spektrafilm/Tools/bundle-licenses.sh',
    'modern_UI/Spektrafilm/Tools/check-bundle-resources.sh',
    'modern_UI/Spektrafilm/Tools/gen-catalog.py',
    'modern_UI/Spektrafilm/Spektrafilm/Resources/StockCatalog.json',
    'modern_UI/Spektrafilm/Spektrafilm/Model/StockCatalogCore.swift',
    'modern_UI/Spektrafilm/Spektrafilm/Panels/Filmstrip.swift',
    'modern_UI/Spektrafilm/Spektrafilm/Windows/AboutWindow.swift',
    'modern_UI/Spektrafilm/SpektrafilmTests/StockListTests.swift',
    'modern_UI/Spektrafilm/Spektrafilm/Resources/Licenses/Profiles-and-LUTs-CHANGELOG.txt',
}
for name in sorted(paths):
    path = ROOT / name
    if name not in approved_import:
        require(not retired.search(name), f'Retired research filename: {name}')
    require(path.suffix.lower() not in private_suffixes and path.name != '.env',
            f'Private input/signing file needs review: {name}')
    if name not in approved_import and path.is_file() and not path.is_symlink() and path.suffix.lower() in text_suffixes:
        body = path.read_text(errors='replace')
        require(not retired.search(body), f'Retired research reference: {name}')

if errors:
    print('\n'.join(f'FAIL: {error}' for error in errors))
    sys.exit(1)
print(f'PASS: notices, product hashes, credits, {len(stocks)} material covers and {len(paths)} candidate source paths checked.')
print('Asset rights and historical secret scanning remain separate release reviews.')
