"""Experimental negative profiles from version-pinned manufacturer vector plots.

numpy/scipy required; --pdf also needs PyMuPDF. PDFs are not bundled.
See profile_sources/experimental_negatives.md for sources and limitations.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from make_pro160ns import ENGINE, build, calibrate

STOCKS = {
    "proimage100": ("kodak_pro_image_100_experimental", "Kodak Pro Image 100", "kodak_gold_200",
                    "https://vklaboratori.com/wp-content/uploads/2018/07/kodak-pro-image-100.pdf", "Kodak E-4L (July 1997), page 3"),
    "reala100": ("fujifilm_superia_reala_100_experimental", "Fujifilm SUPERIA REALA 100", "fujifilm_pro_400h",
                 "https://filmcolors.org/wp-content/uploads/2025/12/Fujicolor-Superia-Reala_AF3-967E.pdf", "Fujifilm AF3-967E (EIGI-00.12-HB), page 4"),
    "natura1600": ("fujifilm_natura_1600_experimental", "Fujifilm NATURA 1600", "fujifilm_pro_400h",
                   "https://asset.fujifilm.com/www/jp/files/2024-04/96b634a89ec6a5abda6b70437f4d75a4/datasheet_natura1600_01.pdf", "Fujifilm 013AR313B (06.4-FP), page 4"),
    "portrait160": ("agfa_portrait_xps_160_experimental", "Agfa Portrait XPS 160", "kodak_portra_160",
                    "https://cacreeks.com/photos/agfaPro.pdf", "Agfa Technical Data PF (09/1998, first edition), page 8"),
    "optima200": ("agfa_optima_ii_200_experimental", "Agfa Optima II 200", "kodak_gold_200",
                  "https://cacreeks.com/photos/agfaPro.pdf", "Agfa Technical Data PF (09/1998, first edition), page 7"),
    "elite200": ("kodak_elite_color_200_experimental", "Kodak Elite Color 200", "kodak_gold_200",
                 "https://125px.com/docs/film/kodak/e4039-Elite.pdf", "Kodak E-4039 (July 2006), page 7"),
    "pro160c": ("fujifilm_pro_160c_experimental", "Fujifilm PRO 160C", "fujifilm_pro_400h",
                "https://asset.fujifilm.com/www/ca/files/2020-03/d52487c5c6f84e7f935c299491c5c1ff/ProfessionalFilmDataGuide.pdf",
                "Fujifilm Professional Film Data Guide (2005), printed page 59 / PDF page 29"),
}

PDF_HASHES = {
    "proimage100": "f2d1a1faa32bbbc96ab4f69ffa5ee7d99f8bc554392dcec42f715fb934d92700",
    "reala100": "ec54079823e729707202749f9d0dfc8b8c52dbf21b74734098ccd7d05ff7ac27",
    "natura1600": "43ce5589c48fb37064294d975317e259d3483fe8b3ee1423978d82eaaa38f53b",
    "portrait160": "982d920110a598a910e7f31f7fa2d7446f4238d84408ae83bfa32e92d1188d79",
    "optima200": "982d920110a598a910e7f31f7fa2d7446f4238d84408ae83bfa32e92d1188d79",
    "elite200": "424d4a25c1c6fe2e3538730e2e49385efd2bad60c98f87366652ec90200b0e8e",
    "pro160c": "64c6455651b9f13f5cd190219e4928d1fdf13ecf33859c4691d830bced8d3d36",
}


def paths(items):
    result, points, end = [], [], None
    for item in items:
        assert item[0] in ("c", "l"), "publication changed: inspect plot again"
        controls = np.array([tuple(p) for p in item[1:]])
        if end is not None and np.linalg.norm(controls[0] - end) > .02:
            result.append(np.concatenate(points))
            points = []
        if item[0] == "l":
            points.append(controls)
        else:
            t = np.linspace(0, 1, 80)[:, None]
            points.append((1-t)**3*controls[0] + 3*(1-t)**2*t*controls[1]
                          + 3*(1-t)*t**2*controls[2] + t**3*controls[3])
        end = controls[-1]
    if points:
        result.append(np.concatenate(points))
    return result


def rows(path, xmap, ymap, step):
    x, y = xmap(path[:, 0]), ymap(path[:, 1])
    # REALA's adjacent vector segments overlap by <0.1 nm at a join.
    # Resolve that drafting overlap, but reject genuinely folded curves.
    assert np.all(np.diff(x) >= -.1), "non-functional plot"
    order = np.argsort(x, kind="stable")
    x, y = x[order], y[order]
    xx = np.arange(np.ceil(x[0]/step)*step, x[-1], step)
    return np.round(np.column_stack((xx, np.interp(xx, x, y))), 7).tolist()


def linear(ticks, values):
    """Piecewise ticks with linear extrapolation only to plotted endpoints."""
    ticks, values = np.array(ticks), np.array(values)
    def convert(x):
        y = np.interp(x, ticks, values)
        y = np.where(x < ticks[0], values[0]+(x-ticks[0])*(values[1]-values[0])/(ticks[1]-ticks[0]), y)
        return np.where(x > ticks[-1], values[-1]+(x-ticks[-1])*(values[-1]-values[-2])/(ticks[-1]-ticks[-2]), y)
    return convert


def extract(key, pdf):
    import pymupdf
    digest = hashlib.sha256(pdf.read_bytes()).hexdigest()
    assert digest == PDF_HASHES[key], "different PDF: inspect and explicitly update extraction"
    doc = pymupdf.open(pdf)
    if key in ("portrait160", "optima200", "elite200", "pro160c"):
        return extract_added(key, doc, digest)
    page = doc[2 if key == "proimage100" else 3]
    d = page.get_drawings()
    stock, name, donor, url, publication = STOCKS[key]
    fourth = None
    if key == "proimage100":
        assert len(d) == 32
        b, r = paths(d[12]["items"])
        g, = paths(d[13]["items"])
        r_s, b_s = paths(d[19]["items"])
        g_s, = paths(d[20]["items"])
        char, sens = [r, g, b], [r_s, g_s, b_s]
        mid, = paths(d[25]["items"])
        minimum, = paths(d[26]["items"])
        exposure = lambda x: (x-241.110382)/46.083284
        density = lambda y: (259.83905-y)/46.123
        swave = lambda x: 250+(x-362.759521)/.40062158
        slog = lambda y: (227.190796-y)/37.86493
        dwave = lambda x: 400+(x-225.106384)/.613829
        ddensity = lambda y: (514.689453-y)/73.733
    elif key == "reala100":
        assert len(d) == 649
        b, = paths(d[17]["items"])
        r, g = paths(d[18]["items"])
        char = [r, g, b]
        sens = paths(d[459]["items"])[::-1]
        fourth, = paths(d[605]["items"])
        mid, = paths(d[360]["items"])
        minimum, = paths(d[331]["items"])
        exposure = linear([68.512,109.172,150.782,191.825,233.151,274.144], [-4,-3,-2,-1,0,1])
        density = linear([125.006,145.923,167.257,187.590,207.923,228.590,248.923,270.673], [3.5,3,2.5,2,1.5,1,.5,0])
        swave = linear([347.654,399.117,449.783,499.783], [400,500,600,700])
        # Relative zero is arbitrary; the arrow and horizontal grid span one log unit.
        slog = lambda y: (225.594-y)/(225.594-174.832)
        dwave = linear([360.011,401.855,442.885,483.207], [400,500,600,700])
        ddensity = linear([398.399,438.757,479.720,519.433,560.166], [2,1.5,1,.5,0])
    else:
        assert len(d) == 42
        b, r, g = paths(d[23]["items"])
        char = [r,g,b]
        sens = paths(d[31]["items"])[::-1]
        fourth, = paths(d[32]["items"])
        mid, minimum = paths(d[41]["items"])
        exposure = linear([89.449,133.160,176.645,220.140,263.343], [-4,-3,-2,-1,0])
        density = linear([116.213,137.372,159.455,181.291,202.846,224.752,246.595,268.019,289.222], [4,3.5,3,2.5,2,1.5,1,.5,0])
        swave = linear([347.446,404.972,461.948,518.899], [400,500,600,700])
        slog = lambda y: (230.504-y)/57.196
        dwave = linear([339.468,399.815,460.207,521.803], [400,500,600,700])
        ddensity = linear([406.763,435.912,466.221,495.605,525.312], [2,1.5,1,.5,0])
    assert len(char) == len(sens) == 3
    source = {"source_url": url, "publication": publication,
              "pdf_sha256": digest,
              "sensitivity_density_over_min": .2 if key == "proimage100" else 1.0,
              "characteristic_rgb": [rows(p,exposure,density,.025) for p in char],
              "relative_log_sensitivity_rgb": [rows(p,swave,slog,2) for p in sens],
              "midscale_spectral_density": rows(mid,dwave,ddensity,2),
              "minimum_spectral_density": rows(minimum,dwave,ddensity,2)}
    if fourth is not None:
        source["fourth_layer_relative_log_sensitivity"] = rows(fourth,swave,slog,2)
    return source


def extract_added(key, doc, digest):
    """Publication-specific axes/channel paths; no stock-to-stock renaming."""
    _, _, _, url, publication = STOCKS[key]
    fourth = None
    if key in ("portrait160", "optima200"):
        portrait = key == "portrait160"
        d = doc[7 if portrait else 6].get_drawings()
        assert len(d) == (172 if portrait else 166)
        def path(index):
            p, = paths(d[index]["items"])
            return p
        char = [path(i) for i in ([49,50,51] if portrait else [105,106,107])]
        sens = [path(i) for i in ([16,15,14] if portrait else [71,70,69])]
        mid = path(29 if portrait else 85)
        minimum = path(28 if portrait else 86)
        exposure = (linear([67.206,92.164,117.122,142.081,167.039], [-3,-2,-1,0,1]) if portrait else
                    linear([247.772,272.882,297.859,322.836,347.813,372.824], [-4,-3,-2,-1,0,1]))
        density = linear([476.079,500.808,525.569,550.297,576.061], [4,3,2,1,0])
        offset = 193.26 if portrait else 0
        swave = linear(np.array([262.469,294.066,325.630,357.227])-offset, [400,500,600,700])
        slog = linear([80.237,111.804,143.403,175.002], [2,1,0,-1])
        dwave = linear(np.array([262.731,294.257,325.750,357.277])-offset, [400,500,600,700])
        ddensity = linear([227.511,258.992,290.439], [2,1,0])
    elif key == "elite200":
        d = doc[6].get_drawings()
        assert len(d) == 259
        # This PDF splits continuous polylines across drawing operations.
        char = paths([it for s in d[4:64] for it in s["items"]])[::-1]
        sens = paths([it for s in d[67:179] for it in s["items"]])[::-1]
        mid, = paths(d[184]["items"])
        minimum, = paths([it for s in d[186:222] for it in s["items"]])
        exposure = linear([96.685,133.594,170.462,207.371,244.239,281.148], [-4,-3,-2,-1,0,1])
        density = linear([103.013,149.117,195.284,241.390,287.493], [4,3,2,1,0])
        swave = linear([114.617,164.604,214.590,264.578], [400,500,600,700])
        slog = linear([350.600,388.637,426.456,464.383,502.092], [3,2,1,0,-1])
        dwave = lambda x: 400+(x-377.186)*300/(561.536-377.186)
        ddensity = lambda y: (274.969-y)*3/(274.969-90.621)
    else:
        d = doc[28].get_drawings()
        assert len(d) == 73
        char = paths(d[56]["items"])[::-1]
        sens = paths(d[42]["items"])[::-1]
        fourth, = paths(d[43]["items"])
        mid, minimum = paths(d[50]["items"])
        exposure = linear([343.942,372.395,400.387,428.380,456.552,484.903], [-4,-3,-2,-1,0,1])
        density = linear([251.536,280.081,308.171,336.262,364.276], [4,3,2,1,0])
        swave = linear([344.206,371.962,399.224,426.716], [400,500,600,700])
        slog = lambda y: (144.417-y)/(144.417-116.742)
        dwave = linear([475.072,503.247,531.274,559.505], [400,500,600,700])
        ddensity = linear([89.101,115.913,143.425,170.754], [3,2,1,0])
    assert len(char) == len(sens) == 3
    result = {"source_url": url, "publication": publication, "pdf_sha256": digest,
              "sensitivity_density_over_min": .2 if key == "elite200" else 1.0,
              "characteristic_rgb": [rows(p,exposure,density,.025) for p in char],
              "relative_log_sensitivity_rgb": [rows(p,swave,slog,2) for p in sens],
              "midscale_spectral_density": rows(mid,dwave,ddensity,2),
              "minimum_spectral_density": rows(minimum,dwave,ddensity,2)}
    if fourth is not None:
        result["fourth_layer_relative_log_sensitivity"] = rows(fourth,swave,slog,2)
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("stock", choices=STOCKS)
    ap.add_argument("--pdf", type=Path)
    ap.add_argument("--calibrate", action="store_true")
    args = ap.parse_args()
    stock, name, donor, _, _ = STOCKS[args.stock]
    source_path = ENGINE / f"tools/profile_sources/{args.stock}_samples.json"
    source = extract(args.stock,args.pdf) if args.pdf else json.loads(source_path.read_text())
    if args.pdf:
        source_path.write_text(json.dumps(source,indent=2)+"\n")
    result = build(source,stock=stock,name=name,donor=donor)
    (ENGINE / f"resources/profiles/{stock}.json").write_text(json.dumps(result,indent=2,allow_nan=False)+"\n")
    print(name, "bounded contrast", result["metadata"]["contrast_scale"])
    if args.calibrate:
        calibrate(stock,donor)


if __name__ == "__main__":
    main()
