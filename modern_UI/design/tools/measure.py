#!/usr/bin/env python3
"""measure.py — read a capture and report the vertical rhythm and left edges.

    python3 measure.py <capture.png> [x-probe]

Prints, in points (the captures are 2x):

  * every ink band: its top, its bottom, its height
  * the **left edge** of each band's first glyph
  * the **gap** to the next band
  * the pitch between successive band tops

The point of the tool is to answer "is this a grid?" with numbers instead of an
opinion: a grid shows up as a *small set* of distinct gaps and edges, and a
patchwork shows up as a long tail of one-off values.
"""
import struct
import sys
import zlib


def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    pos, idat = 8, b""
    w = h = bd = ct = None
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, bd, ct = struct.unpack(">IIBB", chunk[:10])
        elif typ == b"IDAT":
            idat += chunk
        pos += 12 + ln
    raw = zlib.decompress(idat)
    n = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    bpp = n * (bd // 8)
    stride = w * bpp
    out = bytearray(h * stride)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if f == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, n, bytes(out)


def main():
    path = sys.argv[1]
    w, h, n, px = read_png(path)
    stride = w * n

    def lum(x, y):
        i = y * stride + x * n
        return (px[i] * 299 + px[i + 1] * 587 + px[i + 2] * 114) // 1000

    # The panel's own x-range: the card is darker than the ground.
    xs = [x for x in range(w) if lum(x, h // 2) < 60]
    x0, x1 = (min(xs), max(xs)) if xs else (0, w - 1)
    print(f"{path}  {w}x{h}px  panel x {x0}..{x1} ({(x1-x0)/2:.0f}pt wide)")

    rows = [sum(1 for x in range(x0, x1 + 1, 2) if lum(x, y) > 100) for y in range(h)]
    bands = []
    start = None
    for y, c in enumerate(rows):
        if c >= 3 and start is None:
            start = y
        elif c < 3 and start is not None:
            bands.append((start, y - 1))
            start = None
    if start is not None:
        bands.append((start, h - 1))

    values = []
    prev_top = None
    for a, b in bands:
        ink = [x for y in range(a, b + 1) for x in range(x0, x1 + 1) if lum(x, y) > 100]
        left = (min(ink) - x0) / 2
        gap = "" if prev_top is None else f"{(a - prev_top)/2:6.1f}"
        values.append(((b - a + 1) / 2, left, a / 2))
        print(f"  top {a/2:7.1f}  h {(b-a+1)/2:5.1f}  left {left:6.1f} pt  pitch {gap}")
        prev_top = a

    print()
    print("distinct heights:", sorted({round(v[0], 1) for v in values}))
    print("distinct lefts  :", sorted({round(v[1], 1) for v in values}))


if __name__ == "__main__":
    main()
