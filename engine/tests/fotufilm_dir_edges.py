"""Check residual DIR overshoot on the Fotufilm edge-screening inputs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from spk_ctypes import Engine


WIDTH, HEIGHT = 1024, 256
PITCHES_UM = (8.838, 3.90625)
STEPS = ((0.04, 0.12), (0.08, 0.24), (0.16, 0.48))
FLAT_EVS = (-2.5, -1.0, 0.0, 1.5, 3.0)
# Historical screening weights, not luminance coefficients for the render's colour space.
SCREEN_WEIGHTS = [0.2126, 0.7152, 0.0722]
COMMON = dict(auto_exposure=False, grain_active=False, halation_active=False,
              glare_active=False, scanner_sharpening_amount=0, striped=False,
              dir_couplers_active=True, dir_couplers_amount=1,
              print_stock="kodak_portra_endura")


def edge_rgb_line(image: np.ndarray) -> np.ndarray:
    if image.shape[:2] != (HEIGHT, WIDTH):
        raise ValueError(f"Expected an unscaled {WIDTH} × {HEIGHT} render, got {image.shape}")
    return image[32:224, :, :3].mean(axis=0)


def edge_overshoot(line_rgb: np.ndarray) -> float:
    line = line_rgb @ SCREEN_WEIGHTS
    left, right = line[256], line[768]
    low, high = sorted((left, right))
    edge = line[494:530]
    return 100 * max(0, low - edge.min(), edge.max() - high) / max(1, high - low)


def edge_channels(line_rgb: np.ndarray) -> dict:
    left, right = line_rgb[256], line_rgb[768]
    low, high = np.minimum(left, right), np.maximum(left, right)
    edge = line_rgb[494:530]
    span = high - low
    # Report undefined percentages for clipped/flat channels instead of
    # hiding a zero denominator or amplifying fractional-code noise.
    def percentages(excursion):
        return [float(100 * d / n) if n >= 1 else None for (d, n) in zip(excursion, span)]

    return dict(left_codes=left.tolist(), right_codes=right.tolist(),
                overshoot_percent=percentages(np.maximum(0, edge.max(axis=0) - high)),
                undershoot_percent=percentages(np.maximum(0, low - edge.min(axis=0))))


def measure(engine: Engine, pixels: np.ndarray, recipe: dict) -> tuple:
    with engine.open(pixels, recipe) as session:
        enabled, _ = session.render("full")
        session.set_params({"dir_couplers_active": False})
        disabled, _ = session.render("full")
        return enabled, disabled, session.reply["params"]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", action="append", metavar="STEM",
                        help="run a selected stock (repeatable; default: all Fotufilm stocks)")
    parser.add_argument("--report", type=Path, metavar="NEW_JSON_FILE",
                        help="record RGB edge excursions and neutral flat-field deltas")
    args = parser.parse_args()
    if args.report and args.report.exists():
        parser.error(f"report already exists: {args.report}")

    engine_dir = Path(__file__).resolve().parents[1]
    available = {p.stem: p for p in sorted(
        (engine_dir / "resources_product/profiles").glob("*_fotufilm.json"))}
    if not available:
        parser.error("Fotufilm profiles are required")
    unknown = sorted(set(args.profile or ()) - available.keys())
    if unknown:
        parser.error("unknown Fotufilm profile(s): " + ", ".join(unknown))
    profiles = [available[k] for k in dict.fromkeys(args.profile or available)]
    inputs = []
    for low, high in STEPS:
        pixels = np.full((HEIGHT, WIDTH, 3), low, dtype=np.float32)
        pixels[:, WIDTH // 2:] = high
        inputs.append(pixels)

    # Keep the historical 40% / 0.05% gates and exact B&W equality.
    # Report-only measurements do not assert optical or chemical parity.
    with Engine() as engine:
        report = dict(schema=1, engine_build=engine.build_info, width=WIDTH, height=HEIGHT,
                      tier="full", code_max=65535, controls=COMMON, profiles=[]) if args.report else None
        for profile in profiles:
            info = json.loads(profile.read_text())["info"]
            scan_film = info["type"] == "positive"
            peak = 0.0
            cases = []
            for pitch in PITCHES_UM:
                recipe = dict(COMMON, film_stock=profile.stem, scan_film=scan_film,
                              film_format_mm=WIDTH * pitch / 1000)
                edges = []
                for step, pixels in zip(STEPS, inputs):
                    enabled, disabled, resolved = measure(engine, pixels, recipe)
                    on, off = edge_rgb_line(enabled), edge_rgb_line(disabled)
                    overshoot = edge_overshoot(on)
                    label = (profile.stem, pitch, step)
                    assert edge_overshoot(off) <= 0.05, (label, "DIR off")
                    assert overshoot <= 40.0, (label, overshoot)
                    if info["channel_model"] == "bw":
                        assert np.array_equal(enabled, disabled), (label, "B&W DIR")
                    peak = max(peak, overshoot)
                    if report is not None:
                        edges.append(dict(input_neutral_ends=step, on=edge_channels(on), off=edge_channels(off)))

                if report is not None:
                    flats = []
                    for ev in FLAT_EVS:
                        level = 0.18 * 2.0 ** ev
                        pixels = np.full((HEIGHT, WIDTH, 3), level, dtype=np.float32)
                        enabled, disabled, _ = measure(engine, pixels, recipe)
                        on = enabled[HEIGHT // 2, WIDTH // 2, :3].astype(int)
                        off = disabled[HEIGHT // 2, WIDTH // 2, :3].astype(int)
                        flats.append(dict(ev_from_018=ev, input_neutral=level,
                                          off_codes=off.tolist(), on_minus_off_codes=(on - off).tolist()))
                    cases.append(dict(sample_pitch_um=pitch, edges=edges, flats=flats))
            if report is not None:
                # Read encoding and colour space from the session, not from historical defaults.
                colour = {k: resolved[k] for k in ("input_color_space", "input_cctf_decoding",
                                                   "output_color_space", "output_cctf_encoding")}
                report["profiles"].append(dict(stock=profile.stem, colour=colour,
                                               scan_film=scan_film,
                                               print_stock=None if scan_film else resolved["print_stock"],
                                               conditions=cases))
            print(f"{profile.stem}: worst sampled overshoot {peak:.2f}%")

    if report is not None:
        with args.report.open("x", encoding="utf-8") as f:
            json.dump(report, f, indent=2, allow_nan=False)
            f.write("\n")


if __name__ == "__main__":
    main()
