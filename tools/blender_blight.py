"""Área Contaminada modelada no Blender (bpy), no estilo da fortaleza e da cidade: materiais procedurais
assados num atlas de 1024 px por modelo; as partes que brilham (contaminação verde, lampião) ficam numa
malha separada "<nome>_glow" com material de emissão (não entram no atlas, para o brilho não se perder).

  crypt_ruin          mausoléu de pedra em ruínas: degraus, colunas (uma partida), frontão rachado, porta de
                      ferro caída e luz verde vazando de dentro
  cemetery_gate       portal: pilares de pedra e arco de ferro torto, uma folha do portão arrombada
  iron_fence          cerca de ferro enferrujada sobre mureta de pedra
  iron_fence_broken   a mesma, com barras tortas e faltando
  gravestone_a        lápide arredondada partida e inclinada, sobre o monte de terra
  gravestone_b        cruz de pedra com o braço caído
  grave_open          cova aberta: buraco escuro, terra amontoada, tampa de caixão quebrada e pá fincada
  body_remains        cadáver em decomposição na mortalha rasgada, costelas e crânio expostos, mancha no chão
  bones_scatter       ossada espalhada (crânio, costelas, ossos longos)
  blight_pod          casulos de carne doente com tentáculos e pústulas verdes brilhando
  blight_pool         poça tóxica com brilho verde e bolhas
  blight_tree         árvore doente retorcida, com tumores de carne e pústulas brilhando
  grave_lantern       lampião de cemitério em haste torta, com luz esverdeada

Uso (módulo `bpy` do PyPI ou Blender):
  python3 tools/blender_blight.py assets/models/blender [nome ...] [--render pasta]
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
import blender_town as bt  # noqa: E402

GLOW = 9  # nível das peças que brilham (malha separada, sem atlas)


# --------------------------------------------------------------------------- materiais

def mat_flesh():
    """Carne doente: roxo-acinzentado, células escuras, veias esverdeadas, úmida."""
    m, nt, bsdf = bd._mat("flesh")
    base = bd._ramp(nt, bd._noise(nt, 4.0, 6.0, 0.6), [(0.3, (0.3, 0.17, 0.19)), (0.55, (0.44, 0.27, 0.26)), (0.8, (0.27, 0.19, 0.22))])
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 16.0
    cells = bd._ramp(nt, vor.outputs["Distance"], [(0.0, (0.35, 0.18, 0.2)), (0.035, (1, 1, 1))])
    # Manchas escuras de necrose.
    nec = bd._ramp(nt, bd._noise(nt, 6.0, 5.0, 0.6), [(0.55, (1, 1, 1)), (0.72, (0.25, 0.12, 0.14))])
    cells = bd._mix(nt, 1.0, cells, nec, "MULTIPLY")
    c = bd._mix(nt, 1.0, base, cells, "MULTIPLY")
    veins = bd._ramp(nt, bd._noise(nt, 18.0, 8.0, 0.75), [(0.6, (0, 0, 0)), (0.66, (1, 1, 1))])
    c = bd._mix(nt, veins, c, (0.28, 0.42, 0.12))
    nt.links.new(c, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.45
    return m


def mat_soil():
    m, nt, bsdf = bd._mat("soil")
    c = bd._ramp(nt, bd._noise(nt, 6.0, 6.0, 0.65), [(0.3, (0.12, 0.09, 0.06)), (0.6, (0.22, 0.16, 0.1)), (0.8, (0.17, 0.13, 0.09))])
    peb = bd._ramp(nt, bd._noise(nt, 40.0, 2.0, 0.5), [(0.62, (1, 1, 1)), (0.7, (1.6, 1.5, 1.4))])
    c = bd._mix(nt, 1.0, c, peb, "MULTIPLY")
    nt.links.new(c, bsdf.inputs["Base Color"])
    return m


def mat_bone():
    m, nt, bsdf = bd._mat("bone")
    c = bd._ramp(nt, bd._noise(nt, 8.0, 5.0, 0.6), [(0.3, (0.55, 0.5, 0.4)), (0.7, (0.74, 0.69, 0.56))])
    dirt = bd._ramp(nt, bd._noise(nt, 3.0, 4.0, 0.5), [(0.5, (1, 1, 1)), (0.7, (0.5, 0.42, 0.32))])
    c = bd._mix(nt, 1.0, c, dirt, "MULTIPLY")
    nt.links.new(bd._height_dirt(nt, c), bsdf.inputs["Base Color"])
    return m


def mat_toxic():
    """Lama tóxica escura (borda da poça, chão em volta dos casulos)."""
    m, nt, bsdf = bd._mat("toxic")
    c = bd._ramp(nt, bd._noise(nt, 5.0, 6.0, 0.6), [(0.3, (0.07, 0.09, 0.04)), (0.6, (0.14, 0.17, 0.06)), (0.8, (0.1, 0.1, 0.05))])
    nt.links.new(c, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.3
    return m


def mat_glow(name="glow", color=(0.35, 1.0, 0.3), strength=4.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*bd.srgb(color), 1)
    b.inputs["Emission Color"].default_value = (*bd.srgb(color), 1)
    b.inputs["Emission Strength"].default_value = strength
    b.inputs["Roughness"].default_value = 0.4
    return m


def mat_iron():
    m, nt, bsdf = bd._mat("wrought_iron")
    c = bd._ramp(nt, bd._noise(nt, 12.0, 6.0, 0.65), [(0.35, (0.07, 0.065, 0.06)), (0.55, (0.13, 0.11, 0.1)), (0.7, (0.32, 0.14, 0.05))])
    nt.links.new(c, bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.5
    bsdf.inputs["Roughness"].default_value = 0.6
    return m


# --------------------------------------------------------------------------- peças

def tube_obj(name, pts, radii, mat, lv=1, segs=7, rng=None, jitter=0.0):
    bm = bmesh.new()
    bd.tube(bm, [Vector(p) for p in pts], radii, segs, jitter, rng)
    return bd.obj_from_bm(name, bm, mat, lv)


def blob(name, center, size, mat, rng, lv=1, jitter=0.18, subdiv=2):
    """Esfera irregular (casulo, tumor, pústula, monte de terra)."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    for v in bm.verts:
        v.co *= 1.0 + rng.uniform(-jitter, jitter)
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=Vector(center))
    return bd.obj_from_bm(name, bm, mat, lv)


