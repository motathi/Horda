"""Modela no Blender (bpy) os baús espalhados pelo mapa e exporta GLB para o jogo:
  - chest_wood.glb  baú de mantimentos: tábuas claras gastas, cintas de madeira escura e corda
  - chest_iron.glb  baú de equipamentos/guardião: madeira escura, cintas e cantoneiras de ferro
                    rebitadas, fechadura dourada
Cada baú tem dois objetos: "Base" (caixa) e "Lid" (tampa abaulada) com a origem na dobradiça,
para o jogo abrir a tampa (rotação no eixo X) quando o baú é saqueado.
Uso:  python3 tools/blender_chests.py assets/models/blender [--render pasta]   (módulo bpy do PyPI)
Convenção: frente em +Y e topo em +Z no Blender (vira -Z/+Y no glTF/Godot)."""
import math
import os
import random
import sys

import bpy  # noqa: I001 — com o módulo do PyPI, bmesh só existe depois de importar bpy
import bmesh
from mathutils import Euler, Matrix, Vector

W, D, H = 1.1, 0.68, 0.52      # largura (x), profundidade (y), altura da caixa (z)
LID_R = D * 0.5                 # raio da tampa abaulada
LID_K = 0.62                    # achatamento da tampa (altura = LID_R * LID_K)


def args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    out = a[0] if a else "assets/models/blender"
    render = a[a.index("--render") + 1] if "--render" in a else ""
    os.makedirs(out, exist_ok=True)
    return out, render


def reset() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def lin(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def mat(name, color, rough=0.8, metal=0.0, emit=0.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*[lin(c) for c in color], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit > 0:
        b.inputs["Emission Color"].default_value = (*[lin(c) for c in color], 1.0)
        b.inputs["Emission Strength"].default_value = emit
    return m


def obj_from_bm(name, bm, material, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    me.materials.append(material)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def box(name, size, loc, material, rot=(0, 0, 0), bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES")
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Euler(rot).to_matrix())
    bmesh.ops.translate(bm, verts=bm.verts, vec=Vector(loc))
    return obj_from_bm(name, bm, material)


def cyl(name, r, depth, loc, material, rot=(0, 0, 0), segs=8):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=depth)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Euler(rot).to_matrix())
    bmesh.ops.translate(bm, verts=bm.verts, vec=Vector(loc))
    return obj_from_bm(name, bm, material)


def rivet(loc, material, r=0.018):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=4, radius=r)
    bmesh.ops.translate(bm, verts=bm.verts, vec=Vector(loc))
    return obj_from_bm("rivet", bm, material)


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    return o


def arc_strip(name, r, k, width, thick, x, material, segs=10, a0=0.0, a1=math.pi):
    """Faixa curva que acompanha a tampa (no plano YZ, centrada no eixo da tampa), em x."""
    bm = bmesh.new()
    rows = []
    for i in range(segs + 1):
        a = a0 + (a1 - a0) * i / segs
        row = []
        for rr in (r, r + thick):
            for dx in (-width * 0.5, width * 0.5):
                row.append(bm.verts.new((x + dx, -math.cos(a) * rr, math.sin(a) * rr * k)))
        rows.append(row)
    for i in range(segs):
        a, b = rows[i], rows[i + 1]
        # índices: 0 dentro-esq, 1 dentro-dir, 2 fora-esq, 3 fora-dir
        bm.faces.new((a[2], a[3], b[3], b[2]))
        bm.faces.new((a[1], a[0], b[0], b[1]))
        bm.faces.new((a[0], a[2], b[2], b[0]))
        bm.faces.new((a[3], a[1], b[1], b[3]))
    for row, flip in ((rows[0], False), (rows[-1], True)):
        f = (row[0], row[1], row[3], row[2])
        bm.faces.new(tuple(reversed(f)) if flip else f)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, material)


