"""Native regression gate for the upstream controls port.

The frozen Python oracle has no DI or latitude controls. Compare neutral
new defaults against the independent pre-port native engine, then test
zero-strength switches and reset invariants through the actual render ABI.
Usage: upstream_controls.py [--before /path/to/pre-port/engine/build/lib...dylib]
"""
import argparse
import ctypes
from pathlib import Path
import numpy as np
from spk_ctypes import Engine
from parity_schema import NATIVE_ONLY

BASE = dict(auto_exposure=False, grain_active=False, glare_active=False)
ramp = np.geomspace(0.004, 4, 96, dtype=np.float32)
image = np.repeat(ramp[None, :, None], 64, axis=0)
image = np.repeat(image, 3, axis=2)
image[20:44, 32:64] *= np.array([1.5, .6, 1.1], np.float32)

def render(e, delta):
    with e.open(image, BASE | delta) as s:
        return s.render('full')[0]

def check(before):
    with Engine() as e:
        fields = {f['name']: f for f in e.params_schema()['fields']}
        for name, expected in NATIVE_ONLY.items():
            actual = {k: fields[name].get(k) for k in expected}
            assert actual == expected, (name, actual, expected)
        print('native schema: every declared extension matches its pinned contract')
        if before:
            with Engine(dylib=before) as old:
                for stock in ('kodak_portra_400', 'kodak_gold_200', 'fujifilm_provia_100f'):
                    for grain in (False, True):
                        d = dict(film_stock=stock, grain_active=grain)
                        a, b = render(old, d), render(e, d)
                        assert np.array_equal(a, b), (stock, grain, float(np.max(abs(a.astype(float)-b))))
            print('default render: 3 stocks, with/without grain, bit-exact against pre-port engine')
        with e.open(image, BASE) as s:
            original = s.render('full')[0]
            for key, alternate, default in (
                ('halation_scatter_amount', 0, 1),
                ('dir_couplers_active', False, True),
                ('scene_latitude_active', True, False),
            ):
                extra = dict(scene_latitude_highlight_knee=0., scene_latitude_highlight_room=2.) if key.startswith('scene') else {}
                s.set_params(extra | {key: alternate})
                modified = s.render('full')[0]
                assert not np.array_equal(modified, original), key
                s.set_params({key: default})
                assert np.array_equal(s.render('full')[0], original), key
            s.set_params(dict(grain_active=True, grain_sublayers_active=True, grain_amount=0))
            assert np.array_equal(s.render('full')[0], original), 'grain zero != off'
            s.set_params(dict(grain_amount=1))
            grain = s.render('full')[0]
            s.set_params(dict(grain_amount=2))
            stronger = s.render('full')[0]
            rms = lambda a: np.sqrt(np.mean((a.astype(float) - original.astype(float)) ** 2))
            assert rms(stronger) > rms(grain), (rms(grain), rms(stronger))
            s.set_params(dict(grain_active=False, glare_active=True, glare_amount=0))
            assert np.array_equal(s.render('full')[0], original), 'glare zero != off'
            s.set_params(dict(glare_amount=1))
            assert not np.array_equal(s.render('full')[0], original), 'glare amount has no effect'
        print('effects: changes, zero bypasses and exact resets passed')
        # Measurement is read-only; a valid fitted scene transform changes the image.
        e._lib.spk_scene_latitude.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p)]
        with e.open(image, BASE) as s:
            before = s.get_params()
            out = ctypes.c_char_p()
            assert e._lib.spk_scene_latitude(s._handle, b'{}', ctypes.byref(out)) == 0, e._last_error()
            reply = e._take_json(out)
            assert s.get_params() == before, 'measurement mutated parameters'
            assert reply['fit']['valid'], reply['fit']
            s.set_params(reply['fit']['params_delta'])
            assert np.isfinite(s.render('full')[0]).all()
        print('latitude: read-only measurement, valid fit and finite render passed')
        di = render(e, dict(digital_intermediate=True))
        assert np.isfinite(di).all()
        assert not np.array_equal(di, render(e, {}))
        print('DI: finite Cineon frame differs from paper render')

if __name__ == '__main__':
    p = argparse.ArgumentParser();p.add_argument('--before',type=Path)
    check(p.parse_args().before)
