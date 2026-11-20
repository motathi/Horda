"""Textura do chão de pedra (cidade, pedreira, centro da base): lajotas gastas, sem emenda ao repetir.

Gerada proceduralmente com numpy (sem IA): Voronoi periódico em grade com deslocamento aleatório
(um ponto por célula, distância com "volta" nas bordas) para as lajotas, ruído de valor periódico em
oitavas para manchas, relevo calculado da distância à junta (pedras abauladas, luz de cima à esquerda),
juntas cheias de terra, pedras faltando, rachaduras, matinho seco nas frestas, poeira e fuligem.

Uso:  python3 tools/gen_stone_floor.py assets/environment/textures/stone_floor.jpg [tamanho] [semente]
"""
import sys

import numpy as np
from PIL import Image


def smooth(t):
    return t * t * (3 - 2 * t)


def value_noise(size, cells, rng):
    """Ruído de valor periódico (cells x cells reticulado, interpolação suave, fecha nas bordas)."""
    lat = rng.random((cells, cells))
    x = np.arange(size) * cells / size
    i0 = np.floor(x).astype(int)
    f = smooth(x - i0)
    i1 = (i0 + 1) % cells
    i0 %= cells
    a = lat[np.ix_(i0, i0)]
    b = lat[np.ix_(i0, i1)]
    c = lat[np.ix_(i1, i0)]
    d = lat[np.ix_(i1, i1)]
    fy = f[:, None]
    fx = f[None, :]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(size, base, octaves, rng, gain=0.5):
    v = np.zeros((size, size))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        v += value_noise(size, base * 2 ** o, rng) * amp
        tot += amp
        amp *= gain
    return v / tot


def voronoi(size, m, rng, jitter=0.85):
    """Voronoi periódico com m x m células: distâncias F1/F2 (em unidades de célula) e id da mais próxima."""
    pts = (np.arange(m)[:, None, None] * 0 + 0.5 + (rng.random((m, m, 2)) - 0.5) * jitter)
    coord = (np.arange(size) + 0.5) * m / size
    gy, gx = np.meshgrid(coord, coord, indexing="ij")
    cy, cx = np.floor(gy).astype(int), np.floor(gx).astype(int)
    f1 = np.full((size, size), 9.0)
    f2 = np.full((size, size), 9.0)
    ident = np.zeros((size, size), dtype=int)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ny, nx = cy + dy, cx + dx
            p = pts[ny % m, nx % m]
            py = ny + p[..., 0]
            px = nx + p[..., 1]
            d = np.sqrt((gy - py) ** 2 + (gx - px) ** 2)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            ident = np.where(closer, (ny % m) * m + (nx % m), ident)
            f1 = np.where(closer, d, f1)
    return f1, f2, ident


def ss(x, a, b):
    return smooth(np.clip((x - a) / (b - a), 0, 1))


def mixc(base, col, w):
    return base * (1 - w[..., None]) + np.array(col)[None, None, :] * w[..., None]


def generate(size=1024, seed=7):
    rng = np.random.default_rng(seed)
    M = 13  # lajotas por repetição em cada direção (~0,55 m no jogo)
    f1, f2, cid = voronoi(size, M, rng, 0.9)
    edge = (f2 - f1) * 0.5
    cell_rand = rng.random(M * M)[cid]
    cell_rand2 = rng.random(M * M)[cid]
    n_big = fbm(size, 3, 4, rng)
    n_mid = fbm(size, 8, 4, rng)
    n_fine = fbm(size, 48, 3, rng)
    n_jnt = fbm(size, 6, 3, rng)
    # Tom de cada pedra: cinza-marrom escuro, algumas mais quentes ou mais frias.
    pal = np.array([(0.25, 0.235, 0.22), (0.3, 0.28, 0.255), (0.34, 0.315, 0.28), (0.27, 0.265, 0.26), (0.31, 0.27, 0.22)])
    tone = pal[(cell_rand * len(pal)).astype(int) % len(pal)]
    tone = tone * (0.88 + 0.24 * cell_rand2)[..., None]
    c = tone * (0.8 + 0.35 * n_fine)[..., None] * (0.85 + 0.25 * n_mid)[..., None]
    # Relevo: pedras abauladas (altura cresce a partir da junta) + irregularidade; luz de cima à esquerda.
    h = ss(edge, 0.0, 0.16) * (0.85 + 0.3 * n_mid) + n_fine * 0.08
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * size / 24.0
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * size / 24.0
    nrm = np.stack([-gx, -gy, np.ones_like(h)], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    light = np.array([-0.45, -0.55, 0.7])
    light /= np.linalg.norm(light)
    shade = np.clip(0.42 + 0.75 * (nrm @ light), 0.25, 1.25)
    c = c * shade[..., None]
    # Terra (juntas e pedras faltando).
    dirt = np.stack([0.17 + 0.09 * n_mid, 0.13 + 0.07 * n_mid, 0.09 + 0.05 * n_mid], -1) * (0.8 + 0.35 * n_fine)[..., None]
    missing = (cell_rand2 > 0.9).astype(float)
    pebble = ss(fbm(size, 90, 2, rng), 0.62, 0.7)
    dirt_m = mixc(dirt, (0.26, 0.24, 0.21), pebble * 0.4)
    c = c * (1 - missing[..., None]) + dirt_m * missing[..., None]
    jw = 0.035 + 0.035 * n_jnt
    joint = 1 - ss(edge, jw * 0.6, jw)
    c = c * (1 - joint[..., None]) + dirt * joint[..., None]
    # Sombra de oclusão nas juntas (a terra fica mais escura rente à pedra).
    c = c * (1 - 0.35 * ss(edge, jw * 1.4, 0.0))[..., None]
    # Matinho seco em parte das juntas.
    weed = joint * ss(n_jnt * 0.6 + fbm(size, 20, 2, rng) * 0.4, 0.58, 0.68)
    c = mixc(c, (0.29, 0.27, 0.14), weed * 0.85)
    # Rachaduras finas sobre as pedras.
    g1, g2, _ = voronoi(size, 34, rng, 1.0)
    crack = (1 - ss((g2 - g1) * 0.5, 0.0, 0.02)) * ss(n_mid, 0.6, 0.68) * (1 - joint) * (1 - missing)
    c = mixc(c, (0.06, 0.055, 0.05), crack * 0.75)
    # Poeira clara em manchas e fuligem/óleo grandes.
    c = mixc(c, (0.45, 0.41, 0.34), ss(n_big, 0.55, 0.8) * 0.3)
    c = mixc(c, (0.05, 0.045, 0.04), ss(fbm(size, 4, 4, rng), 0.6, 0.75) * 0.55)
    return np.clip(c, 0, 1)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/environment/textures/stone_floor.jpg"
    size = int(sys.argv[2]) if len(sys.argv) > 2 else 1024
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 7
    img = (generate(size, seed) * 255).astype(np.uint8)
    Image.fromarray(img).save(out, quality=90)
    print("textura:", out)


if __name__ == "__main__":
    main()
