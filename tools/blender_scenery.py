"""Objetos de cenário pós-apocalípticos modelados à mão no Blender (bpy), com texturas
procedurais assadas num atlas (mesmo pipeline de tools/blender_defenses.py).

Uso (módulo `bpy` do PyPI ou Blender):
  python3 tools/blender_scenery.py assets/models/blender [nome ...] [--render pasta]
Convenção: comprimento no eixo Y do Blender (vira Z no jogo), topo em +Z, origem no chão.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402,I001
import bmesh  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402

import blender_defenses as bd  # noqa: E402

srgb = bd.srgb


def loft(name, sections, mat, cap=True):
    """Superfície por seções transversais (listas de Vector com o mesmo número de pontos)."""
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in sec] for sec in sections]
    n = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    if cap:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bd.obj_from_bm(name, bm, mat, 1)


def dents(o, rng, count=10, radius=0.35, depth=0.06):
    """Amassados: empurra os vértices para dentro em volta de pontos aleatórios da superfície."""
    me = o.data
    verts = me.vertices
    centers = [verts[rng.randrange(len(verts))].co.copy() for _ in range(count)]
    center_of_mass = sum((v.co for v in verts), Vector()) / len(verts)
    for v in verts:
        for c in centers:
            d = (v.co - c).length
            if d < radius:
                inward = (center_of_mass - v.co).normalized()
                v.co += inward * depth * (1 - d / radius) ** 2


def cylinder(name, r, depth, mat, segs=12):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=depth)
    return bd.obj_from_bm(name, bm, mat, 1)


def slab_box(name, size, mat):
    return bd.box(name, size, mat, 1)


def world_rotate_all(rot_deg, pivot=Vector((0, 0, 0))):
    R = Euler([math.radians(a) for a in rot_deg]).to_matrix().to_4x4()
    T = Matrix.Translation(pivot)
    bpy.context.view_layer.update()  # matrix_world só reflete location/rotation depois disso
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.matrix_world = T @ R @ T.inverted() @ o.matrix_world


# --- Materiais ----------------------------------------------------------------------------

def mat_car_paint(name, paint):
    """Pintura desbotada que vira ferrugem e carvão onde o carro queimou."""
    m, nt, bsdf = bd._mat(name)
    faded = bd._ramp(nt, bd._noise(nt, 8.0, 5.0, 0.5), [(0.3, tuple(c * 0.7 for c in paint)), (0.7, paint)])
    burn = bd._noise(nt, 1.6, 6.0, 0.65)
    rustc = bd._ramp(nt, bd._noise(nt, 12.0, 8.0, 0.7), [(0.3, (0.12, 0.07, 0.045)), (0.6, (0.29, 0.15, 0.08))])
    rust_mask = bd._ramp(nt, burn, [(0.4, (0, 0, 0)), (0.5, (1, 1, 1))])
    c = bd._mix(nt, rust_mask, faded, rustc)
    char_mask = bd._ramp(nt, burn, [(0.5, (0, 0, 0)), (0.58, (1, 1, 1))])
    char = bd._ramp(nt, bd._noise(nt, 30.0, 6.0, 0.7), [(0.3, (0.025, 0.022, 0.02)), (0.7, (0.09, 0.08, 0.07))])
    c = bd._mix(nt, char_mask, c, char)
    streak = bd._ramp(nt, bd._noise(nt, 3.0, 4.0, 0.5, bd._coords(nt, (12.0, 12.0, 0.7))),
                      [(0.45, (1, 1, 1)), (0.7, (0.45, 0.28, 0.18))])
    c = bd._mix(nt, 0.9, c, streak, "MULTIPLY")
    # Sangue escorrido (mão arrastada) em manchas pequenas.
    blood = bd._ramp(nt, bd._noise(nt, 5.0, 3.0, 0.5, bd._coords(nt, (2.0, 2.0, 6.0))), [(0.7, (0, 0, 0)), (0.73, (1, 1, 1))])
    c = bd._mix(nt, blood, c, (0.22, 0.03, 0.02))
    nt.links.new(bd._height_dirt(nt, c), bsdf.inputs["Base Color"])
    return m


def mat_char():
    m, nt, bsdf = bd._mat("charred")
    c = bd._ramp(nt, bd._noise(nt, 20.0, 8.0, 0.7), [(0.3, (0.03, 0.028, 0.026)), (0.6, (0.1, 0.09, 0.08)),
                                                     (0.8, (0.2, 0.18, 0.16))])
    nt.links.new(c, bsdf.inputs["Base Color"])
    return m


def mat_rubber():
    return bd.mat_flat("rubber", (0.07, 0.07, 0.07))


def mat_glass():
    """Vidro escuro sujo, trincado (as trincas claras ficam visíveis de longe)."""
    m, nt, bsdf = bd._mat("glass_dirty")
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 7.0
    vor.inputs["Scale"].default_value = 11.0
    vor.inputs["Randomness"].default_value = 1.0
    cracks = bd._ramp(nt, vor.outputs["Distance"], [(0.0, (0.2, 0.22, 0.22)), (0.015, (0.07, 0.08, 0.085)), (1.0, (0.1, 0.11, 0.12))])
    grime = bd._ramp(nt, bd._noise(nt, 6.0, 6.0, 0.6), [(0.35, (0.5, 0.45, 0.4)), (0.7, (1, 1, 1))])
    cracks = bd._mix(nt, 1.0, cracks, grime, "MULTIPLY")
    nt.links.new(cracks, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.3
    return m


# --- Carro destruído ----------------------------------------------------------------------

def build_car(paint, seed):
    rng = random.Random(seed)
    paint_m = mat_car_paint("car_paint", paint)
    char = mat_char()
    rubber = mat_rubber()
    rust = bd.mat_rust()
    glass = mat_glass()
    blood = bd.mat_flat("blood", (0.2, 0.025, 0.02))
    L, W = 4.0, 1.78
    hw = W / 2

    def body_section(y):
        t = (y + L / 2) / L  # 0 frente .. 1 traseira
        end = min(t, 1 - t)
        taper = min(1.0, end / 0.12)
        w = hw * (0.88 + 0.12 * taper)
        top = 0.93 - 0.14 * (1 - min(1.0, t / 0.18)) - 0.06 * (1 - min(1.0, (1 - t) / 0.1))
        bot = 0.34 + 0.06 * (1 - taper)
        belt = bot + (top - bot) * 0.55
        # Caixas de roda: a lateral sobe num arco em volta de cada eixo.
        for wy in (-1.25, 1.25):
            d = abs(y - wy)
            if d < 0.46:
                bot = max(bot, 0.3 + math.sqrt(max(0.0, 0.46 ** 2 - d * d)) * 0.95)
        pts = [(-w * 0.94, bot), (w * 0.94, bot), (w, bot + 0.1), (w * 1.02, belt), (w * 0.97, top - 0.05),
               (w * 0.85, top), (-w * 0.85, top), (-w * 0.97, top - 0.05), (-w * 1.02, belt), (-w, bot + 0.1)]
        return [Vector((x, y, z)) for x, z in pts]

    ys = [-L / 2 + L * i / 30 for i in range(31)]
    body = loft("body", [body_section(y) for y in ys], paint_m)
    dents(body, rng, 14, 0.45, 0.07)
    # Frente amassada (batida): empurra a parte da frente para trás e para baixo.
    for v in body.data.vertices:
        if v.co.y < -1.6:
            k = (-1.6 - v.co.y) / 0.4
            v.co.y += k * 0.22
            v.co.z -= k * 0.08 * (1 if v.co.x > 0 else 0.3)

    # Cabine: vidros escuros trincados, teto amassado e colunas (para-brisa inclinado).
    y0, y1 = -0.95, 0.95
    secs = []
    for i in range(6):
        t = i / 5
        yb = y0 + (y1 - y0) * t
        yt = -0.45 + (0.6 + 0.45) * t
        sag = 0.07 * math.sin(t * math.pi)
        secs.append([Vector((-hw * 0.86, yb, 0.92)), Vector((hw * 0.86, yb, 0.92)),
                     Vector((hw * 0.7, yt, 1.4 - sag * 1.5)), Vector((-hw * 0.7, yt, 1.37 - sag))])
    loft("glass", secs, glass)
    roof = []
    for i in range(6):
        t = i / 5
        yt = -0.5 + (0.65 + 0.5) * t
        sag = 0.07 * math.sin(t * math.pi)
        roof.append([Vector((-hw * 0.73, yt, 1.37 - sag)), Vector((hw * 0.73, yt, 1.4 - sag * 1.5)),
                     Vector((hw * 0.73, yt, 1.45 - sag * 1.5)), Vector((-hw * 0.73, yt, 1.42 - sag))])
    loft("roof", roof, paint_m)
    for sx in (-1, 1):
        for (ab, at) in (((y0, -0.5)), ((0.0, 0.08)), ((y1, 0.65))):
            bm = bmesh.new()
            bd.tube(bm, [Vector((sx * hw * 0.87, ab, 0.92)), Vector((sx * hw * 0.72, at, 1.41))], [0.045, 0.04], 6, 0.0, None)
            bd.obj_from_bm("pillar", bm, paint_m, 1)
    # Para-brisa estourado: buraco escuro com cacos.
    bd.place(slab_box("hole", (0.55, 0.02, 0.28), char), (-0.25, -0.71, 1.15), (-48, 0, 8))
    # Interior queimado: bancos e volante aparecem pelas janelas.
    bd.place(slab_box("dash", (W * 0.82, 0.3, 0.12), char), (0, y0 + 0.05, 1.0))
    for yy in (-0.15, 0.55):
        for xx in (-0.38, 0.38):
            bd.place(slab_box("seat", (0.5, 0.12, 0.42), char), (xx, yy, 1.12), (rng.uniform(-14, -4), 0, rng.uniform(-6, 6)))
    st = bd.torus("wheel_st", 0.16, 0.02, char, 1)
    bd.place(st, (-0.38, y0 + 0.3, 1.12), (60, 0, 0))
    # Cacos de vidro presos nos cantos da janela da frente.
    for i in range(5):
        bm = bmesh.new()
        x = rng.uniform(-hw * 0.7, hw * 0.7)
        v = [bm.verts.new(p) for p in ((x, y0 + 0.02, 0.95), (x + rng.uniform(0.08, 0.2), y0 + 0.04, 0.95),
                                        (x + rng.uniform(-0.05, 0.1), y0 + 0.12, 0.95 + rng.uniform(0.1, 0.22)))]
        bm.faces.new(v)
        bd.obj_from_bm("shard", bm, glass, 1)
    # Capô levantado torto e porta aberta pendurada.
    # Capô: dobradiça junto ao para-brisa; a frente levanta.
    ang = math.radians(-11)
    hinge = Vector((0.0, -1.0, 0.95))
    off = Vector((0.0, -0.58 * math.cos(ang), -0.58 * math.sin(ang)))
    hood = bd.place(slab_box("hood", (W * 0.84, 1.16, 0.035), paint_m), (hinge + off).to_tuple(), (-11, 0, rng.uniform(3, 7)))
    dents(hood, rng, 3, 0.4, 0.05)
    door = bd.place(slab_box("door", (0.05, 1.0, 0.52), paint_m), (hw + 0.37, -0.82 + 0.33, 0.64), (0, 0, -48))
    dents(door, rng, 2, 0.3, 0.04)
    # Para-choques: o da frente caído no chão, o de trás torto.
    bd.place(slab_box("bumper", (W * 0.95, 0.12, 0.14), rust), (0.15, -2.3, 0.1), (0, 8, 12))
    bd.place(slab_box("bumper", (W * 0.98, 0.12, 0.14), rust), (0, L / 2 + 0.04, 0.47), (0, -5, 0))
    # Rodas: dianteira esquerda sumiu (o carro tomba), as outras com pneus murchos e aros enferrujados.
    for x, y in ((hw - 0.14, -1.25), (-hw + 0.14, 1.25), (hw - 0.14, 1.25)):
        tire = bd.place(cylinder("tire", 0.36, 0.24, rubber, 14), (x, y, 0.3), (0, 90, 0))
        for vv in tire.data.vertices:
            if vv.co.x < -0.2:  # achatado no chão (eixo local X vira -Z depois da rotação)
                vv.co.x = -0.2 + (vv.co.x + 0.2) * 0.35
        bd.place(cylinder("rim", 0.2, 0.26, rust, 10), (x, y, 0.3), (0, 90, 0))
    bd.place(cylinder("rim", 0.2, 0.2, rust, 10), (-hw - 0.5, -1.7, 0.1), (rng.uniform(-10, 10), 90, 0))
    # Faróis quebrados e uma poça de sangue seco ao lado da porta.
    for x in (-hw * 0.65, hw * 0.65):
        bd.place(cylinder("lamp", 0.09, 0.05, char, 8), (x, -L / 2 + 0.17, 0.72), (90, 0, 0))
    puddle = bd.place(cylinder("puddle", 0.55, 0.01, blood, 14), (hw + 0.6, -0.1, 0.006), (0, 0, 0))
    for vv in puddle.data.vertices:
        vv.co.x *= rng.uniform(0.7, 1.3)
    # Tomba para o lado da roda que falta.
    world_rotate_all((-2.5, 5.0, rng.uniform(-3, 3)), Vector((0, 0, 0.3)))


# --- Carroça queimada ----------------------------------------------------------------------

def mat_burnt_wood():
    """Madeira velha com partes carbonizadas (rachaduras pretas e brasa apagada)."""
    m, nt, bsdf = bd._mat("burnt_wood")
    grain_v = bd._coords(nt, (1.0, 0.25, 1.0))
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "X"
    wave.inputs["Scale"].default_value = 9.0
    wave.inputs["Distortion"].default_value = 2.5
    wave.inputs["Detail"].default_value = 4.0
    nt.links.new(grain_v, wave.inputs["Vector"])
    wood = bd._ramp(nt, wave.outputs["Fac"], [(0.15, (0.3, 0.24, 0.17)), (0.5, (0.46, 0.39, 0.3)), (0.85, (0.58, 0.51, 0.42))])
    burn = bd._noise(nt, 2.4, 6.0, 0.65)
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 18.0
    char = bd._ramp(nt, vor.outputs["Distance"], [(0.0, (0.01, 0.01, 0.01)), (0.06, (0.06, 0.05, 0.045)), (1.0, (0.11, 0.1, 0.09))])
    mask = bd._ramp(nt, burn, [(0.47, (0, 0, 0)), (0.55, (1, 1, 1))])
    c = bd._mix(nt, mask, wood, char)
    edge = bd._ramp(nt, burn, [(0.45, (0, 0, 0)), (0.47, (1, 1, 1)), (0.49, (0, 0, 0))])
    c = bd._mix(nt, edge, c, (0.2, 0.08, 0.03))
    nt.links.new(bd._height_dirt(nt, c), bsdf.inputs["Base Color"])
    return m


def mat_canvas():
    m, nt, bsdf = bd._mat("canvas")
    weave = bd._ramp(nt, bd._noise(nt, 60.0, 2.0, 0.4), [(0.3, (0.42, 0.38, 0.3)), (0.7, (0.52, 0.47, 0.38))])
    stain = bd._ramp(nt, bd._noise(nt, 4.0, 6.0, 0.6), [(0.35, (0.3, 0.27, 0.23)), (0.65, (1, 1, 1))])
    c = bd._mix(nt, 1.0, weave, stain, "MULTIPLY")
    soot = bd._ramp(nt, bd._noise(nt, 2.0, 5.0, 0.6), [(0.56, (1, 1, 1)), (0.68, (0.12, 0.1, 0.09))])
    c = bd._mix(nt, 1.0, c, soot, "MULTIPLY")
    blood = bd._ramp(nt, bd._noise(nt, 6.0, 3.0, 0.5), [(0.72, (0, 0, 0)), (0.75, (1, 1, 1))])
    c = bd._mix(nt, blood, c, (0.25, 0.04, 0.03))
    nt.links.new(c, bsdf.inputs["Base Color"])
    return m


def spoked_wheel(name, r, wood, iron, rng, broken=0):
    """Roda de carroça: aro de ferro, cubo e raios (alguns quebrados)."""
    objs = []
    rim = bd.torus(name + "_rim", r, 0.045, iron, 1)
    objs.append(rim)
    hub = cylinder(name + "_hub", 0.1, 0.2, wood, 10)
    hub.rotation_euler = Euler((math.pi / 2, 0, 0))
    objs.append(hub)
    for k in range(10):
        if k < broken:
            continue
        a = k * math.tau / 10 + rng.uniform(-0.05, 0.05)
        bm = bmesh.new()
        bd.tube(bm, [Vector((math.cos(a) * 0.09, math.sin(a) * 0.09, 0)), Vector((math.cos(a) * (r - 0.03), math.sin(a) * (r - 0.03), 0))],
                [0.024, 0.018], 5, 0.0, None)
        objs.append(bd.obj_from_bm(name + "_spoke", bm, wood, 1))
    # Aro de madeira por dentro do ferro.
    objs.append(bd.torus(name + "_felloe", r - 0.04, 0.035, wood, 1))
    return objs


def move(objs, loc, rot):
    """Posiciona um grupo de peças (montadas na origem) como se fosse um objeto só."""
    bpy.context.view_layer.update()
    M = Matrix.Translation(Vector(loc)) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4()
    for o in objs:
        o.matrix_world = M @ o.matrix_world


def build_burned_cart():
    rng = random.Random(55)
    wood = mat_burnt_wood()
    iron = bd.mat_flat("iron", (0.16, 0.15, 0.15))
    canvas = mat_canvas()
    burlap = bd.mat_burlap()
    bone = bd.mat_flat("bone", (0.66, 0.6, 0.48))
    dark = bd.mat_flat("socket", (0.03, 0.02, 0.02))
    L, W = 2.7, 1.3
    bed_z = 0.62
    # Leito: duas longarinas e tábuas atravessadas (algumas faltando).
    for x in (-W / 2 + 0.06, W / 2 - 0.06):
        bd.place(bd.log("rail", L + 0.2, 0.06, wood, rng, 1, bend=0.01), (x, 0, bed_z - 0.05), (90, 0, 0))
    for i in range(11):
        if i in (3, 8):
            continue
        y = -L / 2 + 0.12 + i * (L - 0.24) / 10
        bd.place(bd.plank("floor", W + 0.04, 0.24, 0.04, wood, rng, 1, broken=(i == 9)), (rng.uniform(-0.03, 0.03), y, bed_z), (90, 0, rng.uniform(-2, 2)))
    # Laterais: tábuas em pé, a da direita quebrada pela metade.
    for sx in (-1, 1):
        for row in range(2):
            Lp = L if not (sx > 0 and row == 1) else L * 0.55
            off = 0 if Lp == L else -L * 0.22
            bd.place(bd.plank("side", Lp, 0.2, 0.035, wood, rng, 1, broken=(Lp != L)), (sx * W / 2, off, bed_z + 0.15 + row * 0.22), (0, 0, 90))
        for y in (-L / 2 + 0.1, 0, L / 2 - 0.1):
            bd.place(bd.log("stanchion", 0.6, 0.035, wood, rng, 1, bend=0.0), (sx * (W / 2 + 0.03), y, bed_z + 0.22))
    # Arcos da cobertura (um caído) e lona rasgada e chamuscada.
    for k, y in enumerate((-0.95, 0.0, 0.95)):
        pts = [Vector((math.cos(a) * 0.68, y, bed_z + 0.42 + math.sin(a) * 0.62 * (0.75 if k == 2 else 1.0)))
               for a in [math.pi * i / 10 for i in range(11)]]
        bm = bmesh.new()
        bd.tube(bm, pts, [0.025] * len(pts), 5, 0.0, None)
        hoop = bd.obj_from_bm("hoop", bm, wood, 1)
        if k == 2:
            hoop.rotation_euler = Euler((math.radians(25), 0, math.radians(8)))
    for side in (-1, 1):
        strip = []
        for i in range(9):
            a = math.pi * (0.08 + 0.4 * i / 8) if side < 0 else math.pi * (0.52 + 0.4 * i / 8)
            strip.append(a)
        bm = bmesh.new()
        rows = []
        for j, y in enumerate((-1.0, -0.45, 0.1)):
            row = []
            for a in strip:
                tear = rng.uniform(0.0, 0.25) if j == 2 else 0.0
                row.append(bm.verts.new((math.cos(a) * 0.7, y - tear, bed_z + 0.43 + math.sin(a) * 0.64)))
            rows.append(row)
        for r0, r1 in zip(rows, rows[1:]):
            for i in range(len(strip) - 1):
                if rng.random() < 0.12:
                    continue  # buracos queimados
                bm.faces.new((r0[i], r0[i + 1], r1[i + 1], r1[i]))
        bd.obj_from_bm("canvas", bm, canvas, 1)
    # Eixos e rodas: traseira esquerda quebrada, caída no chão (a carroça tomba).
    bd.place(cylinder("axle", 0.045, W + 0.4, iron, 8), (0, -0.85, 0.48), (0, 90, 0))
    bd.place(cylinder("axle", 0.045, W + 0.4, iron, 8), (0, 0.85, 0.48), (0, 90, 0))
    for sx, y in ((-1, -0.85), (1, -0.85), (1, 0.85)):
        parts = spoked_wheel("wheel", 0.48, wood, iron, rng, broken=(2 if sx > 0 and y > 0 else 0))
        move(parts, (sx * (W / 2 + 0.2), y, 0.48), (0, 90, rng.uniform(0, 30)))
    # Varais: um ainda preso, o outro partido no chão.
    bd.place(bd.log("shaft", 1.9, 0.04, wood, rng, 1, bend=0.02), (-0.35, -L / 2 - 0.85, 0.42), (82, 0, 4))
    # Carga revirada: sacos, caixote quebrado e um crânio.
    for x, y in ((-0.3, 0.6), (0.25, 0.75), (0.0, 0.25)):
        bd.place(bd.sandbag("sack", burlap, rng, 1, (0.32, 0.22, 0.14)), (x, y, bed_z + 0.14), (0, 0, rng.uniform(-30, 30)))
    crate = bd.place(slab_box("crate", (0.5, 0.5, 0.45), wood), (-0.25, -0.65, bed_z + 0.25), (0, 0, 20))
    # Tomba sobre a roda que falta.
    world_rotate_all((0, -9.0, 2.0), Vector((-W / 2, 0.85, 0)))
    # Peças caídas no chão (depois de tombar, para não afundarem).
    parts = spoked_wheel("wheel_off", 0.48, wood, iron, rng, broken=3)
    move(parts, (-W / 2 - 0.85, 1.2, 0.05), (0, 0, rng.uniform(0, 40)))
    bd.place(bd.log("shaft", 1.0, 0.04, wood, rng, 1, bend=0.02), (0.55, -L / 2 - 0.9, 0.05), (90, 0, -18))
    bd.place(bd.sandbag("sack", burlap, rng, 1, (0.32, 0.22, 0.14)), (W / 2 + 0.5, -0.2, 0.12), (rng.uniform(-10, 10), 0, 40))
    bd.place(bd.skull("skull", bone, dark, 1), (W / 2 + 0.25, -1.2, 0.08), (rng.uniform(-20, 20), 15, 120))


# --- Terror: estacas com cabeças e pira de corpos ---------------------------------------

def mat_rotten_skin():
    m, nt, bsdf = bd._mat("rotten_skin")
    c = bd._ramp(nt, bd._noise(nt, 9.0, 6.0, 0.6), [(0.3, (0.3, 0.34, 0.25)), (0.55, (0.44, 0.47, 0.36)), (0.75, (0.36, 0.34, 0.27))])
    veins = bd._ramp(nt, bd._noise(nt, 25.0, 8.0, 0.75), [(0.55, (1, 1, 1)), (0.65, (0.45, 0.3, 0.32))])
    c = bd._mix(nt, 1.0, c, veins, "MULTIPLY")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    # Sangue escorrendo do pescoço (parte de baixo de cada cabeça).
    blood = bd._ramp(nt, bd._noise(nt, 4.0, 3.0, 0.5, bd._coords(nt, (8.0, 8.0, 1.5))), [(0.58, (0, 0, 0)), (0.64, (1, 1, 1))])
    c = bd._mix(nt, blood, c, (0.24, 0.03, 0.02))
    nt.links.new(c, bsdf.inputs["Base Color"])
    return m


def head(name, skin, dark, rng, r=0.17):
    """Cabeça de zumbi: crânio alongado, maçãs fundas, mandíbula caída e órbitas escuras."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=10, radius=r)
    for v in bm.verts:
        v.co.y *= 1.12
        v.co.z *= 1.15
        if v.co.z < -r * 0.2:
            v.co.x *= 0.78  # maxilar estreito
            v.co.y -= 0.02
        if v.co.y < -r * 0.6 and abs(v.co.x) > r * 0.3 and -r * 0.3 < v.co.z < r * 0.3:
            v.co.y += 0.02  # bochechas fundas
        v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * r * 0.04
    n_head = len(bm.faces)
    for sx in (-1, 1):
        res = bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=4, radius=r * 0.24)
        for v in res["verts"]:
            v.co += Vector((sx * r * 0.36, -r * 0.98, r * 0.18))
    res = bmesh.ops.create_cube(bm, size=1.0)
    for v in res["verts"]:
        v.co = Vector((v.co.x * r * 0.9, v.co.y * r * 0.5, v.co.z * r * 0.35)) + Vector((0, -r * 0.75, -r * 0.62))
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.materials.append(skin)
    me.materials.append(dark)
    for i, p in enumerate(me.polygons):
        p.material_index = 1 if i >= n_head else 0
    o = bpy.data.objects.new(name, me)
    o["lv"] = 1
    bpy.context.scene.collection.objects.link(o)
    return o


