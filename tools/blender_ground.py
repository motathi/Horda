"""Vegetação do chão modelada no Blender (bpy) para o MultiMesh do jogo (scripts/world/foliage.gd).

gc_*.glb (vegetação rasteira do chão, para o DecorScatter do world_builder): arbusto seco, samambaia morta,
  cardo com flor murcha, erva rasteira, bardana de folha larga, capim alto com espigas, folhas secas caídas e
  galho caído — tudo com cor por vértice e material de duas faces (sem textura).

grass_tufts.glb: três touceiras de capim seco, cada uma um objeto ("tuft_a", "tuft_b", "tuft_c"),
  folhas finas e curvas (3 triângulos por folha) com cor por vértice — base oliva escura,
  ponta cor de palha ou de capim morto — lidas pelo shader assets/effects/shaders/grass_mesh.gdshader
  (vento pela altura do vértice). Muito leves: dezenas de milhares no mapa.

Uso (módulo `bpy` do PyPI ou Blender):
  python3 tools/blender_ground.py assets/models/blender [nome ...] [--render pasta]
"""
import math
import os
import random
import sys

import bpy  # noqa: I001
import bmesh
from mathutils import Euler, Matrix, Quaternion, Vector


def srgb(c):
    f = lambda x: x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    return tuple(f(x) for x in c)


