#!/usr/bin/env python3
"""Stage ignored maintainer materials into generated resources, never public inputs.
SILVERPHASE_LOCAL_MATERIALS=0 explicitly strips the overlay for distribution.
"""
import argparse
import json
import os
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "private-fixtures/local-experimental-materials"
APP = Path("modern_UI/Spektrafilm/Spektrafilm")
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("resources", type=Path)
a = parser.parse_args()
resources = a.resources.resolve()
engine = resources / "engine"
if not (engine / "profiles").is_dir():
    raise SystemExit("Local materials: prepare engine resources first")
overlay = resources / "LocalMaterials"
# Rebuild the generated subset on every invocation, including transitions to public.
if overlay.exists():
    shutil.rmtree(overlay)
for p in (engine / "profiles").glob("*_experimental.json"):
    p.unlink()
base_filters = json.loads((ROOT / "engine/resources/neutral_print_filters.json").read_text())
product_filters = json.loads((ROOT / "engine/resources_product/neutral_print_filters.json").read_text())
def merge(left, right):
    for key, value in right.items():
        if isinstance(value, dict) and isinstance(left.get(key), dict):
            merge(left[key], value)
        else:
            left[key] = value
merge(base_filters, product_filters)
count = 0
if os.environ.get("SILVERPHASE_LOCAL_MATERIALS", "1") != "0" and ARCHIVE.is_dir():
    catalog = json.loads((ARCHIVE / APP / "Resources/StockCatalog.json").read_text())
    stocks = [s for s in catalog["stocks"] if s["id"].endswith("_experimental")]
    ids = {s["id"] for s in stocks}
    # Only catalogued local materials; superseded migration aliases stay canonical.
    covers = overlay / "FilmCovers"
    covers.mkdir(parents=True)
    for stock in stocks:
        sid = stock["id"]
        if Path(sid).name != sid:
            raise SystemExit("Invalid local material ID")
        shutil.copy2(ARCHIVE / "engine/resources/profiles" / (sid + ".json"), engine / "profiles" / (sid + ".json"))
        shutil.copy2(ARCHIVE / APP / "Resources/FilmCovers" / (sid + "-packaging-v1.png"), covers)
    (overlay / "StockCatalog.json").write_text(json.dumps({"stocks": stocks}, indent=2) + "\n")
    old_filters = json.loads((ARCHIVE / "engine/resources/neutral_print_filters.json").read_text())
    # Include only entries involving a local ID; preserve current product data.
    def local_entries(value):
        if not isinstance(value, dict):
            return {}
        result = {}
        for key, item in value.items():
            if key in ids:
                result[key] = item
            else:
                child = local_entries(item)
                if child:
                    result[key] = child
        return result
    merge(base_filters, local_entries(old_filters))
    (overlay / "README.txt").write_text("Private local material experiments; excluded from public source and distribution.\n")
    count = len(stocks)
(engine / "neutral_print_filters.json").write_text(json.dumps(base_filters, indent=2) + "\n")
print(f"Local materials: {count} staged (SILVERPHASE_LOCAL_MATERIALS=0 for public builds)")
