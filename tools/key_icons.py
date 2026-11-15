#!/usr/bin/env python3
"""Remove o fundo preto dos ícones gerados (assets/ui/hud/src/*.jpg) e salva PNG
com transparência em assets/ui/hud/, recortado e redimensionado para 192 px."""
import glob, os
import numpy as np
from PIL import Image, ImageFilter
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for f in sorted(glob.glob(os.path.join(ROOT, "assets/ui/hud/src/*.jpg"))):
    im = np.asarray(Image.open(f).convert("RGB")).astype(np.float32) / 255.0
    lum = im.max(axis=2)
    # Alfa suave: preto puro some, tons escuros do contorno ficam semi-opacos.
    a = np.clip((lum - 0.05) / 0.12, 0.0, 1.0)
    # Preenche o interior: tudo o que estiver cercado pelo objeto fica opaco.
    mask = Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    a = np.maximum(a, np.asarray(mask).astype(np.float32) / 255.0 * (lum > 0.02))
    rgba = np.dstack([im, a])
    out = Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")
    bbox = out.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    if bbox:
        out = out.crop(bbox)
    w, h = out.size
    side = max(w, h)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(out, ((side - w) // 2, (side - h) // 2))
    sq = sq.resize((192, 192), Image.LANCZOS)
    sq.save(os.path.join(ROOT, "assets/ui/hud", os.path.basename(f)[:-4] + ".png"))
    print("ok", os.path.basename(f))