def lerp3(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


BASE = (0.13, 0.13, 0.06)        # pé da touceira, quase na sombra
MID = (0.3, 0.29, 0.14)          # meio da folha, oliva seco
TIPS = [(0.55, 0.5, 0.29), (0.5, 0.45, 0.25), (0.47, 0.35, 0.19), (0.58, 0.53, 0.36)]  # palha / morto / descorado


def blade(bm, col_layer, root, yaw, length, width, lean, curl, rng, tip_col, broken=False):
    """Folha: tira afinando em 2 segmentos + ponta (3 triângulos), curvando para fora."""
    d = Vector((math.cos(yaw), math.sin(yaw), 0.0))
    side = Vector((-d.y, d.x, 0.0))
    pts = []
    for t in (0.0, 0.45, 1.0):
        bend = lean + curl * t
        if broken and t > 0.5:
            bend = math.radians(105)  # quebrada: a parte de cima tomba para fora
        # Altura e afastamento ao longo de um arco.
        p = root + d * (math.sin(bend) * length * t) + Vector((0, 0, math.cos(bend) * length * t))
        pts.append(p)
    w = [width, width * 0.7, 0.0]
    cols = [BASE, lerp3(MID, tip_col, 0.35), tip_col]
    v = []
    for i, p in enumerate(pts):
        if w[i] > 0:
            v.append((bm.verts.new(p - side * w[i] * 0.5), cols[i]))
            v.append((bm.verts.new(p + side * w[i] * 0.5), cols[i]))
        else:
            v.append((bm.verts.new(p), cols[i]))
    faces = [(v[0], v[1], v[3], v[2]), (v[2], v[3], v[4])]
    for f in faces:
        face = bm.faces.new([x[0] for x in f])
        for loop, (_, c) in zip(face.loops, f):
            # Cor em sRGB direto: o exportador + o importador do Godot já convertem para linear.
            loop[col_layer] = (*c, 1.0)


def make_tuft(name, rng, n_blades, h_range, w_range, lean_range, broken_frac, dead_bias, spread=0.12, seed_heads=0):
    bm = bmesh.new()
    col = bm.loops.layers.float_color.new("Col")
    for i in range(n_blades):
        yaw = i * math.tau / n_blades + rng.uniform(-0.5, 0.5)
        r = rng.uniform(0.0, spread)
        root = Vector((math.cos(yaw) * r, math.sin(yaw) * r, 0.0))
        length = rng.uniform(*h_range)
        tip = TIPS[min(len(TIPS) - 1, int(rng.random() * len(TIPS) * (0.6 + dead_bias)))]
        blade(bm, col, root, yaw, length, rng.uniform(*w_range), math.radians(rng.uniform(*lean_range)),
              math.radians(rng.uniform(15, 35)), rng, tip, broken=rng.random() < broken_frac)
    # Espigas: haste fina e reta com a cabeça mais clara.
    for k in range(seed_heads):
        yaw = rng.uniform(0, math.tau)
        root = Vector((rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), 0))
        blade(bm, col, root, yaw, rng.uniform(0.75, 0.95), 0.025, math.radians(rng.uniform(5, 14)), math.radians(6), rng,
              (0.66, 0.6, 0.42))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.color_attributes.active_color = me.color_attributes["Col"]
    me.color_attributes.render_color_index = me.color_attributes.active_color_index
    for p in me.polygons:
        p.use_smooth = True
    m = bpy.data.materials.get("grass") or bpy.data.materials.new("grass")
    m.use_nodes = True
    nt = m.node_tree
    if not nt.nodes.get("ColAttr"):
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.name = "ColAttr"
        attr.layer_name = "Col"
        nt.links.new(attr.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
        nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def build_grass_tufts():
    rng = random.Random(9)
    # a: touceira média e cheia.
    make_tuft("tuft_a", rng, 12, (0.3, 0.55), (0.07, 0.1), (20, 50), 0.12, 0.2, spread=0.16)
    # b: capim alto e ralo com espigas.
    make_tuft("tuft_b", rng, 9, (0.5, 0.85), (0.06, 0.08), (12, 36), 0.15, 0.3, spread=0.12, seed_heads=3)
    # c: touceira baixa, mais morta, com folhas quebradas tombadas.
    make_tuft("tuft_c", rng, 10, (0.2, 0.4), (0.07, 0.1), (35, 65), 0.45, 0.8, spread=0.2)
    for i, o in enumerate(o for o in bpy.context.scene.objects if o.type == "MESH"):
        o.location = (i * 1.2 - 1.2, 0, 0)  # lado a lado no arquivo; o jogo usa só a malha


# ---------------------------------------------------------------- vegetação rasteira (gc_*)

BARK = (0.3, 0.26, 0.2)
BARK_DARK = (0.16, 0.13, 0.1)
DEAD_LEAVES = [(0.36, 0.22, 0.1), (0.5, 0.31, 0.13), (0.22, 0.14, 0.08), (0.55, 0.45, 0.26), (0.42, 0.36, 0.28)]
DUSTY_GREEN = (0.24, 0.26, 0.14)
YELLOWED = (0.48, 0.42, 0.22)


def face(bm, cl, verts, cols):
    f = bm.faces.new(verts)
    for loop, c in zip(f.loops, cols):
        loop[cl] = (*c, 1.0)
    return f


def V(bm, p):
    return bm.verts.new(p)


def stick(bm, cl, a, b, ra, rb, ca=BARK_DARK, cb=BARK):
    """Galho: prisma triangular afinando de a até b (6 triângulos)."""
    axis = (b - a).normalized()
    ref = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
    u = axis.cross(ref).normalized()
    v = axis.cross(u)
    ring = lambda c, r: [V(bm, c + (u * math.cos(k * math.tau / 3) + v * math.sin(k * math.tau / 3)) * r) for k in range(3)]
    A, B = ring(a, ra), ring(b, rb)
    for k in range(3):
        face(bm, cl, [A[k], A[(k + 1) % 3], B[(k + 1) % 3], B[k]], [ca, ca, cb, cb])


def leaf(bm, cl, base, yaw, length, width, pitch, col, tip_col=None, fold=0.35, droop=0.0):
    """Folha dobrada na nervura (4 triângulos): base, lados, meio levantado e ponta."""
    d = Vector((math.cos(yaw) * math.cos(pitch), math.sin(yaw) * math.cos(pitch), math.sin(pitch)))
    side = Vector((-math.sin(yaw), math.cos(yaw), 0))
    up = side.cross(d).normalized()
    tip_col = tip_col or col
    dark = lerp3(col, (0.08, 0.06, 0.04), 0.35)
    b = V(bm, base)
    mid = V(bm, base + d * length * 0.5 + up * width * fold * 0.4)
    l = V(bm, base + d * length * 0.42 + side * width * 0.5 - up * width * fold * 0.25)
    r = V(bm, base + d * length * 0.42 - side * width * 0.5 - up * width * fold * 0.25)
    t = V(bm, base + d * length - Vector((0, 0, droop)))
    face(bm, cl, [b, l, mid], [dark, col, col])
    face(bm, cl, [b, mid, r], [dark, col, col])
    face(bm, cl, [mid, l, t], [col, col, tip_col])
    face(bm, cl, [mid, t, r], [col, tip_col, col])


def spiky_leaf(bm, cl, base, yaw, length, width, pitch, col, tip_col, lobes=3, droop=0.0):
    """Folha de cardo: nervura com lóbulos pontudos dos dois lados."""
    d = Vector((math.cos(yaw) * math.cos(pitch), math.sin(yaw) * math.cos(pitch), math.sin(pitch)))
    side = Vector((-math.sin(yaw), math.cos(yaw), 0))
    pts = []
    for i in range(lobes + 2):
        t = i / (lobes + 1)
        pts.append(base + d * length * t - Vector((0, 0, droop * t * t)))
    cols = [lerp3(col, tip_col, i / (lobes + 1)) for i in range(lobes + 2)]
    for i in range(lobes + 1):
        a, b = pts[i], pts[i + 1]
        t = (i + 0.5) / (lobes + 1)
        w = width * math.sin(math.pi * min(0.95, t + 0.1))
        for sgn in (1, -1):
            tip = (a + b) * 0.5 + side * w * sgn + d * length * 0.08 + Vector((0, 0, w * 0.25))
            face(bm, cl, [V(bm, a), V(bm, b), V(bm, tip)], [cols[i], cols[i + 1], tip_col])


def rot(v, axis, ang):
    return Quaternion(axis, ang) @ v


def finish(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.color_attributes.active_color = me.color_attributes["Col"]
    me.color_attributes.render_color_index = me.color_attributes.active_color_index
    for p in me.polygons:
        p.use_smooth = True
    m = bpy.data.materials.get("gc") or bpy.data.materials.new("gc")
    m.use_nodes = True
    m.use_backface_culling = False
    nt = m.node_tree
    if not nt.nodes.get("ColAttr"):
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.name = "ColAttr"
        attr.layer_name = "Col"
        nt.links.new(attr.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
        nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.92
    me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    dims = o.dimensions
    print(f"  {name}: {len(me.polygons)} faces, {dims.x:.2f} x {dims.y:.2f} x {dims.z:.2f} m")
    return o


def new_bm():
    bm = bmesh.new()
    return bm, bm.loops.layers.float_color.new("Col")


def build_dry_bush():
    """Arbusto morto: galhos finos ramificados, com poucas folhas secas presas nas pontas."""
    rng = random.Random(21)
    bm, cl = new_bm()

    def branch(p, dv, length, r, depth):
        end = p + dv * length
        stick(bm, cl, p, end, r, r * 0.55, lerp3(BARK_DARK, BARK, 0.3 * (2 - depth)), BARK)
        if depth == 0:
            for _ in range(rng.randint(2, 4)):
                c = rng.choice(DEAD_LEAVES[:4] + [lerp3(DUSTY_GREEN, YELLOWED, 0.5)])
                q = p + (end - p) * rng.uniform(0.5, 1.0)
                leaf(bm, cl, q, rng.uniform(0, math.tau), rng.uniform(0.07, 0.11), rng.uniform(0.04, 0.06),
                     math.radians(rng.uniform(-30, 30)), c, lerp3(c, (0.6, 0.5, 0.32), 0.3))
            return
        for _ in range(2 if depth == 1 else rng.randint(2, 3)):
            ax = dv.cross(Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0.2))).normalized()
            nd = rot(dv, ax, math.radians(rng.uniform(22, 42)))
            nd = (nd + Vector((0, 0, 0.15))).normalized()
            branch(p + (end - p) * rng.uniform(0.6, 1.0), nd, length * rng.uniform(0.6, 0.75), r * 0.6, depth - 1)

    n = 7
    for i in range(n):
        yaw = i * math.tau / n + rng.uniform(-0.4, 0.4)
        el = math.radians(rng.uniform(45, 75))
        dv = Vector((math.cos(yaw) * math.cos(el), math.sin(yaw) * math.cos(el), math.sin(el)))
        branch(Vector((rng.uniform(-0.04, 0.04), rng.uniform(-0.04, 0.04), 0)), dv, rng.uniform(0.38, 0.5), 0.022, 2)
    return finish("gc_dry_bush", bm)


def build_dead_fern():
    """Samambaia morta: frondes arqueadas cor de ferrugem, folíolos em pares que encolhem na ponta."""
    rng = random.Random(5)
    bm, cl = new_bm()
    fern_cols = [(0.42, 0.24, 0.11), (0.33, 0.2, 0.1), (0.5, 0.33, 0.16), (0.36, 0.33, 0.25)]
    n = 9
    for i in range(n):
        yaw = i * math.tau / n + rng.uniform(-0.3, 0.3)
        length = rng.uniform(0.55, 0.8)
        col = rng.choice(fern_cols)
        tip = lerp3(col, (0.62, 0.5, 0.33), 0.45)
        base_col = lerp3(col, (0.12, 0.09, 0.05), 0.5)
        a0, a1 = math.radians(rng.uniform(60, 78)), math.radians(rng.uniform(-40, -15))
        d_h = Vector((math.cos(yaw), math.sin(yaw), 0))
        side = Vector((-math.sin(yaw), math.cos(yaw), 0))
        segs = 7
        p = Vector((0, 0, 0))
        pts = [p.copy()]
        for k in range(segs):
            t = (k + 0.5) / segs
            ang = a0 + (a1 - a0) * t
            p = p + (d_h * math.cos(ang) + Vector((0, 0, math.sin(ang)))) * (length / segs)
            pts.append(p.copy())
        for k in range(segs):
            t0, t1 = k / segs, (k + 1) / segs
            c0, c1 = lerp3(base_col, tip, t0), lerp3(base_col, tip, t1)
            w0, w1 = 0.012 * (1 - t0) + 0.003, 0.012 * (1 - t1) + 0.003
            face(bm, cl, [V(bm, pts[k] - side * w0), V(bm, pts[k] + side * w0), V(bm, pts[k + 1] + side * w1),
                          V(bm, pts[k + 1] - side * w1)], [c0, c0, c1, c1])
            if k == 0:
                continue
            lf = length * (0.22 * math.sin(math.pi * min(1.0, t0 * 1.1)) + 0.03)
            fwd = (pts[k + 1] - pts[k]).normalized()
            for sgn in (1, -1):
                tipp = pts[k] + side * sgn * lf + fwd * lf * 0.45 - Vector((0, 0, lf * 0.35))
                cc = lerp3(col, tip, t0 + 0.2) if rng.random() > 0.15 else (0.2, 0.13, 0.08)
                face(bm, cl, [V(bm, pts[k]), V(bm, pts[k] + fwd * lf * 0.5), V(bm, tipp)], [c0, cc, cc])
    return finish("gc_dead_fern", bm)


def build_thistle():
    """Cardo seco: roseta de folhas espinhosas, hastes com cabeças bulbosas e flor roxa desbotada ou já em pluma."""
    rng = random.Random(13)
    bm, cl = new_bm()
    g, t = (0.3, 0.32, 0.22), (0.47, 0.42, 0.29)
    for i in range(7):
        yaw = i * math.tau / 7 + rng.uniform(-0.3, 0.3)
        spiky_leaf(bm, cl, Vector((0, 0, 0.02)), yaw, rng.uniform(0.28, 0.38), 0.09, math.radians(rng.uniform(12, 30)),
                   g, t, lobes=3, droop=0.06)
    for s in range(3):
        yaw = s * math.tau / 3 + rng.uniform(-0.5, 0.5)
        h = rng.uniform(0.6, 0.9)
        top = Vector((math.cos(yaw) * h * 0.18, math.sin(yaw) * h * 0.18, h))
        base = Vector((math.cos(yaw) * 0.03, math.sin(yaw) * 0.03, 0))
        stick(bm, cl, base, top, 0.012, 0.008, (0.25, 0.25, 0.16), (0.42, 0.38, 0.26))
        for k in range(2):
            q = base + (top - base) * (0.3 + 0.25 * k)
            spiky_leaf(bm, cl, q, yaw + math.pi * k + rng.uniform(-0.5, 0.5), 0.13, 0.045, math.radians(25), g, t, lobes=2)
        # Cabeça: bulbo baixo (icosfera achatada) com brácteas e o topo de flor.
        r = rng.uniform(0.04, 0.055)
        res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r,
                                         matrix=Matrix.Translation(top) @ Matrix.Diagonal((1, 1, 0.8, 1)))
        fs = {f for v in res["verts"] for f in v.link_faces}
        for f in fs:
            for loop in f.loops:
                z = (loop.vert.co.z - top.z) / r
                loop[cl] = (*lerp3((0.22, 0.2, 0.13), (0.42, 0.38, 0.25), z * 0.5 + 0.5), 1.0)
        seeded = s == 2
        fc = (0.72, 0.68, 0.6) if seeded else (0.44, 0.3, 0.4)
        fb = lerp3(fc, (0.2, 0.15, 0.15), 0.4)
        c = top + Vector((0, 0, r * 0.6))
        for k in range(7):
            a = k * math.tau / 7
            spread = (0.07 if seeded else 0.035)
            pa = c + Vector((math.cos(a) * r * 0.5, math.sin(a) * r * 0.5, 0))
            pb = c + Vector((math.cos(a + 0.45) * r * 0.5, math.sin(a + 0.45) * r * 0.5, 0))
            pt = c + Vector((math.cos(a + 0.22) * spread, math.sin(a + 0.22) * spread, 0.06 if seeded else 0.045))
            face(bm, cl, [V(bm, pa), V(bm, pb), V(bm, pt)], [fb, fb, fc])
    return finish("gc_thistle", bm)


