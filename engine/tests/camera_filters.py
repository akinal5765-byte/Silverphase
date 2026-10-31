"""Native lens filters: grey compensation, colour response and cache boundaries."""
import hashlib
import json
from pathlib import Path
import numpy as np
from spk_ctypes import Engine
from product_blackwhite import COMMON, UPSTREAM, PAPER

NAMES = ['w8','w11','w12','w15','w21','w25','w47','w58']
P = 48
patches = np.array([[.184]*3,[.45,.025,.025],[.025,.45,.025],[.025,.025,.45]],np.float32)
chart = np.repeat(np.repeat(patches[None],P,axis=0),P,axis=1)
def values(pixels):
    return np.array([pixels[8:-8,i*P+8:(i+1)*P-8,1].mean()/65535 for i in range(4)])
def run():
    root = Path(__file__).resolve().parents[2]
    manifest = json.loads((root/'engine/resources_product/UPSTREAM.json').read_text())
    relative = 'engine/src/core/camera_filters.hpp'
    assert hashlib.sha256((root/relative).read_bytes()).hexdigest() == manifest['code_sources'][relative]['sha256']
    with Engine() as engine:
        field = next(f for f in engine.params_schema()['fields'] if f['name'] == 'camera_filter')
        assert {key: field.get(key) for key in ['path','type','layer','default','live','range']} == {
            'path':'camera.filter','type':'str','layer':'shoot','default':'','live':False,'range':None}
        for stock in UPSTREAM:
            with engine.open(chart, COMMON | {'film_stock':stock,'print_stock':PAPER,
                      'c_filter_neutral':0,'m_filter_neutral':0,'y_filter_neutral':68}) as session:
                base = session.render('full')[0]; grey = values(base)[0]
                responses = {}
                for name in NAMES:
                    session.set_params({'camera_filter':name})
                    pixels, result = session.render('full',reprint=True)
                    assert not result.negative_was_cached, (stock,name,'stale negative')
                    assert np.ptp(pixels[...,:3].astype(float),axis=2).max() < 140
                    responses[name] = values(pixels)
                    assert abs(responses[name][0]-grey) < .02, (stock,name,'grey compensation',responses[name][0],grey)
                    session.set_params({'print_exposure':.8})
                    assert session.render('full',reprint=True)[1].negative_was_cached
                    session.set_params({'print_exposure':1})
                assert responses['w25'][1] > responses['w47'][1], (stock,'red subject')
                assert responses['w25'][3] < responses['w47'][3], (stock,'blue subject')
                session.set_params({'camera_filter':''})
                np.testing.assert_array_equal(base,session.render('full',reprint=True)[0])
                try:
                    session.set_params({'camera_filter':'w99'})
                    raise AssertionError('unknown filter accepted')
                except Exception as ex:
                    assert 'camera_filter' in str(ex)
                print(stock,'eight filters, compensated grey, cache and reset PASS',flush=True)
        # Colour film must receive the same physical filter, retaining a cast.
        with engine.open(chart, COMMON | {'scan_film': True}) as session:
            base = session.render('full')[0]
            session.set_params({'camera_filter':'w25'})
            red = session.render('full',reprint=True)[0]
            assert not np.array_equal(base,red), 'colour filter has no effect'
            session.set_params({'camera_filter':''})
            np.testing.assert_array_equal(base,session.render('full',reprint=True)[0])
        print('Colour negative filter and reset PASS',flush=True)
    print('Camera filters PASS',flush=True)
if __name__ == '__main__': run()
