"""Headless regressions for native camera/enlarger diffusion controls."""
from __future__ import annotations

import numpy as np

from spk_ctypes import Engine


def test_diffusion_paths() -> None:
    image = np.full((192, 256, 3), 0.08, dtype=np.float32)
    image[90:102, 122:134, :] = 3.0
    common = {"auto_exposure": False, "grain_active": False,
              "grain_sublayers_active": False, "glare_active": False}
    with Engine() as engine:
        with engine.open(image, common) as session:
            original, _ = session.render("full")
            for prefix, tier in (("camera", "full"), ("enlarger", "full")):
                family_results = []
                for family in ("glimmerglass", "black_pro_mist", "pro_mist", "cinebloom"):
                    session.set_params({f"{prefix}_diffusion_family": family,
                                        f"{prefix}_diffusion_strength": 0.5,
                                        f"{prefix}_diffusion_active": True})
                    altered, _ = session.render(tier)
                    assert not np.array_equal(altered, original), (prefix, family)
                    family_results.append(altered)
                    session.set_params({f"{prefix}_diffusion_active": False})
                    restored, _ = session.render(tier)
                    assert np.array_equal(restored, original), (prefix, family)
                assert len({result.tobytes() for result in family_results}) == 4, prefix

                session.set_params({f"{prefix}_diffusion_family": "cinebloom",
                                    f"{prefix}_diffusion_strength": 0.5,
                                    f"{prefix}_diffusion_active": True})
                unit, _ = session.render(tier)
                session.set_params({f"{prefix}_diffusion_range": 0.5})
                narrow, _ = session.render(tier)
                session.set_params({f"{prefix}_diffusion_range": 2.0})
                wide, _ = session.render(tier)
                assert not np.array_equal(narrow, unit), (prefix, "narrow range")
                assert not np.array_equal(wide, unit), (prefix, "wide range")
                assert not np.array_equal(narrow, wide), (prefix, "range endpoints")
                session.set_params({f"{prefix}_diffusion_range": 1.0})
                restored_range, _ = session.render(tier)
                assert np.array_equal(restored_range, unit), (prefix, "range reset")
                session.set_params({f"{prefix}_diffusion_active": False})

            session.set_params({"camera_diffusion_active": True,
                                "camera_diffusion_strength": 0})
            zero, _ = session.render("full")
            assert np.array_equal(zero, original), "zero strength must be identity"
            session.set_params({"camera_diffusion_active": False,
                                "scan_film": True, "enlarger_diffusion_active": False})
            direct, _ = session.render("full")
            session.set_params({"enlarger_diffusion_active": True})
            direct_with_enlarger, _ = session.render("full")
            assert np.array_equal(direct, direct_with_enlarger), "direct scan bypasses enlarger"

        for prefix in ("camera", "enlarger"):
            with engine.open(image, {**common, f"{prefix}_diffusion_active": True}) as session:
                unstriped, _ = session.render("full")
                session.set_params({"striped": True, "strip_rows": 32})
                striped, _ = session.render("full")
                assert np.array_equal(unstriped, striped), f"{prefix} diffusion seams in strips"
    print("diffusion: four families, range, and both stages work; off, zero and stripes are exact")


if __name__ == "__main__":
    test_diffusion_paths()