def rag(name, w, h, mat, rng):
    """Trapo pendurado: tira de pano irregular, levemente ondulada."""
    bm = bmesh.new()
    nz = 6
    rows = []
    for j in range(nz + 1):
        z = -h * j / nz
        ww = w * (1 - 0.5 * j / nz) * rng.uniform(0.8, 1.1)
        y = math.sin(j * 1.3) * 0.03
        rows.append([bm.verts.new((-ww / 2, y, z)), bm.verts.new((ww / 2, y + 0.01, z))])
    for a, b in zip(rows, rows[1:]):
        bm.faces.new((a[0], a[1], b[1], b[0]))
    return bd.obj_from_bm(name, bm, mat, 1)


def build_pike_heads():
    rng = random.Random(66)
    bark = bd.mat_bark()
    cut = bd.mat_fresh_cut()
    skin = mat_rotten_skin()
    dark = bd.mat_flat("socket", (0.03, 0.02, 0.02))
    bone = bd.mat_flat("bone", (0.66, 0.6, 0.48))
    canvas = mat_canvas()
    rope = bd.mat_flat("rope", (0.4, 0.33, 0.22))
    # Três estacas inclinadas, cada uma com uma cabeça (ou crânio) espetada.
    for k, (x, y, h, lean) in enumerate(((0.0, 0.0, 2.6, 4), (-0.55, 0.25, 2.1, -12), (0.5, 0.3, 1.9, 10))):
        st = bd.stake("pike", h, 0.05, bark, cut, rng, 1, tip=0.25)
        bd.place(st, (x, y, 0.0), (rng.uniform(-6, 6), lean, 0))
        bpy.context.view_layer.update()
        top = st.matrix_world @ Vector((0, 0, h - 0.18))
        if k == 1:
            bd.place(bd.skull("skull", bone, dark, 1), top.to_tuple(), (rng.uniform(-10, 10), lean, rng.uniform(-30, 30)))
        else:
            bd.place(head("head", skin, dark, rng), top.to_tuple(), (rng.uniform(-15, 5), lean * 0.5, rng.uniform(-40, 40)))
    # Travessa amarrada com crânios pendurados em cordas e um trapo rasgado.
    bd.place(bd.log("bar", 1.3, 0.035, bark, rng, 1, bend=0.02), (0.0, 0.12, 1.75), (0, 90, 6))
    for i, x in enumerate((-0.45, 0.42)):
        bm = bmesh.new()
        bd.tube(bm, [Vector((x, 0.12, 1.73)), Vector((x + 0.02, 0.12, 1.35))], [0.008, 0.008], 4, 0.0, None)
        bd.obj_from_bm("rope", bm, rope, 1)
        bd.place(bd.skull("skull", bone, dark, 1), (x + 0.02, 0.12, 1.27), (180 + rng.uniform(-15, 15), rng.uniform(-20, 20), rng.uniform(0, 360)))
    bd.place(rag("rag", 0.3, 0.7, canvas, rng), (0.04, 0.05, 1.7), (0, 0, rng.uniform(-10, 10)))
    # Pedras na base que seguram as estacas.
    stone = bd.mat_stone()
    for i in range(6):
        a = i * math.tau / 6
        bd.place(bd.rough_stone("base", (0.18, 0.16, 0.12), stone, rng, 1, 0.25), (math.cos(a) * 0.38, 0.15 + math.sin(a) * 0.32, 0.06))


