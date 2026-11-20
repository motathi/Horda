"""Cidade abandonada modelada no Blender (bpy), no estilo da fortaleza (tools/blender_scenery.py):
materiais procedurais assados num atlas de 1024 px por modelo (cor x oclusão), exportados em GLB.

  house_ruin_a   sobrado de pedra de 2 andares com o canto da frente e metade do telhado desabados
                 (caibros à mostra), janelas tapadas com tábuas, porta caída, chaminé e entulho
  house_ruin_b   casa de enxaimel queimada: base de pedra, esteios e vigas carbonizados, restos de
                 reboco entre eles, chaminé de pedra de pé e o telhado caído no chão
  shack_a        barraco de sobrevivente: tábuas, telhado de zinco, lona, chaminé de lata, sacos de areia
  shack_b        puxadinho encostado num muro quebrado: zinco sobre varas, lona, fogueira e caixotes
  ruin_wall_a    muro de alvenaria quebrado com janela, topo desmoronado e pedras caídas
  ruin_wall_b    canto de muro (em L) arruinado
  ruin_pillar    coluna de pedra partida sobre a base, com um tambor caído ao lado

Uso (módulo `bpy` do PyPI ou Blender):
  python3 tools/blender_town.py assets/models/blender [nome ...] [--render pasta]
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402,I001
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

import blender_defenses as bd  # noqa: E402
import blender_scenery as bs  # noqa: E402

srgb = bd.srgb


# --------------------------------------------------------------------------- materiais

def mat_plaster():
    """Reboco velho: bege sujo, manchas de umidade, rachaduras e fuligem subindo das janelas."""
    m, nt, bsdf = bd._mat("plaster")
    base = bd._ramp(nt, bd._noise(nt, 3.0, 6.0, 0.6), [(0.3, (0.5, 0.46, 0.38)), (0.6, (0.6, 0.56, 0.47)), (0.8, (0.54, 0.5, 0.42))])
    damp = bd._ramp(nt, bd._noise(nt, 1.6, 5.0, 0.6, bd._coords(nt, (1.0, 1.0, 0.45))), [(0.45, (1, 1, 1)), (0.68, (0.55, 0.5, 0.42))])
    c = bd._mix(nt, 1.0, base, damp, "MULTIPLY")
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 9.0
    crack = bd._ramp(nt, vor.outputs["Distance"], [(0.0, (0.45, 0.41, 0.36)), (0.012, (1, 1, 1))])
    # Só parte das rachaduras aparece.
    crack = bd._mix(nt, bd._ramp(nt, bd._noise(nt, 2.0, 3.0, 0.5), [(0.45, (1, 1, 1)), (0.6, (0, 0, 0))]), crack, (1, 1, 1))
    c = bd._mix(nt, 1.0, c, crack, "MULTIPLY")
    soot = bd._ramp(nt, bd._noise(nt, 2.2, 5.0, 0.6, bd._coords(nt, (1.2, 1.2, 0.4))), [(0.5, (1, 1, 1)), (0.7, (0.14, 0.13, 0.12))])
    c = bd._mix(nt, 1.0, c, soot, "MULTIPLY")
    nt.links.new(bd._height_dirt(nt, c), bsdf.inputs["Base Color"])
    return m


def mat_slate():
    """Telhado de ardósia: placas escuras em fileiras (textura de tijolo), musgo e falhas."""
    m, nt, bsdf = bd._mat("slate")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.inputs["Scale"].default_value = 3.2
    brick.inputs["Mortar Size"].default_value = 0.02
    brick.inputs["Brick Width"].default_value = 0.5
    brick.inputs["Row Height"].default_value = 0.22
    brick.inputs["Color1"].default_value = (*srgb((0.2, 0.21, 0.23)), 1)
    brick.inputs["Color2"].default_value = (*srgb((0.14, 0.15, 0.17)), 1)
    brick.inputs["Mortar"].default_value = (*srgb((0.04, 0.04, 0.045)), 1)
    nt.links.new(tc.outputs["UV"], brick.inputs["Vector"])
    nt.links.new(tc.outputs["Object"], brick.inputs["Vector"])
    moss = bd._ramp(nt, bd._noise(nt, 3.0, 6.0, 0.6), [(0.58, (0, 0, 0)), (0.7, (1, 1, 1))])
    c = bd._mix(nt, moss, brick.outputs["Color"], (0.2, 0.22, 0.11))
    nt.links.new(c, bsdf.inputs["Base Color"])
    return m


# --------------------------------------------------------------------------- peças

def strip(name, origin, direction, s0, s1, thick, z_bot, top_fn, mat, segs=6, bot_fn=None):
    """Trecho de parede ao longo de `direction` (de s0 a s1 metros a partir de `origin`), espessura `thick`,
    base z_bot (ou bot_fn(s)) e topo top_fn(s) — o topo pode ser serrilhado (ruína)."""
    d = Vector((direction[0], direction[1], 0)).normalized()
    n = Vector((-d.y, d.x, 0)) * (thick / 2)
    o = Vector((origin[0], origin[1], 0))
    secs = []
    for i in range(segs + 1):
        s = s0 + (s1 - s0) * i / segs
        p = o + d * s
        zb = bot_fn(s) if bot_fn else z_bot
        zt = top_fn(s)
        secs.append([p - n + Vector((0, 0, zb)), p + n + Vector((0, 0, zb)), p + n + Vector((0, 0, zt)), p - n + Vector((0, 0, zt))])
    return bs.loft(name, secs, mat)


def wall(name, origin, direction, length, thick, top_fn, mat, openings=(), segs_per_m=2.0):
    """Parede com aberturas [(s0, s1, z_baixo, z_alto)]: trechos cheios entre elas, peitoril e verga."""
    cuts = sorted({0.0, length, *[o[0] for o in openings], *[o[1] for o in openings]})
    for a, b in zip(cuts, cuts[1:]):
        mid = (a + b) / 2
        segs = max(1, int((b - a) * segs_per_m))
        hole = next((o for o in openings if o[0] <= mid <= o[1]), None)
        if hole is None:
            strip(name, origin, direction, a, b, thick, 0.0, top_fn, mat, segs)
        else:
            if hole[2] > 0.01:
                strip(name + "_sill", origin, direction, a, b, thick, 0.0, lambda s, z=hole[2]: z, mat, 1)
            if min(top_fn(a), top_fn(b)) > hole[3] + 0.05:
                strip(name + "_lintel", origin, direction, a, b, thick, hole[3], top_fn, mat, segs)


def jagged(rng, base_fn, amp=0.25, scale=1.7):
    """Topo desmoronado: altura base com recortes irregulares."""
    seed = rng.uniform(0, 100)
    return lambda s: base_fn(s) - amp * (0.5 + 0.5 * math.sin(s * scale * 2.3 + seed) * math.sin(s * scale * 1.1 + seed * 0.7)) \
        - amp * 0.6 * abs(math.sin(s * scale * 5.7 + seed))


def boards(origin, direction, s_mid, z_mid, w, h, wood, rng):
    """Tábuas pregadas tapando uma janela (em X ou na horizontal)."""
    d = Vector((direction[0], direction[1], 0)).normalized()
    p = Vector((origin[0], origin[1], 0)) + d * s_mid + Vector((-d.y, d.x, 0)) * -0.27
    yaw = math.degrees(math.atan2(d.y, d.x))
    for k in range(3):
        pl = bd.plank("board", w * 1.15, 0.16, 0.035, wood, rng, 1, broken=rng.random() < 0.3)
        ang = (35, -35, 0)[k] if rng.random() < 0.6 else rng.uniform(-12, 12)
        bd.place(pl, (p.x, p.y, z_mid + (k - 1) * h * 0.28), (ang, 0, yaw))


def rubble(center, radius, n, mats, rng, height=0.6):
    """Monte de entulho: pedras de alvenaria/concreto e tijolos."""
    for i in range(n):
        a = rng.uniform(0, math.tau)
        r = radius * math.sqrt(rng.random())
        z = max(0.05, height * (1 - r / radius)) * rng.uniform(0.4, 1.0)
        s = rng.uniform(0.18, 0.45)
        st = bd.rough_stone("rubble", (s, s * rng.uniform(0.6, 1.1), s * rng.uniform(0.4, 0.8)), rng.choice(mats), rng, 1, 0.3)
        bd.place(st, (center[0] + math.cos(a) * r, center[1] + math.sin(a) * r, z), (rng.uniform(-40, 40), rng.uniform(-40, 40), rng.uniform(0, 180)))


def rafter(a, b, r, mat, rng):
    """Caibro/viga de a até b."""
    a, b = Vector(a), Vector(b)
    L = (b - a).length
    lg = bd.log("rafter", L, r, mat, rng, 1, taper=0.95, bend=0.01, segs=6, rings=4)
    lg.location = (a + b) / 2
    lg.rotation_mode = "QUATERNION"
    lg.rotation_quaternion = (b - a).normalized().to_track_quat("Z", "Y")
    return lg


def roof_plane(x0, x1, y_eave, z_eave, y_ridge, z_ridge, thick, mat):
    """Água do telhado: placa de x0 a x1, do beiral (y_eave, z_eave) até a cumeeira."""
    secs = []
    for x in (x0, x1):
        secs.append([Vector((x, y_eave, z_eave)), Vector((x, y_ridge, z_ridge)), Vector((x, y_ridge, z_ridge + thick)),
                     Vector((x, y_eave, z_eave + thick))])
    return bs.loft("roof", secs, mat)


# --------------------------------------------------------------------------- casas

def build_house_ruin_a():
    rng = random.Random(501)
    mas = bs.mat_masonry()
    conc = bs.mat_concrete()
    wood = bd.mat_old_wood("old_wood", blood=False)
    burnt = bs.mat_burnt_wood()
    slate = mat_slate()
    stone = bd.mat_stone()
    W, D, T, H = 7.6, 6.0, 0.45, 6.2
    hx, hy = W / 2, D / 2
    # Frente (y = -hy): porta e janelas; o canto direito desmoronou.
    front_top = jagged(rng, lambda s: H if s < 4.6 else H - (s - 4.6) / (W - 4.6) * (H - 2.4), amp=0.35)
    wall("front", (-hx, -hy), (1, 0), W, T, front_top, mas,
         openings=[(3.2, 4.4, 0.0, 2.35), (1.0, 2.0, 1.0, 2.2), (5.6, 6.5, 1.0, 2.2), (1.0, 2.0, 3.9, 5.2), (3.3, 4.3, 3.9, 5.2)])
    # Lado direito: desaba a partir da frente.
    right_top = jagged(rng, lambda s: 2.4 + (H - 2.4) * min(1.0, s / (D * 0.8)), amp=0.3)
    wall("right", (hx, -hy), (0, 1), D, T, right_top, mas, openings=[(3.6, 4.6, 3.9, 5.1)])
    # Lado esquerdo com a empena (oitão) e janela.
    left_top = lambda s: H + 2.2 * (1 - abs(s - hy) / hy)
    wall("left", (-hx, hy), (0, -1), D, T, left_top, mas, openings=[(2.4, 3.4, 1.0, 2.2), (2.5, 3.5, 4.0, 5.0)])
    # Fundos.
    wall("back", (hx, hy), (-1, 0), W, T, lambda s: H if s > 1.2 else H - 0.4 * (1.2 - s), mas,
         openings=[(1.6, 2.6, 1.0, 2.2), (4.8, 5.8, 1.0, 2.2), (4.8, 5.8, 3.9, 5.2)])
    # Faixa de pedra na base e cunhais.
    for x, y, sx, sy in ((-hx, 0, T + 0.12, D + 0.12), (hx, 0, T + 0.12, D + 0.12), (0, -hy, W + 0.12, T + 0.12), (0, hy, W + 0.12, T + 0.12)):
        bd.place(bd.box("plinth", (sx, sy, 0.55), stone, 1), (x, y, 0.27))
    # Piso do 2º andar (vigas e tábuas), quebrado perto do canto que caiu.
    for i in range(7):
        x = -hx + 0.5 + i * (W - 1.0) / 6
        if x > 1.6 and rng.random() < 0.7:
            rafter((x, -hy + 0.3, 3.0), (x + rng.uniform(-0.3, 0.3), -hy + 1.6, 1.0 + rng.uniform(0, 1.0)), 0.1, burnt, rng)
            continue
        rafter((x, -hy + 0.2, 3.0), (x, hy - 0.2, 3.0), 0.1, wood, rng)
    bd.place(bd.box("floor", (W * 0.55, D - 0.5, 0.12), wood, 1), (-hx + W * 0.3, 0, 3.15))
    # Telhado: metade esquerda inteira (ardósia), direita só com os caibros, alguns caídos.
    ridge_z, eave_z, over = H + 2.2, H - 0.1, 0.45
    for sgn in (-1, 1):
        roof_plane(-hx - 0.3, 0.4, sgn * (hy + over), eave_z, 0.0, ridge_z, 0.12, slate)
    rafter((-hx - 0.3, 0, ridge_z + 0.05), (1.9, 0, ridge_z - 0.25), 0.11, burnt, rng)
    for i in range(6):
        x = 0.7 + i * 0.6
        for sgn in (-1, 1):
            if rng.random() < 0.25:
                continue
            if x > 2.4 and sgn < 0:
                rafter((x, -hy - 0.2, eave_z - 1.0 - rng.uniform(0, 1.2)), (x + rng.uniform(-0.4, 0.4), -0.6, ridge_z - 1.6), 0.07, burnt, rng)
            else:
                rafter((x, sgn * (hy + 0.2), eave_z), (x, 0.0, ridge_z - (0.3 if x > 2.4 else 0.0)), 0.07, burnt, rng)
    # Chaminé na empena esquerda.
    bd.place(bd.box("chimney", (0.85, 0.85, 3.2), mas, 1), (-hx + 0.1, 0.9, ridge_z - 0.2))
    bd.place(bd.box("chimney_cap", (1.0, 1.0, 0.16), stone, 1), (-hx + 0.1, 0.9, ridge_z + 1.45))
    # Janelas tapadas com tábuas e a porta caída de lado.
    boards((-hx, -hy), (1, 0), 1.5, 1.6, 1.0, 1.2, wood, rng)
    boards((-hx, -hy), (1, 0), 3.8, 4.55, 1.0, 1.3, wood, rng)
    boards((hx, hy), (-1, 0), 2.1, 1.6, 1.0, 1.2, wood, rng)
    for k in range(4):
        pl = bd.plank("door", 2.2, 0.3, 0.05, wood, rng, 1, broken=k == 3)
        bd.place(pl, (-0.2 + k * 0.29, -hy - 0.55, 0.9), (0, 62, 8))
    # Entulho do canto desmoronado (dentro e fora) e entulho junto à base.
    rubble((hx - 0.6, -hy - 0.4), 1.8, 26, [mas, conc, stone], rng, 0.9)
    rubble((hx - 1.5, -hy + 1.3), 1.4, 14, [mas, stone], rng, 0.7)
    for i in range(3):
        rafter((hx - rng.uniform(0.5, 2.5), -hy - rng.uniform(0.3, 1.6), 0.15), (hx + rng.uniform(-0.5, 1.0), -hy + rng.uniform(0.5, 2.0), rng.uniform(0.8, 1.8)), 0.09, burnt, rng)


def build_house_ruin_b():
    rng = random.Random(777)
    mas = bs.mat_masonry()
    stone = bd.mat_stone()
    burnt = bs.mat_burnt_wood()
    char = bs.mat_char()
    plaster = mat_plaster()
    rust = bd.mat_rust()
    W, D = 7.0, 5.4
    hx, hy = W / 2, D / 2
    base_h, post_h = 0.7, 2.9
    # Base de pedra.
    for x, y, sx, sy in ((-hx, 0, 0.6, D), (hx, 0, 0.6, D), (0, -hy, W, 0.6), (0, hy, W, 0.6)):
        bd.place(bd.rough_stone("found", (sx, sy, base_h), mas, rng, 1, 0.04), (x, y, base_h / 2))
    # Esteios a cada ~1,75 m, viga de topo e mãos-francesas; reboco entre eles (alguns caíram).
    corners = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
    for ci in range(4):
        a, b = Vector(corners[ci]), Vector(corners[(ci + 1) % 4])
        L = (b - a).length
        n = max(2, round(L / 1.75))
        d = (b - a) / L
        for k in range(n + 1):
            p = a + d * (L * k / n)
            h = post_h * (rng.uniform(0.55, 1.0) if k not in (0, n) else 1.0)
            if not (ci == 0 and k == 2):
                rafter((p.x, p.y, base_h), (p.x + rng.uniform(-0.05, 0.05), p.y + rng.uniform(-0.05, 0.05), base_h + h), 0.12, burnt, rng)
            if k < n:
                q = a + d * (L * (k + 1) / n)
                # Painel de reboco (às vezes só a metade de baixo, com o topo quebrado).
                if rng.random() < 0.6:
                    top = base_h + post_h * (1.0 if rng.random() < 0.5 else rng.uniform(0.35, 0.7))
                    seg = jagged(rng, lambda s, t=top: t, amp=0.18 if top < base_h + post_h - 0.1 else 0.0)
                    strip("panel", (p.x, p.y), (d.x, d.y), 0.1, (q - p).length - 0.1, 0.14, base_h, seg, plaster, 4)
                if rng.random() < 0.5:
                    rafter((p.x, p.y, base_h + 0.2), (q.x, q.y, base_h + post_h * 0.85), 0.07, burnt, rng)
        if ci != 1:
            rafter((a.x, a.y, base_h + post_h), (b.x, b.y, base_h + post_h + rng.uniform(-0.25, 0.0)), 0.13, char, rng)
    # Chaminé de pedra inteira de pé no lado direito.
    bd.place(bd.rough_stone("chimney", (1.2, 1.1, 6.4), stone, rng, 1, 0.03), (hx + 0.2, 0.6, 3.2))
    bd.place(bd.box("chimney_top", (0.8, 0.7, 0.9), mas, 1), (hx + 0.2, 0.6, 6.7))
    # Caibros que sobraram, inclinados; um pedaço do telhado caído no chão (tábuas + zinco).
    for i in range(4):
        x = -hx + 0.8 + i * 1.6
        rafter((x, -hy, base_h + post_h), (x + rng.uniform(-0.3, 0.3), 0.0, base_h + post_h + 1.6 - i * 0.2), 0.08, char, rng)
    for k in range(6):
        pl = bd.plank("roofboard", 2.6, 0.25, 0.04, burnt, rng, 1, broken=rng.random() < 0.5)
        bd.place(pl, (-1.0 + k * 0.27, hy + 1.4, 0.35 + k * 0.05), (rng.uniform(-6, 6), 18, 90 + rng.uniform(-8, 8)))
    sh = bd.tin_sheet("tin", 1.8, 1.0, rust, rng, 1)
    bd.place(sh, (1.4, hy + 1.6, 0.4), (80, 10, 20))
    # Restos queimados dentro.
    for i in range(5):
        rafter((rng.uniform(-hx + 1, hx - 1), rng.uniform(-hy + 1, hy - 1), base_h + 0.1),
               (rng.uniform(-hx + 1, hx - 1), rng.uniform(-hy + 1, hy - 1), base_h + rng.uniform(0.2, 1.4)), 0.1, char, rng)
    rubble((-hx + 1.2, hy - 1.0), 1.0, 10, [mas, stone], rng, 0.5)


# --------------------------------------------------------------------------- barracos

def build_shack_a():
    rng = random.Random(31)
    wood = bd.mat_old_wood("old_wood", blood=False)
    rust = bd.mat_rust()
    canvas = bs.mat_canvas()
    burlap = bd.mat_burlap()
    W, D, hf, hb = 3.6, 2.8, 2.5, 2.05
    hx, hy = W / 2, D / 2
    # Paredes de tábuas em pé (com frestas); a frente com abertura de porta.
    for side, (a, b) in enumerate((((-hx, -hy), (hx, -hy)), ((hx, -hy), (hx, hy)), ((hx, hy), (-hx, hy)), ((-hx, hy), (-hx, -hy)))):
        a, b = Vector(a), Vector(b)
        L = (b - a).length
        d = (b - a) / L
        n = int(L / 0.24)
        for k in range(n):
            s = (k + 0.5) * L / n
            if side == 0 and 1.1 < s < 2.0:
                continue
            p = a + d * s
            # Altura acompanha a inclinação do telhado (frente mais alta).
            t = (p.y + hy) / D
            h = hf + (hb - hf) * t + rng.uniform(-0.05, 0.03)
            pl = bd.plank("wall", h, 0.21, 0.03, wood, rng, 1, broken=rng.random() < 0.12)
            bd.place(pl, (p.x, p.y, h / 2), (0, 90, math.degrees(math.atan2(d.y, d.x))))
    # Esteios nos cantos.
    for x, y in ((-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)):
        h = hf if y < 0 else hb
        rafter((x, y, 0), (x, y, h + 0.05), 0.07, wood, rng)
    # Telhado de zinco em 3 chapas, inclinado para trás, com beiral.
    for k in range(3):
        sh = bd.tin_sheet("roof", 1.45, D + 0.7, rust, rng, 1)
        tilt = math.degrees(math.atan2(hf - hb, D))
        bd.place(sh, (-hx + 0.55 + k * 1.25, 0.0, (hf + hb) / 2 + 0.12), (90 - tilt, 0, 0))
    # Lona pendurada na lateral, porta de tábuas entreaberta e chaminé de lata.
    tarp = bd.tin_sheet("tarp", 2.2, 1.7, canvas, rng, 1, corrugate=0.04)
    bd.place(tarp, (hx + 0.08, -0.2, 1.0), (0, 0, 90))
    for k in range(4):
        pl = bd.plank("door", 1.9, 0.22, 0.035, wood, rng, 1)
        bd.place(pl, (1.0 + k * 0.05, -hy - 0.35 - k * 0.2, 0.95), (0, 90, -55))
    pipe = bs.cylinder("pipe", 0.08, 1.6, rust, 10)
    bd.place(pipe, (-hx + 0.7, 0.6, hb + 0.9))
    bd.place(bs.cylinder("pipecap", 0.15, 0.06, rust, 10), (-hx + 0.7, 0.6, hb + 1.72))
    # Sacos de areia na frente, tambor e caixote.
    for k in range(5):
        sb = bd.sandbag("bag", burlap, rng, 1)
        bd.place(sb, (-hx + 0.3 + k * 0.48, -hy - 0.55, 0.09 + (0.17 if k in (1, 2) else 0.0)), (0, 0, rng.uniform(-10, 10)))
    bs.drum("drum", bs.mat_drum("drum", (0.3, 0.2, 0.14)), rng).location = (hx + 0.55, -hy - 0.5, 0.0)
    bd.place(bd.box("crate", (0.6, 0.6, 0.55), wood, 1), (-hx - 0.5, hy - 0.3, 0.28), (0, 0, 12))


def build_shack_b():
    rng = random.Random(64)
    mas = bs.mat_masonry()
    stone = bd.mat_stone()
    wood = bd.mat_old_wood("old_wood", blood=False)
    rust = bd.mat_rust()
    canvas = bs.mat_canvas()
    char = bs.mat_char()
    # Muro quebrado ao fundo.
    wall("wall", (-2.8, 1.2), (1, 0), 5.6, 0.5, jagged(rng, lambda s: 2.9 - 0.25 * abs(s - 2.2), amp=0.4), mas,
         openings=[(3.6, 4.4, 1.1, 2.0)])
    # Telhado de zinco apoiado no muro e em duas varas na frente.
    for x in (-1.7, 1.3):
        rafter((x, -1.0, 0), (x + rng.uniform(-0.05, 0.05), -1.0, 1.95), 0.06, wood, rng)
    rafter((-2.2, -1.0, 1.95), (1.9, -1.0, 1.9), 0.06, wood, rng)
    for k in range(3):
        sh = bd.tin_sheet("roof", 1.4, 2.6, rust, rng, 1)
        bd.place(sh, (-1.7 + k * 1.2, 0.1, 2.2), (90 - 13, 0, rng.uniform(-3, 3)))
    tarp = bd.tin_sheet("tarp", 1.9, 1.6, canvas, rng, 1, corrugate=0.05)
    bd.place(tarp, (-2.25, -0.1, 1.0), (0, 0, 90))
    # Fogueira com pedras e lenha queimada; caixotes e um colchonete.
    for k in range(8):
        a = k * math.tau / 8
        st = bd.rough_stone("ring", (0.22, 0.18, 0.14), stone, rng, 1, 0.3)
        bd.place(st, (0.4 + math.cos(a) * 0.45, -2.2 + math.sin(a) * 0.45, 0.07))
    for k in range(3):
        rafter((0.4 + math.cos(k * 2.1) * 0.35, -2.2 + math.sin(k * 2.1) * 0.35, 0.05), (0.4, -2.2, 0.35), 0.05, char, rng)
    bd.place(bd.box("crate", (0.6, 0.55, 0.5), wood, 1), (1.6, 0.4, 0.25), (0, 0, 8))
    bd.place(bd.box("crate2", (0.5, 0.5, 0.45), wood, 1), (1.65, 0.45, 0.72), (0, 0, -15))
    bd.place(bd.box("bedroll", (1.8, 0.7, 0.14), canvas, 1), (-0.9, 0.3, 0.07), (0, 0, 4))
    rubble((2.6, 1.0), 0.9, 8, [mas, stone], rng, 0.4)


# --------------------------------------------------------------------------- ruínas

def build_ruin_wall_a():
    rng = random.Random(901)
    mas = bs.mat_masonry()
    stone = bd.mat_stone()
    wall("wall", (-2.3, 0), (1, 0), 4.6, 0.55, jagged(rng, lambda s: 3.4 - 1.2 * max(0.0, s - 3.0) / 1.6, amp=0.45), mas,
         openings=[(1.4, 2.3, 1.1, 2.4)])
    for x, w in ((-2.3, 0.7), (2.15, 0.6)):
        bd.place(bd.box("pier", (w, 0.7, 0.4), stone, 1), (x + w / 2 - 0.3, 0, 0.2))
    rubble((1.6, -0.6), 1.2, 16, [mas, stone], rng, 0.55)
    rubble((-1.4, 0.7), 0.7, 6, [mas], rng, 0.3)


def build_ruin_wall_b():
    rng = random.Random(902)
    mas = bs.mat_masonry()
    stone = bd.mat_stone()
    wall("wall_x", (-2.0, 0), (1, 0), 3.6, 0.55, jagged(rng, lambda s: 2.8 - 0.9 * s / 3.6, amp=0.4), mas)
    wall("wall_y", (-2.0, 0), (0, 1), 3.0, 0.55, jagged(rng, lambda s: 2.8 - 1.4 * s / 3.0, amp=0.4), mas,
         openings=[(1.0, 1.8, 0.9, 2.0)])
    bd.place(bd.box("corner", (0.75, 0.75, 3.3), stone, 1), (-2.0, 0, 1.65))
    rubble((0.0, 1.2), 1.4, 18, [mas, stone], rng, 0.6)


def build_ruin_pillar():
    rng = random.Random(903)
    stone = bd.mat_stone()
    mas = bs.mat_masonry()
    bd.place(bd.box("plinth", (1.15, 1.15, 0.4), stone, 1), (0, 0, 0.2))
    bd.place(bd.box("plinth2", (0.95, 0.95, 0.2), stone, 1), (0, 0, 0.5))
    z = 0.6
    for k, h in enumerate((0.9, 0.85, 0.7)):
        dr = bs.cylinder("drum", 0.38 - k * 0.01, h, stone, 14)
        bd.place(dr, (rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), z + h / 2), (rng.uniform(-2, 2), rng.uniform(-2, 2), rng.uniform(0, 30)))
        bs.dents(dr, rng, 6, 0.25, 0.06)
        z += h
    # Topo partido: lascas.
    for k in range(5):
        a = k * math.tau / 5
        st = bd.rough_stone("chip", (0.25, 0.2, rng.uniform(0.15, 0.35)), stone, rng, 1, 0.25)
        bd.place(st, (math.cos(a) * 0.2, math.sin(a) * 0.2, z + 0.05), (rng.uniform(-20, 20), rng.uniform(-20, 20), rng.uniform(0, 90)))
    fallen = bs.cylinder("fallen", 0.37, 0.85, stone, 14)
    bd.place(fallen, (1.2, 0.5, 0.37), (90, 0, 35))
    bs.dents(fallen, rng, 5, 0.25, 0.06)
    rubble((0.9, -0.6), 0.7, 7, [stone, mas], rng, 0.3)


BUILDERS = {"house_ruin_a": build_house_ruin_a, "house_ruin_b": build_house_ruin_b, "shack_a": build_shack_a,
            "shack_b": build_shack_b, "ruin_wall_a": build_ruin_wall_a, "ruin_wall_b": build_ruin_wall_b,
            "ruin_pillar": build_ruin_pillar}


def main():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    render_dir = None
    if "--render" in a:
        i = a.index("--render")
        render_dir = a[i + 1]
        a = a[:i] + a[i + 2:]
    out = a[0] if a else "assets/models/blender"
    names = a[1:] or list(BUILDERS)
    os.makedirs(out, exist_ok=True)
    for n in names:
        bd.reset()
        BUILDERS[n]()
        objs = bd.join_levels()
        bd.bake_atlas(objs, n)
        for o in objs:
            o.name = n
        bd.export(os.path.join(out, n + ".glb"))
        if render_dir:
            os.makedirs(render_dir, exist_ok=True)
            bs.render_single(objs, os.path.join(render_dir, n + ".png"))


if __name__ == "__main__":
    main()