def build_weed_rosette():
    """Erva rasteira: roseta de folhas largas deitadas no chão, verde-poeira amarelando nas pontas."""
    rng = random.Random(8)
    bm, cl = new_bm()
    for ring, (n, lr, pr) in enumerate(((7, (0.16, 0.22), (4, 14)), (5, (0.1, 0.14), (25, 40)))):
        for i in range(n):
            yaw = i * math.tau / n + ring * 0.4 + rng.uniform(-0.25, 0.25)
            c = lerp3(DUSTY_GREEN, YELLOWED, rng.uniform(0.0, 0.5)) if rng.random() > 0.2 else DEAD_LEAVES[0]
            leaf(bm, cl, Vector((0, 0, 0.01 + ring * 0.01)), yaw, rng.uniform(*lr), rng.uniform(0.07, 0.1),
                 math.radians(rng.uniform(*pr)), c, lerp3(c, YELLOWED, 0.6), fold=0.3, droop=0.02)
    return finish("gc_weed_rosette", bm)


def build_burdock():
    """Bardana: folhas grandes e onduladas em pecíolos, verde escuro empoeirado com bordas queimadas."""
    rng = random.Random(4)
    bm, cl = new_bm()
    n = 6
    for i in range(n):
        yaw = i * math.tau / n + rng.uniform(-0.35, 0.35)
        L = rng.uniform(0.35, 0.48)
        W = L * 0.62
        el = math.radians(rng.uniform(40, 60))
        d = Vector((math.cos(yaw), math.sin(yaw), 0))
        side = Vector((-math.sin(yaw), math.cos(yaw), 0))
        pet_end = d * math.cos(el) * 0.18 + Vector((0, 0, math.sin(el) * 0.18 + 0.02))
        stick(bm, cl, Vector((0, 0, 0)), pet_end, 0.012, 0.008, (0.2, 0.16, 0.12), (0.3, 0.28, 0.17))
        center = lerp3((0.17, 0.2, 0.1), (0.3, 0.31, 0.16), rng.random())
        edge = rng.choice([(0.38, 0.28, 0.14), (0.45, 0.38, 0.2), (0.3, 0.2, 0.1)])
        U, Vn = 5, 3
        grid = []
        for ui in range(U + 1):
            u = ui / U
            w = W * 0.5 * math.sin(math.pi * (u * 0.85 + 0.12)) ** 0.8
            row = []
            for vi in range(Vn):
                v = vi / (Vn - 1) * 2 - 1
                z = 0.12 * u - 0.32 * L * u * u + 0.025 * math.sin(v * 3.0 + u * 7.0) - 0.03 * abs(v)
                p = pet_end + d * u * L + side * v * w + Vector((0, 0, z))
                row.append((V(bm, p), lerp3(center, edge, min(1.0, abs(v) * 0.7 + u * u * 0.5))))
            grid.append(row)
        for ui in range(U):
            for vi in range(Vn - 1):
                q = [grid[ui][vi], grid[ui][vi + 1], grid[ui + 1][vi + 1], grid[ui + 1][vi]]
                face(bm, cl, [x[0] for x in q], [x[1] for x in q])
    return finish("gc_burdock", bm)