def shrouded_body(name, mat, rng, length=1.7):
    """Corpo enrolado em mortalha: perfil de cabeça, ombros, cintura e pés."""
    prof = [(0.0, 0.0), (0.015, 0.07), (0.05, 0.105), (0.11, 0.11), (0.16, 0.08), (0.2, 0.075), (0.25, 0.17),
            (0.4, 0.19), (0.55, 0.16), (0.7, 0.14), (0.86, 0.1), (0.93, 0.09), (0.98, 0.07), (1.0, 0.0)]
    secs = []
    for t, r in prof:
        ring = []
        for k in range(8):
            a = k * math.tau / 8
            rr = r * (1 + rng.uniform(-0.08, 0.08))
            ring.append(Vector((math.cos(a) * rr, t * length, math.sin(a) * rr * 0.75)))
        secs.append(ring)
    o = loft(name, secs, mat)
    return o


def body_ropes(body, rope, length=1.7):
    """Cordas amarrando a mortalha (pescoço, peito, joelhos, tornozelos)."""
    bpy.context.view_layer.update()
    for t, r in ((0.19, 0.085), (0.35, 0.2), (0.7, 0.15), (0.9, 0.1)):
        ring = bd.torus("tie", r, 0.012, rope, 1)
        ring.scale = (1.0, 1.0, 1.0)
        ring.matrix_world = body.matrix_world @ (Matrix.Translation(Vector((0, t * length, 0))) @ Euler((math.pi / 2, 0, 0)).to_matrix().to_4x4() @ Matrix.Diagonal((1.0, 0.78, 1.0, 1.0)))


