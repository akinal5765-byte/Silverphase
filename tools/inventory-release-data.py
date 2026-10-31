#!/usr/bin/env python3
"""Record baked table hashes and their documented input families without rebaking."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--check', action='store_true')
a = p.parse_args()
path = ROOT / 'engine/resources/spektrafilm_constants.bin'
raw = path.read_bytes()
assert raw[:4] == b'SPKR'
version, count, _ = struct.unpack_from('<III', raw, 4)
assert version == 1
fmt = '<64sIIIIIIQQ'
size = struct.calcsize(fmt)
entries = []
for i in range(count):
    name, dtype, ndim, *rest = struct.unpack_from(fmt, raw, 16 + i * size)
    dims, offset, length = rest[:4], rest[4], rest[5]
    name = name.rstrip(b'\0').decode()
    assert offset >= 16 + count * size and offset + length <= len(raw)
    elements = 1
    for d in dims[:ndim]:
        elements *= d
    assert length == elements * [8, 4, 2, 4, 1][dtype]
    if name.startswith(('print_lut/', 'print_lut_axes/')):
        family = 'profile-derived-print-luts'
    elif name.startswith('colour/'):
        family = 'colour-baked-arrays'
    elif name.startswith('hanatos/'):
        family = 'hanatos-spectral-upsampling'
    elif name.startswith('filters/'):
        family = 'filter-curves'
    elif name.startswith('spectral/'):
        family = 'spectral-sampling-grid'
    else:
        raise SystemExit(f'Unclassified data entry: {name}')
    entries.append({'name': name, 'family': family, 'dtype': ['float64','float32','float16','int32','uint8'][dtype],
                    'shape': dims[:ndim], 'bytes': length,
                    'sha256': hashlib.sha256(raw[offset:offset+length]).hexdigest()})
result = {'path': str(path.relative_to(ROOT)), 'sha256': hashlib.sha256(raw).hexdigest(),
          'bytes': len(raw), 'blob_version': version,
          'producer': 'engine/tools/bake_resources.py',
          'scope': 'Current stored arrays only. Not a rebake or a complete upstream licensing determination.',
          'entries': entries}
text = json.dumps(result, indent=2) + '\n'
out = ROOT / 'license/data-inventory.json'
if a.check:
    if not out.is_file() or out.read_text() != text:
        raise SystemExit('Data inventory is stale; review changes and run tools/inventory-release-data.py')
else:
    out.write_text(text)
print(f'PASS: {len(entries)} baked entries, {len(raw)} bytes; stored-data hashes verified.')