def curve_pts(rng, start, direction, length, segs, wobble, up=0.0):
    pts = [Vector(start)]
    d = Vector(direction).normalized()
    for i in range(segs):
        d = (d + Vector((rng.uniform(-wobble, wobble), rng.uniform(-wobble, wobble), rng.uniform(-wobble, wobble) * 0.5 + up))).normalized()
        pts.append(pts[-1] + d * (length / segs))
    return pts


def mound(center, w, d, h, soil, rng):
    """Monte de terra de sepultura."""
    blob("mound", (center[0], center[1], -h * 0.35), (w * 0.5, d * 0.5, h), soil, rng, jitter=0.1)


def tablet(name, w, h, t, mat):
    """Lápide de topo arredondado (perfil extrudado)."""
    prof = [(-w / 2, 0), (w / 2, 0), (w / 2, h - w / 2)]
    for k in range(1, 8):
        a = k * math.pi / 8
        prof.append((math.cos(a) * w / 2, h - w / 2 + math.sin(a) * w / 2))
    prof.append((-w / 2, h - w / 2))
    secs = [[Vector((x, -t / 2, z)) for x, z in prof], [Vector((x, t / 2, z)) for x, z in prof]]
    return bs.loft(name, secs, mat)


# --------------------------------------------------------------------------- cemitério

