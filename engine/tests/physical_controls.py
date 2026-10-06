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


def grain_softness() -> None:
    image = np.full((192, 256, 3), 0.3, dtype=np.float32)
    common = {"auto_exposure": False, "glare_active": False,
              "scanner_sharpening_amount": 0}
    with Engine() as engine:
        field = next(f for f in engine.params_schema()["fields"] if f["name"] == "grain_softness")
        assert field["layer"] == "shoot" and field["default"] == 0.65
        assert field["range"] == [0, 1.3]

        def render(delta, tier="full", source=image):
            # Each fresh pipeline starts at the same RNG state. Compare the
            # same initial realisation, not two stochastic runs of one session.
            with engine.open(source, common | delta) as session:
                return session.render(tier)[0].astype(np.float32)

        for layered in (False, True):
            base = {"grain_active": True, "grain_sublayers_active": layered}
            original = render(base)
            assert np.array_equal(original, render(base | {"grain_softness": 0.65}))
            roughness = []
            for blur in (0, 0.65, 1.3):
                result = render(base | {"grain_softness": blur})
                inner = result[8:-8, 8:-8, :3]
                roughness.append(float(np.mean(np.diff(inner, axis=1) ** 2)))
            assert roughness[0] > roughness[1] > roughness[2], (layered, roughness)
            striped = render(base | {"grain_softness": 1.3, "striped": True, "strip_rows": 32})
            assert np.array_equal(striped, render(base | {"grain_softness": 1.3})), "grain blur strip seams"
        for bypass in ({"grain_active": False}, {"grain_active": True, "grain_amount": 0}):
            assert np.array_equal(render(bypass | {"grain_softness": 0}),
                                  render(bypass | {"grain_softness": 1.3})), bypass
        large = np.full((800, 1024, 3), 0.3, dtype=np.float32)
        for tier in ("live", "full"):
            hard = render({"grain_softness": 0, "preview_long_edge": 800}, tier, large)
            soft = render({"grain_softness": 1.3, "preview_long_edge": 800}, tier, large)
            assert not np.array_equal(hard, soft), tier
            assert np.mean(np.diff(hard[8:-8, 8:-8, :3], axis=1) ** 2) > np.mean(np.diff(soft[8:-8, 8:-8, :3], axis=1) ** 2), tier
    print("grain softness: default identity, both grain models, smoother texture, off/zero bypass, strips and live/full pass")


def scanner_sharpening() -> None:
    # Nonuniform deterministic scene: sharpening a flat field proves nothing.
    image = np.full((128, 256, 3), 0.12, dtype=np.float32)
    image[:, 128:, :] = 0.5
    image[48:80, 112:144, :] = 0.8
    common = {"auto_exposure": False, "grain_active": False,
              "grain_sublayers_active": False, "glare_active": False}
    with Engine() as engine:
        schema = engine.params_schema()
        field = next(f for f in schema["fields"] if f["name"] == "scanner_sharpening_amount")
        assert field["layer"] == "print" and field["default"] == 0.7
        assert field["range"] == [0, 1.4]
        for scan_film in (False, True):
            with engine.open(image, {**common, "scan_film": scan_film}) as session:
                original, _ = session.render("full")
                session.set_params({"scanner_sharpening_amount": 0.7})
                explicit, _ = session.render("full", reprint=True)
                assert np.array_equal(explicit, original), "default must retain old pixels"
                session.set_params({"scanner_sharpening_amount": 0})
                off, result = session.render("full", reprint=True)
                assert result.negative_was_cached, "scan edit must reuse the negative"
                assert not np.array_equal(off, original), (scan_film, "off must change edges")
                for amount in (0.35, 1.4):
                    session.set_params({"scanner_sharpening_amount": amount})
                    changed, _ = session.render("full", reprint=True)
                    assert not np.array_equal(changed, off), (scan_film, amount)
                    assert not np.array_equal(changed, original), (scan_film, amount)
                session.set_params({"scanner_sharpening_amount": 0.7})
                restored, _ = session.render("full", reprint=True)
                assert np.array_equal(restored, original), "toggle back restores exactly"
                session.set_params({"striped": True, "strip_rows": 32})
                striped, _ = session.render("full", reprint=True)
                assert np.array_equal(striped, original), "scan sharpening must have no strip seams"
        with engine.open(image, {**common, "digital_intermediate": True}) as session:
            original, _ = session.render("full")
            session.set_params({"scanner_sharpening_amount": 0})
            off, _ = session.render("full", reprint=True)
            assert np.array_equal(off, original), "DI must bypass scan sharpening"
    print("scan sharpening: old default, off/strength/reset, negative reuse, strips and DI pass")


if __name__ == "__main__":
    print_contrast()
    grain_size()
    preview_and_export_tiers()
    scanner_sharpening()
    grain_softness()