def build_tall_grass():
    """Capim alto: touceira densa de folhas longas com espigas de rabo-de-raposa."""
    rng = random.Random(17)
    make_tuft("gc_tall_grass", rng, 18, (0.6, 1.0), (0.045, 0.06), (6, 26), 0.12, 0.4, spread=0.14, seed_heads=6)
    return bpy.data.objects["gc_tall_grass"]


def build_leaf_litter():
    """Folhas secas caídas: um punhado espalhado rente ao chão, curvadas, em marrons, ferrugem e palha."""
    rng = random.Random(30)
    bm, cl = new_bm()
    litter = [(0.4, 0.2, 0.08), (0.52, 0.27, 0.09), (0.2, 0.12, 0.06), (0.56, 0.42, 0.2), (0.32, 0.17, 0.08),
              (0.45, 0.36, 0.26)]
    for i in range(30):
        a, r = rng.uniform(0, math.tau), 0.6 * math.sqrt(rng.random())
        c = rng.choice(litter)
        leaf(bm, cl, Vector((math.cos(a) * r, math.sin(a) * r, rng.uniform(0.004, 0.035))), rng.uniform(0, math.tau),
             rng.uniform(0.16, 0.24), rng.uniform(0.09, 0.13), math.radians(rng.uniform(-4, 10)), c,
             lerp3(c, (0.15, 0.1, 0.06), 0.4), fold=rng.uniform(0.3, 0.7), droop=0.01)
    stick(bm, cl, Vector((-0.3, -0.1, 0.012)), Vector((0.25, 0.12, 0.01)), 0.008, 0.005)
    return finish("gc_leaf_litter", bm)


