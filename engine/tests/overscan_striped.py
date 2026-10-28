#!/usr/bin/env python3
"""Overscan must preserve every pixel through dimension-changing strip boundaries.

Uses the existing whole-frame renderer as an oracle; no Python model required.
"""
import argparse
from pathlib import Path
import numpy as np
from overscan_checks import frame, render
import spk_ctypes as spk


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dylib', type=Path)
    args = parser.parse_args()
    engine = spk.Engine(args.dylib)
    cases = [
        (240, 360, {'overscan_active': True}),
        (360, 240, {'overscan_active': True, 'overscan_mode': 'filed', 'overscan_carrier': 'black'}),
        (240, 240, {'overscan_active': True, 'overscan_format': '120_6x6'}),
        (324, 240, {'overscan_active': True, 'overscan_format': '120_645', 'scan_film': True}),
        (360, 240, {'overscan_active': True, 'digital_intermediate': True}),
        (240, 360, {'overscan_active': True, 'date_imprint_active': True, 'date_imprint_text': "'26 10 27"}),
        (240, 360, {'overscan_active': True, 'halation_boost_ev': 3}),
        (240, 360, {'date_imprint_active': True, 'date_imprint_text': "'26 10 27"}),
        (240, 360, {}),
    ]
    checks = 0
    for w, h, settings in cases:
        image = frame(w, h)
        whole = render(engine, image, settings, tier='full')
        for rows in (17, 64, 257):
            striped = render(engine, image, dict(settings, striped=True, strip_rows=rows), tier='full')
            assert whole.shape == striped.shape, (settings, rows, whole.shape, striped.shape)
            assert np.array_equal(whole, striped), (settings, rows, np.max(np.abs(whole.astype(int) - striped.astype(int))))
            checks += 1
    engine.close()
    print(f'{checks} overscan/date/plain striped renders match whole-frame pixels exactly')


if __name__ == '__main__':
    main()
