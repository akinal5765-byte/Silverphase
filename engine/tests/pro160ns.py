"""Headless structural/runtime checks; NOT validation against real PRO160NS."""
from pathlib import Path
import importlib.util
import json

import numpy as np
from scipy.special import ndtr

from spk_ctypes import Engine

ENGINE = Path(__file__).resolve().parents[1]
STOCK = "fujifilm_pro_160ns_experimental"


def data_contract():
    path = ENGINE / f"resources/profiles/{STOCK}.json"
    profile = json.loads(path.read_text())
    assert profile["metadata"]["experimental"] is True
    assert "Andrea Volpato" in profile["metadata"]["license"]
    assert profile["metadata"]["approximation_revision"] == 2
    assert "Not performed" in profile["metadata"]["density_inverse"]
    assert profile["info"]["type"] == "negative"
    data = profile["data"]
    assert profile["metadata"]["sensitivity_source_weight"] == .20
    axis = np.array(data["log_exposure"])
    curves = np.array(data["density_curves"])
    layers = np.array(data["density_curves_layers"])
    assert curves.shape == (256, 3) and layers.shape == (256, 3, 3)
    assert np.isfinite(curves).all() and np.all(np.diff(curves, axis=0) >= 0)
    np.testing.assert_allclose(layers.sum(axis=1), curves, atol=1e-12)
    m = data["density_curves_model"]
    for c in range(3):
        expected = ndtr((axis[:, None]-np.array(m["centers"][c]))/m["sigmas"][c])*m["amplitudes"][c]
        np.testing.assert_allclose(expected, layers[:, :, c], atol=1e-12)
    donor = json.loads((ENGINE / "resources/profiles/fujifilm_pro_400h.json").read_text())
    assert data["density_curves"] != donor["data"]["density_curves"]
    assert data["log_sensitivity"] != donor["data"]["log_sensitivity"]
    for field in ("channel_density", "base_density", "midscale_neutral_density"):
        assert data[field] == donor["data"][field]
    spec = importlib.util.spec_from_file_location("generator", ENGINE / "tools/make_pro160ns.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    rebuilt = module.build(json.loads(module.SOURCE.read_text()))
    assert rebuilt == profile, "generator and shipped profile differ"
    print("data: provenance, monotonicity, sublayers, distinct stock, reproducibility PASS")


def runtime():
    ev = np.linspace(-6, 6, 160, dtype=np.float32)
    image = np.broadcast_to((.184*2**ev)[None, :, None], (96, 160, 3)).copy()
    common = {"auto_exposure": False, "grain_active": False, "glare_active": False,
              "halation_active": False, "scanner_sharpening_amount": 0}
    with Engine() as engine:
        with engine.open(image, common | {"film_stock": "fujifilm_pro_400h"}) as old:
            donor, _ = old.render("full")
        papers = json.loads((ENGINE / "resources/print_luts.json").read_text())
        for paper in papers:
            with engine.open(image, common | {"film_stock": STOCK, "print_stock": paper}) as session:
                result, _ = session.render("full")
                assert np.isfinite(result).all() and np.ptp(result[..., :3].astype(float)) > 6500, paper
                assert not np.array_equal(result, donor), "stock only renamed"
                repeated, _ = session.render("full", reprint=True)
                assert np.array_equal(result, repeated), paper
                session.set_params({"striped": True, "strip_rows": 32})
                striped, _ = session.render("full")
                assert np.array_equal(result, striped), paper
                session.set_params({"grain_active": True, "grain_sublayers_active": True})
                grained, _ = session.render("full")
                assert np.isfinite(grained).all() and not np.array_equal(grained, result), paper
                session.set_params({"grain_active": False, "scan_film": True})
                scan, _ = session.render("full")
                assert np.isfinite(scan).all(), paper
        gray = np.full((32, 32, 3), .184, dtype=np.float32)
        for paper in papers:
            with engine.open(gray, common | {"film_stock": STOCK, "print_stock": paper}) as session:
                result, _ = session.render("full")
                rgb = result[..., :3].astype(float).mean(axis=(0, 1))
                assert np.all((rgb > 1000) & (rgb < 64000)), (paper, rgb)
                assert np.max(np.abs(np.log(rgb[[0, 2]]/rgb[1]))) < .02, (paper, rgb)
        with engine.open(image, common | {"film_stock": STOCK, "digital_intermediate": True}) as session:
            intermediate, metadata = session.export_di("fujifilm_crystal_archive_typeii")
            assert intermediate.shape == (96, 160, 4)
            assert metadata["paired_film"] == "fujifilm_pro_400h"
            assert "approximation" in metadata["warning"]
    print(f"native: {len(papers)} papers, repeat/reprint, strips, layered grain, scan, neutral packs PASS")


if __name__ == "__main__":
    data_contract()
    runtime()