def build_crypt_ruin():
    rng = random.Random(1301)
    mas = bs.mat_masonry()
    stone = bd.mat_stone()
    iron = mat_iron()
    bone = mat_bone()
    glow = mat_glow("crypt_glow", (0.35, 1.0, 0.35), 5.0)
    W, D, H = 4.4, 5.4, 3.4
    hx, hy = W / 2, D / 2
    # Degraus e plataforma.
    for k in range(3):
        bd.place(bd.box("step", (W + 1.6 - k * 0.4, 1.1 - k * 0.25, 0.22), stone, 1), (0, -hy - 0.55 + k * 0.12, 0.11 + k * 0.22))
    bd.place(bd.box("plinth", (W + 0.5, D + 0.5, 0.6), stone, 1), (0, 0, 0.3))
    # Paredes (porta na frente; canto de trás desmoronado).
    base = 0.6
    front = lambda s: base + H
    bt.wall("front", (-hx, -hy), (1, 0), W, 0.4, front, mas, openings=[(1.55, 2.85, 0.0, base + 2.3)])
    bt.wall("left", (-hx, hy), (0, -1), D, 0.4, lambda s: base + H, mas)
    bt.wall("right", (hx, -hy), (0, 1), D, 0.4, bt.jagged(rng, lambda s: base + H - max(0.0, s - D * 0.55) * 1.1, amp=0.3), mas)
    bt.wall("back", (hx, hy), (-1, 0), W, 0.4, bt.jagged(rng, lambda s: base + H - max(0.0, 1.6 - s) * 1.2, amp=0.3), mas)
    # Frontão (triângulo) rachado em duas metades, a da direita afundada.
    for x0, x1, apex_left, dz in ((-hx - 0.3, 0.0, False, 0.0), (0.0, hx + 0.3, True, -0.14)):
        secs = []
        for y in (-hy - 0.35, -hy + 0.15):
            z0 = base + H + dz
            apex = Vector((0.0, y, z0 + 1.1))
            pts = [Vector((x0, y, z0)), Vector((x1, y, z0)), apex] if not apex_left else [Vector((x0, y, z0)), Vector((x1, y, z0)), apex]
            secs.append(pts)
        bs.loft("pediment", secs, stone)
    # Telhado de lajes, faltando um pedaço no canto caído.
    for k in range(4):
        y = -hy + 0.3 + k * 1.3
        if k == 3:
            continue
        bd.place(bd.box("roofslab", (W + 0.4, 1.32, 0.25), stone, 1), (0, y + 0.3, base + H + 0.15), (rng.uniform(-3, 3), 0, 0))
    # Colunas na frente (a da direita partida, pedaço caído).
    for sx, h in ((-1, H), (1, H * 0.55)):
        col = bs.cylinder("column", 0.26, h, stone, 12)
        bd.place(col, (sx * (hx - 0.1), -hy - 0.45, base + h / 2))
        bs.dents(col, rng, 5, 0.2, 0.05)
        bd.place(bd.box("capital", (0.7, 0.7, 0.2), stone, 1), (sx * (hx - 0.1), -hy - 0.45, base + 0.1))
    fallen = bs.cylinder("fallen_col", 0.25, 1.4, stone, 12)
    bd.place(fallen, (hx + 1.0, -hy - 1.1, 0.25), (90, 0, 25))
    # Porta de ferro caída de lado, encostada.
    bd.place(bd.box("door", (1.25, 0.08, 2.2), iron, 1), (0.9, -hy - 0.9, 0.95), (62, 0, -12))
    for k in range(4):
        bd.place(bd.box("door_bar", (1.2, 0.05, 0.06), iron, 1), (0.9, -hy - 0.86 + k * 0.0, 0.5 + k * 0.4), (62, 0, -12))
    # Luz verde vazando pela porta (malha que brilha) e névoa verde no chão de dentro.
    gl = bd.box("glow_door", (1.25, 0.05, 2.25), glow, GLOW)
    bd.place(gl, (0.2, -hy + 0.5, base + 1.15))
    # Crânio no degrau e entulho.
    sk = bd.skull("skull", bone, bd.mat_flat("dark", (0.05, 0.04, 0.04)), 1)
    bd.place(sk, (-1.2, -hy - 0.9, 0.62), (0, 0, 20))
    bt.rubble((hx + 0.4, hy - 0.3), 1.3, 14, [mas, stone], rng, 0.7)


