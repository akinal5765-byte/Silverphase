#!/usr/bin/env python3
"""Check RGB pixels in the synthetic-video outputs of --video-look-regression."""
from pathlib import Path
import statistics
import subprocess
import sys


def frames(path):
    return subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(path),
        "-vf", "fps=5,scale=160:90", "-an", "-pix_fmt", "rgb24", "-f", "rawvideo", "-",
    ])


def chroma(data):
    return statistics.mean(max(r, g, b) - min(r, g, b)
                           for r, g, b in zip(data[::3], data[1::3], data[2::3]))


def delta(a, b):
    if len(a) != len(b) or not a:
        raise SystemExit("Input/output samples must have equal nonzero frame counts.")
    return statistics.mean(abs(x - y) for x, y in zip(a, b))


root = Path(sys.argv[1])
source = frames(root / "video-check-legacy-small.mov")
bw = frames(root / "video-look-kodak_tri_x_400.mov")
portra = frames(root / "video-look-kodak_portra_400.mov")
vision = frames(root / "video-look-kodak_vision3_500t.mov")
source_chroma, bw_chroma = chroma(source), chroma(bw)
deltas = [delta(source, portra), delta(source, vision), delta(portra, vision)]
print(f"Mean RGB channel spread: source={source_chroma:.3f}, Tri-X={bw_chroma:.3f}")
print("Mean RGB pixel deltas: source/Portra={:.3f}, source/500T={:.3f}, Portra/500T={:.3f}".format(*deltas))
if source_chroma <= 20 or bw_chroma >= 3 or min(deltas) <= 3:
    raise SystemExit("Look regression: missing monochrome or distinct color development.")
print("PASS: distinct color stocks and monochrome output from the same colored footage")