def mat_charred_bark():
    m, nt, bsdf = bd._mat("charred_bark")
    v = bd._coords(nt, (6.0, 6.0, 6.0))
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 2.5
    nt.links.new(v, vor.inputs["Vector"])
    c = bd._ramp(nt, vor.outputs["Distance"], [(0.0, (0.6, 0.2, 0.04)), (0.04, (0.04, 0.035, 0.03)), (0.25, (0.12, 0.1, 0.085)),
                                              (1.0, (0.2, 0.17, 0.14))])
    nt.links.new(c, bsdf.inputs["Base Color"])
    return m


def build_corpse_pyre():
    rng = random.Random(77)
    wood = mat_charred_bark()
    char = mat_char()
    shroud = mat_canvas()
    rope = bd.mat_flat("rope", (0.3, 0.24, 0.16))
    bone = bd.mat_flat("bone", (0.66, 0.6, 0.48))
    dark = bd.mat_flat("socket", (0.03, 0.02, 0.02))
    ash = bd.mat_flat("ash", (0.24, 0.23, 0.22))
    ember = bd.mat_flat("ember", (0.75, 0.22, 0.04))
    # Toras cruzadas em camadas.
    for layer in range(3):
        for i in range(4):
            off = -0.6 + i * 0.4
            rot = 90 if layer % 2 == 0 else 0
            loc = (off, 0, 0.1 + layer * 0.17) if layer % 2 == 0 else (0, off, 0.1 + layer * 0.17)
            bd.place(bd.log("log", 1.8, rng.uniform(0.07, 0.09), wood, rng, 1, bend=0.02), loc, (rot, 0, rot * 0 + (90 if layer % 2 else 0)) if False else ((90, 0, 0) if layer % 2 == 0 else (0, 90, 0)))
    # Corpos enrolados empilhados por cima, carbonizados.
    for i, (x, y, z, yaw) in enumerate(((-0.35, -0.8, 0.62, 8), (0.25, -0.85, 0.6, -6), (-0.05, -0.75, 0.86, 20))):
        b = shrouded_body("body", shroud if i != 1 else char, rng)
        bd.place(b, (x, y, z), (0, rng.uniform(-15, 15), yaw))
        body_ropes(b, rope)
    # Braço esquelético para fora da pilha e um crânio caído.
    bd.place(bd.skull("skull", bone, dark, 1), (0.95, -0.7, 0.08), (rng.uniform(-30, 30), 20, 140))
    # Anel de cinzas e brasas em volta.
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=20, radius=1.45)
    for v in bm.verts:
        v.co.x *= rng.uniform(0.85, 1.1)
        v.co.y *= rng.uniform(0.85, 1.1)
        v.co.z = 0.01
    bd.obj_from_bm("ash", bm, ash, 1)
    for i in range(14):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.6, 1.3)
        bd.place(bd.rough_stone("coal", (0.05, 0.05, 0.03), ember if i % 2 else char, rng, 1, 0.3), (math.cos(a) * r, math.sin(a) * r, 0.025))


# --- Tambores de óleo e entulho ---------------------------------------------------------