def build_cemetery_gate():
    rng = random.Random(1302)
    stone = bd.mat_stone()
    iron = mat_iron()
    for sx in (-1, 1):
        bd.place(bd.rough_stone("pillar", (0.7, 0.7, 2.8), stone, rng, 1, 0.03), (sx * 1.9, 0, 1.4))
        bd.place(bd.box("cap", (0.9, 0.9, 0.2), stone, 1), (sx * 1.9, 0, 2.9))
        bt.rubble((sx * 1.9 + rng.uniform(-0.5, 0.5), rng.uniform(-0.6, 0.6)), 0.5, 4, [stone], rng, 0.2)
    # Arco de ferro torto entre os pilares, com pontas.
    arc = []
    for k in range(13):
        t = k / 12
        x = -1.6 + 3.2 * t
        z = 2.7 + math.sin(t * math.pi) * 0.9 - (0.25 if 0.55 < t < 0.8 else 0.0)
        arc.append((x, 0, z))
    tube_obj("arch", arc, [0.045] * len(arc), iron, segs=6)
    for k in range(1, 12, 2):
        p = arc[k]
        tube_obj("spike", [p, (p[0], 0, p[2] + 0.35)], [0.03, 0.005], iron, segs=5)
    # Folha esquerda presa, direita arrombada (girada e torta).
    for leaf, (x0, rot, tilt) in enumerate(((-1.55, 0.0, 0.0), (0.05, -70.0, 9.0))):
        for k in range(7):
            x = x0 + k * 0.24
            bar = tube_obj("bar", [(x, 0, 0.05), (x + (rng.uniform(-0.06, 0.06) if leaf else 0), 0, 2.2 + 0.15 * math.sin(k))], [0.025, 0.02], iron, segs=5)
            if leaf:
                bar.rotation_euler = (math.radians(tilt), 0, math.radians(rot))
                bar.location = (0.05 * (1 - math.cos(math.radians(rot))), -0.05, 0)
        for z in (0.3, 1.2, 2.0):
            rail = tube_obj("rail", [(x0, 0, z), (x0 + 1.5, 0, z)], [0.03, 0.03], iron, segs=5)
            if leaf:
                rail.rotation_euler = (math.radians(tilt), 0, math.radians(rot))
    # Corrente arrebentada pendurada.
    tube_obj("chain", [(-0.1, -0.05, 1.3), (0.0, -0.1, 0.9), (0.05, -0.08, 0.6)], [0.02, 0.02, 0.02], iron, segs=4)


def _fence(broken, seed):
    rng = random.Random(seed)
    stone = bd.mat_stone()
    iron = mat_iron()
    L = 3.0
    bd.place(bd.rough_stone("base", (L, 0.4, 0.35), stone, rng, 1, 0.03), (0, 0, 0.17))
    bd.place(bd.box("post", (0.4, 0.4, 1.5), stone, 1), (L / 2, 0, 0.75))
    bd.place(bd.box("postcap", (0.5, 0.5, 0.14), stone, 1), (L / 2, 0, 1.55))
    for k in range(12):
        x = -L / 2 + 0.15 + k * 0.24
        if broken and k in (4, 5, 9):
            continue
        h = 1.55
        top = (x, 0, h)
        if broken and k in (6, 7):
            top = (x + rng.uniform(0.2, 0.45), rng.uniform(-0.4, 0.4), h * 0.75)
        tube_obj("bar", [(x, 0, 0.3), top], [0.022, 0.02], iron, segs=5)
        tube_obj("tip", [top, (top[0], top[1], top[2] + 0.18)], [0.035, 0.004], iron, segs=4)
    for z in (0.5, 1.3):
        if broken and z > 1.0:
            tube_obj("rail", [(-L / 2, 0, z), (-0.3, 0, z)], [0.025, 0.025], iron, segs=5)
            tube_obj("rail_bent", [(0.6, 0, z), (L / 2, 0, z - 0.2)], [0.025, 0.025], iron, segs=5)
        else:
            tube_obj("rail", [(-L / 2, 0, z), (L / 2, 0, z)], [0.025, 0.025], iron, segs=5)


