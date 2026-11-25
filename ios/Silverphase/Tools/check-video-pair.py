#!/usr/bin/env python3
"""Check a Silverphase original/export pair with ffprobe. No files are modified."""
import argparse
import json
import math
import subprocess
from fractions import Fraction


def read(path):
    return json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", path
    ], text=True))


def one_stream(probe, kind):
    matches = [s for s in probe["streams"] if s.get("codec_type") == kind]
    if len(matches) != 1:
        raise ValueError(f"expected one {kind} track, found {len(matches)}")
    return matches[0]


def presented_size(track):
    rotation = next((entry.get("rotation", 0) for entry in track.get("side_data_list", [])
                     if "rotation" in entry), 0)
    size = track["width"], track["height"]
    return size[::-1] if abs(round(rotation / 90)) % 2 else size


def rate(track):
    value = float(Fraction(track["avg_frame_rate"]))
    if not math.isfinite(value) or value <= 0:
        raise ValueError(f"invalid average frame rate: {value}")
    return value


def seconds(track, key):
    return float(track[key])


def require_close(label, a, b, tolerance):
    if not (math.isfinite(a) and math.isfinite(b) and abs(a - b) <= tolerance):
        raise ValueError(f"{label}: {a:.3f}s vs {b:.3f}s exceeds {tolerance:.3f}s")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original")
    parser.add_argument("export")
    parser.add_argument("--min-seconds", type=float, default=0)
    parser.add_argument("--require-uhd-fps", type=int, choices=(30, 60))
    args = parser.parse_args()
    before, after = read(args.original), read(args.export)
    bv, ba = one_stream(before, "video"), one_stream(before, "audio")
    av, aa = one_stream(after, "video"), one_stream(after, "audio")
    b_duration, a_duration = seconds(before["format"], "duration"), seconds(after["format"], "duration")
    if b_duration < args.min_seconds:
        raise ValueError(f"original is only {b_duration:.3f}s; need {args.min_seconds:.3f}s")
    require_close("container duration", b_duration, a_duration, 0.15)
    if presented_size(bv) != presented_size(av):
        raise ValueError(f"display size changed: {presented_size(bv)} vs {presented_size(av)}")
    if abs(rate(bv) - rate(av)) > 0.5:
        raise ValueError(f"average frame rate changed: {rate(bv):.3f} → {rate(av):.3f}")
    if args.require_uhd_fps:
        for label, track in (("original", bv), ("export", av)):
            if sorted(presented_size(track)) != [2160, 3840] or track.get("codec_name") != "hevc":
                raise ValueError(f"{label}: expected UHD HEVC, got {presented_size(track)} {track.get('codec_name')}")
            if abs(rate(track) - args.require_uhd_fps) > 0.5:
                raise ValueError(f"{label}: got {rate(track):.3f} fps, expected {args.require_uhd_fps}")
            if track.get("color_transfer") in {"arib-std-b67", "smpte2084", "log100", "log316"}:
                raise ValueError(f"{label}: unexpected HDR/Log transfer {track['color_transfer']}")
    require_close("relative track start", seconds(ba, "start_time") - seconds(bv, "start_time"),
                  seconds(aa, "start_time") - seconds(av, "start_time"), 0.08)
    require_close("video track duration", seconds(bv, "duration"), seconds(av, "duration"), 0.15)
    require_close("audio track duration", seconds(ba, "duration"), seconds(aa, "duration"), 0.15)
    if av.get("color_primaries") != "bt709" or av.get("color_transfer") != "bt709":
        raise ValueError(f"expected BT.709 SDR tags, got {av.get('color_primaries')} / {av.get('color_transfer')}")
    print(f"PASS: {presented_size(av)}, {rate(av):.3f} fps, {a_duration:.3f}s, one video and one audio track, SDR tags intact.")
    print("Still inspect lip sync at both ends, repeated/dropped frames, grain, halation, and thermals on device.")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"FAIL: {error}")
