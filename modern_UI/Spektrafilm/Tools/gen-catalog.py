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
    "ilford_hp5_plus_400_experimental": 400, "kodak_tri_x_400_experimental": 400,
    "ilford_delta_100_experimental": 100, "ilford_fp4_plus_125_experimental": 125,
    "ilford_xp2_super_400_experimental": 400, "foma_fomapan_100_experimental": 100,
    "fujifilm_c200": 200, "fujifilm_pro_400h": 400,
    "fujifilm_pro_160ns_experimental": 160,
    "fujifilm_superia_reala_100_experimental": 100,
    "fujifilm_natura_1600_experimental": 1600,
    "kodak_pro_image_100_experimental": 100,
    "agfa_portrait_xps_160_experimental": 160,
    "agfa_optima_ii_200_experimental": 200,
    "kodak_elite_color_200_experimental": 200,
    "fujifilm_pro_160c_experimental": 160,
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

EXPERIMENTAL_SPEED_SOURCES = {
    "ilford_hp5_plus_400": "https://www.ilfordphoto.com/amfile/file/download/file/1903/product/691/",
    "kodak_tri_x_400": "https://www.kodakprofessional.com/sites/default/files/wysiwyg/film/f4017_trix_320400.pdf",
    "kodak_tmax_100": "https://www.kodakprofessional.com/sites/default/files/wysiwyg/film/f4016.pdf",
    "ilford_hp5_plus_400_experimental": "https://www.ilfordphoto.com/amfile/file/download/file/1903/product/691/",
    "ilford_delta_100_experimental": "https://www.ilfordphoto.com/amfile/file/download/file/3/product/680/",
    "ilford_fp4_plus_125_experimental": "https://www.ilfordphoto.com/amfile/file/download/file/1919/product/686/",
    "ilford_xp2_super_400_experimental": "https://www.ilfordphoto.com/amfile/file/download/file/1909/product/703/",
    "kodak_tri_x_400_experimental": "https://www.kodakprofessional.com/sites/default/files/wysiwyg/film/f4017_trix_320400.pdf",
    "foma_fomapan_100_experimental": "https://www.foma.cz/en/fomapan-100",
    "fujifilm_pro_160ns_experimental": "https://asset.fujifilm.com/www/jp/files/2024-04/6b75b1c1cb4253623fb2cd7a56ff7443/datasheet_pro160ns_01.pdf",
    "fujifilm_superia_reala_100_experimental": "https://filmcolors.org/wp-content/uploads/2025/12/Fujicolor-Superia-Reala_AF3-967E.pdf",
    "fujifilm_natura_1600_experimental": "https://asset.fujifilm.com/www/jp/files/2024-04/96b634a89ec6a5abda6b70437f4d75a4/datasheet_natura1600_01.pdf",
    "kodak_pro_image_100_experimental": "https://vklaboratori.com/wp-content/uploads/2018/07/kodak-pro-image-100.pdf",
    "agfa_portrait_xps_160_experimental": "https://cacreeks.com/photos/agfaPro.pdf",
    "agfa_optima_ii_200_experimental": "https://cacreeks.com/photos/agfaPro.pdf",
    "kodak_elite_color_200_experimental": "https://125px.com/docs/film/kodak/e4039-Elite.pdf",
    "fujifilm_pro_160c_experimental": "https://asset.fujifilm.com/www/ca/files/2020-03/d52487c5c6f84e7f935c299491c5c1ff/ProfessionalFilmDataGuide.pdf",
}


def main() -> None:
    (OUT / "FilmCovers").mkdir(parents=True, exist_ok=True)
    luts = json.loads(PRINT_LUTS.read_text())
    stocks = []
    retired = {"kodak_tri_x_400_experimental", "ilford_hp5_plus_400_experimental",
               "silverphase_neutral_bw_print_experimental"}
    paths = list(PROFILES.glob("*.json")) + list((REPO / "engine/resources_product/profiles").glob("*.json"))
    for path in sorted(paths, key=lambda p: p.stem):
        if path.stem in retired:
            continue
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
            "speedUnit": ("EI" if info.get("use") == "cine" or sid == "kodak_pro_image_100_experimental" else "ISO") if sid in NOMINAL_SPEEDS else None,
            "speedSource": (EXPERIMENTAL_SPEED_SOURCES[sid] if sid in EXPERIMENTAL_SPEED_SOURCES else
                            FUJI_SPEED_SOURCE if sid.startswith("fujifilm_") else
                            KODAK_CINE_SPEED_SOURCE if info.get("use") == "cine" else
                            KODAK_STILL_SPEED_SOURCE) if sid in NOMINAL_SPEEDS else None,
        })
    (OUT / "StockCatalog.json").write_text(json.dumps({"stocks": stocks}, indent=1))
    print(f"wrote {len(stocks)} stocks")


if __name__ == "__main__":
    main()