def build_iron_fence():
    _fence(False, 1303)


def build_iron_fence_broken():
    _fence(True, 1304)


def build_gravestone_a():
    rng = random.Random(1305)
    stone = bd.mat_stone()
    soil = mat_soil()
    mound((0, 0.9), 0.9, 1.9, 0.28, soil, rng)
    low = tablet("tablet_low", 0.75, 0.55, 0.16, stone)
    low.location = (0, -0.05, 0)
    top = tablet("tablet_top", 0.75, 1.15, 0.16, stone)
    # Parte de cima partida, caída para trás e inclinada.
    top.location = (0.15, 0.35, -0.42)
    top.rotation_euler = (math.radians(-28), math.radians(14), math.radians(8))
    bt.rubble((0.4, -0.3), 0.3, 4, [stone], rng, 0.1)


def build_gravestone_b():
    rng = random.Random(1306)
    stone = bd.mat_stone()
    soil = mat_soil()
    mound((0, 0.9), 0.9, 1.9, 0.26, soil, rng)
    bd.place(bd.box("base", (0.6, 0.35, 0.3), stone, 1), (0, 0, 0.15))
    bd.place(bd.rough_stone("shaft", (0.2, 0.18, 1.5), stone, rng, 1, 0.02), (0, 0, 1.05), (4, -6, 0))
    bd.place(bd.rough_stone("arm", (0.22, 0.17, 0.2), stone, rng, 1, 0.02), (-0.24, 0, 1.4), (4, -6, 0))
    # Braço direito caído no chão.
    bd.place(bd.rough_stone("arm_fallen", (0.5, 0.17, 0.2), stone, rng, 1, 0.04), (0.55, -0.35, 0.1), (0, 8, 35))


def build_grave_open():
    rng = random.Random(1307)
    soil = mat_soil()
    wood = bd.mat_old_wood("old_wood", blood=False)
    stone = bd.mat_stone()
    iron = mat_iron()
    dark = bd.mat_flat("pit", (0.025, 0.02, 0.018))
    # Buraco: "poço" escuro levemente abaixo do chão, com borda de terra.
    bd.place(bd.box("pit", (0.9, 1.9, 0.05), dark, 1), (0, 0, 0.02))
    for sx in (-1, 1):
        mound((sx * 0.85, 0.0), 0.6, 2.2, 0.32, soil, rng)
    mound((0.0, 1.3), 1.0, 0.7, 0.3, soil, rng)
    mound((1.5, -0.4), 1.2, 1.0, 0.5, soil, rng)
    # Tampa do caixão quebrada fora da cova e lápide velha.
    for k in range(3):
        pl = bd.plank("lid", 1.9, 0.24, 0.04, wood, rng, 1, broken=k == 1)
        bd.place(pl, (-1.3 + k * 0.05, -0.2 + k * 0.25, 0.08 + k * 0.02), (rng.uniform(-6, 6), 0, 80 + rng.uniform(-10, 10)))
    t = tablet("stone", 0.6, 0.8, 0.14, stone)
    t.location = (0, 1.6, 0)
    t.rotation_euler = (math.radians(-12), 0, math.radians(5))
    # Pá fincada no monte.
    tube_obj("shovel_handle", [(1.5, -0.4, 0.35), (1.62, -0.48, 1.4)], [0.025, 0.022], wood, segs=6)
    bd.place(bd.box("shovel_blade", (0.24, 0.03, 0.3), iron, 1), (1.47, -0.38, 0.25), (8, 6, 0))


