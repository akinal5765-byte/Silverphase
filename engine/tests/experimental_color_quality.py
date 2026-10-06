"""Plausibility gates relative to stable base films, NOT real-film fidelity."""
import json
from pathlib import Path
import sys

import numpy as np

from spk_ctypes import Engine
from experimental_negatives import unchanged_originals

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from make_negative_profiles import STOCKS
STOCK_PAIRS = [("fujifilm_pro_160ns_experimental", "fujifilm_pro_400h")] + [
    (stock, donor) for stock, _, donor, _, _ in STOCKS.values()]
from make_pro160ns import baked_d55


def run():
    unchanged_originals()
    light = baked_d55()
    ev = np.linspace(-4, 4, 65, dtype=np.float32)
    ramp = np.broadcast_to((.184*2**ev)[None, :, None], (32, 65, 3)).copy()
    colors = np.array([[.184,.184,.184], [.45,.26,.18], [.24,.12,.08],
                       [.55,.12,.08], [.10,.40,.08], [.08,.10,.45], [.28,.08,.32]], dtype=np.float32)
    chart = np.repeat(np.repeat(colors[None, :, :],32,axis=0),32,axis=1)
    common = {"auto_exposure":False, "grain_active":False, "glare_active":False,
              "halation_active":False, "scanner_sharpening_amount":0, "dir_couplers_active":True}
    with Engine() as engine:
        for stock, donor in STOCK_PAIRS:
            p = json.loads((ROOT / f"resources/profiles/{stock}.json").read_text())
            d = json.loads((ROOT / f"resources/profiles/{donor}.json").read_text())
            sums = np.nansum(10**np.array(p["data"]["log_sensitivity"], dtype=float)*light[:,None], axis=0)
            reference = np.nansum(10**np.array(d["data"]["log_sensitivity"], dtype=float)*light[:,None], axis=0)
            np.testing.assert_allclose(sums, reference, rtol=1e-9, err_msg=stock+" arbitrary exposure scale")
            paper = p["info"]["target_print"]
            for edr in (False, True):
                params = common | {"print_stock":paper, "extended_dynamic_range":edr}
                with engine.open(ramp, params | {"film_stock":stock}) as s:
                    image, _ = s.render("full")
                with engine.open(ramp, params | {"film_stock":donor}) as s:
                    base, _ = s.render("full")
                rgb = image[16, :, :3].astype(float)
                assert np.isfinite(rgb).all() and np.all(np.diff(rgb[:,1]) >= -2), stock
                cast = np.max(np.abs(np.log(np.maximum(rgb[:, [0,2]], 1)/np.maximum(rgb[:,1:2], 1))))
                base_rgb = base[16, :, :3].astype(float)
                base_cast = np.max(np.abs(np.log(np.maximum(base_rgb[:,[0,2]],1)/np.maximum(base_rgb[:,1:2],1))))
                span_ratio = np.ptp(rgb[:,1])/np.ptp(base[16,:,1].astype(float))
                # PRO400H itself has ~0.166 log channel ratio in deep shadows.
                # Do not silently demand neutrality the control fails too:
                # limit added cast and separately constrain bright neutrals.
                assert cast < min(.20, base_cast+.025), (stock, edr, "added gray-axis cast", cast,base_cast)
                bright = rgb[:,1] > 20000
                assert np.max(np.abs(np.log(rgb[bright][:,[0,2]]/rgb[bright,1:2]))) < .065, (stock,"bright-neutral cast")
                assert .8 < span_ratio < 1.2, (stock, edr, "collapsed or excessive contrast",span_ratio)
                with engine.open(chart, params | {"film_stock":stock}) as s:
                    image, _ = s.render("full")
                with engine.open(chart, params | {"film_stock":donor}) as s:
                    base, _ = s.render("full")
                rgb = image[:,:,:3].reshape(32,7,32,3).mean(axis=(0,2))
                old = base[:,:,:3].reshape(32,7,32,3).mean(axis=(0,2))
                def chroma(a):
                    u = a[:,0]-(a[:,1]+a[:,2])/2
                    v = np.sqrt(3)/2*(a[:,1]-a[:,2])
                    return np.hypot(u,v), np.arctan2(v,u)
                c,h = chroma(rgb[1:]); bc,bh = chroma(old[1:])
                angle = np.abs(np.angle(np.exp(1j*(h-bh))))*180/np.pi
                assert np.max(angle) < 25, (stock, "unexpected hue rotation",angle)
                assert np.all((c/bc > .65) & (c/bc < 1.4)), (stock,"excess or missing chroma",c/bc)
                assert np.all((rgb[1:3] > 1000) & (rgb[1:3] < 64000)), (stock,"clipped skin-like patches")
                print(stock, "EDR",edr,"gray cast",round(cast,4),"span ratio",round(span_ratio,3),
                      "maximum patch hue change",round(float(max(angle)),2),"PASS",flush=True)


if __name__ == "__main__":
    run()
