#!/usr/bin/env python3
"""Verify the built-in stock artwork in source, an actual app bundle, or both."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'modern_UI/Spektrafilm/Spektrafilm/Resources'
PROVENANCE = ROOT / 'modern_UI/design/film-artwork/generated-stock-covers-v2-manifest.json'
WIDTH, HEIGHT = 1440, 810
WEB_WIDTH, WEB_HEIGHT = 800, 450
WORKFLOW_ART = {'workflow_film_scan-v1.png', 'workflow_digital_intermediate-v1.png'}
WEB_STOCKS = {
    'acros-ii': 'fujifilm_neopan_acros_100_ii',
    'cinestill-800t': 'cinestill_800t',
    'eterna-500': 'fujifilm_eterna_500_fotufilm',
    'hp5-plus': 'ilford_hp5_plus_400',
    'portra-400': 'kodak_portra_400',
    'pro-160ns': 'fujifilm_pro_160ns_fotufilm',
    'reala-100': 'fujifilm_reala_100_fotufilm',
    'vision3-250d': 'kodak_vision3_250d',
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def jpeg_dimensions(path):
    """Read a JPEG start-of-frame segment without a runtime Pillow dependency."""
    data = path.read_bytes()
    require(data[:2] == b'\xff\xd8' and data[-2:] == b'\xff\xd9', f'Invalid JPEG: {path}')
    offset = 2
    sof = {0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf}
    while offset < len(data) - 7:
        require(data[offset] == 0xff, f'Invalid JPEG marker: {path}')
        while offset < len(data) and data[offset] == 0xff:
            offset += 1
        require(offset < len(data), f'Invalid JPEG marker: {path}')
        marker = data[offset]
        offset += 1
        segment_length = int.from_bytes(data[offset:offset+2], 'big')
        require(segment_length >= 2 and offset + segment_length <= len(data), f'Invalid JPEG segment: {path}')
        if marker in sof:
            require(segment_length >= 8, f'Invalid JPEG frame: {path}')
            h = int.from_bytes(data[offset+3:offset+5], 'big')
            w = int.from_bytes(data[offset+5:offset+7], 'big')
            return w, h
        if marker == 0xda:
            break
        offset += segment_length
    raise ValueError(f'No JPEG frame: {path}')


def webp_dimensions(path):
    """Read canvas size from a static WebP RIFF chunk."""
    data = path.read_bytes()
    require(data[:4] == b'RIFF' and data[8:12] == b'WEBP' and
            int.from_bytes(data[4:8], 'little') == len(data) - 8, f'Invalid WebP: {path}')
    kind = data[12:16]
    chunk_size = int.from_bytes(data[16:20], 'little')
    payload = data[20:20 + chunk_size]
    require(len(payload) == chunk_size and len(payload) >= 5, f'Invalid WebP header: {path}')
    if kind == b'VP8X' and len(payload) >= 10:
        require(not payload[0] & 2, f'Animated stock cover: {path}')
        return 1 + int.from_bytes(payload[4:7], 'little'), 1 + int.from_bytes(payload[7:10], 'little')
    if kind == b'VP8 ' and payload[3:6] == b'\x9d\x01\x2a' and len(payload) >= 10:
        return int.from_bytes(payload[6:8], 'little') & 0x3fff, int.from_bytes(payload[8:10], 'little') & 0x3fff
    if kind == b'VP8L' and payload[0] == 0x2f:
        packed = int.from_bytes(payload[1:5], 'little')
        return 1 + (packed & 0x3fff), 1 + ((packed >> 14) & 0x3fff)
    raise ValueError(f'Unknown WebP canvas: {path}')


def verify_size(size, expected, path):
    w, h = size
    require(w * 9 == h * 16 and size == expected, f'{path}: {w}×{h}, expected {expected[0]}×{expected[1]} (exact 16:9)')


def verify_resources(resources, provenance):
    covers = resources / 'FilmCovers'
    stocks = load_json(resources / 'StockCatalog.json')['stocks']
    stock_ids = [item['id'] for item in stocks]
    require(all('cover' not in stock for stock in stocks), 'Catalog still references legacy fallback artwork')
    require(len(stock_ids) == len(set(stock_ids)), 'Duplicated catalog ID')
    require(all(re.fullmatch(r'[a-z0-9_]+', item) and not item.endswith('_experimental') for item in stock_ids),
            'Unexpected non-public ID in the built-in catalog')
    artwork = load_json(covers / 'StockArtwork.json')
    files = artwork['files']
    require(artwork['version'] == 1 and set(files) == set(stock_ids), 'Artwork lookup differs from built-in catalog')
    require(provenance['version'] == 2 and provenance['references'] is False, 'Unrecognized provenance version or input')
    items = {item['id']: item for item in provenance['items']}
    require(len(items) == len(provenance['items']), 'Duplicated source item in artwork provenance')
    aliases = provenance['aliases']
    require(set(aliases).isdisjoint(items) and set(aliases.values()) <= set(items) and
            set(items) | set(aliases) == set(stock_ids), 'Artwork provenance/alias coverage differs from catalog')
    require(files == {sid: aliases.get(sid, sid) + '.jpg' for sid in stock_ids}, 'Misassigned cover file')
    expected = WORKFLOW_ART | set(files.values()) | {'StockArtwork.json'}
    candidate_files = list(covers.iterdir())
    require({path.name for path in candidate_files} == expected, 'Extra or missing cover files (legacy fallbacks must not ship)')
    require(all(path.is_file() and not path.is_symlink() for path in candidate_files), 'Unexpected linked or non-file artwork resource')
    require(len({item['sha256'] for item in items.values()}) == len(items), 'A distinct artwork ID references duplicate art')
    for sid, item in items.items():
        path = covers / files[sid]
        verify_size(jpeg_dimensions(path), (WIDTH, HEIGHT), path)
        require(item['file'] == path.name and item['sha256'] == digest(path), f'Wrong native derivative/checksum: {sid}')
        require(re.fullmatch(r'[0-9a-f]{64}', item['source_sha256']) and item['prompt'].strip(), f'Missing master evidence: {sid}')
    return len(stock_ids), len(items)


def verify_web(provenance):
    items = {item['id']: item for item in provenance['items']}
    expected = {name + '.webp' for name in WEB_STOCKS}
    require({sid for sid, item in items.items() if 'web' in item} == set(WEB_STOCKS.values()), 'Wrong stock IDs selected for website derivatives')
    require({path.name for path in (ROOT / 'docs/site/covers').iterdir()} == expected, 'Website film cover inventory changed')
    for name, sid in WEB_STOCKS.items():
        path = ROOT / f'docs/site/covers/{name}.webp'
        verify_size(webp_dimensions(path), (WEB_WIDTH, WEB_HEIGHT), path)
        web = items[sid]['web']
        require(web['path'] == str(path.relative_to(ROOT)) and web['sha256'] == digest(path), f'Wrong website derivative/checksum: {sid}')


def prepare(plan_path, approved_masters):
    """Process reviewed PNGs; never publish the source masters or modify catalog data."""
    from PIL import Image, ImageCms, ImageOps
    from io import BytesIO

    plan = load_json(plan_path)
    require(plan['references'] is False, 'This collection expects text-only sources')
    planned = {item['id']: item for item in plan['items']}
    require(len(planned) == len(plan['items']), 'Duplicated generation plan item')
    catalog = {item['id']: item for item in load_json(RESOURCES / 'StockCatalog.json')['stocks']}
    aliases = plan['aliases']
    require(set(planned).isdisjoint(aliases) and set(catalog) == set(planned) | set(aliases),
            'The generation plan does not cover the entire built-in catalog')
    for sid, item in planned.items():
        require(re.fullmatch(r'[a-z0-9_]+', sid) and not sid.endswith('_experimental'), f'Invalid source stock ID: {sid}')
        require(item['stage'] == catalog[sid]['stage'] and item['use'] == catalog[sid]['use'],
                f'Generation plan differs from catalog: {sid}')
    canonical = set(planned)
    require(set(aliases.values()) <= canonical and set(WEB_STOCKS.values()) <= canonical, 'Invalid alias or website stock in plan')
    require(len(canonical) == 57 and len(aliases) == 6, 'Expected 57 individual designs + six aliases')
    cover_dir = RESOURCES / 'FilmCovers'
    web_dir = ROOT / 'docs/site/covers'
    out = {'version': 2, 'generator': plan['generator'], 'references': False,
           'native_derivative': {'width': WIDTH, 'height': HEIGHT, 'encoding': 'sRGB JPEG quality 93, 4:4:4, optimize'},
           'web_derivative': {'width': WEB_WIDTH, 'height': WEB_HEIGHT, 'encoding': 'sRGB WebP quality 90, method 6'},
           'transform': 'Centered minimal crop to 16:9 from reviewed PNG, Lanczos resize; no stretching, text overlays, or upscaling.',
           'aliases': dict(sorted(aliases.items())), 'items': []}
    manifest = {'version': 1, 'files': {sid: aliases.get(sid, sid) + '.jpg' for sid in sorted(catalog)}}
    srgb = ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB'))
    # Validate all inputs and write all derivatives to scratch before touching any resources.
    with TemporaryDirectory() as contents:
        stage = Path(contents)
        native = stage / 'FilmCovers'
        web = stage / 'web'
        native.mkdir()
        web.mkdir()
        for sid in sorted(canonical):
            item = planned[sid]
            original = approved_masters / (sid + '.png')
            require(not original.is_symlink(), f'Unexpected master symlink: {sid}')
            require(item['prompt'].strip(), f'Missing actual generation prompt: {sid}')
            with Image.open(original, formats=['PNG']) as png:
                require(png.n_frames == 1 and png.mode in ('RGB', 'RGBA'), f'Expected a static RGB image: {sid}')
                image = ImageOps.exif_transpose(png)
                original_size = image.size
                w, h = original_size
                require(w >= WIDTH and h >= HEIGHT and abs(w * 9 / (h * 16) - 1) <= 0.01,
                        f'{sid}: {w}×{h}; the source must already be near 16:9, without upscaling')
                if image.mode == 'RGBA':
                    require(image.getchannel('A').getextrema() == (255, 255), f'Master has transparency: {sid}')
                image = image.convert('RGB')
                if (profile := png.info.get('icc_profile')):
                    image = ImageCms.profileToProfile(image, BytesIO(profile), srgb, outputMode='RGB')
                # As a static tagged or untagged source, both derivatives use standard sRGB.
                normalized = ImageOps.fit(image, (WIDTH, HEIGHT), Image.Resampling.LANCZOS)
                normalized = Image.frombytes('RGB', normalized.size, normalized.tobytes())  # strip master metadata
                target = native / manifest['files'][sid]
                normalized.save(target, format='JPEG', quality=93, subsampling=0, optimize=True)
            record = dict(id=sid, file=target.name, sha256=digest(target), source_sha256=digest(original),
                          source_dimensions=list(original_size), prompt=item['prompt'])
            for name, stock in WEB_STOCKS.items():
                if stock == sid:
                    target_web = web / (name + '.webp')
                    normalized.resize((WEB_WIDTH, WEB_HEIGHT), Image.Resampling.LANCZOS).save(
                        target_web, format='WEBP', quality=90, method=6)
                    verify_size(webp_dimensions(target_web), (WEB_WIDTH, WEB_HEIGHT), target_web)
                    record['web'] = {'path': f'docs/site/covers/{name}.webp', 'sha256': digest(target_web)}
            out['items'].append(record)
        for filename in WORKFLOW_ART:
            shutil.copyfile(cover_dir / filename, native / filename)
        dump_json(native / 'StockArtwork.json', manifest)
        shutil.copyfile(RESOURCES / 'StockCatalog.json', stage / 'StockCatalog.json')
        verify_resources(stage, out)
        for previous in cover_dir.iterdir():
            if previous.is_file() and previous.suffix.lower() in ('.png', '.jpeg', '.jpg', '.webp') and previous.name not in WORKFLOW_ART:
                previous.unlink()
        for src in native.iterdir():
            if src.name not in WORKFLOW_ART:
                shutil.copyfile(src, cover_dir / src.name)
        for src in web.iterdir():
            shutil.copyfile(src, web_dir / src.name)
        dump_json(PROVENANCE, out)
    return out


def dump_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resources', type=Path, default=RESOURCES, help='Root containing StockCatalog.json and FilmCovers/')
    parser.add_argument('--web', action='store_true', help='Include the public website WebP derivatives')
    parser.add_argument('--prepare', nargs=2, metavar=('PLAN_JSON', 'APPROVED_MASTERS'),
                        type=Path, help='Prepare and verify assets from approved, correctly named PNGs (requires Pillow)')
    args = parser.parse_args()
    try:
        if args.prepare:
            require(args.resources == RESOURCES, '--prepare writes to this checkout, not an app bundle')
            prepare(*args.prepare)
            args.web = True
        provenance = load_json(PROVENANCE)
        stocks, artwork = verify_resources(args.resources, provenance)
        if args.web:
            verify_web(provenance)
    except (ImportError, OSError, KeyError, ValueError, TypeError) as error:
        parser.exit(1, f'FAIL: {error}\n')
    print(f'PASS: {stocks} built-in IDs, {artwork} unique exact 16:9 native images' +
          (f', {len(WEB_STOCKS)} exact 16:9 website derivatives' if args.web else ''))


if __name__ == '__main__':
    main()