def build_body_remains():
    rng = random.Random(1308)
    skin = bs.mat_rotten_skin()
    canvas = bs.mat_canvas()
    bone = mat_bone()
    dark = bd.mat_flat("dark", (0.05, 0.04, 0.04))
    stain = bd.mat_flat("stain", (0.12, 0.03, 0.02))
    # Mancha de sangue seco no chão.
    blob("stain", (0, 0.1, -0.03), (0.9, 1.3, 0.05), stain, rng, jitter=0.25, subdiv=1)
    # Corpo na mortalha rasgada (deitado), costelas expostas no peito.
    body = bs.shrouded_body("body", canvas, rng, 1.7)
    body.rotation_euler = (0, 0, 0)
    body.location = (0, -0.8, 0.12)
    body.scale = (1.0, 1.0, 0.55)
    for k in range(5):
        y = -0.25 + k * 0.08
        tube_obj("rib", [(-0.16, y, 0.15), (-0.05, y, 0.24), (0.05, y, 0.24), (0.16, y, 0.15)], [0.012] * 4, bone, segs=4)
    sk = bd.skull("skull", bone, dark, 1)
    bd.place(sk, (0.02, -0.92, 0.12), (90, 0, rng.uniform(-30, 30)))
    # Braço esticado (pele podre e mão ossuda).
    tube_obj("arm", [(0.2, -0.45, 0.1), (0.55, -0.3, 0.06), (0.85, -0.1, 0.05)], [0.05, 0.04, 0.03], skin, segs=6)
    for f in range(4):
        tube_obj("finger", [(0.85, -0.1, 0.05), (0.98 + f * 0.02, -0.05 + f * 0.03, 0.04)], [0.012, 0.008], bone, segs=4)
    bs.rag("rag", 0.5, 0.3, canvas, rng).location = (-0.35, 0.3, 0.05)


def build_bones_scatter():
    rng = random.Random(1309)
    bone = mat_bone()
    dark = bd.mat_flat("dark", (0.05, 0.04, 0.04))
    for k in range(2):
        sk = bd.skull("skull", bone, dark, 1)
        bd.place(sk, (rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), 0.08), (rng.uniform(-30, 30), rng.uniform(-30, 30), rng.uniform(0, 360)))
    for k in range(9):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.1, 0.9)
        x, y = math.cos(a) * r, math.sin(a) * r
        L = rng.uniform(0.25, 0.45)
        b = rng.uniform(0, math.tau)
        tube_obj("bone", [(x, y, 0.03), (x + math.cos(b) * L, y + math.sin(b) * L, 0.03)], [0.022, 0.017], bone, segs=5)
        blob("knob", (x, y, 0.03), (0.035, 0.035, 0.03), bone, rng, jitter=0.1, subdiv=1)
    # Caixa torácica tombada.
    for k in range(5):
        y = 0.6 + k * 0.07
        tube_obj("rib", [(-0.5, y, 0.02), (-0.42, y, 0.12), (-0.3, y, 0.15), (-0.18, y, 0.1)], [0.012] * 4, bone, segs=4)
    tube_obj("spine", [(-0.48, 0.55, 0.03), (-0.48, 0.95, 0.03)], [0.025, 0.022], bone, segs=5)


# --------------------------------------------------------------------------- contaminação

def build_blight_pod():
    rng = random.Random(1310)
    flesh = mat_flesh()
    toxic = mat_toxic()
    glow = mat_glow("pod_glow", (0.4, 1.0, 0.25), 5.0)
    blob("ground", (0, 0, -0.08), (1.4, 1.2, 0.14), toxic, rng, jitter=0.25)
    for k in range(4):
        a = k * math.tau / 4 + rng.uniform(-0.4, 0.4)
        r = 0.0 if k == 0 else rng.uniform(0.45, 0.75)
        s = (0.55 if k == 0 else rng.uniform(0.28, 0.4))
        c = (math.cos(a) * r, math.sin(a) * r, s * 0.8)
        blob("sac", c, (s, s * 0.9, s * 1.25), flesh, rng, jitter=0.12)
        # Pústulas brilhando na superfície do casulo.
        for p in range(4 if k == 0 else 2):
            pa, pe = rng.uniform(0, math.tau), rng.uniform(-0.2, 0.9)
            pc = (c[0] + math.cos(pa) * math.cos(pe) * s * 0.95, c[1] + math.sin(pa) * math.cos(pe) * s * 0.85, c[2] + math.sin(pe) * s * 1.1)
            blob("pustule", pc, (s * 0.18, s * 0.18, s * 0.16), glow, rng, GLOW, jitter=0.1, subdiv=1)
    # Tentáculos/raízes de carne espalhando pelo chão.
    for k in range(6):
        a = rng.uniform(0, math.tau)
        pts = curve_pts(rng, (math.cos(a) * 0.4, math.sin(a) * 0.4, 0.1), (math.cos(a), math.sin(a), -0.2), rng.uniform(0.8, 1.3), 4, 0.35)
        pts = [Vector((p.x, p.y, max(0.03, p.z))) for p in pts]
        tube_obj("tendril", pts, [0.07, 0.055, 0.04, 0.025, 0.01], flesh, segs=6)