def mat_drum(name, paint):
    m, nt, bsdf = bd._mat(name)
    p = bd._ramp(nt, bd._noise(nt, 7.0, 5.0, 0.5), [(0.3, tuple(c * 0.7 for c in paint)), (0.7, paint)])
    rustc = bd._ramp(nt, bd._noise(nt, 14.0, 8.0, 0.7), [(0.3, (0.13, 0.07, 0.04)), (0.6, (0.33, 0.16, 0.07))])
    mask = bd._ramp(nt, bd._noise(nt, 4.5, 8.0, 0.7), [(0.44, (0, 0, 0)), (0.54, (1, 1, 1))])
    c = bd._mix(nt, mask, p, rustc)
    streak = bd._ramp(nt, bd._noise(nt, 3.0, 4.0, 0.5, bd._coords(nt, (16.0, 16.0, 0.7))), [(0.45, (1, 1, 1)), (0.7, (0.4, 0.24, 0.15))])
    c = bd._mix(nt, 0.9, c, streak, "MULTIPLY")
    nt.links.new(bd._height_dirt(nt, c), bsdf.inputs["Base Color"])
    return m


def drum(name, mat, rng, open_top=False, inner=None):
    """Tambor de 200 L: corpo com dois frisos, tampa com aro e amassados."""
    prof = [(0.0, 0.27), (0.03, 0.29), (0.06, 0.29), (0.3, 0.29), (0.32, 0.305), (0.34, 0.29), (0.58, 0.29),
            (0.6, 0.305), (0.62, 0.29), (0.85, 0.29), (0.88, 0.3), (0.9, 0.28)]
    secs = []
    for z, r in prof:
        secs.append([Vector((math.cos(a) * r, math.sin(a) * r, z)) for a in [k * math.tau / 14 for k in range(14)]])
    o = loft(name, secs, mat, cap=not open_top)
    dents(o, rng, 4, 0.18, 0.03)
    if open_top and inner is not None:
        bm = bmesh.new()
        bmesh.ops.create_circle(bm, cap_ends=True, segments=14, radius=0.27)
        for v in bm.verts:
            v.co.z = 0.6
        bd.obj_from_bm(name + "_ash", bm, inner, 1)
    return o


def build_oil_drums():
    rng = random.Random(88)
    red = mat_drum("drum_red", (0.45, 0.13, 0.09))
    blue = mat_drum("drum_blue", (0.15, 0.24, 0.33))
    yellow = mat_drum("drum_yellow", (0.55, 0.43, 0.12))
    char = mat_char()
    oil = bd.mat_flat("oil", (0.02, 0.02, 0.018))
    # Tambor de fogueira no centro (origem: o jogo põe fogo e luz aqui à noite).
    burn = drum("burn", char, rng, open_top=True, inner=bd.mat_flat("embers", (0.55, 0.16, 0.04)))
    for i in range(5):
        a = i * math.tau / 5
        bm = bmesh.new()
        bmesh.ops.create_circle(bm, cap_ends=True, segments=6, radius=0.035)
        bd.place(bd.obj_from_bm("hole", bm, oil, 1), (math.cos(a) * 0.292, math.sin(a) * 0.292, 0.22), (90, 0, math.degrees(a) + 90))
    bd.place(drum("drum", red, rng), (0.72, 0.15, 0), (0, 0, rng.uniform(0, 360)))
    bd.place(drum("drum", blue, rng), (0.55, 0.78, 0), (0, rng.uniform(-3, 3), rng.uniform(0, 360)))
    # Um tombado, vazando óleo numa poça preta.
    bd.place(drum("drum", yellow, rng), (-0.75, 0.35, 0.3), (0, 90, 25))
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=16, radius=0.6)
    for v in bm.verts:
        v.co.x *= rng.uniform(0.8, 1.4)
        v.co.y *= rng.uniform(0.7, 1.1)
        v.co.z = 0.006
    bd.place(bd.obj_from_bm("oil", bm, oil, 1), (-1.35, 0.75, 0), (0, 0, 20))
    # Pneu velho encostado.
    tire = bd.torus("tire", 0.3, 0.11, mat_rubber(), 1)
    bd.place(tire, (0.0, -0.75, 0.32), (75, 0, 10))


def mat_concrete():
    m, nt, bsdf = bd._mat("concrete")
    c = bd._ramp(nt, bd._noise(nt, 5.0, 6.0, 0.6), [(0.3, (0.24, 0.23, 0.22)), (0.55, (0.34, 0.33, 0.31)), (0.75, (0.29, 0.27, 0.25))])
    pores = bd._ramp(nt, bd._noise(nt, 60.0, 4.0, 0.6), [(0.55, (1, 1, 1)), (0.7, (0.6, 0.58, 0.55))])
    c = bd._mix(nt, 1.0, c, pores, "MULTIPLY")
    soot = bd._ramp(nt, bd._noise(nt, 2.2, 5.0, 0.6), [(0.5, (1, 1, 1)), (0.66, (0.22, 0.2, 0.19))])
    c = bd._mix(nt, 1.0, c, soot, "MULTIPLY")
    nt.links.new(bd._height_dirt(nt, c), bsdf.inputs["Base Color"])
    return m


def build_rubble_pile():
    rng = random.Random(99)
    conc = mat_concrete()
    brick = bd.mat_flat("brick", (0.42, 0.2, 0.14))
    iron = bd.mat_rust()
    wood = mat_burnt_wood()
    # Lajes de concreto quebradas, empilhadas e inclinadas.
    for i in range(14):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.0, 1.0) * (0.5 if i > 9 else 1.0)
        size = (rng.uniform(0.3, 0.65), rng.uniform(0.25, 0.5), rng.uniform(0.1, 0.2))
        z = 0.12 + max(0.0, 0.7 - r) * 0.6 + (0.3 if i > 9 else 0.0)
        slab = bd.rough_stone("slab", size, conc, rng, 1, 0.35)
        bd.place(slab, (math.cos(a) * r, math.sin(a) * r, z), (rng.uniform(-35, 35), rng.uniform(-35, 35), rng.uniform(0, 180)))
    # Vergalhões tortos saindo do concreto.
    for i in range(6):
        x, y = rng.uniform(-0.6, 0.6), rng.uniform(-0.5, 0.5)
        pts = [Vector((x, y, 0.2)), Vector((x + rng.uniform(-0.15, 0.15), y + rng.uniform(-0.15, 0.15), 0.6)),
               Vector((x + rng.uniform(-0.4, 0.4), y + rng.uniform(-0.4, 0.4), rng.uniform(0.8, 1.1)))]
        bm = bmesh.new()
        bd.tube(bm, pts, [0.014, 0.013, 0.012], 4, 0.0, None)
        bd.obj_from_bm("rebar", bm, iron, 1)
    # Tijolos soltos espalhados e uma viga queimada.
    for i in range(22):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.5, 1.5)
        bd.place(bd.box("brick", (0.22, 0.1, 0.07), brick, 1), (math.cos(a) * r, math.sin(a) * r, 0.04), (rng.uniform(-20, 20), rng.uniform(-20, 20), rng.uniform(0, 180)))
    bd.place(bd.log("beam", 2.2, 0.09, wood, rng, 1, bend=0.02), (0.2, 0.1, 0.45), (75, 0, 30))


# --- Fortaleza central (forte de pedra em ruínas, adaptado pelos sobreviventes) ------------

def mat_masonry():
    """Alvenaria de pedra (textura de tijolo do Blender) suja, com fuligem, musgo e escorridos.
    Coordenada u = x + y serve tanto para as paredes da frente quanto para as laterais."""
    m, nt, bsdf = bd._mat("masonry")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    nt.links.new(sep.outputs[0], add.inputs[0])
    nt.links.new(sep.outputs[1], add.inputs[1])
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(add.outputs[0], comb.inputs[0])
    nt.links.new(sep.outputs[2], comb.inputs[1])
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = 0.035
    brick.inputs["Brick Width"].default_value = 0.62
    brick.inputs["Row Height"].default_value = 0.34
    brick.inputs["Color1"].default_value = (*srgb((0.42, 0.4, 0.36)), 1)
    brick.inputs["Color2"].default_value = (*srgb((0.3, 0.29, 0.27)), 1)
    brick.inputs["Mortar"].default_value = (*srgb((0.08, 0.075, 0.07)), 1)
    brick.offset = 0.5
    nt.links.new(comb.outputs[0], brick.inputs["Vector"])
    var = bd._ramp(nt, bd._noise(nt, 6.0, 6.0, 0.6), [(0.3, (0.62, 0.6, 0.56)), (0.7, (1, 1, 1))])
    c = bd._mix(nt, 1.0, brick.outputs["Color"], var, "MULTIPLY")
    soot = bd._ramp(nt, bd._noise(nt, 1.5, 5.0, 0.6, bd._coords(nt, (1.0, 1.0, 0.35))), [(0.48, (1, 1, 1)), (0.66, (0.16, 0.15, 0.14))])
    c = bd._mix(nt, 1.0, c, soot, "MULTIPLY")
    streak = bd._ramp(nt, bd._noise(nt, 3.0, 4.0, 0.5, bd._coords(nt, (7.0, 7.0, 0.5))), [(0.45, (1, 1, 1)), (0.68, (0.5, 0.47, 0.42))])
    c = bd._mix(nt, 1.0, c, streak, "MULTIPLY")
    moss = bd._ramp(nt, bd._noise(nt, 4.0, 6.0, 0.6), [(0.6, (0, 0, 0)), (0.7, (1, 1, 1))])
    c = bd._mix(nt, moss, c, (0.17, 0.19, 0.1))
    nt.links.new(bd._height_dirt(nt, c), bsdf.inputs["Base Color"])
    return m


