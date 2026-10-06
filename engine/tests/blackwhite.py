"""Headless monochrome contracts, not validation against real film scans."""
import argparse
import json
from pathlib import Path
import sys

import numpy as np

from spk_ctypes import Engine
from experimental_negatives import unchanged_originals

ENGINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ENGINE / "tools"))
from make_blackwhite_profiles import build, PAPER, SOURCE
from scipy.special import ndtr

COLORS = np.array([[.184,.184,.184],[.55,.12,.08],[.1,.4,.08],
                   [.08,.1,.45],[.45,.26,.18],[.24,.12,.08],[.28,.08,.32]], dtype=np.float32)
IMAGE = np.repeat(np.repeat(COLORS[None, :, :], 32, axis=0), 32, axis=1)
COMMON = {"auto_exposure":False, "grain_active":False, "glare_active":False,
          "halation_active":False, "scanner_sharpening_amount":0}


def chart_contract(profiles):
    # Independently read anchors on the original PDF charts, absolute density.
    # This is a digitization regression, NOT a real-film scan calibration.
    samples = json.loads(SOURCE.read_text())
    anchors = {"hp5": [(2, .80), (3, 1.43)], "fp4": [(2, .63), (4, 1.87)],
               "delta100": [(2, .35), (3, 1.02)], "xp2": [(2, .90), (4, 1.84)],
               "trix": [(-2, .85), (0, 2.11)]}
    for key, points in anchors.items():
        p = profiles[samples[key]["stock"]]
        m = p["data"]["density_curves_model"]
        x = np.array(points)[:, 0] - p["metadata"]["exposure_origin_relative_log10"]
        predicted = (ndtr((x[:, None]-m["centers"][0])/m["sigmas"][0]) * m["amplitudes"][0]).sum(1)
        predicted += p["data"]["base_density"][0]
        np.testing.assert_allclose(predicted, np.array(points)[:, 1], atol=.04, rtol=0,
                                   err_msg=key + " manufacturer-chart anchors")
        assert p["metadata"]["fit_max_density_error"] < .06
        assert len(samples[key]["characteristic"]) == 85
    # Kodak's solid spectral curve has a green dip, not a flat 2.55 plateau.
    spectral = np.array(samples["trix"]["sensitivity"])
    np.testing.assert_allclose(np.interp([400, 500, 600], *spectral.T),
                               [2.73, 2.26, 2.40], atol=.04, rtol=0)


def color_baseline(path, write):
    with Engine() as engine:
        with engine.open(IMAGE, COMMON | {"film_stock":"kodak_portra_400", "print_stock":"kodak_portra_endura"}) as s:
            pixels, _ = s.render("full")
    if write:
        np.save(path, pixels)
        print("saved pre-change colour baseline", flush=True)
    else:
        np.testing.assert_array_equal(pixels, np.load(path))
        print("existing colour output byte-identical PASS", flush=True)


def neutral(pixels, tag):
    rgb = pixels[..., :3].astype(float)
    assert np.isfinite(rgb).all()
    # CAT02/colour matrices retain small floating point round-trip differences.
    assert np.max(np.ptp(rgb, axis=2)) <= 40, (tag, np.max(np.ptp(rgb, axis=2)))
    assert np.ptp(rgb) > 1000, (tag, "flat result")


def run():
    unchanged_originals()
    profiles = build()
    chart_contract(profiles)
    for stock, expected in profiles.items():
        actual = json.loads((ENGINE / f"resources/profiles/{stock}.json").read_text())
        assert actual == expected, stock
        assert actual["info"]["channel_model"] in ("monochrome", "chromogenic_monochrome")
        assert "Andrea Volpato" in actual["metadata"]["license"]
        curves = np.array(actual["data"]["density_curves"])
        assert np.all(np.diff(curves, axis=0) >= 0)
        layers = np.array(actual["data"]["density_curves_layers"])
        np.testing.assert_allclose(layers.sum(axis=1), curves, atol=1e-12)
    results = []
    with Engine() as engine:
        for row in json.loads(SOURCE.read_text()).values():
            stock = row["stock"]
            with engine.open(IMAGE, COMMON | {"film_stock":stock, "print_stock":PAPER, "extended_dynamic_range":True}) as s:
                printed, _ = s.render("full")
                neutral(printed, stock)
                s.set_params({"dir_couplers_amount":0, "dir_couplers_active":False, "extended_dynamic_range":False})
                no_couplers, _ = s.render("full")
                np.testing.assert_array_equal(printed, no_couplers)
                s.set_params({"density_curve_gamma":1.25})
                contrast, _ = s.render("full")
                assert not np.array_equal(printed, contrast)
                s.set_params({"density_curve_gamma":1, "striped":True, "strip_rows":16})
                striped, _ = s.render("full")
                np.testing.assert_array_equal(printed, striped)
                s.set_params({"grain_active":True})
                grain, _ = s.render("full")
                neutral(grain, stock + " grain")
                assert not np.array_equal(grain, printed)
                repeated, _ = s.render("full")
                neutral(repeated, stock + " repeated stochastic grain")
                s.set_params({"grain_sublayers_active":False})
                simple, _ = s.render("full")
                neutral(simple, stock + " simple grain")
                s.set_params({"grain_active":False, "scan_film":True})
                scan, _ = s.render("full")
                neutral(scan, stock + " raw scan")
                assert not np.array_equal(scan, printed)
                s.set_params({"scan_film":False, "digital_intermediate":True})
                di, _ = s.render("full")
                neutral(di, stock + " DI")
                # The exporter uses the full-resolution Cineon entry point,
                # not the display-view rendering tested above.
                cineon, metadata = s.render_digital_intermediate()
                neutral(cineon, stock + " Cineon export")
                assert metadata["encoding"] == "cineon"
                s.set_params({"digital_intermediate":False, "halation_active":True})
                halo, _ = s.render("full")
                neutral(halo, stock + " halo")
                s.set_params({"halation_active":False, "film_stock":"kodak_portra_400", "print_stock":"kodak_portra_endura"})
                color, _ = s.render("full")
                assert np.max(np.ptp(color[..., :3].astype(float), axis=2)) > 1000
                s.set_params({"film_stock":stock, "print_stock":PAPER})
                restored, _ = s.render("full")
                np.testing.assert_array_equal(restored, printed)
                results.append(printed)
            ev = np.linspace(-6, 6, 128, dtype=np.float32)
            ramp = np.broadcast_to((.184*2**ev)[None, :, None], (32, 128, 3)).copy()
            with engine.open(ramp, COMMON | {"film_stock":stock, "print_stock":PAPER}) as s:
                tones, _ = s.render("full")
                neutral(tones, stock + " exposure ramp")
                gray = tones[16, :, 1].astype(float)
                assert np.all(np.diff(gray) >= -1), (stock, "reversed tone response")
                assert np.ptp(gray) > 30000, (stock, "collapsed tonal range")
                s.set_params({"exposure_compensation_ev":1})
                shifted, _ = s.render("full")
                assert not np.array_equal(shifted, tones)
            print(stock, "print / controls / strips / grain / scan / DI / stock switching PASS", flush=True)
    assert all(not np.array_equal(a, b) for i, a in enumerate(results) for b in results[:i])
    print("six distinct colour-to-gray and tone responses PASS", flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--baseline", type=Path)
    ap.add_argument("--write-baseline", action="store_true")
    args = ap.parse_args()
    if args.baseline:
        color_baseline(args.baseline, args.write_baseline)
    if not args.write_baseline:
        run()