def build_blight_pool():
    rng = random.Random(1311)
    toxic = mat_toxic()
    flesh = mat_flesh()
    glow = mat_glow("pool_glow", (0.3, 0.95, 0.25), 3.0)
    # Borda de lama tóxica e superfície que brilha, levemente abaixo da borda.
    bm = bmesh.new()
    n = 18
    outer, inner = [], []
    for k in range(n):
        a = k * math.tau / n
        r = 1.4 + 0.35 * math.sin(a * 3 + 1.2) + rng.uniform(-0.15, 0.15)
        outer.append(bm.verts.new((math.cos(a) * r * 1.25, math.sin(a) * r, 0.02)))
        inner.append(bm.verts.new((math.cos(a) * r * 1.0, math.sin(a) * r * 0.78, 0.06)))
    for k in range(n):
        bm.faces.new([outer[k], outer[(k + 1) % n], inner[(k + 1) % n], inner[k]])
    inner_co = [v.co.copy() for v in inner]
    bd.obj_from_bm("rim", bm, toxic, 1)
    bm = bmesh.new()
    pts = [bm.verts.new((co.x * 1.02, co.y * 1.02, 0.045)) for co in inner_co]
    bm.faces.new(pts)
    bd.obj_from_bm("surface", bm, glow, GLOW)
    # Bolhas e pedaços de carne boiando.
    for k in range(7):
        a, r = rng.uniform(0, math.tau), rng.uniform(0, 0.9)
        s = rng.uniform(0.05, 0.12)
        blob("bubble", (math.cos(a) * r, math.sin(a) * r * 0.75, 0.06), (s, s, s * 0.7), glow, rng, GLOW, jitter=0.05, subdiv=1)
    for k in range(3):
        a, r = rng.uniform(0, math.tau), rng.uniform(0.3, 1.0)
        blob("chunk", (math.cos(a) * r, math.sin(a) * r * 0.7, 0.05), (0.18, 0.12, 0.06), flesh, rng, jitter=0.2, subdiv=1)


