"""Pedras do mapa modeladas no Blender (bpy), no clima seco do jogo.

Cada pedra nasce de uma icosfera esticada e "lascada" por planos de corte aleatórios (como rocha
partida), com a base cortada reta, faces planas (sombreado facetado) e cor por vértice: cinza-marrom
variando por face, poeira clara nas faces de cima, líquen seco em algumas faces e a base escurecida.

  rock_boulder_a / rock_boulder_b   matacões (pedras de recurso grandes)
  rock_small_a / rock_small_b       pedras pequenas de recurso
  rock_slab                         laje em camadas (sedimentar), decoração
  rock_shards                       lascas pontudas de pedreira, decoração
  rock_pebbles                      seixos espalhados, decoração rente ao chão

Uso (módulo `bpy` do PyPI ou Blender):
  python3 tools/blender_rocks.py assets/models/blender [nome ...] [--render pasta]
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

lerp3, new_bm = bg.lerp3, bg.new_bm

STONE = [(0.3, 0.29, 0.28), (0.26, 0.25, 0.24), (0.33, 0.31, 0.28), (0.28, 0.28, 0.29)]
DUST = (0.52, 0.47, 0.38)
LICHEN = [(0.42, 0.4, 0.2), (0.5, 0.42, 0.2), (0.34, 0.33, 0.18)]
BASE_DARK = (0.12, 0.11, 0.1)


def chiseled(bm, rng, center, size, cuts=14, flat_bottom=0.25, jitter=0.03, subdiv=1):
    """Rocha lascada: icosfera esticada em `size` cortada por `cuts` planos (faces planas e quinas vivas)
    e com a base reta. Devolve as faces criadas."""
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=subdiv, radius=1.0)
    for v in tmp.verts:
        v.co = Vector((v.co.x * size.x, v.co.y * size.y, v.co.z * size.z))
    for _ in range(cuts):
        a = rng.uniform(0, math.tau)
        el = rng.uniform(-0.35, 1.1)
        n = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
        # Distância do corte: proporcional ao tamanho na direção do plano.
        ext = abs(n.x) * size.x + abs(n.y) * size.y + abs(n.z) * size.z
        d = ext * rng.uniform(0.42, 0.72) / max(0.001, n.length)
        geom = tmp.verts[:] + tmp.edges[:] + tmp.faces[:]
        bmesh.ops.bisect_plane(tmp, geom=geom, plane_co=n * d, plane_no=n, clear_outer=True)
        bmesh.ops.holes_fill(tmp, edges=tmp.edges[:], sides=0)
    # Base reta (a pedra assenta no chão, um pouco enterrada).
    zb = -size.z * flat_bottom
    geom = tmp.verts[:] + tmp.edges[:] + tmp.faces[:]
    bmesh.ops.bisect_plane(tmp, geom=geom, plane_co=Vector((0, 0, zb)), plane_no=Vector((0, 0, -1)), clear_outer=True)
    bmesh.ops.holes_fill(tmp, edges=tmp.edges[:], sides=0)
    for v in tmp.verts:
        if v.co.z > zb + 0.01:
            v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * jitter * size.length
        v.co.z -= zb
    # Normais para fora (o fechamento dos cortes pode sair invertido): compara com o centro da pedra.
    cen = sum((v.co for v in tmp.verts), Vector()) / max(1, len(tmp.verts))
    flip = []
    for f in tmp.faces:
        f.normal_update()
        if f.normal.dot(f.calc_center_median() - cen) < 0:
            flip.append(f)
    if flip:
        bmesh.ops.reverse_faces(tmp, faces=flip)
    me = bpy.data.meshes.new("tmp")
    tmp.to_mesh(me)
    tmp.free()
    before = set(bm.faces)
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    new = [f for f in bm.faces if f not in before]
    bmesh.ops.translate(bm, verts=list({v for f in new for v in f.verts}), vec=center)
    return new


def paint(bm, cl, faces, rng, base=None, height=1.0, lichen=0.12, dust=0.32, z0=0.0):
    """Cor por face: tom de pedra com variação, poeira no topo, líquen em algumas faces, base escura."""
    base = base or rng.choice(STONE)
    for f in faces:
        f.normal_update()
        n = f.normal
        shade = rng.uniform(0.82, 1.12)
        c = tuple(x * shade for x in base)
        up = max(0.0, min(1.0, (n.z - 0.45) / 0.45))
        c = lerp3(c, DUST, up * dust * rng.uniform(0.6, 1.0))
        if rng.random() < lichen and n.z > 0.1:
            c = lerp3(c, rng.choice(LICHEN), rng.uniform(0.5, 0.85))
        if n.z < -0.7:
            c = BASE_DARK
        for loop in f.loops:
            t = max(0.0, min(1.0, (loop.vert.co.z - z0) / max(0.05, height * 0.45)))
            loop[cl] = (*lerp3(lerp3(c, BASE_DARK, 0.55), c, t), 1.0)


def done(name, bm):
    o = bg.finish(name, bm)
    for p in o.data.polygons:
        p.use_smooth = False  # facetado: quinas vivas
    return o


def build_boulder(name, seed, size):
    rng = random.Random(seed)
    bm, cl = new_bm()
    fs = chiseled(bm, rng, Vector((0, 0, 0)), size, cuts=26, subdiv=2)
    paint(bm, cl, fs, rng, height=size.z * 1.3)
    # Pedra menor encostada (como um pedaço que se soltou).
    s2 = size * rng.uniform(0.35, 0.45)
    fs2 = chiseled(bm, rng, Vector((size.x * 0.95, size.y * 0.35, 0)), s2, cuts=12)
    # Cascalho solto ao pé da pedra.
    for k in range(5):
        a = rng.uniform(0, math.tau)
        sp = Vector((math.cos(a) * size.x * 1.05, math.sin(a) * size.y * 1.05, 0))
        s3 = size * rng.uniform(0.1, 0.16)
        paint(bm, cl, chiseled(bm, rng, sp, s3, cuts=5, subdiv=0), rng, height=s3.z * 1.3, lichen=0.0)
    paint(bm, cl, fs2, rng, height=s2.z * 1.3)
    return done(name, bm)


def build_rock_boulder_a():
    return build_boulder("rock_boulder_a", 3, Vector((1.0, 0.8, 0.75)))


def build_rock_boulder_b():
    return build_boulder("rock_boulder_b", 8, Vector((0.9, 0.95, 0.95)))


def build_small(name, seed, size):
    rng = random.Random(seed)
    bm, cl = new_bm()
    fs = chiseled(bm, rng, Vector((0, 0, 0)), size, cuts=18, subdiv=2)
    paint(bm, cl, fs, rng, height=size.z * 1.3)
    return done(name, bm)


def build_rock_small_a():
    return build_small("rock_small_a", 12, Vector((0.55, 0.45, 0.4)))


def build_rock_small_b():
    return build_small("rock_small_b", 15, Vector((0.5, 0.5, 0.5)))


def build_rock_slab():
    """Laje sedimentar: três camadas achatadas e desalinhadas, a de cima menor."""
    rng = random.Random(21)
    bm, cl = new_bm()
    base = rng.choice(STONE)
    z = 0.0
    for k, (sx, sy, sz) in enumerate(((1.3, 0.95, 0.28), (1.05, 0.8, 0.24), (0.7, 0.55, 0.2))):
        c = Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.12, 0.12), z))
        fs = chiseled(bm, rng, c, Vector((sx, sy, sz)), cuts=8, flat_bottom=0.5, jitter=0.03)
        paint(bm, cl, fs, rng, base=tuple(x * (0.92 + 0.06 * k) for x in base), height=sz * 2.5, z0=z)
        z += sz * 0.95
    return done("rock_slab", bm)


def build_rock_shards():
    """Lascas de pedreira: pedras compridas e pontudas inclinadas umas nas outras."""
    rng = random.Random(33)
    bm, cl = new_bm()
    for k in range(5):
        a = k * math.tau / 5 + rng.uniform(-0.3, 0.3)
        r = rng.uniform(0.2, 0.6)
        size = Vector((rng.uniform(0.25, 0.4), rng.uniform(0.2, 0.32), rng.uniform(0.7, 1.3)))
        fs = chiseled(bm, rng, Vector((0, 0, 0)), size, cuts=9, flat_bottom=0.2)
        verts = list({v for f in fs for v in f.verts})
        tilt = Matrix.Rotation(rng.uniform(0.15, 0.5), 4, Vector((-math.sin(a), math.cos(a), 0)))
        bmesh.ops.transform(bm, matrix=tilt, verts=verts)
        bmesh.ops.translate(bm, verts=verts, vec=Vector((math.cos(a) * r, math.sin(a) * r, 0)))
        paint(bm, cl, fs, rng, height=size.z * 1.4, lichen=0.06)
    return done("rock_shards", bm)


def build_rock_pebbles():
    """Seixos: uma dúzia de pedrinhas lascadas espalhadas rente ao chão."""
    rng = random.Random(44)
    bm, cl = new_bm()
    for k in range(12):
        a, r = rng.uniform(0, math.tau), 0.7 * math.sqrt(rng.random())
        s = rng.uniform(0.06, 0.16)
        size = Vector((s * rng.uniform(1.0, 1.6), s, s * rng.uniform(0.5, 0.8)))
        fs = chiseled(bm, rng, Vector((math.cos(a) * r, math.sin(a) * r, 0)), size, cuts=5, flat_bottom=0.3, subdiv=0)
        paint(bm, cl, fs, rng, height=size.z * 1.3, lichen=0.05)
    return done("rock_pebbles", bm)


BUILDERS = {"rock_boulder_a": build_rock_boulder_a, "rock_boulder_b": build_rock_boulder_b,
            "rock_small_a": build_rock_small_a, "rock_small_b": build_rock_small_b, "rock_slab": build_rock_slab,
            "rock_shards": build_rock_shards, "rock_pebbles": build_rock_pebbles}


def render_lineup(out_png):
    import blender_trees as bt
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for i, n in enumerate(BUILDERS):
        o = BUILDERS[n]()
        o.location = ((i % 4) * 2.8 - 4.2, (i // 4) * 2.8, 0)
    bt.to_linear_for_preview()
    sc = bpy.context.scene
    g = bpy.data.meshes.new("ground")
    b = bmesh.new()
    bmesh.ops.create_grid(b, x_segments=1, y_segments=1, size=12)
    b.to_mesh(g)
    gm = bpy.data.materials.new("dirt")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.09, 0.065, 0.035, 1)
    g.materials.append(gm)
    sc.collection.objects.link(bpy.data.objects.new("ground", g))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 32
    sc.collection.objects.link(cam)
    cam.location = (0, -8.5, 7.5)
    cam.rotation_euler = Euler((math.radians(50), 0, 0))
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
    sc.render.resolution_x, sc.render.resolution_y = 1400, 800
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
        render_lineup(os.path.join(render_dir, "rocks.png"))


if __name__ == "__main__":
    main()