def build_fallen_branch():
    """Galho caído: tronco fino deitado e torto, com forquilhas e umas folhas mortas."""
    rng = random.Random(41)
    bm, cl = new_bm()
    pts = [Vector((-0.6, 0, 0.03)), Vector((-0.2, 0.05, 0.05)), Vector((0.2, -0.04, 0.045)), Vector((0.6, 0.03, 0.025))]
    rads = [0.035, 0.03, 0.024, 0.016]
    grey = (0.36, 0.32, 0.26)
    for k in range(3):
        stick(bm, cl, pts[k], pts[k + 1], rads[k], rads[k + 1], lerp3(BARK_DARK, grey, 0.5), grey)
    for k, (yaw, ln) in enumerate(((0.7, 0.32), (-0.9, 0.25), (0.5, 0.2))):
        a = pts[k + 1] if k < 2 else pts[2]
        b = a + Vector((math.cos(yaw) * ln, math.sin(yaw) * ln, rng.uniform(0.02, 0.1)))
        stick(bm, cl, a, b, rads[k + 1] * 0.6, 0.006, lerp3(BARK_DARK, grey, 0.4), grey)
        for _ in range(2):
            c = rng.choice(DEAD_LEAVES)
            leaf(bm, cl, a + (b - a) * rng.uniform(0.5, 1), rng.uniform(0, math.tau), 0.1, 0.06,
                 math.radians(rng.uniform(-15, 10)), c)
    return finish("gc_fallen_branch", bm)


