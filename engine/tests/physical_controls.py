"""Headless pixel regressions for Silverphase's grain and paper controls.

Run after ``engine/build.sh dylib``. The two controls are native extensions,
so the Python spektrafilm reference has no corresponding slider oracle.
"""
from __future__ import annotations

import numpy as np

from spk_ctypes import Engine


def print_contrast() -> None:
    ramp = np.linspace(0.02, 1.2, 128, dtype=np.float32)
    image = np.repeat(ramp[None, :, None], 64, axis=0)
    image = np.repeat(image, 3, axis=2)
    papers = (
        "kodak_portra_endura", "kodak_supra_endura", "kodak_endura_premier",
        "fujifilm_crystal_archive_typeii", "kodak_2383", "kodak_2393",
        "kodak_ektacolor_edge", "kodak_ultra_endura",
    )
    with Engine() as engine:
        for paper in papers:
            with engine.open(image, {
                "film_stock": "kodak_portra_400", "print_stock": paper,
                "auto_exposure": False, "grain_active": False, "glare_active": False,
            }) as session:
                original, _ = session.render("full")
                for contrast in (0.7, 1.3):
                    session.set_params({"print_contrast": contrast})
                    changed, _ = session.render("full", reprint=True)
                    assert not np.array_equal(changed, original), (paper, contrast)
                session.set_params({"print_contrast": 1.0})
                restored, _ = session.render("full", reprint=True)
                assert np.array_equal(restored, original), paper
    print(f"print contrast: {len(papers)} papers changed and reset exactly")


def grain_size() -> None:
    image = np.full((128, 128, 3), 0.3, dtype=np.float32)
    with Engine() as engine:
        with engine.open(image, {
            "film_stock": "kodak_portra_400", "print_stock": "kodak_portra_endura",
            "auto_exposure": False, "grain_active": False, "glare_active": False,
        }) as session:
            clean, _ = session.render("full")
            clean = clean[:, :, :3].astype(np.float32)
            session.set_params({"grain_active": True, "grain_sublayers_active": True})
            normal, _ = session.render("full")
            rms = []
            for scale in (0.5, 1.0, 2.0):
                session.set_params({"grain_size_scale": scale})
                changed, _ = session.render("full")
                noise = changed[:, :, :3].astype(np.float32) - clean
                rms.append(float(np.sqrt(np.mean(noise * noise))))
                if scale == 1.0:
                    assert np.array_equal(changed, normal)
            assert rms[0] < rms[1] < rms[2], rms
            session.set_params({"grain_size_scale": 1.0})
            restored, _ = session.render("full")
            assert np.array_equal(restored, normal)
    print(f"grain size: RMS increases {rms} and resets exactly")


def preview_and_export_tiers() -> None:
    ramp = np.linspace(0.02, 1.2, 1024, dtype=np.float32)
    image = np.repeat(ramp[None, :, None], 800, axis=0)
    image = np.repeat(image, 3, axis=2)
    with Engine() as engine:
        with engine.open(image, {
            "film_stock": "kodak_portra_400", "print_stock": "kodak_portra_endura",
            "auto_exposure": False, "glare_active": False,
            "preview_long_edge": 800,
        }) as session:
            for key, value in (("grain_size_scale", 1.5), ("print_contrast", 1.2)):
                if key == "print_contrast":
                    session.set_params({"grain_active": False,
                                        "grain_sublayers_active": False})
                before = {tier: session.render(tier)[0] for tier in ("live", "full")}
                session.set_params({key: value})
                after = {tier: session.render(tier)[0] for tier in ("live", "full")}
                for tier in ("live", "full"):
                    assert not np.array_equal(before[tier], after[tier]), (key, tier)
                session.set_params({key: 1.0})
                for tier in ("live", "full"):
                    restored, _ = session.render(tier)
                    assert np.array_equal(restored, before[tier]), (key, tier)
    print("preview/full: both controls change both tiers and reset exactly")


if __name__ == "__main__":
    print_contrast()
    grain_size()
    preview_and_export_tiers()
