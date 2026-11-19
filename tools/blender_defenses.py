"""Defesas pós-apocalípticas modeladas à mão no Blender (bpy), com texturas procedurais
"assadas" (bake, Cycles) num atlas e oclusão de ambiente embutida. Exporta GLB para o jogo.

Cada defesa tem peças por nível de melhoria em objetos separados (Lv1, Lv2, Lv3): o jogo
mostra Lv2 a partir do nível 2 e Lv3 no nível 3.

Uso (módulo `bpy` do PyPI ou Blender):
  python3 tools/blender_defenses.py assets/models/blender [nome ...] [--render pasta]
  blender --background --python tools/blender_defenses.py -- assets/models/blender barricade
Convenção: comprimento no eixo X do Blender, frente (lado dos zumbis) em -Y, topo em +Z.
"""
import math
import os
import random
import sys

import bpy  # noqa: I001 — com o módulo do PyPI, bmesh só existe depois de importar bpy
import bmesh
from mathutils import Euler, Matrix, Vector

ATLAS = 1024


# --- Utilidades ------------------------------------------------------------------------

def srgb(c):
    f = lambda x: x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    return tuple(f(x) for x in c)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def obj_from_bm(name, bm, mat, collection_tag):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    o["lv"] = collection_tag
    bpy.context.scene.collection.objects.link(o)
    return o


def place(o, loc=(0, 0, 0), rot=(0, 0, 0)):
    o.location = loc
    o.rotation_euler = Euler([math.radians(a) for a in rot])
    return o


def tube(bm, pts, radii, segs=7, jitter=0.0, rng=None, cap=True):
    """Tubo ao longo de uma polilinha (troncos, estacas, arame)."""
    rings = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        side = d.cross(Vector((0, 0, 1)))
        if side.length < 1e-3:
            side = d.cross(Vector((1, 0, 0)))
        side.normalize()
        up = d.cross(side).normalized()
        ring = []
        for k in range(segs):
            a = k * math.tau / segs
            r = radii[i] * (1.0 + (rng.uniform(-jitter, jitter) if rng else 0.0))
            ring.append(bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * r))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
    if cap:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    return rings


def log(name, length, radius, mat, rng, lv, taper=0.85, bend=0.03, segs=8, rings=7, end_mat=None):
    bm = bmesh.new()
    pts, radii = [], []
    phase = rng.uniform(0, math.tau)
    for i in range(rings):
        t = i / (rings - 1)
        pts.append(Vector((math.sin(t * math.pi + phase) * bend, math.cos(t * 2.1 + phase) * bend * 0.6,
                           (t - 0.5) * length)))
        radii.append(radius * (1.0 - (1.0 - taper) * t))
    tube(bm, pts, radii, segs, 0.08, rng)
    o = obj_from_bm(name, bm, mat, lv)
    return o


def stake(name, length, radius, wood, tip_mat, rng, lv, tip=0.28):
    """Estaca apontada: tronco + ponta talhada (madeira clara exposta)."""
    bm = bmesh.new()
    pts = [Vector((rng.uniform(-0.01, 0.01), rng.uniform(-0.01, 0.01), z)) for z in
           (0.0, length * 0.33, length * 0.66, length - tip)]
    rings = tube(bm, pts, [radius * f for f in (1.0, 0.97, 0.93, 0.9)], 7, 0.06, rng, cap=False)
    bm.faces.new(list(reversed(rings[0])))
    apex = bm.verts.new(pts[-1] + Vector((rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02), tip)))
    top = rings[-1]
    tip_faces = []
    for k in range(len(top)):
        tip_faces.append(bm.faces.new((top[k], top[(k + 1) % len(top)], apex)))
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.materials.append(wood)
    me.materials.append(tip_mat)
    n_body = len(me.polygons) - len(top)
    for i, p in enumerate(me.polygons):
        p.material_index = 1 if i >= n_body else 0
    o = bpy.data.objects.new(name, me)
    o["lv"] = lv
    bpy.context.scene.collection.objects.link(o)
    return o


def plank(name, L, W, T, mat, rng, lv, broken=False):
    """Tábua irregular: cantos lascados, leve empeno e ponta quebrada opcional."""
    bm = bmesh.new()
    nx = 8
    top, bot = [], []
    for i in range(nx + 1):
        x = -L / 2 + L * i / nx
        warp = math.sin(i / nx * math.pi) * rng.uniform(-0.01, 0.01)
        for zs, lst in ((W / 2, top), (-W / 2, bot)):
            z = zs + rng.uniform(-0.006, 0.006)
            if broken and i == nx:
                z = zs * rng.uniform(0.1, 0.9) if zs > 0 else zs
                x -= rng.uniform(0.03, 0.12)
            lst.append((x, warp, z))
    verts = []
    for y in (-T / 2, T / 2):
        row_t = [bm.verts.new((x, wy + y, z)) for x, wy, z in top]
        row_b = [bm.verts.new((x, wy + y, z)) for x, wy, z in bot]
        verts.append((row_t, row_b))
    (ft, fb), (bt, bb) = verts
    for i in range(nx):
        bm.faces.new((fb[i], fb[i + 1], ft[i + 1], ft[i]))
        bm.faces.new((bt[i], bt[i + 1], bb[i + 1], bb[i]))
        bm.faces.new((ft[i], ft[i + 1], bt[i + 1], bt[i]))
        bm.faces.new((bb[i], bb[i + 1], fb[i + 1], fb[i]))
    bm.faces.new((fb[0], ft[0], bt[0], bb[0]))
    bm.faces.new((bb[nx], bt[nx], ft[nx], fb[nx]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, mat, lv)


def tin_sheet(name, w, h, mat, rng, lv, corrugate=0.022):
    """Chapa de zinco ondulada, amassada e com um canto dobrado."""
    bm = bmesh.new()
    nx, nz = 14, 6
    grid = []
    for j in range(nz + 1):
        row = []
        for i in range(nx + 1):
            x = -w / 2 + w * i / nx
            z = -h / 2 + h * j / nz
            y = math.sin(x * 38.0) * corrugate
            y += rng.uniform(-0.008, 0.008) + 0.03 * math.exp(-((x - w * 0.25) ** 2 + (z - h * 0.1) ** 2) / 0.02)
            if i > nx - 3 and j > nz - 3:
                y -= 0.06 * (i - (nx - 3)) * (j - (nz - 3)) / 9.0
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for j in range(nz):
        for i in range(nx):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    ext = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.y += 0.006
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, mat, lv)


def sandbag(name, mat, rng, lv, size=(0.5, 0.3, 0.17)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges, cuts=2, use_grid_fill=True)
    for _ in range(4):
        bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.6, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0] * 2, v.co.y * size[1] * 2, v.co.z * size[2] * 2))
        v.co.z -= abs(v.co.x) * 0.05 + rng.uniform(0, 0.01)
    return obj_from_bm(name, bm, mat, lv)


def barbed_wire(name, length, coil_r, mat, rng, lv, loops=11):
    bm = bmesh.new()
    pts = []
    n = loops * 8
    for i in range(n + 1):
        t = i / n
        a = t * loops * math.tau
        pts.append(Vector(((t - 0.5) * length, math.cos(a) * coil_r, math.sin(a) * coil_r * 0.8)))
    tube(bm, pts, [0.008] * len(pts), 3, 0.0, None)
    # Farpas: pequenos "X" planos ao longo do arame (2 triângulos cada).
    for i in range(2, n, 4):
        p = pts[i]
        for d, s_ in ((Vector((0.025, 0.02, 0.03)), Vector((0.006, 0, 0))), (Vector((-0.02, 0.03, -0.025)), Vector((0, 0, 0.006)))):
            a1, a2 = bm.verts.new(p - d - s_), bm.verts.new(p - d + s_)
            b1, b2 = bm.verts.new(p + d + s_), bm.verts.new(p + d - s_)
            bm.faces.new((a1, a2, b1, b2))
    return obj_from_bm(name, bm, mat, lv)


def skull(name, bone, dark, lv):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=9, radius=0.1)
    for v in bm.verts:
        v.co.y *= 1.15
        if v.co.z < -0.03:
            v.co.x *= 0.8
    me_faces = len(bm.faces)
    for sx in (-1, 1):
        r = bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=4, radius=0.026)
        for v in r["verts"]:
            v.co += Vector((sx * 0.038, -0.095, 0.01))
    r = bmesh.ops.create_cube(bm, size=1.0)
    for v in r["verts"]:
        v.co = Vector((v.co.x * 0.11, v.co.y * 0.08, v.co.z * 0.05)) + Vector((0, -0.06, -0.09))
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.materials.append(bone)
    me.materials.append(dark)
    for i, p in enumerate(me.polygons):
        if me_faces <= i < me_faces + 2 * 24:
            p.material_index = 1
    o = bpy.data.objects.new(name, me)
    o["lv"] = lv
    bpy.context.scene.collection.objects.link(o)
    return o


