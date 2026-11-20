"""Árvores do mapa modeladas no Blender (bpy), no clima seco e pós-apocalíptico do jogo.

Cada árvore é um GLB em assets/models/blender/ com cor por vértice (sem textura), lido por
PropFactory.make_tree (scripts/world/prop_factory.gd):
  tree_dry_a / tree_dry_b    folhosas secas: tronco torto, galhos à mostra, copa rala em tufos amarelados,
                             oliva e ferrugem, com folhas soltas nas bordas para quebrar a silhueta
  pine_dry_a / pine_dry_b    pinheiros meio secos: andares de galhos caídos com agulhas escuras, alguns
                             galhos mortos cor de ferrugem e tocos quebrados no tronco pelado de baixo
  tree_dead_a / tree_dead_b  mortas: galhos retorcidos e pelados; a "b" queimada (carvão com pontas de cinza)

Uso (módulo `bpy` do PyPI ou Blender):
  python3 tools/blender_trees.py assets/models/blender [nome ...] [--render pasta]
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402,I001
import bmesh  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402

import blender_ground as bg  # noqa: E402

face, V, leaf, lerp3, new_bm, finish, rot = bg.face, bg.V, bg.leaf, bg.lerp3, bg.new_bm, bg.finish, bg.rot

BARK_D = (0.13, 0.11, 0.09)
BARK_L = (0.33, 0.29, 0.24)
CROWN = [(0.3, 0.31, 0.14), (0.42, 0.38, 0.16), (0.46, 0.29, 0.11), (0.24, 0.26, 0.12), (0.37, 0.35, 0.2)]
NEEDLES = [(0.15, 0.19, 0.1), (0.22, 0.24, 0.12), (0.27, 0.27, 0.14)]
NEEDLES_DEAD = (0.4, 0.24, 0.1)
CHAR = (0.06, 0.055, 0.05)
ASH = (0.35, 0.33, 0.3)


def tube(bm, cl, pts, radii, cols, sides=6, rng=None):
    """Tronco/galho: tubo de `sides` lados ao longo de uma polilinha, afinando, com a cor da casca
    variando por anel (e um pouco por lado, para parecer casca rachada)."""
    rings = []
    prev_u = None
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        ref = prev_u if prev_u is not None else (Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0)))
        u = (ref - d * ref.dot(d)).normalized() if prev_u is not None else d.cross(ref).normalized()
        v = d.cross(u)
        prev_u = u
        ring = []
        for k in range(sides):
            a = k * math.tau / sides
            r = radii[i] * (1.0 + (rng.uniform(-0.12, 0.12) if rng else 0.0))
            ring.append(V(bm, p + (u * math.cos(a) + v * math.sin(a)) * r))
        rings.append(ring)
    for i in range(len(pts) - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            shade = 0.82 + 0.18 * ((k * 7) % 3) / 2.0
            c0 = tuple(x * shade for x in cols[i])
            c1 = tuple(x * shade for x in cols[i + 1])
            face(bm, cl, [rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]], [c0, c0, c1, c1])
    # Tampa na ponta (galho quebrado ou fim do tronco).
    tip = V(bm, pts[-1] + (pts[-1] - pts[-2]).normalized() * radii[-1] * 0.6)
    for k in range(sides):
        face(bm, cl, [rings[-1][k], rings[-1][(k + 1) % sides], tip], [cols[-1]] * 3)


def curve(rng, start, direction, length, segs, wobble, up_bias=0.0, droop=0.0):
    """Polilinha torta: cada segmento desvia um pouco, com tendência a subir (up_bias) ou cair (droop)."""
    pts = [start.copy()]
    d = direction.normalized()
    for i in range(segs):
        d = (d + Vector((rng.uniform(-wobble, wobble), rng.uniform(-wobble, wobble), rng.uniform(-wobble, wobble) * 0.5
                         + up_bias - droop * (i + 1) / segs))).normalized()
        pts.append(pts[-1] + d * (length / segs))
    return pts


def bark_cols(n, dark=BARK_D, light=BARK_L, rng=None):
    return [lerp3(dark, light, min(1.0, 0.25 + 0.75 * i / max(1, n - 1)) * (rng.uniform(0.85, 1.0) if rng else 1))
            for i in range(n)]


def clump(bm, cl, rng, center, radius, col, squash=0.7, leaves=8):
    """Tufo de folhagem: icosfera irregular (achatada embaixo), escura por baixo e clara em cima,
    com folhas soltas apontando para fora na borda."""
    res = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=radius,
                                     matrix=Matrix.Translation(center) @ Matrix.Diagonal((1, 1, squash, 1)))
    verts = res["verts"]
    for v in verts:
        off = v.co - center
        v.co = center + off * rng.uniform(0.78, 1.18)
        if v.co.z < center.z - radius * squash * 0.35:
            v.co.z = center.z - radius * squash * 0.35 + (v.co.z - center.z + radius * squash * 0.35) * 0.3
    top = lerp3(col, (0.62, 0.55, 0.3), 0.3)
    bot = lerp3(col, (0.05, 0.05, 0.03), 0.6)
    fs = {f for v in verts for f in v.link_faces}
    for f in fs:
        for loop in f.loops:
            t = max(0.0, min(1.0, (loop.vert.co.z - center.z) / (radius * squash) * 0.5 + 0.5))
            n = rng.uniform(0.9, 1.08)
            loop[cl] = (*(x * n for x in lerp3(bot, top, t)), 1.0)
    for _ in range(leaves):
        a, el = rng.uniform(0, math.tau), rng.uniform(-0.4, 0.9)
        dvec = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el) * squash))
        base = center + dvec * radius * 0.85
        c = lerp3(col, rng.choice(CROWN), 0.5)
        leaf(bm, cl, base, a, rng.uniform(0.35, 0.55) * radius, rng.uniform(0.2, 0.3) * radius,
             el * 0.6, c, lerp3(c, (0.6, 0.52, 0.3), 0.3), fold=0.4)


def needle_fan(bm, cl, rng, pts, width, col, dead=False):
    """Galho de pinheiro: lâmina de agulhas em zigue-zague dos dois lados do galho, caindo para baixo."""
    base_col = lerp3(col, (0.04, 0.05, 0.03), 0.45)
    tip_col = NEEDLES_DEAD if dead else lerp3(col, (0.36, 0.34, 0.18), 0.35)
    n = len(pts)
    for i in range(1, n - 1):
        a, b = pts[i], pts[i + 1]
        d = (b - a).normalized()
        side = d.cross(Vector((0, 0, 1)))
        if side.length < 1e-4:
            side = Vector((1, 0, 0))
        side.normalize()
        t = i / (n - 1)
        w = width * (1.0 - t * 0.75)
        ca, cb = lerp3(base_col, tip_col, t), lerp3(base_col, tip_col, (i + 1) / (n - 1))
        for sgn in (1, -1):
            for j in range(2):
                q = a + (b - a) * (j / 2.0)
                q2 = a + (b - a) * ((j + 1) / 2.0)
                tipp = (q + q2) * 0.5 + side * w * sgn + d * w * 0.35 - Vector((0, 0, w * rng.uniform(0.35, 0.6)))
                face(bm, cl, [V(bm, q), V(bm, q2), V(bm, tipp)], [ca, cb, lerp3(ca, tip_col, 0.5)])
        # Agulhas de cima (um "telhado" em V invertido dá volume vista de cima).
        up = (a + b) * 0.5 + Vector((0, 0, w * 0.18))
        face(bm, cl, [V(bm, a - side * w * 0.5), V(bm, up), V(bm, b - side * w * 0.3)], [ca, cb, cb])
        face(bm, cl, [V(bm, a + side * w * 0.5), V(bm, b + side * w * 0.3), V(bm, up)], [ca, cb, cb])


# ------------------------------------------------------------------ folhosas secas

def build_broadleaf(name, seed, height, n_main, crown_cols, sparse):
    rng = random.Random(seed)
    bm, cl = new_bm()
    trunk_h = height * rng.uniform(0.42, 0.5)
    lean = Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), 1))
    tpts = curve(rng, Vector((0, 0, -0.15)), lean, trunk_h, 5, 0.08, up_bias=0.15)
    tr = [0.42 * height / 7, 0.3 * height / 7, 0.27 * height / 7, 0.25 * height / 7, 0.23 * height / 7, 0.21 * height / 7]
    # Raízes: o pé do tronco abre em 4 sapatas.
    for k in range(4):
        a = k * math.tau / 4 + rng.uniform(-0.3, 0.3)
        rp = [Vector((0, 0, 0.35)), Vector((math.cos(a) * 0.45, math.sin(a) * 0.45, 0.05)),
              Vector((math.cos(a) * 0.8, math.sin(a) * 0.8, -0.1))]
        tube(bm, cl, rp, [tr[0] * 0.6, tr[0] * 0.35, 0.03], bark_cols(3, rng=rng), sides=5)
    tube(bm, cl, tpts, tr, bark_cols(len(tpts), rng=rng), sides=7, rng=rng)
    top = tpts[-1]
    tips = []

    def branch(start, d, length, r, depth):
        pts = curve(rng, start, d, length, 3, 0.18, up_bias=0.12 if depth > 0 else 0.0)
        tube(bm, cl, pts, [r, r * 0.8, r * 0.6, r * 0.4], bark_cols(4, lerp3(BARK_D, BARK_L, 0.3), BARK_L, rng),
             sides=5 if depth > 0 else 4)
        if depth == 0:
            tips.append((pts[-1], length))
            return
        for _ in range(rng.randint(2, 3)):
            t = rng.uniform(0.55, 1.0)
            idx = min(len(pts) - 2, int(t * (len(pts) - 1)))
            q = pts[idx].lerp(pts[idx + 1], t * (len(pts) - 1) - idx)
            nd = rot((pts[-1] - pts[0]).normalized(), Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)).normalized(),
                     math.radians(rng.uniform(25, 50)))
            branch(q, nd, length * rng.uniform(0.55, 0.7), r * 0.55, depth - 1)

    for i in range(n_main):
        a = i * math.tau / n_main + rng.uniform(-0.4, 0.4)
        el = math.radians(rng.uniform(30, 60))
        d = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
        start = tpts[-2 - (i % 2)] if i % 3 else top
        branch(start, d, height * rng.uniform(0.3, 0.4), tr[-1] * 0.75, 1)
    # Galho seco quebrado no meio do tronco (pelado).
    q = tpts[2]
    a = rng.uniform(0, math.tau)
    tube(bm, cl, [q, q + Vector((math.cos(a) * 0.7, math.sin(a) * 0.7, 0.3))], [tr[2] * 0.4, 0.04],
         bark_cols(2, rng=rng), sides=4)
    # Copa: tufos nas pontas; os mais altos e de fora maiores. Alguns galhos ficam pelados (copa rala).
    for p, ln in tips:
        if rng.random() < sparse:
            continue
        col = rng.choice(crown_cols)
        clump(bm, cl, rng, p + Vector((0, 0, 0.15)), rng.uniform(0.8, 1.15) * height / 7, col, leaves=9)
    # Pontas de galhos secos furando a copa (a árvore está morrendo).
    for p, ln in tips[::3]:
        a = rng.uniform(0, math.tau)
        tube(bm, cl, [p, p + Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, 0.9))], [0.05, 0.015],
             bark_cols(2, lerp3(BARK_D, BARK_L, 0.4), (0.45, 0.42, 0.37), rng), sides=4)
    return finish(name, bm)


def build_tree_dry_a():
    return build_broadleaf("tree_dry_a", 3, 7.0, 5, CROWN[:4], 0.18)


def build_tree_dry_b():
    # Mais alta, mais rala e mais "morrendo": mais ferrugem e amarelo.
    return build_broadleaf("tree_dry_b", 11, 7.5, 4, [CROWN[1], CROWN[2], CROWN[4], CROWN[2]], 0.32)


# ------------------------------------------------------------------ pinheiros meio secos

def build_pine(name, seed, height, dead_frac):
    rng = random.Random(seed)
    bm, cl = new_bm()
    tpts = curve(rng, Vector((0, 0, -0.15)), Vector((rng.uniform(-0.05, 0.05), 0, 1)), height, 7, 0.04, up_bias=0.3)
    r0 = 0.28 * height / 8
    tube(bm, cl, tpts, [r0 * (1.0 - 0.85 * i / (len(tpts) - 1)) + 0.02 for i in range(len(tpts))],
         bark_cols(len(tpts), (0.12, 0.09, 0.07), (0.36, 0.25, 0.17), rng), sides=6, rng=rng)
    # Tocos de galhos quebrados no tronco pelado de baixo.
    for k in range(5):
        z = rng.uniform(0.25, 0.42) * height
        p = Vector((0, 0, z)) + (tpts[2] - tpts[0]) * 0.0
        a = rng.uniform(0, math.tau)
        tube(bm, cl, [p, p + Vector((math.cos(a), math.sin(a), rng.uniform(-0.1, 0.2))) * rng.uniform(0.25, 0.6)],
             [0.05, 0.02], bark_cols(2, rng=rng), sides=4)
    # Andares de galhos: de 45% da altura até o topo, encurtando para cima.
    whorls = 7
    for w in range(whorls):
        t = w / (whorls - 1)
        z = height * (0.45 + 0.5 * t)
        n = rng.randint(5, 7) if t < 0.8 else 4
        length = height * (0.3 * (1 - t) + 0.07)
        for i in range(n):
            if t < 0.5 and rng.random() < 0.18:
                continue  # buraco: galho caído
            a = i * math.tau / n + w * 0.7 + rng.uniform(-0.3, 0.3)
            d = Vector((math.cos(a), math.sin(a), rng.uniform(0.05, 0.25)))
            pts = curve(rng, Vector((0, 0, z)), d, length, 4, 0.08, droop=0.55)
            dead = rng.random() < dead_frac * (1.3 - t)
            tube(bm, cl, pts[:3], [0.05, 0.035, 0.02], bark_cols(3, rng=rng), sides=4)
            needle_fan(bm, cl, rng, pts, length * 0.32, (0.3, 0.2, 0.09) if dead else rng.choice(NEEDLES), dead)
    # Ponta: lâminas em cruz formando um espigão.
    tip = tpts[-1]
    for k in range(4):
        a = k * math.tau / 4
        side = Vector((math.cos(a), math.sin(a), 0))
        b = tip - Vector((0, 0, height * 0.12))
        face(bm, cl, [V(bm, b + side * height * 0.06), V(bm, tip + Vector((0, 0, 0.3))), V(bm, b - side * 0.02)],
             [NEEDLES[0], NEEDLES[2], NEEDLES[0]])
    return finish(name, bm)


def build_pine_dry_a():
    return build_pine("pine_dry_a", 5, 8.0, 0.18)


def build_pine_dry_b():
    return build_pine("pine_dry_b", 23, 8.5, 0.4)


# ------------------------------------------------------------------ mortas

def build_dead(name, seed, height, burnt):
    rng = random.Random(seed)
    bm, cl = new_bm()
    dark, light = (CHAR, lerp3(CHAR, ASH, 0.5)) if burnt else ((0.14, 0.12, 0.1), (0.42, 0.39, 0.34))
    tpts = curve(rng, Vector((0, 0, -0.15)), Vector((rng.uniform(-0.25, 0.25), rng.uniform(-0.2, 0.2), 1)),
                 height * 0.55, 5, 0.14, up_bias=0.1)
    r0 = 0.32 * height / 6
    tube(bm, cl, tpts, [r0 * (1 - 0.55 * i / (len(tpts) - 1)) for i in range(len(tpts))],
         bark_cols(len(tpts), dark, light, rng), sides=7, rng=rng)
    for k in range(4):
        a = k * math.tau / 4 + rng.uniform(-0.3, 0.3)
        rp = [Vector((0, 0, 0.3)), Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, 0.0)),
              Vector((math.cos(a) * 0.9, math.sin(a) * 0.9, -0.12))]
        tube(bm, cl, rp, [r0 * 0.55, r0 * 0.3, 0.03], bark_cols(3, dark, light, rng), sides=5)

    def branch(start, d, length, r, depth):
        pts = curve(rng, start, d, length, 4, 0.3, up_bias=0.1)
        cols = bark_cols(5, lerp3(dark, light, 0.4), ASH if burnt else light, rng)
        tube(bm, cl, pts, [r, r * 0.75, r * 0.55, r * 0.35, r * 0.15], cols, sides=5 if depth > 1 else 4)
        if depth == 0:
            return
        for _ in range(rng.randint(1, 3)):
            t = rng.uniform(0.4, 0.95)
            idx = min(len(pts) - 2, int(t * (len(pts) - 1)))
            nd = rot((pts[-1] - pts[0]).normalized(), Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0.3)).normalized(),
                     math.radians(rng.uniform(25, 60)))
            branch(pts[idx], nd, length * rng.uniform(0.5, 0.7), r * 0.55, depth - 1)

    for i in range(4 if burnt else 5):
        a = i * math.tau / 5 + rng.uniform(-0.5, 0.5)
        el = math.radians(rng.uniform(25, 65))
        d = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
        branch(tpts[-1 - (i % 3)], d, height * rng.uniform(0.3, 0.42), r0 * 0.45, 2 if not burnt else 1)
    if burnt:
        # Tronco partido no alto: ponta lascada.
        top = tpts[-1]
        for k in range(5):
            a = k * math.tau / 5
            side = Vector((math.cos(a), math.sin(a), 0)) * r0 * 0.45
            face(bm, cl, [V(bm, top + side), V(bm, top + rot(side, Vector((0, 0, 1)), 1.25)),
                          V(bm, top + side * 0.3 + Vector((0, 0, rng.uniform(0.2, 0.6))))], [CHAR, CHAR, ASH])
    return finish(name, bm)


def build_tree_dead_a():
    return build_dead("tree_dead_a", 7, 6.5, False)


def build_tree_dead_b():
    return build_dead("tree_dead_b", 19, 5.5, True)


BUILDERS = {"tree_dry_a": build_tree_dry_a, "tree_dry_b": build_tree_dry_b, "pine_dry_a": build_pine_dry_a,
            "pine_dry_b": build_pine_dry_b, "tree_dead_a": build_tree_dead_a, "tree_dead_b": build_tree_dead_b}


def to_linear_for_preview():
    """No jogo a cor por vértice é sRGB (o importador converte); na prévia do Cycles convertemos aqui."""
    f = lambda x: x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    for me in bpy.data.meshes:
        a = me.color_attributes.get("Col")
        if a:
            for d in a.data:
                c = d.color
                d.color = (f(c[0]), f(c[1]), f(c[2]), c[3])


def render_lineup(out_png):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    names = list(BUILDERS)
    for i, n in enumerate(names):
        o = BUILDERS[n]()
        o.location = (i * 4.6 - 2.5 * 4.6, 3, 0)
    to_linear_for_preview()
    sc = bpy.context.scene
    g = bpy.data.meshes.new("ground")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=20)
    bm.to_mesh(g)
    gm = bpy.data.materials.new("dirt")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.07, 0.05, 0.025, 1)
    g.materials.append(gm)
    sc.collection.objects.link(bpy.data.objects.new("ground", g))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 30
    sc.collection.objects.link(cam)
    cam.location = (0, -21, 15)
    cam.rotation_euler = Euler((math.radians(58), 0, 0))
    sc.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = Euler((math.radians(45), math.radians(10), math.radians(-35)))
    sc.collection.objects.link(sun)
    sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.22, 0.24, 0.27, 1)
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 32
    sc.render.resolution_x, sc.render.resolution_y = 1600, 800
    sc.render.filepath = out_png
    bpy.ops.render.render(write_still=True)
    print("prévia:", out_png)


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
        bpy.ops.wm.read_factory_settings(use_empty=True)
        BUILDERS[n]()
        bg.export(os.path.join(out, n + ".glb"))
    if render_dir:
        os.makedirs(render_dir, exist_ok=True)
        render_lineup(os.path.join(render_dir, "trees.png"))


if __name__ == "__main__":
    main()
