"""Reproducible, experimental PRO160NS profile; never edits measured stocks.

Requires numpy/scipy. --pdf additionally requires PyMuPDF and extracts the
vector plots from Fujifilm publication 163AR109A, page 8. The PDF is not bundled.
Runtime has no Python dependency. See profile_sources/pro160ns.md for limits.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import struct
import sys
from pathlib import Path

import numpy as np
from scipy.optimize import least_squares, nnls
from scipy.special import ndtr

ENGINE = Path(__file__).resolve().parents[1]
SOURCE = ENGINE / "tools/profile_sources/pro160ns_samples.json"
STOCK = "fujifilm_pro_160ns_experimental"
URL = "https://asset.fujifilm.com/www/jp/files/2024-04/6b75b1c1cb4253623fb2cd7a56ff7443/datasheet_pro160ns_01.pdf"


def baked_d55():
    """Use exactly the daylight spectrum the native engine integrates."""
    with (ENGINE / "resources/spektrafilm_constants.bin").open("rb") as fh:
        magic, version, count, _ = struct.unpack("<4sIII", fh.read(16))
        assert magic == b"SPKR" and version == 1
        entries = [struct.unpack("<64sIIIIIIQQ", fh.read(104)) for _ in range(count)]
        row = next(r for r in entries if r[0].rstrip(b"\0") == b"colour/sd_illuminant/D55")
        assert row[1:4] == (0, 1, 81)
        fh.seek(row[-2])
        return np.frombuffer(fh.read(row[-1]), dtype="<f8").copy()


def sample_path(items):
    """Sample cubic Beziers, preserving disconnected subpaths/channel order."""
    paths, points, end = [], [], None
    for item in items:
        assert item[0] == "c", "unexpected PDF path; re-check this publication"
        controls = np.array([(p.x, p.y) for p in item[1:]])
        if end is not None and np.linalg.norm(controls[0] - end) > 0.02:
            paths.append(np.concatenate(points))
            points = []
        t = np.linspace(0, 1, 80)[:, None]
        points.append((1-t)**3*controls[0] + 3*(1-t)**2*t*controls[1]
                      + 3*(1-t)*t**2*controls[2] + t**3*controls[3])
        end = controls[-1]
    if points:
        paths.append(np.concatenate(points))
    return paths


def extract(pdf):
    import pymupdf
    page = pymupdf.open(pdf)[7]
    drawings = page.get_drawings()
    assert len(drawings) == 119 and abs(page.rect.width - 595) < .01
    char = sample_path(drawings[90]["items"])
    sens = sample_path(drawings[115]["items"])
    spectra = sample_path(drawings[65]["items"])
    fourth = sample_path(drawings[116]["items"])
    assert (len(char), len(sens), len(spectra), len(fourth)) == (3, 3, 2, 1)

    def rows(path, xmap, ymap, step):
        x, y = xmap(path[:, 0]), ymap(path[:, 1])
        assert np.all(np.diff(x) >= -1e-7), "non-functional plot"
        xx = np.arange(np.ceil(x[0]/step)*step, x[-1], step)
        return np.round(np.column_stack((xx, np.interp(xx, x, y))), 7).tolist()

    exposure = lambda x: (x - 266.0880126953125) / 44.385
    density = lambda y: (295.8590087890625 - y) / 44.392
    wave_sens = lambda x: np.interp(x, [332.523, 343.938, 403.264, 461.514, 520.286, 532.836],
                                   [380.59, 400, 500, 600, 700, 721.36])
    wave_dye = lambda x: np.interp(x, [332.228, 394.55, 456.983, 519.89, 532.071],
                                  [400, 500, 600, 700, 719.36])
    result = {
        "source_url": URL, "publication": "163AR109A (04.7-FG), page 8",
        "pdf_sha256": hashlib.sha256(pdf.read_bytes()).hexdigest(),
        "characteristic_rgb": [rows(p, exposure, density, .025) for p in char[::-1]],
        "relative_log_sensitivity_rgb": [rows(p, wave_sens, lambda y: (235.288-y)/58.88, 2)
                                         for p in sens[::-1]],
        "fourth_layer_relative_log_sensitivity": rows(fourth[0], wave_sens, lambda y: (235.288-y)/58.88, 2),
        "midscale_spectral_density": rows(spectra[0], wave_dye, lambda y: (548.892-y)/65.815, 2),
        "minimum_spectral_density": rows(spectra[1], wave_dye, lambda y: (548.892-y)/65.815, 2),
    }
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    SOURCE.write_text(json.dumps(result, indent=2) + "\n")
    return result


def build_revision1(source, *, stock=STOCK, name="Fujifilm PRO160NS", donor="fujifilm_pro_400h"):
    """Archived revision-1 reconstruction, retained for numerical comparisons.

    Not used for shipped profiles: its narrow-band inverse and unconstrained
    relative sensitivity scale failed the colour plausibility gate.
    """
    prior_path = ENGINE / f"resources/profiles/{donor}.json"
    prior = json.loads(prior_path.read_text())
    wl = np.array(prior["data"]["wavelengths"])
    minimum = np.array(source["minimum_spectral_density"])
    mid = np.array(source["midscale_spectral_density"])
    valid = (wl >= max(minimum[0, 0], mid[0, 0])) & (wl <= min(minimum[-1, 0], mid[-1, 0]))
    base = np.interp(wl, *minimum.T)
    midscale = np.interp(wl, *mid.T)
    dyes = np.array(prior["data"]["channel_density"], dtype=float)
    dyes = np.nan_to_num(dyes)
    dyes /= dyes.max(axis=0)
    coeff, _ = nnls(dyes[valid], (midscale-base)[valid])
    prediction = dyes @ coeff
    # Common wavelength correction retains the donor's channel separation,
    # but exactly matches the published neutral spectrum within measured bounds.
    dyes *= ((midscale-base) / np.maximum(prediction, 1e-8))[:, None]
    dyes /= dyes[valid].max(axis=0)

    # Narrow-band proxy, NOT a full Status-M densitometer inverse. At these
    # wavelengths the donor dye basis is near diagonal; account for its leakage.
    bands = np.array([650., 550., 450.])
    mixing = np.column_stack([np.interp(bands, wl, dyes[:, c]) for c in range(3)])
    char = [np.array(c) for c in source["characteristic_rgb"]]
    x = np.linspace(max(c[0, 0] for c in char), min(c[-1, 0] for c in char), 200)
    measured = np.column_stack([np.interp(x, *c.T) for c in char])
    dmin = np.array([c[:, 1].min() for c in char])
    effective = np.array([nnls(mixing, y)[0] for y in measured-dmin])
    effective = np.maximum.accumulate(effective, axis=0)

    # Absolute ISO exposure placement is not recovered. Match the existing
    # runtime convention: relative log exposure 0 at green dye density 0.7.
    origin = float(np.interp(.7, effective[:, 1], x))
    xx = x - origin
    axis = np.array(prior["data"]["log_exposure"])
    centers, amplitudes, sigmas, layers, errors = [], [], [], [], []
    for c in range(3):
        # The sheet does not measure saturation: a bounded shoulder prior is
        # explicit, not invented extra measurement points.
        maximum = max(float(effective[-1, c]) + .55,
                      sum(prior["data"]["density_curves_model"]["amplitudes"][c]))
        init = np.r_[[-1.0, .5, 1.8], [maximum/3]*3, [.55]*3]
        def evaluate(t, exposure):
            return ndtr((exposure[:, None]-t[:3])/t[6:]) * t[3:6]
        def residual(t):
            data_error = evaluate(t, xx).sum(axis=1)-effective[:, c]
            return np.r_[data_error, (t[3:6].sum()-maximum)*.3,
                         np.minimum(np.diff(t[:3]), 0)*2]
        fit = least_squares(residual, init,
                            bounds=(np.r_[[-3]*3, [.02]*3, [.15]*3],
                                    np.r_[[4]*3, [3]*3, [1.5]*3]), max_nfev=3000)
        order = np.argsort(fit.x[:3])
        centers.append(fit.x[:3][order].tolist())
        amplitudes.append(fit.x[3:6][order].tolist())
        sigmas.append(fit.x[6:][order].tolist())
        layers.append(evaluate(fit.x, axis)[:, order])
        errors.append(float(np.sqrt(np.mean((evaluate(fit.x, xx).sum(axis=1)-effective[:, c])**2))))
    layer_curves = np.stack(layers, axis=-1)
    sensitivity = []
    for rows in source["relative_log_sensitivity_rgb"]:
        rows = np.array(rows)
        values = np.interp(wl, *rows.T)
        # No measured tails: extend downward in log sensitivity, never hold
        # the endpoint constant into UV/IR.
        values -= np.maximum(rows[0, 0]-wl, 0)/12
        values -= np.maximum(wl-rows[-1, 0], 0)/12
        sensitivity.append(values)
    sensitivity = np.array(sensitivity).T
    # Neutral daylight normalization is not a stock-specific Hanatos colour
    # calibration. Do not carry over the donor's fitted surface or window.
    light = baked_d55()
    sums = (10**sensitivity * light[:, None]).sum(axis=0)
    sensitivity += np.log10(sums[1]/sums)
    profile = copy.deepcopy(prior)
    profile["metadata"].update({
        "created": "2026-10-04", "version": "silverphase-pro160ns-experimental-1" if stock == STOCK else f"silverphase-{stock}-1",
        "modified_by": "Silverphase / akinal5765-byte",
        "datasource": source["source_url"] + " ; " + source["publication"],
        "derivation": "Derived from Andrea Volpato's spektrafilm PRO400H dye basis (CC BY-SA 4.0). "
                      "PRO160NS vector characteristic, sensitivity, minimum and neutral spectra replace donor data. "
                      "No donor Hanatos adaptation retained. Fourth-layer effects, grain, couplers and shoulder remain approximate.",
        "experimental": True, "source_pdf_sha256": source["pdf_sha256"],
        "donor_sha256": hashlib.sha256(prior_path.read_bytes()).hexdigest(),
        "fit_rms_effective_density_rgb": errors,
        "exposure_origin_log10_lux_seconds": origin,
        "density_inverse": "650/550/450 nm narrow-band proxy; NOT full Status-M inverse",
    })
    if stock != STOCK:
        profile["metadata"]["derivation"] = (
            f"Derived from Andrea Volpato's spektrafilm {donor} dye basis (CC BY-SA 4.0). "
            f"{name} manufacturer characteristic, sensitivity, minimum and neutral spectra replace donor data. "
            "No donor Hanatos adaptation retained. Dye separation, unmeasured shoulder, grain, couplers "
            "and any fourth-layer effects remain approximate; nominal speed is display metadata only.")
    profile["info"].update(stock=stock, name=f"{name} (Experimental)")
    if "sensitivity_density_over_min" in source:
        profile["info"]["log_sensitivity_density_over_min"] = source["sensitivity_density_over_min"]
    def masked(a):
        a = a.tolist()
        for i in np.flatnonzero(~valid):
            a[i] = [None]*3 if isinstance(a[i], list) else None
        return a
    profile["data"] = {
        "wavelengths": wl.tolist(), "log_sensitivity": sensitivity.tolist(),
        "channel_density": masked(dyes), "base_density": masked(base),
        "midscale_neutral_density": masked(midscale), "log_exposure": axis.tolist(),
        "density_curves": layer_curves.sum(axis=1).tolist(),
        "density_curves_layers": layer_curves.tolist(),
        "density_curves_model": {"model_type": "cdfs", "centers": centers,
                                 "amplitudes": amplitudes, "sigmas": sigmas},
    }
    assert max(errors) < .04, errors
    return profile


def build(source, *, stock=STOCK, name="Fujifilm PRO160NS", donor="fujifilm_pro_400h"):
    """Revision 2: constrained creative approximation on a stable film basis.

    Manufacturer plots do not uniquely identify individual dye spectra.
    Retain the base's coupled dye/sensitivity calibration, then use only
    bounded spectral and contrast changes. No invented Status-M inverse.
    """
    path = ENGINE / f"resources/profiles/{donor}.json"
    profile = json.loads(path.read_text())
    data = profile["data"]
    wl = np.array(data["wavelengths"])
    axis = np.array(data["log_exposure"])
    source_curve = np.array(source["characteristic_rgb"][1])
    net = source_curve[:, 1] - source_curve[:, 1].min()
    chosen = (net >= .35) & (net <= 1.2)
    assert chosen.sum() >= 5, "insufficient midtone curve samples"
    source_slope = float(np.polyfit(source_curve[chosen, 0], net[chosen], 1)[0])
    base_curve = np.array(data["density_curves"])[:, 1]
    base_net = base_curve - base_curve.min()
    chosen = (base_net >= .35) & (base_net <= 1.2)
    base_slope = float(np.polyfit(axis[chosen], base_net[chosen], 1)[0])
    # Only a quarter of the plotted slope difference is carried over, and
    # total contrast change is bounded to +/-10%. Measurement densities are
    # not the base's separated dye densities, so equality is not justified.
    gamma = 1.0 + float(np.clip(.25 * (source_slope / base_slope - 1), -.1, .1))
    model = data["density_curves_model"]
    centers = np.array(model["centers"]) / gamma
    sigmas = np.array(model["sigmas"]) / gamma
    amplitudes = np.array(model["amplitudes"])
    layers = np.stack([ndtr((axis[:,None]-centers[c])/sigmas[c])*amplitudes[c]
                       for c in range(3)], axis=-1)
    data["density_curves"] = layers.sum(axis=1).tolist()
    data["density_curves_layers"] = layers.tolist()
    model.update(centers=centers.tolist(), sigmas=sigmas.tolist())

    light = baked_d55()
    base_logs = np.array(data["log_sensitivity"], dtype=float)
    base_sensitivity = np.nan_to_num(10**base_logs)
    reference = (base_sensitivity * light[:, None]).sum(axis=0)
    published = []
    for rows in source["relative_log_sensitivity_rgb"]:
        rows = np.array(rows)
        values = np.interp(wl, *rows.T)
        values -= np.maximum(rows[0, 0]-wl, 0)/12
        values -= np.maximum(wl-rows[-1, 0], 0)/12
        published.append(10**values)
    published = np.array(published).T
    published[~np.isfinite(base_logs)] = 0
    published *= reference / (published * light[:,None]).sum(axis=0)
    # Linear sensitivity mixture, NOT a blend of rendered images. Base
    # calibration remains dominant. Relative chart zero cannot alter speed.
    weight = .20
    sensitivity = (1-weight)*base_sensitivity + weight*published
    logs = np.log10(np.maximum(sensitivity, 1e-30)).tolist()
    for i, c in np.argwhere(~np.isfinite(base_logs)):
        logs[i][c] = None
    data["log_sensitivity"] = logs
    # Keep the base's dye spectra, mask, reference density and adaptation.
    # Published neutral absorption cannot uniquely separate three dyes.
    profile["info"].update(stock=stock, name=f"{name} (Experimental)")
    profile["metadata"].update(
        created="2026-10-04", version="silverphase-colour-approximation-2",
        modified_by="Silverphase / akinal5765-byte", experimental=True,
        datasource=source["source_url"] + " ; " + source["publication"],
        source_pdf_sha256=source["pdf_sha256"], donor_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        derivation=f"CC BY-SA 4.0 derivative of Andrea Volpato's {donor}. "
                   "Stable dye spectra, base absorption, shoulders and base Hanatos calibration retained. "
                   "Manufacturer relative sensitivity contributes 20% after daylight normalization; "
                   "midtone slope adjusts contrast by at most 10%. A creative colour approximation, "
                   "NOT a measured or independently validated reproduction of the named stock.",
        approximation_revision=2, base_stock=donor,
        density_inverse="Not performed: no Status-M or narrow-band inverse in revision 2",
        sensitivity_source_weight=weight, contrast_scale=gamma,
        published_green_slope=source_slope, base_green_slope=base_slope,
        exposure_convention="Base film's D55 integrated sensitivity retained per channel; ISO/EI is display metadata",
        source_spectra_usage="Minimum and neutral absorption are archived source observations, not used to reconstruct dyes",
        hanatos_calibration="Inherited base-film calibration, not independently fitted for the named stock")
    return profile


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--pdf", type=Path)
    ap.add_argument("--out", type=Path, default=ENGINE / f"resources/profiles/{STOCK}.json")
    ap.add_argument("--calibrate", action="store_true", help="fit TH-KG3 neutral print packs through native engine")
    args = ap.parse_args()
    source = extract(args.pdf) if args.pdf else json.loads(SOURCE.read_text())
    result = build(source)
    args.out.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")
    print(result["info"]["name"], "bounded contrast", result["metadata"]["contrast_scale"])
    if args.calibrate:
        assert args.out.resolve() == (ENGINE / f"resources/profiles/{STOCK}.json").resolve()
        calibrate()


def calibrate(stock=STOCK, donor="fujifilm_pro_400h"):
    """White balance at one reference grey, not empirical stock colour QA."""
    sys.path.insert(0, str(ENGINE / "tests"))
    from spk_ctypes import Engine
    path = ENGINE / "resources/neutral_print_filters.json"
    table = json.loads(path.read_text())
    image = np.full((32, 32, 3), .184, dtype=np.float32)
    with Engine() as engine:
        for paper, illuminants in table.items():
            if donor not in illuminants.get("TH-KG3", {}):
                continue  # the synthetic B&W print is not a colour-paper target
            initial = illuminants["TH-KG3"][donor]
            with engine.open(image, {"film_stock": stock, "print_stock": paper,
                                    "auto_exposure": False, "grain_active": False,
                                    "glare_active": False, "halation_active": False,
                                    "scanner_sharpening_amount": 0}) as session:
                def residual(pack):
                    session.set_params({"c_filter_neutral": initial[0],
                                        "m_filter_neutral": float(pack[0]),
                                        "y_filter_neutral": float(pack[1])})
                    rgba, _ = session.render("full", reprint=True)
                    rgb = rgba[..., :3].astype(float).mean(axis=(0, 1))
                    assert np.all((rgb > 1000) & (rgb < 64000)), (paper, rgb)
                    return np.log(np.maximum(rgb[[0, 2]], 1e-5)/max(rgb[1], 1e-5))
                # Native readback is uint16: a large difference step avoids
                # differentiating quantization plateaus instead of the print.
                fit = least_squares(residual, initial[1:], bounds=(0, 180),
                                    diff_step=.015, xtol=1e-5, ftol=1e-6, gtol=1e-6,
                                    max_nfev=100)
                error = float(np.max(np.abs(residual(fit.x))))
                assert error < .015, (paper, fit.x, error)
                illuminants["TH-KG3"][stock] = [initial[0], *fit.x.tolist()]
                print(paper, "neutral log RGB ratio error", error)
    path.write_text(json.dumps(table, indent=4) + "\n")


if __name__ == "__main__":
    main()