def wall_loft(name, a, b, thick, top_fn, mat, segs=16, base=0.0):
    """Muro de A a B (no chão), espessura `thick`, com o topo dado por top_fn(t) (desmoronado)."""
    a, b = Vector((a[0], a[1], 0.0)), Vector((b[0], b[1], 0.0))
    d = (b - a).normalized()
    nrm = Vector((-d.y, d.x, 0)) * (thick / 2)
    secs = []
    for i in range(segs + 1):
        t = i / segs
        p = a.lerp(b, t)
        h = top_fn(t)
        secs.append([p - nrm + Vector((0, 0, base)), p + nrm + Vector((0, 0, base)), p + nrm + Vector((0, 0, h)), p - nrm + Vector((0, 0, h))])
    return loft(name, secs, mat)


def build_keep():
    rng = random.Random(1234)
    mas = mat_masonry()
    stone = bd.mat_stone()
    wood = bd.mat_old_wood("old_wood", blood=False)
    bark = bd.mat_bark()
    cut = bd.mat_fresh_cut()
    rust = bd.mat_rust()
    burlap = bd.mat_burlap()
    canvas = mat_canvas()
    iron = bd.mat_flat("iron", (0.14, 0.13, 0.13))
    dark = bd.mat_flat("socket", (0.03, 0.025, 0.02))
    bone = bd.mat_flat("bone", (0.66, 0.6, 0.48))
    cloth = bd.mat_flat("rag", (0.26, 0.07, 0.05))
    char = mat_char()
    W, D, H, T = 5.8, 5.0, 4.8, 0.6   # largura (X), profundidade (Y), altura, espessura
    hx, hy = W / 2, D / 2
    # Frente = -Y (vira +Z no jogo, onde fica o portão).
    def front_top(t):  # canto esquerdo da frente desmoronado
        if t < 0.3:
            return 2.1 + (H - 2.1) * (t / 0.3) ** 1.6 + rng.uniform(-0.12, 0.12)
        return H + rng.uniform(-0.08, 0.05)
    def left_top(t):   # o lado esquerdo também caiu perto da frente
        if t < 0.28:
            return 2.1 + (H - 2.1) * (t / 0.28) ** 1.4 + rng.uniform(-0.12, 0.12)
        return H + rng.uniform(-0.08, 0.05)
    flat = lambda t: H + rng.uniform(-0.06, 0.06)
    wall_loft("wall_f", (-hx, -hy), (hx, -hy), T, front_top, mas)
    wall_loft("wall_l", (-hx, -hy), (-hx, hy), T, left_top, mas)
    wall_loft("wall_b", (-hx, hy), (hx, hy), T, flat, mas)
    wall_loft("wall_r", (hx, -hy), (hx, hy), T, flat, mas)
    # Embasamento de pedras grandes e cunhais (pedras de canto) para dar silhueta.
    for (x0, y0, x1, y1) in ((-hx, -hy, hx, -hy), (hx, -hy, hx, hy), (hx, hy, -hx, hy), (-hx, hy, -hx, -hy)):
        n = 9
        for i in range(n):
            t = (i + 0.5) / n
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
            bd.place(bd.rough_stone("plinth", (0.7, T + 0.25, 0.42), stone, rng, 1, 0.12), (x, y, 0.2), (0, 0, ang))
    for cx, cy, top in ((hx, -hy, H), (hx, hy, H), (-hx, hy, H)):
        z = 0.4
        k = 0
        while z < top - 0.2:
            h = rng.uniform(0.38, 0.48)
            sx, sy = (0.75, 0.55) if k % 2 == 0 else (0.55, 0.75)
            bd.place(bd.rough_stone("quoin", (sx, sy, h * 0.96), stone, rng, 1, 0.1), (cx, cy, z + h / 2))
            z += h
            k += 1
    # Ameias no topo (algumas caídas), só onde o muro está inteiro.
    def merlons(a, b, skip_until=0.0):
        a, b = Vector((a[0], a[1], 0.0)), Vector((b[0], b[1], 0.0))
        n = int((b - a).length / 0.75)
        ang = math.degrees(math.atan2(b.y - a.y, b.x - a.x))
        for i in range(n):
            t = (i + 0.5) / n
            if t < skip_until or rng.random() < 0.18:
                continue
            p = a.lerp(b, t)
            bd.place(bd.rough_stone("merlon", (0.48, T + 0.04, rng.uniform(0.5, 0.62)), mas, rng, 1, 0.08), (p.x, p.y, H + 0.27), (0, 0, ang))
    merlons((-hx, -hy), (hx, -hy), 0.36)
    merlons((-hx, -hy), (-hx, hy), 0.34)
    merlons((-hx, hy), (hx, hy))
    merlons((hx, -hy), (hx, hy))
    # Seteiras escuras nas paredes.
    for x in (0.9, 2.0):
        bd.place(bd.box("slit", (0.14, 0.05, 0.7), dark, 1), (x, -hy - T / 2 - 0.005, 3.2))
    for y in (-1.2, 0.2, 1.4):
        bd.place(bd.box("slit", (0.05, 0.14, 0.7), dark, 1), (hx + T / 2 + 0.005, y, 3.2))
        bd.place(bd.box("slit", (0.05, 0.14, 0.7), dark, 1), (-hx - T / 2 - 0.005, y + 0.6, 3.0)) if y > 0 else None
    # Portão: arco de pedra, vão escuro e portas de madeira reforçadas com ferro.
    gx = 0.55
    bd.place(bd.box("gate_void", (1.7, 0.08, 2.5), dark, 1), (gx, -hy - T / 2 - 0.01, 1.25))
    arch = [Vector((gx + math.cos(a) * 1.0, -hy - T / 2 - 0.08, 2.15 + math.sin(a) * 0.65)) for a in [math.pi * i / 12 for i in range(13)]]
    bm = bmesh.new()
    bd.tube(bm, arch, [0.17] * len(arch), 6, 0.08, rng)
    bd.obj_from_bm("arch", bm, stone, 1)
    for sx in (-1, 1):
        bd.place(bd.box("jamb", (0.3, 0.3, 2.2), stone, 1), (gx + sx * 1.0, -hy - T / 2 - 0.08, 1.1))
        for k in range(4):
            bd.place(bd.plank("door", 2.1, 0.22, 0.06, wood, rng, 1), (gx + sx * (0.12 + k * 0.2), -hy - T / 2 - 0.1, 1.08), (0, 90, 0))
        for z in (0.45, 1.55):
            bd.place(bd.box("band", (0.82, 0.03, 0.09), iron, 1), (gx + sx * 0.42, -hy - T / 2 - 0.15, z))
    bd.place(bd.plank("bar", 1.8, 0.2, 0.08, wood, rng, 1), (gx, -hy - T / 2 - 0.2, 1.05), (90, 0, 0))
    for sx in (-1, 1):
        for k in range(3):
            bd.place(bd.sandbag("bag", burlap, rng, 1), (gx + sx * (1.55 + 0.1 * k), -hy - T / 2 - 0.45, 0.15 + k * 0.2),
                     (0, 0, 90 + rng.uniform(-10, 10)))
        st = bd.stake("gatepike", 2.2, 0.04, bark, cut, rng, 1, tip=0.22)
        bd.place(st, (gx + sx * 2.05, -hy - T / 2 - 0.55, 0.0), (rng.uniform(-6, 6), sx * 6, 0))
        bd.place(bd.skull("skull", bone, dark, 1), (gx + sx * 2.17, -hy - T / 2 - 0.55, 2.12), (0, 0, rng.uniform(-30, 30)))
    gate = bpy.data.objects.new("GateLight", None)
    gate.location = (gx, -hy - 1.2, 1.9)
    bpy.context.scene.collection.objects.link(gate)
    # Canto desmoronado: entulho na base, andaime de troncos e remendos de tábua e zinco.
    for i in range(16):
        a = rng.uniform(math.pi, 1.5 * math.pi) if i < 10 else rng.uniform(0, math.tau)
        r = rng.uniform(0.3, 1.6)
        bd.place(bd.rough_stone("rubble", (rng.uniform(0.25, 0.5),) * 3, mas if i % 3 else stone, rng, 1, 0.3),
                 (-hx + math.cos(a) * r * 0.9, -hy + math.sin(a) * r * 0.9, rng.uniform(0.1, 0.35)), (rng.uniform(0, 40), rng.uniform(0, 40), rng.uniform(0, 90)))
    for x in (-hx + 0.3, -hx + 1.5):
        bd.place(bd.log("scaf", 4.6, 0.06, bark, rng, 1, bend=0.0), (x, -hy - T / 2 - 0.5, 2.3))
    for y in (-hy + 0.3, -hy + 1.4):
        bd.place(bd.log("scaf", 4.6, 0.06, bark, rng, 1, bend=0.0), (-hx - T / 2 - 0.5, y, 2.3))
    for z in (1.6, 3.2, 4.4):
        bd.place(bd.log("scafbar", 1.6, 0.045, bark, rng, 1, bend=0.0), (-hx + 0.9, -hy - T / 2 - 0.5, z), (0, 90, rng.uniform(-4, 4)))
        bd.place(bd.log("scafbar", 1.5, 0.045, bark, rng, 1, bend=0.0), (-hx - T / 2 - 0.5, -hy + 0.85, z), (90, 0, rng.uniform(-4, 4)))
    for k in range(6):
        bd.place(bd.plank("patch", 1.7, 0.26, 0.04, wood, rng, 1, broken=k == 4), (-hx + 0.9, -hy - T / 2 - 0.08, 2.3 + k * 0.33), (0, rng.uniform(-6, 6), 0))
    bd.place(bd.tin_sheet("tin", 1.5, 1.2, rust, rng, 1), (-hx - T / 2 - 0.08, -hy + 0.9, 2.9), (0, 0, 90))
    bd.place(bd.tin_sheet("tin", 1.2, 1.0, rust, rng, 1), (1.9, -hy - T / 2 - 0.06, 1.0), (0, 4, 0))
    # Deck de tábuas no topo (o que se vê de cima): lona, caixotes, barris e sacos de areia.
    for i in range(14):
        y = -hy + 0.25 + i * (D - 0.5) / 13
        bd.place(bd.plank("deck", W - 0.4 if y > -hy + 1.3 else W - 1.9, 0.36, 0.05, wood, rng, 1, broken=(i == 2)),
                 ((0.0 if y > -hy + 1.3 else 0.75) + rng.uniform(-0.04, 0.04), y, H - 0.4), (90, 0, rng.uniform(-1.5, 1.5)))
    for x, y, r in ((-1.6, 1.4, 15), (-0.9, 1.8, -10), (0.2, 1.6, 30)):
        bd.place(bd.box("crate", (0.6, 0.6, 0.55), wood, 1), (x, y, H - 0.1), (0, 0, r))
    bd.place(bd.box("crate", (0.5, 0.5, 0.45), wood, 1), (-1.2, 1.6, H + 0.4), (0, 0, 40))
    tarp_secs = []
    for i in range(5):
        y = -0.6 + i * 0.4
        tarp_secs.append([Vector((-1.0, y, H - 0.3)), Vector((-0.2, y, H + 0.55 - 0.05 * i)), Vector((0.6, y, H - 0.3))])
    bm = bmesh.new()
    rows = [[bm.verts.new(p) for p in sec] for sec in tarp_secs]
    for r0, r1 in zip(rows, rows[1:]):
        for k in range(2):
            bm.faces.new((r0[k], r0[k + 1], r1[k + 1], r1[k]))
    bd.obj_from_bm("tarp", bm, canvas, 1)
    for i in range(7):
        bd.place(bd.sandbag("bag", burlap, rng, 1, (0.4, 0.22, 0.13)), (-2.3 + i * 0.55, -hy + 0.5, H - 0.25), (0, 0, rng.uniform(-8, 8)))
    # Torre de vigia (fundo-direita): mais alta, com plataforma, fogueira-farol e antena de sucata.
    tx, ty, TH = hx - 0.9, hy - 0.9, 7.2
    wall_loft("tower_f", (tx - 1.15, ty - 1.15), (tx + 1.15, ty - 1.15), 0.5, lambda t: TH, mas, 4, base=H - 0.6)
    wall_loft("tower_b", (tx - 1.15, ty + 1.15), (tx + 1.15, ty + 1.15), 0.5, lambda t: TH, mas, 4, base=H - 0.6)
    wall_loft("tower_l", (tx - 1.15, ty - 1.15), (tx - 1.15, ty + 1.15), 0.5, lambda t: TH, mas, 4, base=H - 0.6)
    wall_loft("tower_r", (tx + 1.15, ty - 1.15), (tx + 1.15, ty + 1.15), 0.5, lambda t: TH, mas, 4, base=H - 0.6)
    for k in range(8):
        a = k * math.tau / 8
        if k == 5:
            continue
        x = tx + max(-1, min(1, math.cos(a) * 1.42)) * 1.15
        y = ty + max(-1, min(1, math.sin(a) * 1.42)) * 1.15
        bd.place(bd.rough_stone("tmerlon", (0.45, 0.45, 0.55), mas, rng, 1, 0.08), (x, y, TH + 0.27))
    for i in range(6):
        bd.place(bd.plank("tdeck", 2.1, 0.36, 0.05, wood, rng, 1), (tx, ty - 0.9 + i * 0.36, TH - 0.25), (90, 0, 0))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.25, radius2=0.5, depth=0.4)
    bd.place(bd.obj_from_bm("brazier", bm, iron, 1), (tx, ty, TH + 0.2))
    bd.place(bd.rough_stone("coals", (0.42, 0.42, 0.08), char, rng, 1, 0.2), (tx, ty, TH + 0.42))
    beacon = bpy.data.objects.new("Beacon", None)
    beacon.location = (tx, ty, TH + 0.6)
    bpy.context.scene.collection.objects.link(beacon)
    # Antena de rádio improvisada com cabos e bandeira vermelha esfarrapada.
    bm = bmesh.new()
    bd.tube(bm, [Vector((tx + 0.85, ty + 0.85, TH)), Vector((tx + 0.9, ty + 0.88, TH + 2.4))], [0.04, 0.025], 5, 0.0, None)
    bd.obj_from_bm("antenna", bm, rust, 1)
    for k in range(3):
        bd.place(bd.log("crossbar", 0.6 - k * 0.15, 0.015, rust, rng, 1, bend=0.0), (tx + 0.88, ty + 0.87, TH + 1.4 + k * 0.4), (0, 90, 30))
    flag = bd.plank("flag", 0.9, 0.5, 0.01, cloth, rng, 1, broken=True)
    bd.place(flag, (tx + 1.35, ty + 0.88, TH + 2.05), (90, 0, 0))
    # Arame farpado ao longo da frente intacta e corrente pendurada.
    bd.place(bd.barbed_wire("wire", W * 0.6, 0.12, iron, rng, 1, loops=12), (0.8, -hy - T / 2 - 0.05, H + 0.15))
    bd.place(bd.chain("chain", 1.4, iron, 1), (2.4, -hy - T / 2 - 0.1, 4.2))