def build_blight_tree():
    rng = random.Random(1312)
    bark = bs.mat_charred_bark()
    flesh = mat_flesh()
    glow = mat_glow("tree_glow", (0.4, 1.0, 0.25), 5.0)
    trunk = curve_pts(rng, (0, 0, -0.1), (0.15, 0.05, 1), 4.2, 7, 0.22, up=0.15)
    tube_obj("trunk", trunk, [0.38, 0.32, 0.27, 0.24, 0.2, 0.16, 0.12, 0.08], bark, segs=8, rng=rng, jitter=0.08)
    for k in range(4):
        a = k * math.tau / 4 + rng.uniform(-0.3, 0.3)
        root = curve_pts(rng, (0, 0, 0.3), (math.cos(a), math.sin(a), -0.5), 1.1, 3, 0.25)
        tube_obj("root", [Vector((p.x, p.y, max(-0.05, p.z))) for p in root], [0.2, 0.12, 0.07, 0.02], bark, segs=6)
    # Galhos retorcidos e pelados.
    for k in range(6):
        i = rng.randint(3, 6)
        a = rng.uniform(0, math.tau)
        br = curve_pts(rng, trunk[i], (math.cos(a), math.sin(a), rng.uniform(0.0, 0.7)), rng.uniform(1.3, 2.2), 4, 0.45)
        tube_obj("branch", br, [0.09, 0.06, 0.04, 0.02, 0.005], bark, segs=5)
        if rng.random() < 0.6:
            tw = curve_pts(rng, br[2], (rng.uniform(-1, 1), rng.uniform(-1, 1), 0.6), 0.9, 3, 0.5)
            tube_obj("twig", tw, [0.035, 0.02, 0.01, 0.003], bark, segs=4)
    # Tumores de carne no tronco com pústulas brilhando.
    for k in range(4):
        i = rng.randint(1, 5)
        p = trunk[i]
        a = rng.uniform(0, math.tau)
        s = rng.uniform(0.18, 0.32)
        c = (p.x + math.cos(a) * 0.22, p.y + math.sin(a) * 0.22, p.z)
        blob("tumor", c, (s, s, s * 1.2), flesh, rng, jitter=0.15)
        blob("pustule", (c[0] + math.cos(a) * s * 0.9, c[1] + math.sin(a) * s * 0.9, c[2] + s * 0.3), (s * 0.3, s * 0.3, s * 0.25), glow, rng, GLOW, jitter=0.1, subdiv=1)


def build_grave_lantern():
    rng = random.Random(1313)
    iron = mat_iron()
    stone = bd.mat_stone()
    glow = mat_glow("lantern_glow", (0.8, 1.0, 0.45), 6.0)
    bd.place(bd.rough_stone("base", (0.45, 0.45, 0.3), stone, rng, 1, 0.04), (0, 0, 0.15))
    pole = [(0, 0, 0.3), (0.03, 0.0, 1.4), (0.0, 0, 2.3), (0.25, 0, 2.6), (0.55, 0, 2.55)]
    tube_obj("pole", pole, [0.05, 0.045, 0.04, 0.035, 0.03], iron, segs=6)
    tube_obj("hook", [(0.55, 0, 2.55), (0.55, 0, 2.35)], [0.015, 0.015], iron, segs=4)
    # Gaiola do lampião com o miolo brilhando.
    cx, cz = 0.55, 2.1
    for sx in (-1, 1):
        for sy in (-1, 1):
            tube_obj("cage", [(cx + sx * 0.12, sy * 0.12, cz - 0.2), (cx + sx * 0.12, sy * 0.12, cz + 0.2)], [0.012, 0.012], iron, segs=4)
    bd.place(bd.box("cage_top", (0.32, 0.32, 0.06), iron, 1), (cx, 0, cz + 0.23))
    bd.place(bd.box("cage_bottom", (0.3, 0.3, 0.05), iron, 1), (cx, 0, cz - 0.22))
    blob("flame", (cx, 0, cz), (0.09, 0.09, 0.14), glow, rng, GLOW, jitter=0.05, subdiv=1)


BUILDERS = {"crypt_ruin": build_crypt_ruin, "cemetery_gate": build_cemetery_gate, "iron_fence": build_iron_fence,
            "iron_fence_broken": build_iron_fence_broken, "gravestone_a": build_gravestone_a, "gravestone_b": build_gravestone_b,
            "grave_open": build_grave_open, "body_remains": build_body_remains, "bones_scatter": build_bones_scatter,
            "blight_pod": build_blight_pod, "blight_pool": build_blight_pool, "blight_tree": build_blight_tree,
            "grave_lantern": build_grave_lantern}


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
        solid = [o for o in objs if o.name != "Lv%d" % GLOW]
        glow = [o for o in objs if o.name == "Lv%d" % GLOW]
        bd.bake_atlas(solid, n)
        for o in solid:
            o.name = n
        for o in glow:
            o.name = n + "_glow"
        bd.export(os.path.join(out, n + ".glb"))
        if render_dir:
            os.makedirs(render_dir, exist_ok=True)
            bs.render_single(solid + glow, os.path.join(render_dir, n + ".png"))


if __name__ == "__main__":
    main()
