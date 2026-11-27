#!/usr/bin/env python3
"""Check release-table parity and reciprocal links for maintained doc pairs."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PAIRS = [
    ('README.md', 'README.en.md'),
    ('docs/README.md', 'docs/README.zh-CN.md'),
    ('docs/BINARY-RELEASES.md', 'docs/BINARY-RELEASES.zh-CN.md'),
    ('docs/LIGHTROOM-CLASSIC.md', 'docs/LIGHTROOM-CLASSIC.en.md'),
    ('docs/LOCAL-MATERIALS.md', 'docs/LOCAL-MATERIALS.zh-CN.md'),
    ('docs/showcase/README.md', 'docs/showcase/README.zh-CN.md'),
    ('ios/README.md', 'ios/README.zh-CN.md'),
    ('ios/DESIGN.md', 'ios/DESIGN.en.md'),
    ('ios/CONTROL-AUDIT.md', 'ios/CONTROL-AUDIT.en.md'),
    ('ios/APP-STORE.md', 'ios/APP-STORE.zh-CN.md'),
    ('modern_UI/Spektrafilm/README.md', 'modern_UI/Spektrafilm/README.en.md'),
    ('modern_UI/Spektrafilm/VALIDATION.md', 'modern_UI/Spektrafilm/VALIDATION.en.md'),
    ('ARCHITECTURE.md', 'ARCHITECTURE.zh-CN.md'),
    ('API-SPEC-callable-render-service.md', 'API-SPEC-callable-render-service.zh-CN.md'),
    ('CONTRACT-frontend-backend.md', 'CONTRACT-frontend-backend.zh-CN.md'),
    ('CONTRIBUTING.md', 'CONTRIBUTING.zh-CN.md'),
    ('LICENSES.md', 'LICENSES.zh-CN.md'),
]

def nav_links(path):
    header = '\n'.join(path.read_text().splitlines()[:20])
    targets = re.findall(r'\]\(([^ )#]+)(?:#[^ )]*)?\)', header)
    targets += re.findall(r'href="([^"#]+)(?:#[^"]*)?"', header)
    for target in targets:
        if not target.startswith(('https://', 'http://')):
            yield (path.parent / target).resolve()

def versions(name):
    text = (ROOT / name).read_text()
    rows = []
    for line in text.splitlines():
        parts = [p.strip() for p in line.strip('|').split('|')]
        if len(parts) != 5 or not re.fullmatch(r'\d+\.\d+\.\d+', parts[0]):
            continue
        version, platform, build, _, link_column = parts
        note = re.search(r'\]\(((?:ios|modern_UI)/[^ )]+\.md)\)', link_column)
        assert build.isdigit() and note, line
        assert (ROOT / note[1]).is_file(), note[1]
        rows.append((version, platform, build, note[1]))
    assert rows and len(rows) == len(set(rows)), name
    return rows

assert versions('README.md') == versions('README.en.md'), 'README versions/platforms/builds/notes differ'
for left, right in PAIRS:
    first, second = ROOT / left, ROOT / right
    assert second in nav_links(first), f'{left} must link to {right}'
    assert first in nav_links(second), f'{right} must link to {left}'
print(f'PASS: {len(PAIRS)} reciprocal language pairs and matching README release history')