def torus(name, major, minor, mat, lv):
    bm = bmesh.new()
    seg, ring = 14, 6
    vs = []
    for i in range(seg):
        a = i * math.tau / seg
        c = Vector((math.cos(a) * major, math.sin(a) * major, 0))
        row = []
        for j in range(ring):
            b = j * math.tau / ring
            n = Vector((math.cos(a) * math.cos(b), math.sin(a) * math.cos(b), math.sin(b)))
            row.append(bm.verts.new(c + n * minor))
        vs.append(row)
    for i in range(seg):
        for j in range(ring):
            bm.faces.new((vs[i][j], vs[(i + 1) % seg][j], vs[(i + 1) % seg][(j + 1) % ring], vs[i][(j + 1) % ring]))
    return obj_from_bm(name, bm, mat, lv)


# --- Materiais procedurais (assados no atlas) ---------------------------------------------

def _mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.9
    return m, nt, bsdf


def _ramp(nt, fac, stops):
    n = nt.nodes.new("ShaderNodeValToRGB")
    els = n.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], (*srgb(stops[0][1]), 1)
    els[1].position, els[1].color = stops[-1][0], (*srgb(stops[-1][1]), 1)
    for p, c in stops[1:-1]:
        e = els.new(p)
        e.color = (*srgb(c), 1)
    nt.links.new(fac, n.inputs[0])
    return n.outputs[0]


def _noise(nt, scale, detail=6.0, rough=0.6, vec=None):
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    n.inputs["Roughness"].default_value = rough
    if vec is not None:
        nt.links.new(vec, n.inputs["Vector"])
    return n.outputs["Fac"]


def _mix(nt, fac, a, b, blend="MIX"):
    n = nt.nodes.new("ShaderNodeMix")
    n.data_type = "RGBA"
    n.blend_type = blend
    n.clamp_factor = True
    for sock, v in ((n.inputs[0], fac), (n.inputs[6], a), (n.inputs[7], b)):
        if isinstance(v, float):
            sock.default_value = v
        elif isinstance(v, tuple):
            sock.default_value = (*srgb(v), 1)
        else:
            nt.links.new(v, sock)
    return n.outputs[2]


def _coords(nt, scale=(1, 1, 1)):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    vm = nt.nodes.new("ShaderNodeVectorMath")
    vm.operation = "MULTIPLY"
    vm.inputs[1].default_value = scale
    nt.links.new(tc.outputs["Object"], vm.inputs[0])
    return vm.outputs[0]


