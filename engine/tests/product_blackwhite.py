"""Upstream B&W adoption: native renders and supported legacy IDs.
No SciPy/reference dependency. Run after engine/build.sh dylib and bundle.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import numpy as np
from spk_ctypes import Engine

ROOT = Path(__file__).resolve().parents[2]
PRODUCT = ROOT / 'engine/resources_product'
UPSTREAM = ['kodak_tri_x_400', 'ilford_hp5_plus_400', 'kodak_tmax_100', 'fujifilm_neopan_acros_100_ii']
PAPER = 'ilford_multigrade_iv_rc'
COMMON = {'auto_exposure': False, 'grain_active': False, 'glare_active': False,
          'halation_active': False, 'extended_dynamic_range': False,
          'input_color_space': 'sRGB', 'input_cctf_decoding': False,
          'output_color_space': 'sRGB', 'output_cctf_encoding': True,
          'scanner_sharpening_amount': 0}


def run():
    assert not list((ROOT/'engine/resources/profiles').glob('*_experimental.json'))
    manifest = json.loads((PRODUCT / 'UPSTREAM.json').read_text())
    for relative, expected in manifest['sha256'].items():
        assert hashlib.sha256((PRODUCT / relative).read_bytes()).hexdigest() == expected, relative
    with tempfile.TemporaryDirectory() as tmp:
        res = Path(tmp)
        (res/'profiles').mkdir()
        for f in (ROOT/'engine/resources').iterdir():
            if f.name not in ('profiles', 'neutral_print_filters.json'):
                os.symlink(f, res/f.name)
        for directory in (ROOT/'engine/resources/profiles', PRODUCT/'profiles'):
            for f in directory.glob('*.json'):
                os.symlink(f, res/'profiles'/f.name)
        # The pack is a caller decision, just as in the upstream macOS app.
        img = np.repeat(np.repeat(np.array([[.184,.184,.184],[.45,.04,.03],[.08,.25,.06],[.15,.28,.55]], np.float32)[None],64,0),64,1)
        with Engine(resources=res) as e:
            print(e._lib.spk_build_info().decode(), flush=True)
            def render(stock, **delta):
                with e.open(img, COMMON | {'film_stock':stock, 'print_stock':PAPER,
                          'c_filter_neutral':0, 'm_filter_neutral':0, 'y_filter_neutral':68} | delta) as s:
                    return s.render('full')[0]
            # Removed self-authored material IDs must fail rather than selecting a donor.
            for retired in ('kodak_pro_image_100_experimental', 'ilford_xp2_super_400_experimental'):
                try:
                    render(retired)
                except RuntimeError as error:
                    assert 'no profile' in str(error), str(error)
                else:
                    raise AssertionError('retired material unexpectedly rendered: ' + retired)
            # Historical IDs for the same adopted materials retain their migration.
            for sid in UPSTREAM[:2]:
                np.testing.assert_array_equal(render(sid), render(sid+'_experimental'), err_msg=sid+' legacy alias')
            for sid in UPSTREAM:
                pixels = render(sid)
                rgb = pixels[...,:3].astype(float)
                assert np.ptp(rgb,axis=2).max() < 140, (sid,'non-neutral print')
                assert np.ptp(rgb) > 1000, (sid,'flat print')
                # Silver paper must gate EDR regardless of saved preference.
                np.testing.assert_array_equal(pixels,render(sid,extended_dynamic_range=True))
                grained = render(sid,grain_active=True)
                assert np.ptp(grained[...,:3].astype(float),axis=2).max() < 140, (sid,'colour grain')
                if sid in UPSTREAM:
                    # Native callers receive the same single-layer policy as Swift.
                    with e.open(img, COMMON | {'film_stock':sid, 'print_stock':PAPER,
                              'scan_film':True, 'grain_active':True}) as s:
                        s.render('full')
                ramp = np.broadcast_to((.184*2**np.linspace(-6,6,128,dtype=np.float32))[None,:,None], (32,128,3)).copy()
                with e.open(ramp, COMMON | {'film_stock':sid, 'print_stock':PAPER,
                            'c_filter_neutral':0, 'm_filter_neutral':0, 'y_filter_neutral':68}) as session:
                    tones, _ = session.render('full')
                    assert np.diff(tones[16,:,1].astype(float)).min() >= -1, (sid, 'reversed ramp')
                    session.set_params({'digital_intermediate':True})
                    cineon, meta = session.render_digital_intermediate()
                    assert meta['encoding'] == 'cineon'
                    assert np.ptp(cineon[...,:3].astype(float),axis=2).max() < 140, (sid,'non-neutral DI')
                print(sid, 'neutral print / grain / EDR / ramp / DI PASS', flush=True)
            # Legacy synthetic-paper selections now use the upstream paper.
            np.testing.assert_array_equal(render(UPSTREAM[0]), render(UPSTREAM[0],print_stock='silverphase_neutral_bw_print_experimental'))
    print('Upstream B&W adoption checks PASS', flush=True)

if __name__ == '__main__':
    run()
