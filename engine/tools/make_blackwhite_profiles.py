"""Build explicitly approximate B&W stocks from hand-digitized published plots.

numpy/scipy are generator-only dependencies. No manufacturer PDF is bundled.
See profile_sources/blackwhite.md for the limits of the neutral silver/dye model.
"""
import copy
import hashlib
import json

import numpy as np
from scipy.optimize import least_squares
from scipy.special import ndtr

from make_pro160ns import ENGINE, baked_d55

SOURCE = ENGINE / "tools/profile_sources/blackwhite_samples.json"
PAPER = "silverphase_neutral_bw_print_experimental"


def build(source=None):
    samples = source or json.loads(SOURCE.read_text())
    skeleton_path = ENGINE / "resources/profiles/kodak_portra_400.json"
    skeleton = json.loads(skeleton_path.read_text())
    axis = np.array(skeleton["data"]["log_exposure"])
    wl = np.array(skeleton["data"]["wavelengths"])
    profiles = {}
    for key, row in list(samples.items()) + [("paper", None)]:
        if row:
            curve = np.array(row["characteristic"])
            dmin = curve[0, 1]
            density = np.maximum.accumulate(curve[:, 1] - dmin)
            origin = float(np.interp(.7, density, curve[:, 0]))
            x = curve[:, 0] - origin
            maximum = row["shoulder_prior"] - dmin
            def evaluate(t, xx):
                return ndtr((xx[:, None] - t[:3]) / t[6:]) * t[3:6]
            def residual(t):
                return np.r_[evaluate(t, x).sum(axis=1) - density,
                             (t[3:6].sum() - maximum) * .3,
                             np.minimum(np.diff(t[:3]), 0) * 2]
            fit = least_squares(residual, np.r_[[-1, .5, 1.8], [maximum/3]*3, [.55]*3],
                                bounds=(np.r_[[-4]*3, [.001]*3, [.1]*3],
                                        np.r_[[5]*3, [4]*3, [2]*3]), max_nfev=5000)
            order = np.argsort(fit.x[:3])
            centers, amplitudes, sigmas = [fit.x[n:n+3][order] for n in (0, 3, 6)]
            rms = float(np.sqrt(np.mean((evaluate(fit.x, x).sum(axis=1) - density)**2)))
            maximum_error = float(np.max(abs(evaluate(fit.x, x).sum(axis=1) - density)))
            assert rms < .04, (key, rms)
            assert maximum_error < .06, (key, "local curve distortion", maximum_error)
            sens = np.array(row["sensitivity"])
            if row["sensitivity_scale"] == "relative_linear":
                response = np.interp(wl, *sens.T, left=0, right=0)
                log_sens = np.log10(np.maximum(response, 1e-10))
            else:
                log_sens = np.interp(wl, *sens.T)
                log_sens -= np.maximum(sens[0, 0]-wl, 0)/12
                log_sens -= np.maximum(wl-sens[-1, 0], 0)/12
            stock, name = row["stock"], row["name"]
            chromogenic = key == "xp2"
            # Published relative sensitivity has an arbitrary vertical zero.
            # Use the existing engine's daylight/green exposure convention,
            # NOT the ISO label, to avoid arbitrary chart scales burning film.
            light = baked_d55()
            reference = np.array(skeleton["data"]["log_sensitivity"], dtype=float)[:, 1]
            gain = np.nansum(10**reference * light) / np.sum(10**log_sens * light)
            log_sens += np.log10(gain)
        else:
            stock, name = PAPER, "Silverphase Neutral B&W Print"
            dmin, origin, rms = .02, 0., 0.
            maximum_error = 0.
            centers, amplitudes, sigmas = np.array([.1, .45, .8]), np.array([.85]*3), np.array([.65]*3)
            log_sens = -.5 * ((wl-550)/80)**2 / np.log(10)
            chromogenic = False
        layers = ndtr((axis[:, None]-centers)/sigmas) * amplitudes
        profile = copy.deepcopy(skeleton)
        profile["info"].update(stock=stock, name=name + " (Experimental)",
                               type="negative", stage="filming" if row else "printing",
                               support="film" if row else "paper", use="still",
                               channel_model="chromogenic_monochrome" if chromogenic else "monochrome",
                               target_print=PAPER if row else "", densitometer="status_A",
                               grain_size_scale=row["grain_size_prior"] if row else 1.)
        profile["metadata"].update(
            created="2026-10-04", version="silverphase-blackwhite-experimental-2",
            modified_by="Silverphase / akinal5765-byte", experimental=True,
            datasource=(row["url"] + " ; " + row["publication"]) if row else "Synthetic neutral B&W print; no branded paper measurements",
            derivation="Andrea Volpato's CC BY-SA profile container; colour dye data completely replaced. "
                       "Digitized manufacturer plots, approximate relative sensitivity, neutral optical density, "
                       "synthetic CDF sublayers, shoulder and grain priors. NOT a calibrated film or paper reproduction.",
            donor_sha256=hashlib.sha256(skeleton_path.read_bytes()).hexdigest(),
            source_pdf_sha256=row["pdf_sha256"] if row else None,
            process=row["process"] if row else "Synthetic neutral print response",
            fit_rms_density=rms, exposure_origin_relative_log10=origin,
            fit_max_density_error=maximum_error,
            chart_digitization=row.get("digitization", {"method": "coarse hand-estimated knots"}) if row else None,
            sensitivity_interpretation="Published ILFORD/FOMA relative chart values treated as linear; Kodak as log10. "
                                       "Spectrogram light-source effects are not inverted; absolute ISO is not recovered. "
                                       "Film response is normalized to the existing daylight/green exposure convention.")
        profile["data"] = dict(
            wavelengths=wl.tolist(), log_exposure=axis.tolist(),
            log_sensitivity=np.repeat(log_sens[:, None], 3, axis=1).tolist(),
            channel_density=np.full((81, 3), 1/3).tolist(),
            base_density=np.full(81, dmin).tolist(), midscale_neutral_density=np.full(81, dmin+.7).tolist(),
            density_curves=np.repeat(layers.sum(axis=1)[:, None], 3, axis=1).tolist(),
            density_curves_layers=np.repeat(layers[:, :, None], 3, axis=2).tolist(),
            density_curves_model=dict(model_type="cdfs", centers=[centers.tolist()]*3,
                                      amplitudes=[amplitudes.tolist()]*3, sigmas=[sigmas.tolist()]*3))
        profiles[stock] = profile
    return profiles


if __name__ == "__main__":
    profiles = build()
    for stock, profile in profiles.items():
        (ENGINE / f"resources/profiles/{stock}.json").write_text(json.dumps(profile, indent=2, allow_nan=False) + "\n")
        print(stock, "curve-fit RMS", profile["metadata"]["fit_rms_density"])
    path = ENGINE / "resources/neutral_print_filters.json"
    table = json.loads(path.read_text())
    table[PAPER] = {"TH-KG3": {stock: [0., 0., 0.] for stock in profiles if stock != PAPER}}
    path.write_text(json.dumps(table, indent=2) + "\n")