# --- Muralha da base: paliçada sobre base de pedra, portão e torres do portão --------------

RING_LEN = 4.2


def build_ring_wall(variant):
    rng = random.Random(500 + variant)
    mas = mat_masonry()
    stone = bd.mat_stone()
    bark = bd.mat_bark()
    cut = bd.mat_fresh_cut()
    rust = bd.mat_rust()
    rope = bd.mat_flat("rope", (0.4, 0.33, 0.22))
    bone = bd.mat_flat("bone", (0.66, 0.6, 0.48))
    dark = bd.mat_flat("socket", (0.03, 0.02, 0.02))
    iron = bd.mat_flat("iron", (0.15, 0.14, 0.14))
    L = RING_LEN
    # Base de pedra (1 m) com topo irregular.
    wall_loft("base", (-L / 2, 0), (L / 2, 0), 0.85, lambda t: 1.0 + rng.uniform(-0.08, 0.08), mas, 8)
    for i in range(7):
        bd.place(bd.rough_stone("foot", (0.62, 1.0, 0.36), stone, rng, 1, 0.14), (-L / 2 + 0.3 + i * (L - 0.6) / 6, 0, 0.17))
    # Paliçada de troncos apontados por cima.
    n = 11
    for i in range(n):
        x = -L / 2 + (i + 0.5) * L / n + rng.uniform(-0.03, 0.03)
        h = rng.uniform(2.0, 2.35)
        bd.place(bd.stake("pale", h, 0.19, bark, cut, rng, 1, tip=0.4), (x, rng.uniform(-0.05, 0.05), 0.85), (rng.uniform(-3, 3), rng.uniform(-3, 3), 0))
    for z in (1.45, 2.3):
        bd.place(bd.log("rail", L + 0.1, 0.07, bark, rng, 1, bend=0.02), (0, -0.24, z), (0, 90, 0))
        bd.place(bd.log("rail", L + 0.1, 0.07, bark, rng, 1, bend=0.02), (0, 0.24, z), (0, 90, 0))
    for x in (-L / 2 + 0.6, L / 2 - 0.6):
        bd.place(bd.torus("lash", 0.24, 0.02, rope, 1), (x, 0, 2.3), (0, 0, 0))
    if variant == 1:
        bd.place(bd.tin_sheet("patch", 1.3, 0.9, rust, rng, 1), (0.6, -0.27, 1.75), (0, 3, 0))
        bd.place(bd.skull("skull", bone, dark, 1), (-1.2, -0.12, 3.15), (0, 0, rng.uniform(-30, 30)))
        bd.place(bd.barbed_wire("wire", L - 0.4, 0.1, iron, rng, 1, loops=10), (0, -0.3, 2.85))
    else:
        for i in range(4):
            bd.place(bd.stake("outspike", 1.1, 0.04, bark, cut, rng, 1), (-1.5 + i, -0.6, 0.0), (-45 + rng.uniform(-6, 6), 0, rng.uniform(-10, 10)))


