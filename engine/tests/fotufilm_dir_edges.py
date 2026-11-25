"""Check residual DIR overshoot on the Fotufilm edge-screening inputs."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from spk_ctypes import Engine


def edge_overshoot(image: np.ndarray) -> float:
    weights = [0.2126, 0.7152, 0.0722]
    line = image[32:224, :, :3].mean(axis=0) @ weights
    left, right = line[256], line[768]
    low, high = sorted((left, right))
    edge = line[494:530]
    return 100 * max(0, low - edge.min(), edge.max() - high) / max(1, high - low)


def main() -> None:
    engine_dir = Path(__file__).resolve().parents[1]
    profiles = sorted((engine_dir / "resources_product/profiles").glob("*_fotufilm.json"))
    assert profiles, "Fotufilm profiles are required"
    width, height = 1024, 256
    pitches = (8.838, 3.90625)
    steps = ((0.04, 0.12), (0.08, 0.24), (0.16, 0.48))
    inputs = []
    for low, high in steps:
        pixels = np.full((height, width, 3), low, dtype=np.float32)
        pixels[:, width // 2:] = high
        inputs.append(pixels)

    # Internal screening tolerance for these inputs and the chosen output
    # path. Physical film fidelity requires a measured density response.
    max_overshoot = 40.0
    with Engine() as engine:
        for profile in profiles:
            info = json.loads(profile.read_text())["info"]
            peak = 0.0
            for pitch in pitches:
                recipe = dict(
                    film_stock=profile.stem, print_stock="kodak_portra_endura",
                    scan_film=info["type"] == "positive", film_format_mm=width * pitch / 1000,
                    auto_exposure=False, grain_active=False, halation_active=False,
                    glare_active=False, scanner_sharpening_amount=0, striped=False,
                    dir_couplers_active=True, dir_couplers_amount=1,
                )
                for step, pixels in zip(steps, inputs):
                    with engine.open(pixels, recipe) as session:
                        enabled, _ = session.render("full")
                        session.set_params({"dir_couplers_active": False})
                        disabled, _ = session.render("full")
                    overshoot = edge_overshoot(enabled)
                    label = (profile.stem, pitch, step)
                    assert edge_overshoot(disabled) <= 0.05, (label, "DIR off")
                    assert overshoot <= max_overshoot, (label, overshoot)
                    if info["channel_model"] == "bw":
                        assert np.array_equal(enabled, disabled), (label, "B&W DIR")
                    peak = max(peak, overshoot)
            print(f"{profile.stem}: worst sampled overshoot {peak:.2f}%")


if __name__ == "__main__":
    main()
