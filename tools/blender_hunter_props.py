"""Modela no Blender (bpy) os objetos do Caçador e exporta GLB para o jogo:
  - eagle.glb      águia-de-cabeça-branca low-poly com asas articuladas e animações
                   "fly" (bater de asas), "glide" (planar) e "dive" (mergulho, asas recolhidas)
  - bow.glb        arco recurvo de madeira com corda (empunhadura na origem)
  - bear_trap.glb  armadilha de urso aberta (mandíbulas dentadas sobre a base)
Uso (Blender instalado ou módulo bpy do PyPI):
  blender --background --python tools/blender_hunter_props.py -- assets/models/blender
  python3 tools/blender_hunter_props.py assets/models/blender      (com `pip install bpy`)
Convenção: frente em +Y e topo em +Z no Blender (vira -Z/+Y no glTF/Godot)."""
import math
import os
import sys

import bpy  # noqa: I001 — com o módulo do PyPI, bmesh só existe depois de importar bpy
import bmesh
from mathutils import Euler, Vector

FPS = 24


def out_dir() -> str:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    d = args[0] if args else "assets/models/blender"
    os.makedirs(d, exist_ok=True)
    return d


def reset() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def mat(name: str, color, rough: float = 0.8, metal: float = 0.0, emit: float = 0.0):
    """color em sRGB (como num seletor de cor); o Blender guarda em linear."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    color = tuple(srgb_to_linear(c) for c in color)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit > 0.0:
        b.inputs["Emission Color"].default_value = (*color, 1.0)
        b.inputs["Emission Strength"].default_value = emit
    return m


def link(obj, parent=None):
    bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def empty(name: str, loc=(0, 0, 0), parent=None):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    return link(e, parent)


def mesh_obj(name: str, bm: bmesh.types.BMesh, material, loc=(0, 0, 0), parent=None, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    me.materials.append(material)
    o = bpy.data.objects.new(name, me)
    o.location = loc
    return link(o, parent)


def ellipsoid(name, scale, material, loc=(0, 0, 0), parent=None, segs=10, rings=7):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    return mesh_obj(name, bm, material, loc, parent, smooth=False)


def cone(name, r1, r2, depth, material, loc=(0, 0, 0), rot=(0, 0, 0), parent=None, segs=6):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Euler(rot).to_matrix())
    return mesh_obj(name, bm, material, loc, parent)


def slab(name, pts2d, thick, material, loc=(0, 0, 0), parent=None, z_curve=0.0):
    """Polígono plano (x, y) com espessura; z_curve arqueia levemente (asas)."""
    bm = bmesh.new()
    top = [bm.verts.new((x, y, thick * 0.5 + z_curve * (x * x))) for x, y in pts2d]
    bot = [bm.verts.new((x, y, -thick * 0.5 + z_curve * (x * x))) for x, y in pts2d]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(pts2d)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((top[i], top[j], bot[j], bot[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_obj(name, bm, material, loc, parent)


def export(path: str) -> None:
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True,
                              export_animation_mode="NLA_TRACKS", export_yup=True)
    print("exportado:", path)


# --- Águia ------------------------------------------------------------------------------

def build_eagle(path: str) -> None:
    reset()
    brown = mat("eagle_brown", (0.36, 0.22, 0.12), 0.85)
    dark = mat("eagle_dark", (0.2, 0.13, 0.08), 0.85)
    white = mat("eagle_white", (0.95, 0.93, 0.88), 0.7)
    yellow = mat("eagle_yellow", (1.0, 0.75, 0.15), 0.5)
    black = mat("eagle_eye", (0.02, 0.02, 0.02), 0.2)

    root = empty("Eagle")
    body = ellipsoid("Body", (0.16, 0.4, 0.15), brown, (0, 0, 0), root)
    ellipsoid("Chest", (0.13, 0.22, 0.12), dark, (0, 0.12, -0.04), body)
    head = ellipsoid("Head", (0.11, 0.13, 0.11), white, (0, 0.42, 0.07), body)
    # Bico curvo: cone para a frente com a ponta virada para baixo.
    cone("Beak", 0.045, 0.008, 0.13, yellow, (0, 0.15, -0.015), (math.radians(-100), 0, 0), head)
    for sx in (-1, 1):
        ellipsoid("Eye", (0.018, 0.018, 0.018), black, (sx * 0.075, 0.07, 0.035), head, 6, 4)
        # Sobrancelha escura dá o olhar feroz.
        slab("Brow", [(-0.035, 0.02), (0.035, 0.0), (0.035, -0.015), (-0.035, 0.0)], 0.01, dark,
             (sx * 0.07, 0.065, 0.06), head)
    slab("Tail", [(-0.07, -0.3), (0.07, -0.3), (0.17, -0.72), (0.08, -0.76), (0.0, -0.73),
                  (-0.08, -0.76), (-0.17, -0.72)], 0.025, white, (0, 0, 0.0), body)
    for sx in (-1, 1):
        leg = cone("Leg", 0.03, 0.022, 0.16, yellow, (sx * 0.07, -0.12, -0.17), (math.radians(30), 0, 0), body)
        for k in (-1, 0, 1):
            cone("Claw", 0.012, 0.0, 0.06, dark, (k * 0.02, -0.04, -0.09), (math.radians(150), 0, 0), leg, 4)

    # Asas: braço (ombro -> cotovelo) e mão com penas primárias em "dedos".
    inner_pts = [(0.0, 0.12), (0.0, -0.14), (0.25, -0.2), (0.55, -0.2), (0.55, 0.1), (0.25, 0.13)]
    outer_pts = [(0.0, 0.1), (0.3, 0.07), (0.55, 0.0), (0.68, -0.03), (0.58, -0.07), (0.7, -0.1),
                 (0.57, -0.13), (0.66, -0.17), (0.52, -0.18), (0.58, -0.23), (0.42, -0.22),
                 (0.45, -0.27), (0.25, -0.25), (0.0, -0.2)]
    for side, sx in (("L", -1), ("R", 1)):
        pin = empty("Wing%s_in" % side, (sx * 0.12, 0.06, 0.05), body)
        slab("Wing%s_in_mesh" % side, [(sx * x, y) for x, y in inner_pts], 0.022, brown, (0, 0, 0), pin)
        pout = empty("Wing%s_out" % side, (sx * 0.55, 0.0, 0.0), pin)
        slab("Wing%s_out_mesh" % side, [(sx * x, y) for x, y in outer_pts], 0.016, dark, (0, 0, 0), pout)

    # Animações (eixo Y = frente: girar em Y abre/fecha a asa para cima/baixo).
    def anim(track: str, frames: list, cyclic: bool = True):
        """frames: lista de (frame, {objeto: (rot_xyz_graus, loc ou None)})."""
        objs = {}
        for f, poses in frames:
            for name in poses:
                objs.setdefault(name, []).append((f, poses[name]))
        for name, keys in objs.items():
            o = bpy.data.objects[name]
            o.animation_data_create()
            act = bpy.data.actions.new("%s_%s" % (track, name))
            o.animation_data.action = act
            base_loc = o.location.copy()
            for f, (rot, loc) in keys:
                o.rotation_euler = Euler([math.radians(a) for a in rot])
                o.keyframe_insert("rotation_euler", frame=f)
                if loc is not None:
                    o.location = base_loc + Vector(loc)
                    o.keyframe_insert("location", frame=f)
            o.location = base_loc
            o.rotation_euler = Euler((0, 0, 0))
            t = o.animation_data.nla_tracks.new()
            t.name = track
            strip = t.strips.new(track, int(keys[0][0]), act)
            strip.name = track
            o.animation_data.action = None

    def wings(rin, rout, sweep=0.0, body_z=None):
        d = {
            "WingL_in": ((0, -rin, sweep), None), "WingR_in": ((0, rin, -sweep), None),
            "WingL_out": ((0, -rout, sweep * 0.6), None), "WingR_out": ((0, rout, -sweep * 0.6), None),
        }
        if body_z is not None:
            d["Body"] = ((0, 0, 0), (0, 0, body_z))
        return d

    anim("fly", [(1, wings(38, 22, 0, 0.0)), (4, wings(10, 25, 0, 0.03)), (7, wings(-32, -18, 0, 0.05)),
                 (10, wings(-8, -30, 0, 0.02)), (13, wings(38, 22, 0, 0.0))])
    anim("glide", [(1, wings(6, -4, 0, 0.0)), (24, wings(10, -2, 0, 0.03)), (48, wings(6, -4, 0, 0.0))])
    anim("dive", [(1, wings(20, 10, -55, 0.0)), (6, wings(28, 40, -75, 0.0)), (12, wings(28, 40, -75, 0.0))])
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 48
    export(path)


# --- Arco ----------------------------------------------------------------------------------

def build_bow(path: str) -> None:
    reset()
    wood = mat("bow_wood", (0.45, 0.27, 0.13), 0.6)
    grip = mat("bow_grip", (0.2, 0.12, 0.07), 0.9)
    string = mat("bow_string", (0.85, 0.82, 0.72), 0.5)
    tip = mat("bow_tip", (0.75, 0.75, 0.78), 0.3, 0.8)
    root = empty("Bow")
    # Arco no plano YZ: empunhadura na origem, braços curvam para trás e as pontas recurvam à frente.
    pts = []
    n = 14
    for i in range(n + 1):
        t = -1.0 + 2.0 * i / n
        z = t * 0.68
        y = -0.2 * (abs(t) ** 1.6)
        if abs(t) > 0.82:
            y += 0.22 * (abs(t) - 0.82) / 0.18 * 0.5
        pts.append(Vector((0, y, z)))
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        t = -1.0 + 2.0 * i / n
        r = 0.045 * (1.0 - 0.5 * abs(t))
        nxt = pts[min(i + 1, n)] - pts[max(i - 1, 0)]
        nxt.normalize()
        side = Vector((1, 0, 0))
        up = nxt.cross(side).normalized()
        ring = [bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * r * (1.6 if k % 2 == 0 else 1.0))
                for k, a in enumerate([j * math.tau / 6 for j in range(6)])]
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(6):
            bm.faces.new((a[k], a[(k + 1) % 6], b[(k + 1) % 6], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh_obj("Limbs", bm, wood, (0, 0, 0), root)
    cone("Grip", 0.055, 0.055, 0.18, grip, (0, -0.005, 0), (0, 0, 0), root, 8)
    top, bot = pts[-1], pts[0]
    length = (top - bot).length
    cone("String", 0.009, 0.009, length, string, ((top + bot) * 0.5).to_tuple(), (0, 0, 0), root, 4)
    for p in (top, bot):
        cone("Nock", 0.014, 0.0, 0.05, tip, p.to_tuple(), (0 if p.z > 0 else math.pi, 0, 0), root, 5)
    export(path)


# --- Armadilha de urso ------------------------------------------------------------------

def build_trap(path: str) -> None:
    reset()
    iron = mat("trap_iron", (0.5, 0.49, 0.47), 0.45, 0.85)
    rust = mat("trap_rust", (0.5, 0.27, 0.12), 0.8, 0.3)
    root = empty("BearTrap")
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.16, radius2=0.14, depth=0.04)
    mesh_obj("Plate", bm, rust, (0, 0, 0.02), root)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.42, radius2=0.42, depth=0.025)
    ring = mesh_obj("Base", bm, iron, (0, 0, 0.012), root)
    for side, sx in (("A", 1), ("B", -1)):
        pivot = empty("Jaw%s" % side, (0, 0, 0.03), root)
        pivot.rotation_euler = Euler((0, math.radians(-14 * sx), 0))
        # Mandíbula: meia argola com dentes triangulares virados para dentro.
        bm = bmesh.new()
        segs = 10
        r0, r1 = 0.36, 0.42
        inner, outer = [], []
        for i in range(segs + 1):
            a = math.pi * i / segs - math.pi / 2
            inner.append(bm.verts.new((sx * r0 * math.cos(a), r0 * math.sin(a), 0.0)))
            outer.append(bm.verts.new((sx * r1 * math.cos(a), r1 * math.sin(a), 0.0)))
        top_i = [bm.verts.new((v.co.x, v.co.y, 0.035)) for v in inner]
        top_o = [bm.verts.new((v.co.x, v.co.y, 0.035)) for v in outer]
        for i in range(segs):
            bm.faces.new((inner[i], inner[i + 1], outer[i + 1], outer[i]))
            bm.faces.new((top_i[i], top_o[i], top_o[i + 1], top_i[i + 1]))
            bm.faces.new((inner[i], top_i[i], top_i[i + 1], inner[i + 1]))
            bm.faces.new((outer[i], outer[i + 1], top_o[i + 1], top_o[i]))
        for i in range(1, segs):
            a = math.pi * i / segs - math.pi / 2
            c = Vector((sx * r0 * math.cos(a), r0 * math.sin(a), 0.0))
            tang = Vector((-math.sin(a) * sx, math.cos(a), 0)).normalized() * 0.03
            tipv = c * (1.0 - 0.18 / r0)
            v1 = bm.verts.new(c - tang)
            v2 = bm.verts.new(c + tang)
            v3 = bm.verts.new((c.x * 0.97, c.y * 0.97, 0.13))
            v4 = bm.verts.new((c.x, c.y, 0.035))
            bm.faces.new((v1, v2, v3))
            bm.faces.new((v2, v4, v3))
            bm.faces.new((v4, v1, v3))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh_obj("Jaw%s_mesh" % side, bm, iron, (0, 0, 0), pivot)
    # Molas laterais.
    for sx in (-1, 1):
        cone("Spring", 0.035, 0.035, 0.22, iron, (sx * 0.5, 0, 0.03), (0, math.pi / 2, 0), root, 6)
    export(path)


if __name__ == "__main__":
    d = out_dir()
    build_eagle(os.path.join(d, "eagle.glb"))
    build_bow(os.path.join(d, "bow.glb"))
    build_trap(os.path.join(d, "bear_trap.glb"))
