"""Headless contracts/render checks, not validation against real negatives."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import numpy as np
from scipy.special import ndtr

import pro160ns
from spk_ctypes import Engine

ENGINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ENGINE / "tools"))
from make_negative_profiles import STOCKS
from make_pro160ns import build


def data_contract(key):
    stock, name, donor, _, _ = STOCKS[key]
    profile = json.loads((ENGINE / f"resources/profiles/{stock}.json").read_text())
    source = json.loads((ENGINE / f"tools/profile_sources/{key}_samples.json").read_text())
    assert profile == build(source, stock=stock, name=name, donor=donor)
    assert profile["metadata"]["experimental"] is True
    assert "Andrea Volpato" in profile["metadata"]["license"]
    assert profile["metadata"]["approximation_revision"] == 2
    assert "Not performed" in profile["metadata"]["density_inverse"]
    donor_bytes = (ENGINE / f"resources/profiles/{donor}.json").read_bytes()
    assert profile["metadata"]["donor_sha256"] == hashlib.sha256(donor_bytes).hexdigest()
    assert profile["info"]["type"] == "negative"
    data = profile["data"]
    assert profile["metadata"]["sensitivity_source_weight"] == .20
    curves = np.array(data["density_curves"])
    layers = np.array(data["density_curves_layers"])
    axis = np.array(data["log_exposure"])
    assert curves.shape == (256, 3) and layers.shape == (256, 3, 3)
    assert np.isfinite(curves).all() and np.all(np.diff(curves, axis=0) >= 0)
    np.testing.assert_allclose(layers.sum(axis=1), curves, atol=1e-12)
    model = data["density_curves_model"]
    for c in range(3):
        expected = ndtr((axis[:,None]-model["centers"][c])/model["sigmas"][c])*model["amplitudes"][c]
        np.testing.assert_allclose(expected, layers[:,:,c], atol=1e-12)
    old = json.loads(donor_bytes)["data"]
    for field in ("channel_density", "base_density", "midscale_neutral_density"):
        assert data[field] == old[field]
    assert data["density_curves"] != old["density_curves"]
    assert data["log_sensitivity"] != old["log_sensitivity"]
    print(stock, "provenance / CDF sublayers / reproducibility PASS", flush=True)


def unchanged_originals():
    repo = ENGINE.parent
    paths = subprocess.check_output(["git","ls-tree","-r","--name-only","HEAD","engine/resources/profiles"],cwd=repo,text=True).splitlines()
    for path in paths:
        original = subprocess.check_output(["git","show",f"HEAD:{path}"],cwd=repo)
        assert (repo/path).read_bytes() == original, path
    original_table = json.loads(subprocess.check_output(["git","show","HEAD:engine/resources/neutral_print_filters.json"],cwd=repo))
    current = json.loads((ENGINE/"resources/neutral_print_filters.json").read_text())
    for paper, lights in original_table.items():
        for light, stocks in lights.items():
            for stock, values in stocks.items():
                assert current[paper][light][stock] == values, (paper,light,stock)
    print(len(paths), "original profiles and all original filter packs unchanged PASS",flush=True)


def color_and_switching():
    """Exercise chromatic inputs, not a claim of real-film colour accuracy."""
    colors = np.array([[.184,.184,.184], [.55,.12,.08], [.10,.40,.08],
                       [.08,.10,.45], [.45,.26,.18], [.24,.12,.08], [.28,.08,.32]],dtype=np.float32)
    image = np.repeat(np.repeat(colors[None,:,:],32,axis=0),32,axis=1)
    params = {"auto_exposure":False, "grain_active":False, "glare_active":False,
              "halation_active":False, "scanner_sharpening_amount":0,
              "print_stock":"kodak_portra_endura"}
    outputs = []
    with Engine() as engine:
        for stock, *_ in STOCKS.values():
            with engine.open(image, params | {"film_stock":stock}) as session:
                rendered, _ = session.render("full")
                means = rendered[:,:,:3].reshape(32,len(colors),32,3).mean(axis=(0,2))
                assert np.all(np.isfinite(means))
                assert np.max(np.ptp(means[1:],axis=1)) > 1000, (stock,"chromatic input collapsed to gray")
                assert len(np.unique(means.round(),axis=0)) == len(colors), stock
                skin = means[4:6]
                assert np.all((skin > 1000) & (skin < 64000)), (stock,"skin patch clipped",skin)
                session.set_params({"film_stock":"kodak_portra_400"})
                session.render("full")
                session.set_params({"film_stock":stock})
                restored, _ = session.render("full")
                np.testing.assert_array_equal(restored,rendered,err_msg=stock+" stale stock cache")
                outputs.append(rendered)
    for i in range(len(outputs)):
        for j in range(i):
            assert not np.array_equal(outputs[i],outputs[j]), "distinct stocks have identical colour response"
    print("7 chromatic/skin-like patches: non-gray, unclipped skin, stock switching and distinct response PASS",flush=True)


if __name__ == "__main__":
    unchanged_originals()
    for key, (stock, *_rest) in STOCKS.items():
        data_contract(key)
        pro160ns.STOCK = stock
        pro160ns.runtime()
    color_and_switching()
