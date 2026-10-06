"""Re-digitize ILFORD raster and Kodak vector charts from pinned PDFs.

Generator only: needs PyMuPDF, numpy and scipy. PDFs are not redistributed.
Coordinates refer to the original embedded raster, NOT a browser screenshot.
The existing knots guide curve selection; grid lines are explicitly excluded.
Review the plotted result whenever changing an axis calibration or source PDF.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import pymupdf
from scipy.ndimage import median_filter

from make_blackwhite_profiles import SOURCE

# page index, image pixel x at exposure 0, pixels/logH, y at D=0, pixels/D
CHARTS = {
    "hp5": (4, 8, 90.5, 277, 90),
    "fp4": (4, 8, 86.25, 263, 84.5),
    "delta100": (3, 10, 96, 294, 94.5),
    "xp2": (2, 8, 54.75, 168, 54),
}
# Selection windows only, pinned to make repeated extraction idempotent.
GUIDES = {
    "hp5": [[0,.17],[.5,.18],[1,.22],[1.5,.38],[2,.68],[2.5,.98],[3,1.29],[3.5,1.62],[4,1.94],[4.15,2.1]],
    "fp4": [[0,.07],[.5,.08],[1,.12],[1.5,.31],[2,.6],[2.5,.98],[3,1.4],[3.5,1.73],[4,1.86],[4.1,1.86]],
    "delta100": [[0,.08],[.5,.08],[1,.08],[1.5,.12],[2,.35],[2.5,.63],[3,1],[3.5,1.4],[4,1.8]],
    "xp2": [[.2,.25],[.5,.25],[1,.28],[1.5,.5],[2,.9],[2.5,1.25],[3,1.5],[3.5,1.69],[4,1.82],[4.4,1.9]],
}


def digitize(pdf_dir, samples):
    result = json.loads(json.dumps(samples))
    for key, (page, x0, sx, y0, sy) in CHARTS.items():
        row = result[key]
        path = pdf_dir / (key + ".pdf")
        assert hashlib.sha256(path.read_bytes()).hexdigest() == row["pdf_sha256"], key
        with pymupdf.open(path) as doc:
            xref = doc[page].get_images(full=True)[0][0]
            pix = pymupdf.Pixmap(doc, xref)
            pixels = np.frombuffer(pix.samples, np.uint8).reshape(pix.height, pix.width, pix.n)
        ink = pixels[..., :3].mean(axis=2) < 100
        guide = np.array(GUIDES[key])
        points = []
        for px in range(int(np.ceil(x0 + guide[0, 0]*sx)), int(x0 + guide[-1, 0]*sx) + 1):
            exposure = (px-x0)/sx
            # Skip vertical half-stop grid lines and their antialiasing.
            if abs(exposure*2-round(exposure*2))*sx/2 < 5:
                continue
            expected = float(np.interp(exposure, *guide.T))
            yy = np.flatnonzero(ink[:, px])
            density = (y0-yy)/sy
            keep = (abs(density-expected) < .14) & (density > 0)
            # Half-density horizontal grid lines, including the thicker Delta grid.
            keep &= abs(density*2-np.round(density*2))*sy/2 >= 3
            yy = yy[keep]
            if len(yy):
                points.append((exposure, (y0-float(np.median(yy)))/sy))
        trace = np.array(points)
        assert len(trace) > 80 and np.max(np.diff(trace[:, 0])) < .3, key
        # A few pixels of plateaux/line antialiasing should not reverse density.
        trace[:, 1] = np.maximum.accumulate(median_filter(trace[:, 1], size=7, mode="nearest"))
        xx = np.linspace(guide[0, 0], guide[-1, 0], 85)
        row["characteristic"] = np.round(np.column_stack((xx, np.interp(xx, *trace.T))), 6).tolist()
        row["digitization"] = {
            "method": "embedded-raster trace; grid excluded; monotonic 85-point resampling",
            "page": page + 1, "axis_pixels": [x0, sx, y0, sy],
            "trace_points": len(trace), "density_reading_uncertainty": .04,
        }
    row = result["trix"]
    path = pdf_dir / "trix.pdf"
    assert hashlib.sha256(path.read_bytes()).hexdigest() == row["pdf_sha256"]
    with pymupdf.open(path) as doc:
        drawings = doc[7].get_drawings()
        # F-4017: 400TX 35mm, 7-minute T-MAX curve (short dashed line).
        curve = drawings[101]
        assert len(curve["items"]) == 136 and curve["dashes"] != "[] 0"
        pts = np.array([[p.x, p.y] for item in curve["items"] for p in item[1:]])
        pts = pts[np.argsort(pts[:, 0])]
        xx = np.linspace(pts[0, 0], pts[-1, 0], 85)
        row["characteristic"] = np.round(np.column_stack(
            ((xx-354.416)/36.8874-4, (247.978-np.interp(xx, *pts.T))/46.124)), 6).tolist()
        # Solid D=1 above gross fog spectral sensitivity, not the D=0.3 line.
        spectral = drawings[73]
        assert len(spectral["items"]) == 43 and spectral["dashes"] == "[] 0"
        pts = []
        for item in spectral["items"]:
            if item[0] == "l":
                pts.extend([[p.x, p.y] for p in item[1:]])
            elif item[0] == "c":
                p = np.array([[v.x, v.y] for v in item[1:]])
                for t in np.linspace(0, 1, 21):
                    pts.append((1-t)**3*p[0]+3*(1-t)**2*t*p[1]+3*(1-t)*t*t*p[2]+t**3*p[3])
            else:
                raise ValueError("unexpected spectral path item")
        pts = np.array(pts)
        pts = pts[np.argsort(pts[:, 0])]
        xx = np.linspace(pts[0, 0], pts[-1, 0], 85)
        row["sensitivity"] = np.round(np.column_stack(
            ((xx-95.031)/.40172+300, (442.973-np.interp(xx, *pts.T))/37.4)), 6).tolist()
    row["digitization"] = {"method": "PDF vector paths; 7-minute characteristic and D=1 spectral curves",
                           "page": 8, "drawing_indices": [101, 73], "density_reading_uncertainty": .02}
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf_dir", type=Path)
    parser.add_argument("--write", action="store_true", help="replace the source samples after review")
    args = parser.parse_args()
    old = json.loads(SOURCE.read_text())
    updated = digitize(args.pdf_dir, old)
    for key in list(CHARTS) + ["trix"]:
        a, b = np.array(old[key]["characteristic"]), np.array(updated[key]["characteristic"])
        print(key, "max density correction", np.max(abs(b[:, 1]-np.interp(b[:, 0], *a.T))))
    if args.write:
        SOURCE.write_text(json.dumps(updated, indent=2) + "\n")
