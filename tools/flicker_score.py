#!/usr/bin/env python3
"""Mede o piscar entre quadros consecutivos: média da diferença e % de pixels que
mudam > 24 (imagem toda e só um recorte, opcional x0,y0,x1,y1)."""
import sys, glob
import numpy as np
from PIL import Image
fs = sorted(glob.glob(sys.argv[1] + "/f*.png"))
crop = tuple(int(v) for v in sys.argv[2].split(",")) if len(sys.argv) > 2 else None
def score(box):
    prev = None; diffs = []; big = []
    for f in fs:
        im = Image.open(f).convert("L")
        if box: im = im.crop(box)
        a = np.asarray(im).astype(np.int16)
        if prev is not None:
            d = np.abs(a - prev); diffs.append(d.mean()); big.append((d > 24).mean() * 100)
        prev = a
    return np.mean(diffs), np.mean(big)
m, b = score(None); print(f"tela toda: diff={m:.2f} piscando={b:.2f}%")
if crop:
    m, b = score(crop); print(f"recorte {crop}: diff={m:.2f} piscando={b:.2f}%")
