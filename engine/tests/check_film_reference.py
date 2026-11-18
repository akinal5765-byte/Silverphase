#!/usr/bin/env python3
"""Check the Metal 5219 reference without a retired Python renderer."""
import argparse
import hashlib
import math
from pathlib import Path
import re
import subprocess
import sys


CHART_SHA256 = "f3326175369912b86e49918e13ddd3928f0937e84b16b49b6f2a1a272772b077"
TESTS = Path(__file__).resolve().parent


def checkpoints(report):
    result = {}
    for line in report.splitlines():
        if not line or line.startswith("#"):
            continue
        name, *fields = line.split("\t")
        values = [float(field) for field in fields]
        if name in result or len(values) != 15 or not all(map(math.isfinite, values)):
            raise ValueError(f"Invalid checkpoint {name}")
        result[name] = values
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("resources", type=Path, help="Resources/engine from the app being verified")
    parser.add_argument("chart", type=Path, help="BabelColor CC_Avg30_spectrum_CGATS.txt")
    parser.add_argument("--report", type=Path, help="Save the raw diagnostic TSV")
    args = parser.parse_args()
    if hashlib.sha256(args.chart.read_bytes()).hexdigest() != CHART_SHA256:
        parser.error("BabelColor fixture has a different hash. Use the exact file linked in VALIDATION.md.")
    run = subprocess.run(
        [TESTS.parent / "build" / "film_reference", args.resources, args.chart],
        text=True, stdout=subprocess.PIPE, check=False,
    )
    if args.report:
        args.report.write_text(run.stdout)
    if run.returncode:
        return run.returncode

    reference = checkpoints((TESTS / "reference-data" / "5219-stages.tsv").read_text())
    actual = checkpoints(run.stdout)
    if reference.keys() != actual.keys():
        raise ValueError("Engine output is missing one or more reference checkpoints")

    fields = ("reconstruction EV", "film exposure", "negative density", "paper density", "final RGB")
    tolerances = (.005, .003, .002, .003, .003)
    failed = False
    for group, (label, tolerance) in enumerate(zip(fields, tolerances)):
        errors = [(abs(reference[name][i] - values[i]), name, i % 3 + 1)
                  for name, values in actual.items()
                  for i in range(3 * group, 3 * group + 3)]
        error, sample, channel = max(errors)
        failed |= error > tolerance
        print(f"{label:18} max drift {error:.6f} ({sample} ch {channel}, limit {tolerance:g})")

    tone = next(line for line in run.stdout.splitlines() if line.startswith("# Kodak R/G/B"))
    print(tone.removeprefix("# ").replace("\t", "  "))
    grain = [line.split("\t")[1:] for line in run.stdout.splitlines() if line.startswith("# blue grain\t")]
    if len(grain) != 3:
        raise ValueError("Incomplete granularity results")
    for ev, _ref_density, density, ref_rms, rms in grain:
        print(f"Blue granularity at {float(ev):.2f} EV, D={float(density):.3f}: "
              f"{float(rms):.2f} vs Kodak {float(ref_rms):.2f} RMS × 1000")
    errors = [(abs(error), name, channel + 1, error)
              for name, values in actual.items() if re.fullmatch(r"[A-F][1-4]", name)
              for channel, error in enumerate(values[:3])]
    worst, name, channel, signed = max(errors)
    mean = sum(error for error, *_ in errors) / len(errors)
    print(f"ColorChecker reconstruction: mean |error| {mean:.3f} EV, "
          f"worst {worst:.3f} EV ({name} ch {channel}, signed {signed:+.3f})")
    return int(failed)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        sys.exit(str(error))