BUILDERS = {"grass_tufts": build_grass_tufts, "gc_dry_bush": build_dry_bush, "gc_dead_fern": build_dead_fern,
            "gc_thistle": build_thistle, "gc_weed_rosette": build_weed_rosette, "gc_burdock": build_burdock,
            "gc_tall_grass": build_tall_grass, "gc_leaf_litter": build_leaf_litter,
            "gc_fallen_branch": build_fallen_branch}


def render_lineup(names, out_png):
    """Prévia de todas as plantas lado a lado sobre terra."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    for i, n in enumerate(names):
        o = BUILDERS[n]()
        o.location = ((i % 4) * 1.9 - 2.85, (i // 4) * 1.9 - 0.4, 0)
    render_patch(out_png, scatter=False, cam=((0, -5.6, 4.6), 50, 32))


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
                              export_vertex_color="NAME", export_vertex_color_name="Col", export_all_vertex_colors=False)
    print("exportado:", path)


def render_patch(out_png, scatter=True, cam=((0, -6.5, 5.5), 52, 35)):
    """Prévia: um canteiro de 6×6 m com as touceiras espalhadas ao acaso, vista de cima inclinada."""
    sc = bpy.context.scene
    tufts = [o for o in sc.objects if o.type == "MESH"]
    rng = random.Random(3)
    for i in range(380 if scatter else 0):
        src = rng.choice(tufts)
        c = bpy.data.objects.new("inst", src.data)
        c.location = (rng.uniform(-3, 3), rng.uniform(-3, 3), 0)
        c.rotation_euler = Euler((0, 0, rng.uniform(0, math.tau)))
        s = rng.uniform(0.8, 1.3)
        c.scale = (s, s, s)
        sc.collection.objects.link(c)
    for t in tufts:
        t.hide_render = scatter
    g = bpy.data.meshes.new("ground")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=8)
    bm.to_mesh(g)
    gm = bpy.data.materials.new("dirt")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*srgb((0.3, 0.26, 0.16)), 1)
    g.materials.append(gm)
    sc.collection.objects.link(bpy.data.objects.new("ground", g))
    loc, tilt, lens = cam
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = lens
    sc.collection.objects.link(cam)
    cam.location = loc
    cam.rotation_euler = Euler((math.radians(tilt), 0, 0))
    sc.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = Euler((math.radians(50), math.radians(10), math.radians(-35)))
    sc.collection.objects.link(sun)
    sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (*srgb((0.5, 0.52, 0.55)), 1)
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.7
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 32
    sc.render.resolution_x, sc.render.resolution_y = 1200, 800
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
    if names == ["lineup"]:
        render_lineup([n for n in BUILDERS if n.startswith("gc_")], os.path.join(render_dir or out, "ground_cover.png"))
        return
    for n in names:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        BUILDERS[n]()
        export(os.path.join(out, n + ".glb"))
        if render_dir and n == "grass_tufts":
            os.makedirs(render_dir, exist_ok=True)
            render_patch(os.path.join(render_dir, n + ".png"))


if __name__ == "__main__":
    main()
