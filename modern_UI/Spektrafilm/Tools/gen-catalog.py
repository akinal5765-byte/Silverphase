#!/usr/bin/env python3
"""Build Resources/StockCatalog.json and Resources/FilmCovers/ from the engine's
profile library, so the app never parses the 5.6 MB of sensitometric JSON.

    Tools/gen-catalog.py
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
REPO = HERE.parents[1]

# Read from the engine's own baked resources, not from the Python reference
# tree under `src/`. This is the difference the standalone repo makes: `src/`
# is not here, and `engine/resources/` is — the same 28 profiles the engine
# opens at run time, plus `print_luts.json`, which is the metadata index over
# the 8 print-preview LUTs (`paired_film`, `lut_size`, and so on) that the bake
# wrote. Deriving the catalog from the engine's inputs means the catalog cannot
# disagree with what the engine will actually load.
PROFILES = REPO / "engine/resources/profiles"
PRINT_LUTS = REPO / "engine/resources/print_luts.json"
COVERS_SRC = REPO / "modern_UI/film_covers"
OUT = HERE / "Spektrafilm/Resources"

# stock id -> substring of the cover filename
COVERS = {
    "kodak_portra_400": "Kodak_Portra_400",
    "kodak_portra_160": "Kodak_Portra_160",
    "kodak_portra_800": "Kodak_Portra_800",
    "kodak_portra_800_push1": "Kodak_Portra_800",
    "kodak_portra_800_push2": "Kodak_Portra_800",
    "kodak_gold_200": "Kodak_Gold_200",
    "kodak_ektachrome_100": "Kodak_Ektachrome_100",
    "kodak_ultramax_400": "Kodak_UltraMax_400",
    "fujifilm_provia_100f": "Fujifilm_Provia_100F",
    "fujifilm_velvia_100": "Fujifilm_Velvia_100",
    "fujifilm_xtra_400": "Fujifilm_Color_400",
}


# Manufacturer nominal speeds are display metadata, not measured sensitometry.
# Push profiles retain the underlying stock's nominal ISO; processing is in name.
# Camera motion-picture stocks are rated by EI, not relabelled as ISO.
KODAK_STILL_SPEED_SOURCE = "https://www.kodakprofessional.com/en-gb/node/133"
FUJI_SPEED_SOURCE = "https://asset.fujifilm.com/www/us/files/2020-04/9cdee030ab7fc76bbcfddbcd38650038/ProfessionalFilmDataGuide.pdf"
KODAK_CINE_SPEED_SOURCE = "https://www.kodak.com/en/motion/products/camera-films/"
NOMINAL_SPEEDS = {
    "kodak_tri_x_400": 400, "ilford_hp5_plus_400": 400,
    "kodak_tmax_100": 100, "fujifilm_neopan_acros_100_ii": 100,
    "fujifilm_c200": 200, "fujifilm_pro_400h": 400,
    "fujifilm_provia_100f": 100, "fujifilm_velvia_100": 100,
    "fujifilm_xtra_400": 400,
    "kodak_ektachrome_100": 100, "kodak_ektar_100": 100,
    "kodak_gold_200": 200, "kodak_kodachrome_64": 64,
    "kodak_portra_160": 160, "kodak_portra_400": 400,
    "kodak_portra_800": 800, "kodak_portra_800_push1": 800,
    "kodak_portra_800_push2": 800, "kodak_ultramax_400": 400,
    "kodak_verita_200d": 200, "kodak_vision3_200t": 200,
    "kodak_vision3_250d": 250, "kodak_vision3_500t": 500,
    "kodak_vision3_50d": 50,
}

STOCK_SPEED_SOURCES = {
    "ilford_hp5_plus_400": "https://www.ilfordphoto.com/amfile/file/download/file/1903/product/691/",
    "kodak_tri_x_400": "https://www.kodakprofessional.com/sites/default/files/wysiwyg/film/f4017_trix_320400.pdf",
    "kodak_tmax_100": "https://www.kodakprofessional.com/sites/default/files/wysiwyg/film/f4016.pdf",
}


def main() -> None:
    (OUT / "FilmCovers").mkdir(parents=True, exist_ok=True)
    luts = json.loads(PRINT_LUTS.read_text())
    stocks = []
    paths = list(PROFILES.glob("*.json")) + list((REPO / "engine/resources_product/profiles").glob("*.json"))
    for path in sorted(paths, key=lambda p: p.stem):
        info = json.loads(path.read_text())["info"]
        sid = path.stem
        cover = None
        if sid in COVERS:
            src = next(COVERS_SRC.glob(f"*{COVERS[sid]}*"), None)
            if src:
                cover = f"{sid}.jpg"
                dst = OUT / "FilmCovers" / cover
                if not dst.exists():
                    subprocess.run(["sips", "-Z", "160", str(src), "--out", str(dst)],
                                   check=True, capture_output=True)
        stocks.append({
            "id": sid,
            "name": info.get("name", sid),
            "stage": info.get("stage"),            # filming | printing
            "use": info.get("use", "still"),       # still | cine
            "type": info.get("type"),
            "channelModel": info.get("channel_model", "color"),
            "targetPrint": ("ilford_multigrade_iv_rc" if info.get("stage") == "filming" and info.get("channel_model") in ("bw", "monochrome", "chromogenic_monochrome") else info.get("target_print")),
            "hasPreviewLUT": sid in luts,
            "pairedFilm": luts[sid]["paired_film"] if sid in luts else None,
            "cover": cover,
            "nominalSpeed": NOMINAL_SPEEDS.get(sid) if info.get("stage") == "filming" else None,
            "speedUnit": ("EI" if info.get("use") == "cine" else "ISO") if sid in NOMINAL_SPEEDS else None,
            "speedSource": (STOCK_SPEED_SOURCES[sid] if sid in STOCK_SPEED_SOURCES else
                            FUJI_SPEED_SOURCE if sid.startswith("fujifilm_") else
                            KODAK_CINE_SPEED_SOURCE if info.get("use") == "cine" else
                            KODAK_STILL_SPEED_SOURCE) if sid in NOMINAL_SPEEDS else None,
        })
    (OUT / "StockCatalog.json").write_text(json.dumps({"stocks": stocks}, indent=1))
    print(f"wrote {len(stocks)} stocks")


if __name__ == "__main__":
    main()
