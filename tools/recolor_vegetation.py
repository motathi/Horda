#!/usr/bin/env python3
"""Recolore as texturas de vegetação para um visual pós-apocalíptico (folhas secas e doentes):
pixels verdes perdem saturação e puxam para oliva/palha; flores ficam desbotadas.
Idempotente em relação ao original guardado no git (rode sobre os arquivos originais).
Uso: python3 tools/recolor_vegetation.py"""
import colorsys
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
N = os.path.join(ROOT, "assets/third_party/quaternius_nature")
JOBS = {
    # arquivo: (força no verde, saturação, brilho, matiz alvo em graus, saturação geral)
    os.path.join(N, "Leaves_NormalTree_C.png"): (0.85, 0.45, 0.8, 50, 0.7),
    os.path.join(N, "Leaves_TwistedTree_C.png"): (0.85, 0.45, 0.8, 45, 0.55),
    os.path.join(N, "Leaves.png"): (0.85, 0.45, 0.8, 50, 0.6),
    os.path.join(N, "Leaf_Pine_C.png"): (1.0, 0.42, 0.72, 62, 0.8),
    os.path.join(N, "Grass.png"): (0.9, 0.45, 0.85, 46, 0.8),
    os.path.join(N, "Flowers.png"): (0.85, 0.35, 0.8, 48, 0.5),
    os.path.join(ROOT, "assets/models/textures/tree.jpg"): (0.85, 0.45, 0.8, 50, 0.8),
}


def recolor(path, strength, sat_mult, val_mult, target_hue, all_sat=1.0):
    im = Image.open(path)
    mode = im.mode
    rgba = np.asarray(im.convert("RGBA")).astype(np.float32) / 255.0
    rgb = rgba[..., :3]
    hsv = np.vectorize(colorsys.rgb_to_hsv, otypes=[float, float, float])(rgb[..., 0], rgb[..., 1], rgb[..., 2])
    h, s, v = [np.asarray(c) for c in hsv]
    deg = h * 360.0
    # Peso: 1 nos verdes (70°–170°), cai suavemente fora disso; flores (qualquer matiz) via sat_mult global.
    green = np.clip(1.0 - np.abs(deg - 115.0) / 65.0, 0.0, 1.0) ** 0.5 * strength
    if os.path.basename(path) == "Flowers.png":
        green = np.full_like(green, strength)
    new_deg = deg + (target_hue - deg) * green
    s2 = s * (1.0 - green * (1.0 - sat_mult)) * all_sat
    v2 = v * (1.0 - green * (1.0 - val_mult))
    out = np.vectorize(colorsys.hsv_to_rgb, otypes=[float, float, float])((new_deg % 360.0) / 360.0, s2, v2)
    rgba[..., 0], rgba[..., 1], rgba[..., 2] = out
    res = Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA")
    if mode != "RGBA":
        res = res.convert("RGB")
    res.save(path, quality=92) if path.endswith(".jpg") else res.save(path)
    print("recolorido:", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    for p, args in JOBS.items():
        recolor(p, *args)