def build_ring_gate():
    """Folha do portão (centrada; o jogo a pendura pela borda): tábuas, travessas em Z, ferro e pontas."""
    rng = random.Random(600)
    wood = bd.mat_old_wood("old_wood", blood=True)
    bark = bd.mat_bark()
    cut = bd.mat_fresh_cut()
    iron = bd.mat_flat("iron", (0.14, 0.13, 0.13))
    rust = bd.mat_rust()
    Wd, Hd = 3.55, 2.5
    n = 10
    for i in range(n):
        x = -Wd / 2 + (i + 0.5) * Wd / n
        h = Hd + rng.uniform(-0.1, 0.15)
        bd.place(bd.stake("board", h, 0.17, bark, cut, rng, 1, tip=0.3), (x, 0, 0.05))
    for z in (0.45, 2.0):
        bd.place(bd.plank("cross", Wd, 0.26, 0.07, wood, rng, 1), (0, -0.2, z), (0, 0, 0))
    bd.place(bd.plank("diag", 3.6, 0.24, 0.07, wood, rng, 1), (0, -0.25, 1.22), (0, -24, 0))
    for z in (0.6, 1.85):
        bd.place(bd.box("band", (Wd + 0.05, 0.04, 0.1), iron, 1), (0, -0.28, z))
    for i in range(6):
        bd.place(bd.stake("spike", 0.45, 0.025, iron, iron, rng, 1, tip=0.15), (-1.5 + i * 0.6, -0.3, 1.2), (90, 0, rng.uniform(-8, 8)))
    bd.place(bd.tin_sheet("patch", 1.0, 0.7, rust, rng, 1), (-0.9, -0.24, 1.2), (0, 5, 0))


def build_ring_tower():
    rng = random.Random(700)
    mas = mat_masonry()
    bark = bd.mat_bark()
    wood = bd.mat_old_wood("old_wood", blood=False)
    cut = bd.mat_fresh_cut()
    rust = bd.mat_rust()
    burlap = bd.mat_burlap()
    S = 0.85
    # Base de pedra (1,8 m) e torre de troncos com plataforma, parapeito e meia-água de zinco.
    for (a, b) in (((-S, -S), (S, -S)), ((-S, S), (S, S)), ((-S, -S), (-S, S)), ((S, -S), (S, S))):
        wall_loft("tbase", a, b, 0.5, lambda t: 1.8 + rng.uniform(-0.1, 0.1), mas, 4)
    bd.place(bd.box("cap", (2 * S + 0.5, 2 * S + 0.5, 0.22), mas, 1), (0, 0, 1.78))
    for sx in (-1, 1):
        for sy in (-1, 1):
            bd.place(bd.log("post", 3.4, 0.09, bark, rng, 1, bend=0.0), (sx * S, sy * S, 3.3))
    for i in range(7):
        y = -S + i * (2 * S) / 6
        bd.place(bd.plank("deck", 2 * S + 0.3, 0.3, 0.05, wood, rng, 1), (0, y, 3.4), (90, 0, rng.uniform(-2, 2)))
    for side in range(4):
        for k in range(6):
            t = -1 + 2 * (k + 0.5) / 6
            h = rng.uniform(0.8, 1.05)
            pos = (t * S, S * (1 if side == 0 else -1), 3.45 + h / 2) if side < 2 else (S * (1 if side == 2 else -1), t * S, 3.45 + h / 2)
            bd.place(bd.stake("pal", h, 0.07, bark, cut, rng, 1, tip=0.12), (pos[0], pos[1], 3.45), (0, 0, 0))
    roof = bd.tin_sheet("roof", 2.2, 1.4, rust, rng, 1, corrugate=0.03)
    bd.place(roof, (0, 0.35, 5.05), (90 - 24, 0, 0))
    for k in range(4):
        bd.place(bd.sandbag("bag", burlap, rng, 1, (0.36, 0.2, 0.12)), (-0.6 + k * 0.4, -S - 0.05, 3.55), (0, 0, rng.uniform(-8, 8)))


BUILDERS = {
    "ring_wall_a": lambda: build_ring_wall(0),
    "ring_wall_b": lambda: build_ring_wall(1),
    "ring_gate": build_ring_gate,
    "ring_tower": build_ring_tower,
    "keep_ruin": build_keep,
    "oil_drums": build_oil_drums,
    "rubble_pile": build_rubble_pile,
    "pike_heads": build_pike_heads,
    "corpse_pyre": build_corpse_pyre,
    "burned_cart": build_burned_cart,
    "car_wreck_a": lambda: build_car((0.24, 0.35, 0.35), 101),   # verde-azulado desbotado
    "car_wreck_b": lambda: build_car((0.36, 0.14, 0.11), 202),   # vermelho queimado
}


# --- Prévia ------------------------------------------------------------------------------

def render_single(objs, out_png):
    sc = bpy.context.scene
    dims = Vector((max(o.dimensions.x for o in objs), max(o.dimensions.y for o in objs), max(o.dimensions.z for o in objs)))
    ground = bpy.data.meshes.new("ground")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=12)
    bm.to_mesh(ground)
    g = bpy.data.objects.new("ground", ground)
    ground.materials.append(bd.mat_flat("dirt", (0.2, 0.16, 0.12)))
    sc.collection.objects.link(g)
    size = max(dims.x, dims.y, dims.z)
    cams = []
    for i, (yaw, pitch) in enumerate(((35, 58), (-145, 50))):
        cam = bpy.data.objects.new("cam%d" % i, bpy.data.cameras.new("cam%d" % i))
        cam.data.lens = 50
        sc.collection.objects.link(cam)
        dist = size * 1.8
        a = math.radians(yaw)
        e = math.radians(90 - pitch)
        cam.location = (math.sin(a) * math.cos(e) * dist, -math.cos(a) * math.cos(e) * dist, math.sin(e) * dist + dims.z * 0.4)
        direction = Vector((0, 0, dims.z * 0.4)) - Vector(cam.location)
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        cams.append(cam)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = Euler((math.radians(50), math.radians(10), math.radians(-35)))
    sc.collection.objects.link(sun)
    sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (*srgb((0.45, 0.47, 0.5)), 1)
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sc.render.resolution_x, sc.render.resolution_y = 800, 600
    sc.cycles.samples = 48
    base = out_png[:-4]
    for i, cam in enumerate(cams):
        sc.camera = cam
        sc.render.filepath = "%s_%d.png" % (base, i)
        bpy.ops.render.render(write_still=True)
    print("prévia:", base)


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
            render_single(objs, os.path.join(render_dir, n + ".png"))


if __name__ == "__main__":
    main()
