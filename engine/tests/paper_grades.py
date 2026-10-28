"""Physical Multigrade controls: ordered contrast, compensated grey, print cache.
Run against the native dylib; no Python reference or SciPy required.
"""
import json
from pathlib import Path
import numpy as np
from spk_ctypes import Engine
from product_blackwhite import COMMON, UPSTREAM, LOCAL, PAPER

ROOT = Path(__file__).resolve().parents[2]
GRADES = json.loads((ROOT/'engine/resources_product/paper_grades.json').read_text())['grades']
P = 48
row = np.repeat(.184 * 2**np.array([-3,-1,-.5,0,.5,1,3],dtype=np.float32),P)
ramp = np.broadcast_to(row[None,:,None],(P,len(row),3)).copy()


def density(encoded):
    linear = np.where(encoded <= .04045, encoded/12.92, ((encoded+.055)/1.055)**2.4)
    return -np.log10(np.maximum(linear,1e-6))


def run():
    with Engine() as engine:
        for stock in UPSTREAM + LOCAL:
            with engine.open(ramp,COMMON|{'film_stock':stock,'print_stock':PAPER,
                                  'c_filter_neutral':0, **GRADES['2']}) as session:
                session.render('full')
                spans, greys, midtones = [], [], []
                for grade, fields in GRADES.items():
                    session.set_params(fields)
                    pixels, result = session.render('full', reprint=True)
                    assert result.negative_was_cached, (stock,grade,'negative rebuilt')
                    rgb = pixels[...,:3].astype(float)/65535
                    assert np.ptp(rgb,axis=2).max() < .002, (stock,grade,'tinted paper')
                    patch = np.array([rgb[8:-8,i*P+8:(i+1)*P-8,1].mean() for i in range(7)])
                    d = density(patch)
                    spans.append(d[0]-d[-1]); greys.append(d[3]); midtones.append(d[2]-d[4])
                # Endpoints can both hit the paper's limits at hard grades; compare
                # midtone contrast too, where clipping cannot hide the control.
                assert np.all(np.diff(spans) >= -1e-5), (stock,'unordered endpoints',spans)
                assert np.all(np.diff(midtones) > 0), (stock,'unordered midtone contrast',midtones)
                assert spans[-1] > 1.3*spans[0], (stock,'grade control ineffective')
                assert np.ptp(greys) < .04, (stock,'exposure compensation lost',greys)
                print(stock,'contrast spans',np.round(spans,3).tolist(),
                      'grey density spread',round(float(np.ptp(greys)),4),'cached negative PASS',flush=True)
    print('Seven paper grades on eight films PASS',flush=True)

if __name__ == '__main__':
    run()