def build(kind: str, path: str) -> None:
    reset()
    rnd = random.Random(7 if kind == "wood" else 11)
    iron = kind == "iron"
    if iron:
        plank_cols = [(0.30, 0.19, 0.11), (0.27, 0.17, 0.10), (0.33, 0.21, 0.12)]
        band = mat("iron", (0.22, 0.22, 0.24), 0.45, 0.9)
        rv = mat("rivet", (0.35, 0.34, 0.33), 0.4, 0.9)
        lock_m = mat("gold", (0.86, 0.64, 0.25), 0.3, 1.0)
    else:
        plank_cols = [(0.62, 0.46, 0.30), (0.56, 0.41, 0.26), (0.66, 0.50, 0.33)]
        band = mat("darkwood", (0.24, 0.15, 0.08), 0.85)
        rv = mat("nail", (0.3, 0.29, 0.28), 0.5, 0.8)
        lock_m = mat("iron_lock", (0.28, 0.27, 0.27), 0.45, 0.85)
    planks = [mat("plank%d" % i, c, 0.88) for i, c in enumerate(plank_cols)]
    inner = mat("inner", (0.08, 0.05, 0.03), 1.0)
    base_parts = []

    # Caixa: fundo, laterais em tábuas horizontais com pequenas variações (gastas).
    n_rows = 3
    ph = H / n_rows
    for side, (sx, sy, along) in {"front": (0, D * 0.5, "x"), "back": (0, -D * 0.5, "x"),
                                   "left": (-W * 0.5, 0, "y"), "right": (W * 0.5, 0, "y")}.items():
        for r in range(n_rows):
            z = ph * (r + 0.5)
            jitter = rnd.uniform(-0.006, 0.006)
            m = planks[rnd.randrange(len(planks))]
            if along == "x":
                base_parts.append(box("p", (W + 0.03, 0.045, ph - 0.012), (sx, sy + jitter, z), m, bevel=0.006))
            else:
                base_parts.append(box("p", (0.045, D - 0.02, ph - 0.012), (sx + jitter, sy, z), m, bevel=0.006))
    base_parts.append(box("bottom", (W, D, 0.05), (0, 0, 0.03), planks[0]))
    base_parts.append(box("inner", (W - 0.08, D - 0.08, 0.02), (0, 0, H - 0.04), inner))
    # Pés.
    for x in (-W * 0.5 + 0.06, W * 0.5 - 0.06):
        for y in (-D * 0.5 + 0.05, D * 0.5 - 0.05):
            base_parts.append(box("foot", (0.12, 0.1, 0.05), (x, y, -0.005), band))
    # Cintas verticais que abraçam a caixa (frente, fundo e trás).
    for x in (-W * 0.3, W * 0.3):
        base_parts.append(box("band", (0.07, 0.012, H), (x, D * 0.5 + 0.028, H * 0.5), band))
        base_parts.append(box("band", (0.07, 0.012, H), (x, -D * 0.5 - 0.028, H * 0.5), band))
        base_parts.append(box("band", (0.07, D + 0.07, 0.012), (x, 0, -0.002), band))
        for z in (0.07, H * 0.5, H - 0.07):
            base_parts.append(rivet((x, D * 0.5 + 0.036, z), rv))
            base_parts.append(rivet((x, -D * 0.5 - 0.036, z), rv))
    # Aro na borda de cima e cantoneiras.
    base_parts.append(box("rim", (W + 0.07, 0.03, 0.05), (0, D * 0.5 + 0.022, H - 0.025), band))
    base_parts.append(box("rim", (W + 0.07, 0.03, 0.05), (0, -D * 0.5 - 0.022, H - 0.025), band))
    base_parts.append(box("rim", (0.03, D + 0.07, 0.05), (W * 0.5 + 0.022, 0, H - 0.025), band))
    base_parts.append(box("rim", (0.03, D + 0.07, 0.05), (-W * 0.5 - 0.022, 0, H - 0.025), band))
    if iron:
        for x in (-W * 0.5 - 0.02, W * 0.5 + 0.02):
            for y in (-D * 0.5 - 0.02, D * 0.5 + 0.02):
                base_parts.append(box("corner", (0.07, 0.07, H + 0.02), (x, y, H * 0.5), band))
                for z in (0.08, H - 0.08):
                    base_parts.append(rivet((x + (0.036 if x > 0 else -0.036), y, z), rv))
    # Alças laterais.
    for x in (-W * 0.5 - 0.05, W * 0.5 + 0.05):
        base_parts.append(box("handle_plate", (0.02, 0.16, 0.08), (x - (0.02 if x > 0 else -0.02), 0, H * 0.62), band))
        base_parts.append(cyl("handle", 0.012, 0.15, (x + (0.03 if x > 0 else -0.03), 0, H * 0.5), lock_m if iron else band, rot=(math.pi * 0.5, 0, 0), segs=6))
    # Placa da fechadura (frente).
    base_parts.append(box("lockplate", (0.16, 0.025, 0.18), (0, D * 0.5 + 0.04, H - 0.11), lock_m, bevel=0.01))
    base_parts.append(cyl("keyhole", 0.016, 0.03, (0, D * 0.5 + 0.054, H - 0.1), inner, rot=(math.pi * 0.5, 0, 0)))
    base_parts.append(box("keyslot", (0.012, 0.03, 0.04), (0, D * 0.5 + 0.054, H - 0.135), inner))
    base = join(base_parts, "Base")

    # Tampa abaulada: tábuas em arco ao redor da dobradiça (traseira, no topo da caixa).
    lid_parts = []
    segs = 6
    k = LID_K
    for i in range(segs):
        a0 = math.pi * i / segs
        a1 = math.pi * (i + 1) / segs
        m = planks[rnd.randrange(len(planks))]
        lid_parts.append(arc_strip("lp", LID_R - 0.04, k, W + 0.02, 0.045, 0, m, 2, a0 + 0.012, a1 - 0.012))
    # Tampas laterais (meia elipse com espessura).
    for x in (-W * 0.5 + 0.01, W * 0.5 - 0.01):
        bm = bmesh.new()
        prof = [(-math.cos(math.pi * i / 12) * (LID_R - 0.01), math.sin(math.pi * i / 12) * (LID_R - 0.01) * k) for i in range(13)]
        a = [bm.verts.new((x - 0.02, y, z)) for y, z in prof]
        b = [bm.verts.new((x + 0.02, y, z)) for y, z in prof]
        bm.faces.new(a)
        bm.faces.new(list(reversed(b)))
        for i in range(13):
            j = (i + 1) % 13
            bm.faces.new((a[i], a[j], b[j], b[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        lid_parts.append(obj_from_bm("lidside", bm, planks[1]))
    for x in (-W * 0.3, W * 0.3):
        lid_parts.append(arc_strip("lband", LID_R + 0.003, k, 0.075, 0.014, x, band, 12))
        for i in range(1, 6):
            a = math.pi * i / 6
            lid_parts.append(rivet((x, -math.cos(a) * (LID_R + 0.02), math.sin(a) * (LID_R + 0.02) * k), rv))
    for x in (-W * 0.5 - 0.01, W * 0.5 + 0.01):
        lid_parts.append(arc_strip("lrim", LID_R - 0.04, k, 0.03, 0.05, x, band, 12))
    if not iron:
        # Corda amarrada em volta da tampa.
        rope = mat("rope", (0.55, 0.47, 0.33), 0.95)
        lid_parts.append(arc_strip("rope", LID_R + 0.005, k, 0.025, 0.02, W * 0.08, rope, 12))
    # Lingueta da fechadura (frente da tampa, encaixa na placa).
    lid_parts.append(box("hasp", (0.08, 0.02, 0.12), (0, LID_R + 0.03, -0.02), lock_m, bevel=0.006))
    lid = join(lid_parts, "Lid")
    # A tampa foi construída com o eixo no centro; a dobradiça fica na borda de trás.
    bpy.ops.object.select_all(action="DESELECT")
    lid.data.transform(Matrix.Translation((0, LID_R, 0)))
    lid.location = (0, -LID_R, H)

    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True)
    print("exportado:", path, len(base.data.polygons) + len(lid.data.polygons), "faces")


def render(path: str, out_png: str, open_lid: bool) -> None:
    """Prévia rápida (Cycles na CPU) do baú montado."""
    lid = bpy.data.objects["Lid"]
    if open_lid:
        lid.rotation_euler = (1.75, 0, 0)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 24
    sc.cycles.device = "CPU"
    sc.render.resolution_x = 640
    sc.render.resolution_y = 480
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    cam.location = (1.7, 2.1, 1.5)
    cam.rotation_euler = (Vector((0, 0, 0.4)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (0.8, 0.2, 0.9)
    sc.collection.objects.link(sun)
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.25, 0.27, 0.3, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    sc.world = w
    sc.render.filepath = out_png
    bpy.ops.render.render(write_still=True)


def main():
    out, rdir = args()
    for kind in ("wood", "iron"):
        p = os.path.join(out, "chest_%s.glb" % kind)
        build(kind, p)
        if rdir:
            os.makedirs(rdir, exist_ok=True)
            render(p, os.path.join(rdir, "chest_%s.png" % kind), False)
            render(p, os.path.join(rdir, "chest_%s_open.png" % kind), True)


if __name__ == "__main__":
    main()
