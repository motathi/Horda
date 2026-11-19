"""Vegetação do chão modelada no Blender (bpy) para o MultiMesh do jogo (scripts/world/foliage.gd).

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
from mathutils import Euler, Vector


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


BUILDERS = {"grass_tufts": build_grass_tufts}


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
                              export_vertex_color="NAME", export_vertex_color_name="Col", export_all_vertex_colors=False)
    print("exportado:", path)


def render_patch(out_png):
    """Prévia: um canteiro de 6×6 m com as touceiras espalhadas ao acaso, vista de cima inclinada."""
    sc = bpy.context.scene
    tufts = [o for o in sc.objects if o.type == "MESH"]
    rng = random.Random(3)
    for i in range(380):
        src = rng.choice(tufts)
        c = bpy.data.objects.new("inst", src.data)
        c.location = (rng.uniform(-3, 3), rng.uniform(-3, 3), 0)
        c.rotation_euler = Euler((0, 0, rng.uniform(0, math.tau)))
        s = rng.uniform(0.8, 1.3)
        c.scale = (s, s, s)
        sc.collection.objects.link(c)
    for t in tufts:
        t.hide_render = True
    g = bpy.data.meshes.new("ground")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=8)
    bm.to_mesh(g)
    gm = bpy.data.materials.new("dirt")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*srgb((0.3, 0.26, 0.16)), 1)
    g.materials.append(gm)
    sc.collection.objects.link(bpy.data.objects.new("ground", g))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 35
    sc.collection.objects.link(cam)
    cam.location = (0, -6.5, 5.5)
    cam.rotation_euler = Euler((math.radians(52), 0, 0))
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
    for n in names:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        BUILDERS[n]()
        export(os.path.join(out, n + ".glb"))
        if render_dir:
            os.makedirs(render_dir, exist_ok=True)
            render_patch(os.path.join(render_dir, n + ".png"))


if __name__ == "__main__":
    main()