def _height_dirt(nt, color):
    """Escurece a parte de baixo (lama/sujeira subindo do chão)."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    mp = nt.nodes.new("ShaderNodeMapRange")
    mp.inputs["From Min"].default_value = 0.0
    mp.inputs["From Max"].default_value = 0.45
    mp.inputs["To Min"].default_value = 0.75
    mp.inputs["To Max"].default_value = 0.0
    nt.links.new(sep.outputs[2], mp.inputs["Value"])
    return _mix(nt, mp.outputs[0], color, (0.09, 0.07, 0.05))


def mat_old_wood(name="old_wood", blood=True):
    m, nt, bsdf = _mat(name)
    # Veios ao longo do comprimento (X): faixas que variam em Z, esticadas em X e distorcidas por ruído.
    grain_v = _coords(nt, (0.25, 1.0, 1.0))
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "Z"
    wave.inputs["Scale"].default_value = 9.0
    wave.inputs["Distortion"].default_value = 2.5
    wave.inputs["Detail"].default_value = 4.0
    wave.inputs["Detail Scale"].default_value = 2.0
    nt.links.new(grain_v, wave.inputs["Vector"])
    fine = _noise(nt, 40.0, 3.0, 0.5, _coords(nt, (0.15, 1.0, 3.0)))
    gr = _mix(nt, 0.35, wave.outputs["Fac"], fine)
    base = _ramp(nt, gr, [(0.15, (0.24, 0.19, 0.14)), (0.5, (0.4, 0.34, 0.27)), (0.85, (0.53, 0.47, 0.4))])
    blotch = _ramp(nt, _noise(nt, 6.0, 8.0, 0.7), [(0.35, (0.25, 0.22, 0.2)), (0.7, (1, 1, 1))])
    c = _mix(nt, 0.8, base, blotch, "MULTIPLY")
    if blood:
        mask = _ramp(nt, _noise(nt, 3.5, 4.0, 0.55), [(0.66, (0, 0, 0)), (0.7, (1, 1, 1))])
        c = _mix(nt, mask, c, (0.2, 0.03, 0.02))
    nt.links.new(_height_dirt(nt, c), bsdf.inputs["Base Color"])
    return m


def mat_bark():
    m, nt, bsdf = _mat("bark")
    v = _coords(nt, (8.0, 8.0, 2.0))
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 3.0
    nt.links.new(v, vor.inputs["Vector"])
    cracks = _ramp(nt, vor.outputs["Distance"], [(0.0, (0.07, 0.055, 0.04)), (0.08, (0.3, 0.24, 0.17)), (1.0, (0.4, 0.33, 0.25))])
    c = _mix(nt, 0.6, cracks, _ramp(nt, _noise(nt, 12.0), [(0.3, (0.6, 0.55, 0.5)), (0.7, (1, 1, 1))]), "MULTIPLY")
    nt.links.new(_height_dirt(nt, c), bsdf.inputs["Base Color"])
    return m


def mat_fresh_cut():
    m, nt, bsdf = _mat("fresh_cut")
    c = _ramp(nt, _noise(nt, 20.0, 4.0), [(0.3, (0.42, 0.31, 0.19)), (0.7, (0.56, 0.43, 0.28))])
    nt.links.new(c, bsdf.inputs["Base Color"])
    return m


def mat_rust():
    m, nt, bsdf = _mat("rust")
    # Zinco velho: metal cinza manchado, com placas de ferrugem alaranjada e escura.
    big = _noise(nt, 3.0, 8.0, 0.7)
    metal = _ramp(nt, _noise(nt, 18.0, 6.0, 0.6), [(0.3, (0.24, 0.24, 0.23)), (0.7, (0.4, 0.39, 0.37))])
    rustc = _ramp(nt, _noise(nt, 9.0, 8.0, 0.7), [(0.3, (0.15, 0.07, 0.035)), (0.5, (0.33, 0.15, 0.06)),
                                                  (0.7, (0.44, 0.23, 0.1))])
    rmask = _ramp(nt, big, [(0.42, (0, 0, 0)), (0.6, (1, 1, 1))])
    c = _mix(nt, rmask, metal, rustc)
    streak = _ramp(nt, _noise(nt, 3.0, 4.0, 0.5, _coords(nt, (14.0, 14.0, 0.8))), [(0.45, (1, 1, 1)), (0.68, (0.4, 0.2, 0.1))])
    c = _mix(nt, 0.85, c, streak, "MULTIPLY")
    nt.links.new(_height_dirt(nt, c), bsdf.inputs["Base Color"])
    return m


def mat_burlap():
    m, nt, bsdf = _mat("burlap")
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = 60.0
    wave.inputs["Distortion"].default_value = 0.5
    weave = _ramp(nt, wave.outputs["Fac"], [(0.2, (0.27, 0.22, 0.15)), (0.8, (0.38, 0.32, 0.22))])
    stain = _ramp(nt, _noise(nt, 5.0, 6.0), [(0.4, (0.35, 0.3, 0.25)), (0.65, (1, 1, 1))])
    nt.links.new(_height_dirt(nt, _mix(nt, 0.8, weave, stain, "MULTIPLY")), bsdf.inputs["Base Color"])
    return m


def mat_flat(name, color):
    m, nt, bsdf = _mat(name)
    c = _ramp(nt, _noise(nt, 25.0), [(0.3, tuple(x * 0.75 for x in color)), (0.7, color)])
    nt.links.new(c, bsdf.inputs["Base Color"])
    return m


# --- Barricada ----------------------------------------------------------------------------

def build_barricade():
    rng = random.Random(7)
    wood = mat_old_wood()
    bark = mat_bark()
    cut = mat_fresh_cut()
    rust = mat_rust()
    burlap = mat_burlap()
    rope = mat_flat("rope", (0.45, 0.37, 0.24))
    iron = mat_flat("iron", (0.16, 0.15, 0.15))
    bone = mat_flat("bone", (0.66, 0.6, 0.48))
    dark = mat_flat("socket", (0.03, 0.02, 0.02))
    L = 3.0
    # Nível 1: base improvisada.
    place(log("skid", L + 0.15, 0.085, bark, rng, 1, bend=0.02), (0, 0.05, 0.1), (0, 90, 0))
    for x in (-1.12, 1.12):
        for sgn in (-1, 1):
            place(log("xframe", 1.95, 0.07, bark, rng, 1), (x + sgn * 0.04, 0.0, 0.78), (sgn * 38, 0, rng.uniform(-4, 4)))
        place(torus("lash", 0.085, 0.022, rope, 1), (x, 0.0, 0.78), (0, 90, 0))
    for i, z in enumerate((0.38, 0.66, 0.94, 1.2)):
        Lp = rng.uniform(2.55, 3.1)
        broken = i == 2
        place(plank("plank", Lp, rng.uniform(0.2, 0.25), 0.045, wood, rng, 1, broken),
              (rng.uniform(-0.18, 0.18), -0.14, z), (0, rng.uniform(-4.5, 4.5), 0))
    xs = [-1.35, -0.9, -0.45, 0.0, 0.45, 0.9, 1.35]
    for x in xs:
        h = rng.uniform(1.35, 1.75)
        place(stake("stake", h, 0.05, bark, cut, rng, 1), (x + rng.uniform(-0.06, 0.06), 0.05, 0.02),
              (rng.uniform(-5, 5), rng.uniform(-6, 6), 0))
    for x in (-1.0, 0.1, 1.05):
        place(stake("spear", 1.3, 0.045, bark, cut, rng, 1), (x, 0.0, 0.15), (55 + rng.uniform(-6, 6), 0, rng.uniform(-10, 10)))
    # Nível 2: chapas de zinco enferrujadas e sacos de areia.
    place(tin_sheet("tin", 1.25, 0.85, rust, rng, 2), (-0.68, -0.2, 0.72), (0, 3, 0))
    place(tin_sheet("tin", 1.1, 0.7, rust, rng, 2), (0.72, -0.21, 0.62), (0, -5, 0))
    for i, x in enumerate((-1.05, -0.5, 0.05, 0.6, 1.1)):
        place(sandbag("bag", burlap, rng, 2), (x, -0.42, 0.12), (0, 0, rng.uniform(-8, 8)))
    for x in (-0.78, -0.22, 0.38, 0.9):
        place(sandbag("bag", burlap, rng, 2), (x, -0.4, 0.33), (0, rng.uniform(-6, 6), rng.uniform(-12, 12)))
    # Nível 3: arame farpado no topo, pregos de ferro e crânio de aviso.
    place(barbed_wire("wire", L - 0.2, 0.13, iron, rng, 3), (0, -0.05, 1.5), (0, 0, 0))
    for i in range(9):
        x = -1.3 + i * 0.32
        place(stake("nail", 0.32, 0.016, iron, iron, rng, 3, tip=0.1), (x, -0.25, 0.75 + (i % 2) * 0.3),
              (90 + rng.uniform(-8, 8), 0, rng.uniform(-10, 10)))
    # Crânio de aviso espetado numa estaca mais alta.
    place(stake("skullpole", 1.95, 0.04, bark, cut, rng, 3, tip=0.2), (0.18, 0.12, 0.0), (0, 0, 0))
    place(skull("skull", bone, dark, 3), (0.18, 0.12, 1.86), (rng.uniform(-6, 6), 0, 12))


# --- Muro de pedra ------------------------------------------------------------------------

def mat_stone():
    m, nt, bsdf = _mat("stone")
    v = _coords(nt, (1.0, 1.0, 1.0))
    base = _ramp(nt, _noise(nt, 2.5, 6.0, 0.6, v), [(0.3, (0.27, 0.26, 0.24)), (0.5, (0.4, 0.38, 0.35)),
                                                   (0.7, (0.5, 0.47, 0.42))])
    pits = _ramp(nt, _noise(nt, 28.0, 8.0, 0.8, v), [(0.35, (0.55, 0.53, 0.5)), (0.6, (1, 1, 1))])
    c = _mix(nt, 0.8, base, pits, "MULTIPLY")
    # Fuligem escorrida (fogo antigo) e musgo escuro no topo das pedras.
    soot = _ramp(nt, _noise(nt, 2.0, 4.0, 0.5, _coords(nt, (3.0, 3.0, 0.5))), [(0.5, (1, 1, 1)), (0.72, (0.25, 0.23, 0.22))])
    c = _mix(nt, 1.0, c, soot, "MULTIPLY")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sep.inputs[0])
    up = nt.nodes.new("ShaderNodeMapRange")
    up.inputs["From Min"].default_value = 0.55
    up.inputs["From Max"].default_value = 0.95
    nt.links.new(sep.outputs[2], up.inputs["Value"])
    moss_n = _ramp(nt, _noise(nt, 9.0, 6.0, 0.6), [(0.4, (0, 0, 0)), (0.62, (1, 1, 1))])
    mm = nt.nodes.new("ShaderNodeMath")
    mm.operation = "MULTIPLY"
    nt.links.new(up.outputs[0], mm.inputs[0])
    nt.links.new(moss_n, mm.inputs[1])
    c = _mix(nt, mm.outputs[0], c, (0.16, 0.18, 0.09))
    nt.links.new(_height_dirt(nt, c), bsdf.inputs["Base Color"])
    return m


def rough_stone(name, size, mat, rng, lv, jitter=0.14):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges, cuts=1, use_grid_fill=True)
    for v in bm.verts:
        v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * jitter * 0.5
    bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.35, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    return obj_from_bm(name, bm, mat, lv)


def box(name, size, mat, lv):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    return obj_from_bm(name, bm, mat, lv)


def build_stone_wall():
    rng = random.Random(21)
    stone = mat_stone()
    mortar = mat_flat("mortar", (0.11, 0.1, 0.09))
    wood = mat_old_wood("old_wood", blood=False)
    bark = mat_bark()
    cut = mat_fresh_cut()
    rust = mat_rust()
    iron = mat_flat("iron", (0.16, 0.15, 0.15))
    bone = mat_flat("bone", (0.66, 0.6, 0.48))
    dark = mat_flat("socket", (0.03, 0.02, 0.02))
    L, D = 4.0, 0.9
    # Perfil do topo desmoronado (altura por posição em X).
    def top_at(x):
        return 2.15 + 0.18 * math.sin(x * 1.7 + 0.4) - (0.45 if -0.6 < x < 0.35 else 0.0) * (1 - abs(x + 0.12) / 0.48)
    # Núcleo de argamassa só até abaixo da parte desmoronada (não aparece no topo).
    place(box("core", (L - 0.08, D - 0.16, 1.5), mortar, 1), (0, 0, 0.75))
    z = 0.0
    course = 0
    while z < 2.4:
        h = rng.uniform(0.27, 0.4) * (1.15 if course == 0 else 1.0)
        x = -L / 2 + (rng.uniform(0, 0.3) if course % 2 else 0.0)
        while x < L / 2 - 0.05:
            w = min(rng.uniform(0.38, 0.75), L / 2 - x)
            cx = x + w / 2
            if z + h * 0.5 < top_at(cx) and w > 0.12:
                for side in ((-0.22, 0.48), (0.22, 0.48)) if rng.random() < 0.35 else ((0.0, D),):
                    sx = (w - 0.03) / 2
                    place(rough_stone("st", (sx * 2.06, side[1] * rng.uniform(0.95, 1.05), h * 1.03 - 0.02), stone, rng, 1),
                          (cx, side[0] + rng.uniform(-0.025, 0.025), z + h / 2), (rng.uniform(-3, 3), rng.uniform(-3, 3), rng.uniform(-4, 4)))
            x += w
        z += h
        course += 1
    # Vigas de madeira (estrutura antiga) e entulho na base.
    for x in (-L / 2 - 0.05, L / 2 + 0.05):
        place(log("post", 2.5, 0.11, bark, rng, 1, bend=0.02), (x, 0.0, 1.2))
    place(log("beam", L + 0.3, 0.085, bark, rng, 1, bend=0.03), (0, -0.5, 1.15), (0, 90, 0))
    for i in range(7):
        sgn = -1 if i % 2 else 1
        place(rough_stone("rubble", (rng.uniform(0.16, 0.34),) * 3, stone, rng, 1, 0.25),
              (rng.uniform(-1.8, 1.8), sgn * rng.uniform(0.55, 0.8), 0.06), (rng.uniform(0, 40), rng.uniform(0, 40), 0))
    # Nível 2: paliçada de estacas e tábuas no topo.
    for i in range(11):
        x = -1.85 + i * 0.37
        t = top_at(x)
        place(stake("pal", rng.uniform(0.7, 1.0), 0.05, bark, cut, rng, 2), (x, -0.25, t - 0.15),
              (-12 + rng.uniform(-5, 5), rng.uniform(-5, 5), 0))
    for zz in (0.12, 0.4):
        place(plank("hoard", L - 0.2, 0.2, 0.04, wood, rng, 2), (0, -0.33, 2.0 + zz), (0, rng.uniform(-3, 3), 0))
    # Nível 3: remendos de zinco, pontas de ferro, arame farpado e crânios.
    place(tin_sheet("patch", 1.0, 0.9, rust, rng, 3), (-0.15, -0.48, 1.45), (0, 4, 0))
    place(tin_sheet("patch", 0.8, 0.7, rust, rng, 3), (1.3, -0.48, 0.75), (0, -6, 0))
    for i in range(8):
        x = -1.7 + i * 0.48
        place(stake("spike", 0.4, 0.02, iron, iron, rng, 3, tip=0.14), (x, -0.42, 0.7 + (i % 3) * 0.35),
              (90 + rng.uniform(-8, 8), 0, rng.uniform(-12, 12)))
    place(barbed_wire("wire", L - 0.3, 0.12, iron, rng, 3, loops=14), (0, -0.25, 2.75))
    for x in (-1.48, 1.11):
        place(stake("skullpole", 1.1, 0.035, bark, cut, rng, 3, tip=0.15), (x, -0.25, top_at(x) - 0.1))
        place(skull("skull", bone, dark, 3), (x, -0.25, top_at(x) + 1.0), (rng.uniform(-8, 8), 0, rng.uniform(-20, 20)))


# --- Muro de ferro (sucata soldada) -----------------------------------------------------

def mat_painted_metal():
    """Chapa pintada de verde-oliva desbotado, com a tinta descascada mostrando ferrugem."""
    m, nt, bsdf = _mat("painted_metal")
    paint = _ramp(nt, _noise(nt, 6.0, 5.0, 0.5), [(0.3, (0.2, 0.23, 0.16)), (0.7, (0.29, 0.31, 0.22))])
    rustc = _ramp(nt, _noise(nt, 14.0, 8.0, 0.7), [(0.3, (0.16, 0.08, 0.04)), (0.6, (0.34, 0.16, 0.07))])
    chip = _ramp(nt, _noise(nt, 7.0, 10.0, 0.75), [(0.55, (0, 0, 0)), (0.6, (1, 1, 1))])
    c = _mix(nt, chip, paint, rustc)
    streak = _ramp(nt, _noise(nt, 3.0, 4.0, 0.5, _coords(nt, (16.0, 16.0, 0.7))), [(0.45, (1, 1, 1)), (0.7, (0.45, 0.25, 0.15))])
    c = _mix(nt, 0.9, c, streak, "MULTIPLY")
    nt.links.new(_height_dirt(nt, c), bsdf.inputs["Base Color"])
    return m


def ibeam(name, h, mat, lv, w=0.16):
    bm = bmesh.new()
    for size, off in (((w, 0.03, h), (0, -w * 0.5, 0)), ((w, 0.03, h), (0, w * 0.5, 0)), ((0.03, w, h), (0, 0, 0))):
        r = bmesh.ops.create_cube(bm, size=1.0)
        for v in r["verts"]:
            v.co = Vector((v.co.x * size[0] + off[0], v.co.y * size[1] + off[1], v.co.z * size[2] + h / 2))
    return obj_from_bm(name, bm, mat, lv)


def plate(name, w, h, t, mat, rivet_mat, rng, lv, rivets=True):
    """Chapa levemente empenada com rebites na borda (frente em -Y)."""
    bm = bmesh.new()
    nx, nz = 6, 6
    for side in (-t / 2, t / 2):
        pass
    grid_f, grid_b = [], []
    for j in range(nz + 1):
        rf, rb = [], []
        for i in range(nx + 1):
            x = -w / 2 + w * i / nx
            z = -h / 2 + h * j / nz
            dent = rng.uniform(-0.006, 0.006) + 0.025 * math.exp(-((x - w * rng.uniform(-0.3, 0.3)) ** 2 + z ** 2) / 0.05) * (1 if rng.random() < 0.3 else 0)
            rf.append(bm.verts.new((x, -t / 2 + dent, z)))
            rb.append(bm.verts.new((x, t / 2 + dent, z)))
        grid_f.append(rf)
        grid_b.append(rb)
    for j in range(nz):
        for i in range(nx):
            bm.faces.new((grid_f[j][i], grid_f[j + 1][i], grid_f[j + 1][i + 1], grid_f[j][i + 1]))
            bm.faces.new((grid_b[j][i], grid_b[j][i + 1], grid_b[j + 1][i + 1], grid_b[j + 1][i]))
    for i in range(nx):
        bm.faces.new((grid_f[0][i], grid_f[0][i + 1], grid_b[0][i + 1], grid_b[0][i]))
        bm.faces.new((grid_f[nz][i], grid_b[nz][i], grid_b[nz][i + 1], grid_f[nz][i + 1]))
    for j in range(nz):
        bm.faces.new((grid_f[j][0], grid_b[j][0], grid_b[j + 1][0], grid_f[j + 1][0]))
        bm.faces.new((grid_f[j][nx], grid_f[j + 1][nx], grid_b[j + 1][nx], grid_b[j][nx]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me_plate = len(bm.faces)
    if rivets:
        step = 0.3
        pts = []
        nxr = max(2, int(w / step))
        nzr = max(2, int(h / step))
        for i in range(nxr + 1):
            for z in (-h / 2 + 0.04, h / 2 - 0.04):
                pts.append((-w / 2 + 0.04 + (w - 0.08) * i / nxr, z))
        for j in range(1, nzr):
            for x in (-w / 2 + 0.04, w / 2 - 0.04):
                pts.append((x, -h / 2 + 0.04 + (h - 0.08) * j / nzr))
        for x, z in pts:
            r = bmesh.ops.create_cone(bm, cap_ends=True, segments=4, radius1=0.02, radius2=0.013, depth=0.016)
            for v in r["verts"]:
                v.co = Vector((v.co.x + x, v.co.z - t / 2 - 0.006, v.co.y + z))
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    me.materials.append(rivet_mat)
    for i, p in enumerate(me.polygons):
        p.material_index = 0 if i < me_plate else 1
    o = bpy.data.objects.new(name, me)
    o["lv"] = lv
    bpy.context.scene.collection.objects.link(o)
    return o


def saw_blade(name, r, mat, lv, teeth=18):
    bm = bmesh.new()
    outer = []
    for i in range(teeth * 2):
        a = i * math.pi / teeth
        rr = r if i % 2 == 0 else r * 0.86
        outer.append((math.cos(a) * rr, math.sin(a) * rr))
    top = [bm.verts.new((x, -0.006, z)) for x, z in outer]
    bot = [bm.verts.new((x, 0.006, z)) for x, z in outer]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(outer)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((top[i], top[j], bot[j], bot[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, mat, lv)


def chain(name, length, mat, lv, link=0.07):
    bm = bmesh.new()
    n = int(length / (link * 0.8))
    for i in range(n):
        z = -i * link * 0.8
        seg, ring = 6, 3
        rot = Matrix.Rotation(math.pi / 2 * (i % 2), 4, "Z")
        vs = []
        for a_i in range(seg):
            a = a_i * math.tau / seg
            c = Vector((math.cos(a) * link * 0.35, 0, math.sin(a) * link * 0.55))
            row = []
            for b_i in range(ring):
                b = b_i * math.tau / ring
                nrm = Vector((math.cos(a) * math.cos(b), math.sin(b), math.sin(a) * math.cos(b)))
                row.append(bm.verts.new(rot @ (c + nrm * 0.011) + Vector((0, 0, z))))
            vs.append(row)
        for a_i in range(seg):
            for b_i in range(ring):
                bm.faces.new((vs[a_i][b_i], vs[(a_i + 1) % seg][b_i], vs[(a_i + 1) % seg][(b_i + 1) % ring], vs[a_i][(b_i + 1) % ring]))
    return obj_from_bm(name, bm, mat, lv)


def build_iron_wall():
    rng = random.Random(33)
    painted = mat_painted_metal()
    rust = mat_rust()
    iron = mat_flat("iron", (0.16, 0.15, 0.15))
    stone = mat_stone()
    bone = mat_flat("bone", (0.66, 0.6, 0.48))
    dark = mat_flat("socket", (0.03, 0.02, 0.02))
    blade = mat_flat("blade", (0.42, 0.42, 0.43))
    L = 4.0
    # Nível 1: vigas em I, chapas soldadas com rebites, base de pedra e topo serrilhado.
    for x in (-1.95, -0.65, 0.65, 1.95):
        place(ibeam("beam", 2.75, rust, 1), (x, 0.0, 0.0), (0, 0, rng.uniform(-1.5, 1.5)))
    for i in range(9):
        place(rough_stone("foot", (0.5, 1.05, 0.32), stone, rng, 1, 0.18), (-1.9 + i * 0.475, 0, 0.14))
    xs = [-2.0, -1.25, -0.4, 0.45, 1.25, 2.0]
    for r_i, (z0, z1) in enumerate(((0.28, 1.15), (1.1, 1.95), (1.9, 2.55))):
        for k in range(len(xs) - 1):
            w = xs[k + 1] - xs[k] + rng.uniform(0.02, 0.1)
            top = z1 + (rng.uniform(-0.25, 0.12) if r_i == 2 else 0.0)
            h = top - z0
            m = painted if rng.random() < 0.55 else rust
            place(plate("plate", w, h, 0.05, m, iron, rng, 1), ((xs[k] + xs[k + 1]) / 2 + rng.uniform(-0.03, 0.03),
                  -0.09 - r_i * 0.012 - (k % 2) * 0.01, z0 + h / 2), (0, rng.uniform(-2.5, 2.5), 0))
    # Nível 2: vergalhões afiados no topo e chapas de reforço em diagonal.
    for i in range(14):
        x = -1.9 + i * 0.29
        place(stake("rebar", rng.uniform(0.4, 0.75), 0.016, iron, iron, rng, 2, tip=0.12),
              (x, -0.02, 2.35 + rng.uniform(-0.15, 0.05)), (rng.uniform(-14, 6), rng.uniform(-10, 10), 0))
    for x in (-1.3, 1.3):
        place(plate("brace", 0.22, 2.2, 0.04, rust, iron, rng, 2), (x, -0.17, 1.35), (0, 32 if x < 0 else -32, 0))
    # Nível 3: arame farpado, serras soldadas na frente, correntes e um crânio.
    place(barbed_wire("wire", L - 0.2, 0.13, iron, rng, 3, loops=14), (0, -0.02, 2.8))
    for x, z in ((-1.3, 0.75), (0.0, 1.5), (1.3, 0.75)):
        place(saw_blade("saw", 0.26, blade, 3), (x, -0.17, z), (0, rng.uniform(0, 30), 0))
    for x in (-0.65, 0.65):
        place(chain("chain", 1.1, iron, 3), (x, -0.2, 2.45))
    place(skull("skull", bone, dark, 3), (0.65, -0.24, 1.3), (rng.uniform(-10, 10), 0, 6))


# --- Armadilha de espinhos ---------------------------------------------------------------

def mat_bloody_iron():
    m, nt, bsdf = _mat("bloody_iron")
    c = _ramp(nt, _noise(nt, 10.0, 6.0, 0.6), [(0.3, (0.13, 0.1, 0.09)), (0.55, (0.36, 0.17, 0.07)), (0.75, (0.3, 0.29, 0.28))])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    tip = nt.nodes.new("ShaderNodeMapRange")
    tip.inputs["From Min"].default_value = 0.12
    tip.inputs["From Max"].default_value = 0.32
    nt.links.new(sep.outputs[2], tip.inputs["Value"])
    c = _mix(nt, tip.outputs[0], c, (0.28, 0.03, 0.02))
    nt.links.new(c, bsdf.inputs["Base Color"])
    return m


def build_spikes():
    rng = random.Random(44)
    wood = mat_old_wood()
    bloody = mat_bloody_iron()
    iron = mat_flat("iron", (0.16, 0.15, 0.15))
    bark = mat_bark()
    cut = mat_fresh_cut()
    bone = mat_flat("bone", (0.66, 0.6, 0.48))
    dark = mat_flat("socket", (0.03, 0.02, 0.02))
    S = 2.0
    # Nível 1: estrado de tábuas cravejado de pregos e lâminas enferrujadas (pontas ensanguentadas).
    for i in range(6):
        place(plank("deck", S + rng.uniform(-0.05, 0.08), 0.3, 0.05, wood, rng, 1, broken=(i == 4)),
              (rng.uniform(-0.04, 0.04), -0.85 + i * 0.34, 0.06), (90, 0, rng.uniform(-3, 3)))
    for x in (-0.8, 0.8):
        place(log("rail", S, 0.05, bark, rng, 1, bend=0.01), (x, 0, 0.03), (90, 0, 0))
    for gx in range(6):
        for gy in range(6):
            x = -0.8 + gx * 0.32 + rng.uniform(-0.05, 0.05)
            y = -0.8 + gy * 0.32 + rng.uniform(-0.05, 0.05)
            place(stake("nail", rng.uniform(0.34, 0.5), 0.032, bloody, bloody, rng, 1, tip=0.2), (x, y, 0.06),
                  (rng.uniform(-14, 14), rng.uniform(-14, 14), 0))
    # Nível 2: lâminas triangulares (sucata afiada) entre os pregos e estacas nas bordas.
    for i in range(10):
        bm = bmesh.new()
        w = rng.uniform(0.12, 0.2)
        hgt = rng.uniform(0.25, 0.38)
        v = [bm.verts.new(p) for p in ((-w / 2, 0, 0), (w / 2, 0, 0), (rng.uniform(-0.03, 0.03), 0, hgt))]
        v2 = [bm.verts.new((p.co.x, 0.012, p.co.z)) for p in v]
        bm.faces.new(v)
        bm.faces.new(list(reversed(v2)))
        for k in range(3):
            bm.faces.new((v[k], v[(k + 1) % 3], v2[(k + 1) % 3], v2[k]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        place(obj_from_bm("shard", bm, bloody, 2), (rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8), 0.07),
              (rng.uniform(-10, 10), 0, rng.uniform(0, 180)))
    for i in range(8):
        a = i * math.tau / 8 + 0.3
        place(stake("edge", 0.6, 0.04, bark, cut, rng, 2), (math.cos(a) * 1.0, math.sin(a) * 1.0, 0.0),
              (math.degrees(math.sin(a)) * -0.5, math.degrees(math.cos(a)) * 0.5, 0))
    # Nível 3: arame farpado em volta e ossos espalhados.
    for i, (x, y, r) in enumerate(((0, -1.0, 0), (0, 1.0, 0), (-1.0, 0, 90), (1.0, 0, 90))):
        place(barbed_wire("wire", 1.9, 0.08, iron, rng, 3, loops=8), (x, y, 0.1), (0, 0, r))
    place(skull("skull", bone, dark, 3), (0.35, 0.25, 0.14), (rng.uniform(-30, 30), 20, rng.uniform(0, 360)))
    for i in range(4):
        place(log("bone", 0.32, 0.022, bone, rng, 3, bend=0.0), (rng.uniform(-0.7, 0.7), rng.uniform(-0.7, 0.7), 0.1),
              (90, 0, rng.uniform(0, 180)))


# --- Torre de arqueiros (atalaia de sucata) ------------------------------------------

def ladder(name, h, mat, rng, lv, w=0.42):
    objs = []
    for x in (-w / 2, w / 2):
        o = log(name + "_rail", h, 0.03, mat, rng, lv, bend=0.0, segs=6)
        place(o, (x, 0, h / 2))
    for i in range(int(h / 0.36)):
        o = log(name + "_rung", w + 0.08, 0.02, mat, rng, lv, bend=0.0, segs=5)
        place(o, (0, 0, 0.3 + i * 0.36), (0, 90, rng.uniform(-3, 3)))
    return objs


def build_archer_tower():
    rng = random.Random(111)
    bark = mat_bark()
    wood = mat_old_wood()
    cut = mat_fresh_cut()
    rust = mat_rust()
    burlap = mat_burlap()
    iron = mat_flat("iron", (0.16, 0.15, 0.15))
    rope = mat_flat("rope", (0.4, 0.33, 0.22))
    cloth = mat_flat("rag", (0.24, 0.07, 0.05))
    bone = mat_flat("bone", (0.66, 0.6, 0.48))
    dark = mat_flat("socket", (0.03, 0.02, 0.02))
    stone = mat_stone()
    H = 4.3   # altura da plataforma
    S = 1.05  # meia largura no topo
    B = 1.3   # meia largura na base (pernas abertas)
    # Pernas de tronco inclinadas, cada uma num pé de pedras.
    for sx in (-1, 1):
        for sy in (-1, 1):
            a = Vector((sx * B, sy * B, 0.0))
            b = Vector((sx * S, sy * S, H + 0.9))
            bm = bmesh.new()
            tube(bm, [a, a.lerp(b, 0.5) + Vector((rng.uniform(-0.03, 0.03), 0, 0)), b], [0.11, 0.1, 0.09], 8, 0.06, rng)
            obj_from_bm("leg", bm, bark, 1)
            for k in range(3):
                place(rough_stone("foot", (0.22, 0.2, 0.14), stone, rng, 1, 0.25),
                      (a.x + rng.uniform(-0.2, 0.2), a.y + rng.uniform(-0.2, 0.2), 0.07), (0, 0, rng.uniform(0, 90)))
    # Travamentos em X nos quatro lados (corda amarrada nos cruzamentos).
    for side in range(4):
        ax = side % 2
        sgn = -1 if side < 2 else 1
        for z0, z1 in ((0.3, 2.2), (2.2, 4.1)):
            def at(z, t):
                w = B + (S - B) * (z / (H + 0.9))
                return Vector((t * w, sgn * w, z)) if ax == 0 else Vector((sgn * w, t * w, z))
            for t0, t1 in ((-1, 1), (1, -1)):
                bm = bmesh.new()
                tube(bm, [at(z0, t0 * 0.95), at(z1, t1 * 0.95)], [0.05, 0.05], 6, 0.05, rng)
                obj_from_bm("brace", bm, bark, 1)
            mid = at((z0 + z1) / 2, 0)
            place(torus("lash", 0.07, 0.02, rope, 1), mid.to_tuple(), (90 if ax == 0 else 0, 0 if ax == 0 else 90, 0))
    # Plataforma de tábuas com vigas por baixo.
    for x in (-S + 0.1, S - 0.1):
        place(log("joist", 2.5, 0.07, bark, rng, 1, bend=0.01), (x, 0, H - 0.08), (90, 0, 0))
    for i in range(9):
        y = -S - 0.15 + i * (2 * S + 0.3) / 8
        place(plank("deck", 2 * S + 0.45, 0.26, 0.05, wood, rng, 1, broken=(i == 7)), (rng.uniform(-0.04, 0.04), y, H), (90, 0, rng.uniform(-2, 2)))
    # Parapeito: tábuas na vertical, umas mais curtas, e postes nos cantos.
    for side in range(4):
        for k in range(7):
            t = -1 + 2 * (k + 0.5) / 7
            h = rng.uniform(0.75, 1.0)
            pos = (t * (S + 0.18), (S + 0.2) * (1 if side == 0 else -1), H + h / 2) if side < 2 else ((S + 0.2) * (1 if side == 2 else -1), t * (S + 0.18), H + h / 2)
            o = plank("pal", h, 0.28, 0.04, wood, rng, 1, broken=rng.random() < 0.3)
            place(o, pos, (0, 90, 0 if side < 2 else 90))
    for sx in (-1, 1):
        for sy in (-1, 1):
            place(log("post", 2.1, 0.055, bark, rng, 1, bend=0.0), (sx * (S + 0.2), sy * (S + 0.2), H + 1.05))
    # Telhado de zinco inclinado (cai para trás), escada e bandeira esfarrapada.
    # Meia-água: cobre só a metade de trás (de cima ainda se vê a plataforma e o parapeito).
    roof = tin_sheet("roof", 2.6, 1.5, rust, rng, 1, corrugate=0.03)
    place(roof, (0, 0.5, H + 2.05), (90 - 24, 0, 0))
    lad = ladder("ladder", H + 0.2, bark, rng, 1)
    bpy.context.view_layer.update()
    for o in [o for o in bpy.context.scene.objects if o.name.startswith("ladder")]:
        o.matrix_world = Matrix.Translation(Vector((0.3, -B - 0.25, 0))) @ Euler((math.radians(-14), 0, 0)).to_matrix().to_4x4() @ o.matrix_world
    place(log("flagpole", 1.6, 0.025, bark, rng, 1, bend=0.0), (S + 0.2, S + 0.2, H + 2.9))
    flag = plank("flag", 0.7, 0.4, 0.01, cloth, rng, 1, broken=True)
    place(flag, (S + 0.55, S + 0.2, H + 3.45), (90, 0, 0))
    # Nível 2: sacos de areia no parapeito e chapas de zinco remendando a frente.
    for k in range(5):
        place(sandbag("bag", burlap, rng, 2, (0.4, 0.22, 0.13)), (-0.9 + k * 0.45, -(S + 0.32), H + 0.95), (0, 0, rng.uniform(-8, 8)))
    for side, (pos, rot) in enumerate((((0, -(S + 0.26), H + 0.45), (0, 0, 0)), ((S + 0.26, 0, H + 0.45), (0, 0, 90)))):
        place(tin_sheet("patch", 1.6, 0.8, rust, rng, 2), pos, (rot[0] + 90 if False else 0, 0, rot[2]))
    for i in range(6):
        a = i * math.tau / 6 + 0.3
        place(stake("legspike", 0.9, 0.035, bark, cut, rng, 2), (math.cos(a) * 1.75, math.sin(a) * 1.75, 0.0),
              (math.degrees(math.sin(a)) * 0.6, -math.degrees(math.cos(a)) * 0.6, 0))
    # Nível 3: arame farpado em volta da plataforma, crânios no parapeito e lampião.
    for side in range(4):
        rot = 0 if side < 2 else 90
        pos = (0, (S + 0.24) * (1 if side == 0 else -1), H + 1.1) if side < 2 else ((S + 0.24) * (1 if side == 2 else -1), 0, H + 1.1)
        place(barbed_wire("wire", 2 * S + 0.3, 0.1, iron, rng, 3, loops=9), pos, (0, 0, rot))
    for sx, sy in ((-1, -1), (1, -1)):
        place(skull("skull", bone, dark, 3), (sx * (S + 0.2), sy * (S + 0.2), H + 2.2), (0, 0, rng.uniform(-30, 30)))
    place(barbed_wire("legwire", 2.6, 0.12, iron, rng, 3, loops=10), (0, -B - 0.05, 0.5), (0, 0, 0))


# --- Base comum: berço de dormentes (toras empilhadas em cruz) ---------------------------

def crib(bark, rng, half, layers, lv=1, z0=0.0, r=0.1):
    for k in range(layers):
        z = z0 + r + k * (2 * r * 0.9)
        for s_ in (-1, 1):
            if k % 2 == 0:
                place(log("crib", 2 * half + 0.35, r, bark, rng, lv, bend=0.01), (0, s_ * (half - r), z), (0, 90, rng.uniform(-2, 2)))
            else:
                place(log("crib", 2 * half + 0.35, r, bark, rng, lv, bend=0.01), (s_ * (half - r), 0, z), (90, 0, rng.uniform(-2, 2)))
    top = z0 + layers * 2 * r * 0.9 + r * 0.4
    return top


def deck(wood, rng, half, z, lv=1):
    n = int(2 * half / 0.26) + 1
    for i in range(n):
        x = -half + i * (2 * half) / (n - 1)
        place(plank("deck", 2 * half + 0.1, 0.26, 0.05, wood, rng, lv), (x, 0, z), (90, 0, 90 + rng.uniform(-2, 2)))


# --- Balista ----------------------------------------------------------------------------

def build_ballista():
    rng = random.Random(222)
    bark = mat_bark()
    wood = mat_old_wood("old_wood", blood=False)
    cut = mat_fresh_cut()
    rust = mat_rust()
    burlap = mat_burlap()
    iron = mat_flat("iron", (0.16, 0.15, 0.15))
    rope = mat_flat("rope", (0.42, 0.35, 0.23))
    bone = mat_flat("bone", (0.66, 0.6, 0.48))
    dark = mat_flat("socket", (0.03, 0.02, 0.02))
    painted = mat_painted_metal()
    half = 1.15
    top = crib(bark, rng, half, 5)
    deck(wood, rng, half, top)
    z = top + 0.03
    # Arma (gira): poste central, berço em A, coronha, arcos de madeira, corda, virote e manivela.
    T = 0
    place(log("pivot", 0.9, 0.12, bark, rng, T, bend=0.0), (0, 0, z + 0.45))
    place(torus("collar", 0.14, 0.03, iron, T), (0, 0, z + 0.85), (0, 0, 0))
    place(box("stock", (0.2, 2.3, 0.18), wood, T), (0, 0.15, z + 1.0))
    place(box("trough", (0.08, 2.0, 0.04), iron, T), (0, 0.2, z + 1.1))
    for sx in (-1, 1):
        pts = [Vector((sx * 0.08, 1.05, z + 1.02)), Vector((sx * 0.55, 0.95, z + 1.03)), Vector((sx * 0.95, 0.72, z + 1.04)),
               Vector((sx * 1.2, 0.42, z + 1.05))]
        bm = bmesh.new()
        tube(bm, pts, [0.075, 0.065, 0.05, 0.04], 7, 0.05, rng)
        obj_from_bm("arm", bm, bark, T)
        bm = bmesh.new()
        tube(bm, [pts[-1], Vector((0, -0.55, z + 1.1))], [0.012, 0.012], 4, 0.0, None)
        obj_from_bm("string", bm, rope, T)
        place(torus("wrap", 0.085, 0.02, rope, T), (sx * 0.35, 1.0, z + 1.02), (0, 90, 0))
    bolt = stake("bolt", 2.1, 0.035, wood, iron, rng, T, tip=0.25)
    place(bolt, (0, -0.85, z + 1.16), (-90, 0, 0))
    place(torus("winch", 0.22, 0.03, iron, T), (0.18, -0.85, z + 0.95), (0, 90, 0))
    place(log("winchaxle", 0.5, 0.03, iron, rng, T, bend=0.0), (0, -0.85, z + 0.95), (0, 90, 0))
    place(plate("shield", 1.0, 0.55, 0.03, painted, iron, rng, T), (0, 1.12, z + 0.6), (0, 0, 0))
    # Munição ao lado: feixe de virotes amarrado.
    for i in range(5):
        place(stake("spare", 1.7, 0.03, wood, iron, rng, 1, tip=0.2), (-0.75 + i * 0.07, -0.6, z + 0.04 + (i % 2) * 0.06), (-90, 0, rng.uniform(-3, 3)))
    # Nível 2: sacos de areia em volta e chapas pregadas no berço.
    for side in range(4):
        for k in range(4):
            t = -0.9 + k * 0.6
            pos = (t, -(half + 0.25), 0.15) if side == 0 else ((t, half + 0.25, 0.15) if side == 1 else ((-(half + 0.25), t, 0.15) if side == 2 else (half + 0.25, t, 0.15)))
            place(sandbag("bag", burlap, rng, 2), pos, (0, 0, (0 if side < 2 else 90) + rng.uniform(-8, 8)))
    place(tin_sheet("patch", 1.6, 0.6, rust, rng, 2), (0, -(half + 0.05), top - 0.4), (0, 0, 0))
    place(tin_sheet("patch", 1.6, 0.6, rust, rng, 2), (half + 0.05, 0, top - 0.4), (0, 0, 90))
    # Nível 3: estacas para fora, arame farpado e crânio pendurado.
    for i in range(8):
        a = i * math.tau / 8 + 0.2
        place(stake("spike", 1.0, 0.04, bark, cut, rng, 3), (math.cos(a) * 1.55, math.sin(a) * 1.55, 0.05),
              (math.degrees(math.sin(a)) * 0.7, -math.degrees(math.cos(a)) * 0.7, 0))
    place(barbed_wire("wire", 2.4, 0.11, iron, rng, 3, loops=9), (0, -(half + 0.1), top + 0.15))
    place(barbed_wire("wire", 2.4, 0.11, iron, rng, 3, loops=9), (-(half + 0.1), 0, top + 0.15), (0, 0, 90))
    place(skull("skull", bone, dark, 3), (half + 0.05, -(half + 0.05), top + 0.1), (0, 0, 40))


# --- Torre de canhão --------------------------------------------------------------------

def build_cannon():
    rng = random.Random(333)
    bark = mat_bark()
    wood = mat_old_wood("old_wood", blood=False)
    stone = mat_stone()
    burlap = mat_burlap()
    rust = mat_rust()
    iron = mat_flat("iron", (0.13, 0.12, 0.12))
    bone = mat_flat("bone", (0.66, 0.6, 0.48))
    dark = mat_flat("socket", (0.03, 0.02, 0.02))
    painted = mat_painted_metal()
    # Base: plataforma de pedra circular (bastião baixo) com topo de tábuas.
    R = 1.35
    ring_n = 14
    for layer in range(4):
        for i in range(ring_n):
            a = (i + 0.5 * (layer % 2)) * math.tau / ring_n
            place(rough_stone("block", (0.5, 0.4, 0.3), stone, rng, 1, 0.18),
                  (math.cos(a) * (R - 0.2), math.sin(a) * (R - 0.2), 0.15 + layer * 0.31), (0, 0, math.degrees(a)))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=R - 0.25, radius2=R - 0.25, depth=1.2)
    place(obj_from_bm("core", bm, stone, 1), (0, 0, 0.6))
    z = 1.28
    deck(wood, rng, R - 0.35, z)
    z += 0.03
    # Arma (gira): carreta de madeira com rodas e cano de ferro com cintas, apontando para +Y.
    T = 0
    for sx in (-1, 1):
        bm = bmesh.new()
        pts = [(-0.75, 0.0), (0.55, 0.0), (0.55, 0.32), (0.1, 0.5), (-0.55, 0.42), (-0.75, 0.2)]
        top_v = [bm.verts.new((sx * 0.32 - 0.05, y, z + h)) for y, h in pts]
        bot_v = [bm.verts.new((sx * 0.32 + 0.05, y, z + h)) for y, h in pts]
        bm.faces.new(top_v)
        bm.faces.new(list(reversed(bot_v)))
        for i in range(len(pts)):
            j = (i + 1) % len(pts)
            bm.faces.new((top_v[i], top_v[j], bot_v[j], bot_v[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        obj_from_bm("cheek", bm, wood, T)
        for y in (-0.5, 0.35):
            place(torus("wheel", 0.24, 0.05, iron, T), (sx * 0.45, y, z + 0.24), (0, 90, 0))
            place(log("hub", 0.16, 0.06, wood, rng, T, bend=0.0), (sx * 0.45, y, z + 0.24), (0, 90, 0))
    place(log("axle", 1.0, 0.04, iron, rng, T, bend=0.0), (0, -0.5, z + 0.24), (0, 90, 0))
    place(log("axle", 1.0, 0.04, iron, rng, T, bend=0.0), (0, 0.35, z + 0.24), (0, 90, 0))
    prof = [(-0.75, 0.2), (-0.62, 0.22), (-0.55, 0.19), (0.0, 0.17), (0.6, 0.14), (1.05, 0.13), (1.15, 0.155), (1.25, 0.15)]
    secs = []
    for y, r in prof:
        secs.append([Vector((math.cos(a) * r, y, math.sin(a) * r)) for a in [k * math.tau / 12 for k in range(12)]])
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in sec] for sec in secs]
    for ra, rb in zip(rings, rings[1:]):
        for k in range(12):
            bm.faces.new((ra[k], ra[(k + 1) % 12], rb[(k + 1) % 12], rb[k]))
    bm.faces.new(list(reversed(rings[0])))
    inner = [bm.verts.new(p.co * Vector((0.6, 1, 0.6)) + Vector((0, 0.02, 0))) for p in rings[-1]]
    for k in range(12):
        bm.faces.new((rings[-1][k], rings[-1][(k + 1) % 12], inner[(k + 1) % 12], inner[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    barrel = obj_from_bm("barrel", bm, iron, T)
    place(barrel, (0, 0.1, z + 0.62), (8, 0, 0))
    for y in (-0.35, 0.25, 0.85):
        place(torus("band", 0.185 - y * 0.03, 0.022, rust, T), (0, 0.1 + y, z + 0.62 + y * 0.14), (90 - 8, 0, 0))
    place(plate("mantlet", 1.0, 0.45, 0.03, painted, iron, rng, T), (0, 0.72, z + 0.38), (0, 0, 0))
    # Balas empilhadas e barril de pólvora.
    balls = [(0, 0, 0), (0.17, 0, 0), (0.085, 0.15, 0), (0.085, 0.05, 0.14)]
    for bx, by, bz in balls:
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=0.085)
        place(obj_from_bm("ball", bm, iron, 1), (-0.75 + bx, -0.7 + by, z + 0.085 + bz))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.2, radius2=0.2, depth=0.45)
    place(obj_from_bm("keg", bm, wood, 1), (0.75, -0.7, z + 0.22))
    # Nível 2: muro de sacos de areia na borda e mais barris.
    for i in range(16):
        a = i * math.tau / 16
        if -0.6 < a - math.pi * 0.5 < 0.6:
            continue  # vão na frente para o cano
        place(sandbag("bag", burlap, rng, 2, (0.42, 0.24, 0.15)), (math.cos(a) * (R - 0.15), math.sin(a) * (R - 0.15), z + 0.16),
              (0, 0, math.degrees(a) + 90 + rng.uniform(-6, 6)))
    for i in range(3):
        a = math.pi + 0.5 + i * 0.5
        place(sandbag("bag", burlap, rng, 2, (0.42, 0.24, 0.15)), (math.cos(a) * (R - 0.15), math.sin(a) * (R - 0.15), z + 0.45),
              (0, 0, math.degrees(a) + 90))
    # Nível 3: chapas de ferro em volta da base, arame farpado e crânios.
    for i in range(6):
        a = i * math.tau / 6 + 0.25
        place(plate("armor", 0.9, 0.9, 0.04, rust, iron, rng, 3), (math.cos(a) * (R + 0.05), math.sin(a) * (R + 0.05), 0.55),
              (0, 0, math.degrees(a) + 90))
    place(barbed_wire("wire", 2.6, 0.11, iron, rng, 3, loops=10), (0, -(R + 0.15), 1.25))
    for a in (2.2, 4.0):
        place(skull("skull", bone, dark, 3), (math.cos(a) * (R - 0.15), math.sin(a) * (R - 0.15), z + 0.35), (0, 0, math.degrees(a)))


# --- Torre elétrica (gambiarra de sucata) ------------------------------------------------

def mat_copper():
    m, nt, bsdf = _mat("copper")
    c = _ramp(nt, _noise(nt, 14.0, 6.0, 0.6), [(0.3, (0.32, 0.17, 0.08)), (0.55, (0.55, 0.3, 0.14)), (0.75, (0.22, 0.36, 0.3))])
    nt.links.new(c, bsdf.inputs["Base Color"])
    return m


def build_tesla():
    rng = random.Random(444)
    rust = mat_rust()
    copper = mat_copper()
    iron = mat_flat("iron", (0.15, 0.14, 0.14))
    conc = mat_stone()
    painted = mat_painted_metal()
    bat = mat_flat("battery", (0.08, 0.08, 0.09))
    yellow = mat_flat("hazard", (0.55, 0.42, 0.08))
    bone = mat_flat("bone", (0.66, 0.6, 0.48))
    dark = mat_flat("socket", (0.03, 0.02, 0.02))
    cable = mat_flat("cable", (0.04, 0.04, 0.04))
    rubber = mat_flat("rubber", (0.07, 0.07, 0.07))
    # Base: bloco de concreto com baterias de carro e um gerador velho.
    place(rough_stone("pad", (1.15, 1.15, 0.3), conc, rng, 1, 0.08), (0, 0, 0.15))
    for i, (x, y) in enumerate(((-0.6, -0.65), (-0.2, -0.7), (0.6, -0.55))):
        place(box("battery", (0.32, 0.22, 0.24), bat, 1), (x, y, 0.42), (0, 0, rng.uniform(-10, 10)))
        for dx in (-0.08, 0.08):
            place(log("term", 0.05, 0.025, copper if dx < 0 else iron, rng, 1, bend=0.0), (x + dx, y, 0.56))
    place(box("generator", (0.6, 0.45, 0.45), painted, 1), (0.45, 0.45, 0.52), (0, 0, 15))
    place(log("exhaust", 0.4, 0.04, rust, rng, 1, bend=0.0), (0.6, 0.55, 0.9))
    # Mastro: tripé de canos enferrujados com travessas.
    Htop = 4.4
    feet = [Vector((math.cos(a) * 0.75, math.sin(a) * 0.75, 0.3)) for a in (math.pi / 2, math.pi / 2 + math.tau / 3, math.pi / 2 + 2 * math.tau / 3)]
    apex = Vector((0, 0, Htop))
    for f in feet:
        bm = bmesh.new()
        tube(bm, [f, f.lerp(apex, 0.5), apex], [0.06, 0.055, 0.05], 8, 0.03, rng)
        obj_from_bm("pipe", bm, rust, 1)
    for t in (0.25, 0.5, 0.75):
        pts = [f.lerp(apex, t) for f in feet]
        for i in range(3):
            bm = bmesh.new()
            tube(bm, [pts[i], pts[(i + 1) % 3]], [0.03, 0.03], 6, 0.0, None)
            obj_from_bm("rung", bm, rust, 1)
    place(log("mast", 1.3, 0.05, iron, rng, 1, bend=0.0), (0, 0, Htop + 0.5))
    # Bobina de cobre no topo, isoladores e prato de descarga.
    for k in range(6):
        place(torus("coil", 0.28 - k * 0.012, 0.03, copper, 1), (0, 0, Htop + 0.15 + k * 0.08))
    place(torus("rim", 0.42, 0.045, iron, 1), (0, 0, Htop + 0.72))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.22)
    place(obj_from_bm("ball", bm, iron, 1), (0, 0, Htop + 1.0))
    # Cabos pendurados das baterias até o mastro.
    for i, f in enumerate(feet):
        a = Vector((-0.6 + i * 0.5, -0.65, 0.55))
        b = f.lerp(apex, 0.5)
        mid = (a + b) / 2 + Vector((0, 0, -0.35))
        bm = bmesh.new()
        tube(bm, [a, mid, b], [0.018, 0.018, 0.018], 4, 0.0, None)
        obj_from_bm("cable", bm, cable, 1)
    # Placa de perigo amarela presa no tripé.
    place(plate("sign", 0.4, 0.3, 0.02, yellow, iron, rng, 1, rivets=False), (0, -0.48, 1.5), (0, 0, 0))
    # Nível 2: segunda bobina, isoladores de vidro e pneus segurando os pés.
    for k in range(5):
        place(torus("coil2", 0.36, 0.025, copper, 2), (0, 0, 2.6 + k * 0.07))
    for f in feet:
        place(torus("tire", 0.28, 0.1, rubber, 2), (f.x, f.y, 0.38))
    # Nível 3: arame farpado em volta da base e crânios nos isoladores.
    for i in range(3):
        a = i * math.tau / 3
        place(barbed_wire("wire", 1.9, 0.1, iron, rng, 3, loops=8), (math.cos(a) * 1.0, math.sin(a) * 1.0, 0.45), (0, 0, math.degrees(a) + 90))
    for f in feet[:2]:
        p = f.lerp(apex, 0.75)
        place(skull("skull", bone, dark, 3), (p.x * 1.4, p.y * 1.4, p.z), (0, 0, 0))


BUILDERS = {"archer_tower": build_archer_tower, "ballista": build_ballista, "cannon": build_cannon, "tesla": build_tesla, "barricade": build_barricade, "stone_wall": build_stone_wall, "iron_wall": build_iron_wall,
            "spikes": build_spikes}


# --- Atlas: UV, bake de cor + oclusão e exportação --------------------------------------

def join_levels():
    groups = {}
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH":
            groups.setdefault(int(o.get("lv", 1)), []).append(o)
    out = []
    for lv in sorted(groups):
        bpy.ops.object.select_all(action="DESELECT")
        for o in groups[lv]:
            o.select_set(True)
        bpy.context.view_layer.objects.active = groups[lv][0]
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        bpy.ops.object.join()
        j = bpy.context.view_layer.objects.active
        # lv 0 = peça giratória (arma da torre), sempre visível; o jogo a gira para o alvo.
        j.name = "Turret" if lv == 0 else "Lv%d" % lv
        out.append(j)
    # Mesma origem (0,0,0) para todos os níveis.
    for o in out:
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.context.scene.cursor.location = (0, 0, 0)
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return out


def bake_atlas(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006)
    bpy.ops.uv.pack_islands(margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")
    col_img = bpy.data.images.new(name + "_col", ATLAS, ATLAS)
    ao_img = bpy.data.images.new(name + "_ao", ATLAS, ATLAS)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    mats = {m for o in objs for m in o.data.materials}

    def set_target(img):
        for m in mats:
            nt = m.node_tree
            n = nt.nodes.get("BakeTarget") or nt.nodes.new("ShaderNodeTexImage")
            n.name = "BakeTarget"
            n.image = img
            nt.nodes.active = n

    set_target(col_img)
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    sc.render.bake.use_pass_color = True
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=8)
    set_target(ao_img)
    bpy.ops.object.bake(type="AO", margin=8)
    # Cor * oclusão (as frestas escurecem de verdade).
    import numpy as np
    c = np.array(col_img.pixels[:]).reshape(-1, 4)
    a = np.array(ao_img.pixels[:]).reshape(-1, 4)[:, :1]
    c[:, :3] *= 0.5 + 0.5 * a
    col_img.pixels[:] = c.flatten()
    final = bpy.data.materials.new(name)
    final.use_nodes = True
    bsdf = final.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.88
    tex = final.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = col_img
    final.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(final)
    return col_img


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_image_format="JPEG",
                              export_jpeg_quality=88, export_yup=True, export_apply=True)
    print("exportado:", path)


def render_levels(objs, out_png):
    """Prévia para aprovação: os 3 níveis lado a lado (Cycles)."""
    sc = bpy.context.scene
    shown = []
    width = max(o.dimensions.x for o in objs)
    height = max(o.dimensions.z for o in objs)
    gap = width + 0.7
    for i, n in enumerate((1, 2, 3)):
        for o in objs:
            lv = 0 if o.name == "Turret" else int(o.name[2:])
            if lv <= n:
                c = o.copy()
                c.data = o.data
                c.location = ((i - 1) * gap, 0, 0)
                sc.collection.objects.link(c)
                shown.append(c)
    for o in objs:
        o.hide_render = True
    ground = bpy.data.meshes.new("ground")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30)
    bm.to_mesh(ground)
    g = bpy.data.objects.new("ground", ground)
    gm = mat_flat("dirt", (0.2, 0.16, 0.12))
    ground.materials.append(gm)
    sc.collection.objects.link(g)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 40
    sc.collection.objects.link(cam)
    k = max(gap * 3.0 / 10.8, height / 4.0)
    tall = height > 3.5
    cam.location = (0, -10.5 * k, 6.2 * k * (0.55 if tall else 1.0) + height * (0.55 if tall else 0.3))
    cam.rotation_euler = Euler((math.radians(70 if tall else 62), 0, 0))
    sc.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = Euler((math.radians(50), math.radians(10), math.radians(-35)))
    sc.collection.objects.link(sun)
    sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (*srgb((0.45, 0.47, 0.5)), 1)
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sc.render.resolution_x, sc.render.resolution_y = 1600, 800
    sc.cycles.samples = 48
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
        reset()
        BUILDERS[n]()
        objs = join_levels()
        bake_atlas(objs, n)
        export(os.path.join(out, n + ".glb"))
        if render_dir:
            os.makedirs(render_dir, exist_ok=True)
            render_levels(objs, os.path.join(render_dir, n + "_niveis.png"))


if __name__ == "__main__":
    main()
