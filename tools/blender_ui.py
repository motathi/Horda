"""Arte da interface da tela inicial renderizada no Blender (Cycles), estilo fantasia sombria de RTS:
metal escuro com bordas douradas, rebites e brasa nas rachaduras.

  ui_logo.png            logotipo "HORDA": letras extrudadas em ferro escuro com rachaduras em brasa,
                         chanfro dourado, sobre uma placa de lâmina com bordas douradas (fundo transparente)
  ui_button_*.png        botão (normal, hover, pressed, disabled): placa de ferro chanfrada com filete
                         dourado, rebites nos cantos e, no hover, brasa acesa por dentro — para 9-slice
  ui_panel.png           moldura de painel: borda de ferro com filete dourado e gemas vermelhas nos
                         cantos, miolo de pedra escura — para 9-slice
  ui_divider.png         divisor: filete dourado com gema no meio

Fontes: Gloock (logotipo) — SIL Open Font License (assets/ui/fonts/OFL-*.txt).

Uso (módulo `bpy` do PyPI ou Blender):
  python3 tools/blender_ui.py assets/ui/title [nome ...]
"""
import math
import os
import sys

import bpy  # noqa: I001
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_LOGO = os.path.join(HERE, "..", "assets", "ui", "fonts", "Gloock-Regular.ttf")


# ------------------------------------------------------------------ materiais

def mat_metal(name, color, rough=0.35, metallic=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    return m


def mat_iron(name, base=(0.05, 0.045, 0.042), ember=0.0, crack_scale=6.0, glow_center=0.0):
    """Ferro escuro martelado (ruído na rugosidade) com rachaduras em brasa (Voronoi distância à borda)
    e, opcionalmente, brilho de brasa vindo do centro (glow_center)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*base, 1)
    b.inputs["Metallic"].default_value = 0.85
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 18.0
    nz.inputs["Detail"].default_value = 8.0
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    rr = nt.nodes.new("ShaderNodeMapRange")
    rr.inputs["To Min"].default_value = 0.3
    rr.inputs["To Max"].default_value = 0.65
    nt.links.new(nz.outputs["Fac"], rr.inputs["Value"])
    nt.links.new(rr.outputs["Result"], b.inputs["Roughness"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    nt.links.new(nz.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    emit_total = None
    if ember > 0:
        vor = nt.nodes.new("ShaderNodeTexVoronoi")
        vor.feature = "DISTANCE_TO_EDGE"
        vor.inputs["Scale"].default_value = crack_scale
        nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
        cr = nt.nodes.new("ShaderNodeMapRange")
        cr.inputs["From Min"].default_value = 0.0
        cr.inputs["From Max"].default_value = 0.035
        cr.inputs["To Min"].default_value = 1.0
        cr.inputs["To Max"].default_value = 0.0
        nt.links.new(vor.outputs["Distance"], cr.inputs["Value"])
        # Só parte das rachaduras acende (ruído grande).
        n2 = nt.nodes.new("ShaderNodeTexNoise")
        n2.inputs["Scale"].default_value = 2.5
        nt.links.new(tc.outputs["Object"], n2.inputs["Vector"])
        g2 = nt.nodes.new("ShaderNodeMapRange")
        g2.inputs["From Min"].default_value = 0.42
        g2.inputs["From Max"].default_value = 0.62
        nt.links.new(n2.outputs["Fac"], g2.inputs["Value"])
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        nt.links.new(cr.outputs["Result"], mul.inputs[0])
        nt.links.new(g2.outputs["Result"], mul.inputs[1])
        emit_total = mul.outputs[0]
        b.inputs["Emission Strength"].default_value = ember
    if glow_center > 0:
        grad = nt.nodes.new("ShaderNodeTexGradient")
        grad.gradient_type = "SPHERICAL"
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (0.35, 1.4, 1.0)
        nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], grad.inputs["Vector"])
        gp = nt.nodes.new("ShaderNodeMath")
        gp.operation = "POWER"
        gp.inputs[1].default_value = 1.6
        nt.links.new(grad.outputs["Fac"], gp.inputs[0])
        if emit_total is not None:
            add = nt.nodes.new("ShaderNodeMath")
            add.operation = "ADD"
            nt.links.new(emit_total, add.inputs[0])
            nt.links.new(gp.outputs[0], add.inputs[1])
            emit_total = add.outputs[0]
        else:
            emit_total = gp.outputs[0]
        b.inputs["Emission Strength"].default_value = max(ember, glow_center)
    if emit_total is not None:
        col = nt.nodes.new("ShaderNodeMix")
        col.data_type = "RGBA"
        col.inputs[6].default_value = (0, 0, 0, 1)
        col.inputs[7].default_value = (1.0, 0.28, 0.05, 1)
        nt.links.new(emit_total, col.inputs[0])
        nt.links.new(col.outputs[2], b.inputs["Emission Color"])
    return m


def mat_gem():
    m = bpy.data.materials.new("gem")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.5, 0.02, 0.02, 1)
    b.inputs["Roughness"].default_value = 0.08
    b.inputs["Emission Color"].default_value = (1.0, 0.05, 0.02, 1)
    b.inputs["Emission Strength"].default_value = 1.2
    return m


GOLD = (0.83, 0.55, 0.22)


# ------------------------------------------------------------------ cena

def scene(width, height, ortho_w, persp=False, cam_z=10.0, tilt=0.0):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    if persp:
        cam.data.lens = 85
    else:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho_w
    cam.location = (0, -math.tan(tilt) * cam_z, cam_z)
    cam.rotation_euler = (tilt, 0, 0)
    sc.collection.objects.link(cam)
    sc.camera = cam
    # Luz: principal quente de cima à esquerda, contraluz vermelha de baixo, preenchimento frio.
    for name, typ, loc, rot, energy, color, size in (
            ("key", "AREA", (-4, 3, 6), (math.radians(-30), math.radians(-35), 0), 900, (1.0, 0.86, 0.68), 4),
            ("rim", "AREA", (3, -5, 2), (math.radians(70), 0, math.radians(20)), 500, (1.0, 0.25, 0.08), 3),
            ("fill", "AREA", (5, 4, 5), (math.radians(-35), math.radians(40), 0), 180, (0.5, 0.6, 1.0), 5)):
        ld = bpy.data.lights.new(name, typ)
        ld.energy = energy
        ld.color = color
        ld.size = size
        lo = bpy.data.objects.new(name, ld)
        lo.location = loc
        lo.rotation_euler = rot
        sc.collection.objects.link(lo)
    # Mundo: gradiente escuro (dá reflexo ao metal) — não aparece (fundo transparente).
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    bgn = nt.nodes["Background"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.02, 0.015, 0.012, 1)
    ramp.color_ramp.elements[1].color = (0.55, 0.45, 0.35, 1)
    nt.links.new(sep.outputs["Z"], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], bgn.inputs["Color"])
    bgn.inputs["Strength"].default_value = 0.6
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 64
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.resolution_x, sc.render.resolution_y = width, height
    return sc


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("render:", path)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def poly_mesh(name, outline, depth, bevel=0.0, z=0.0):
    """Placa: polígono (lista de (x, y)) extrudado em `depth`, com chanfro opcional."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, z)) for x, y in outline]
    f = bm.faces.new(vs)
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    top = [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=top, vec=(0, 0, depth))
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = link(bpy.data.objects.new(name, me))
    if bevel > 0:
        mod = o.modifiers.new("bev", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.limit_method = "ANGLE"
    for p in me.polygons:
        p.use_smooth = False
    return o


def chamfer_rect(w, h, c):
    return [(-w / 2 + c, -h / 2), (w / 2 - c, -h / 2), (w / 2, -h / 2 + c), (w / 2, h / 2 - c), (w / 2 - c, h / 2),
            (-w / 2 + c, h / 2), (-w / 2, h / 2 - c), (-w / 2, -h / 2 + c)]


def frame_ring(name, w, h, c, thick, depth, z, mat):
    """Moldura chanfrada (anel): retângulo externo menos o interno."""
    outer = chamfer_rect(w, h, c)
    inner = chamfer_rect(w - thick * 2, h - thick * 2, max(0.01, c - thick * 0.6))
    bm = bmesh.new()
    vo = [bm.verts.new((x, y, z)) for x, y in outer]
    vi = [bm.verts.new((x, y, z)) for x, y in inner]
    n = len(vo)
    for i in range(n):
        bm.faces.new([vo[i], vo[(i + 1) % n], vi[(i + 1) % n], vi[i]])
    r = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
    top = [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=top, vec=(0, 0, depth))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = link(bpy.data.objects.new(name, me))
    mod = o.modifiers.new("bev", "BEVEL")
    mod.width = min(thick, depth) * 0.35
    mod.segments = 3
    me.materials.append(mat)
    return o


def rivet(x, y, z, r, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=r, location=(x, y, z))
    o = bpy.context.active_object
    o.scale.z = 0.55
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def gem(x, y, z, r):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=r, location=(x, y, z))
    o = bpy.context.active_object
    o.scale.z = 0.6
    o.data.materials.append(mat_gem())
    return o


# ------------------------------------------------------------------ peças

def build_logo(out):
    sc = scene(1600, 560, 0, persp=True, cam_z=26.0, tilt=math.radians(9))
    iron = mat_iron("iron_letters", base=(0.07, 0.06, 0.055), ember=6.0, crack_scale=3.2)
    gold = mat_metal("gold", GOLD, rough=0.28)
    plate_iron = mat_iron("plate", base=(0.035, 0.03, 0.03))
    # Texto extrudado, convertido em malha: face da frente = ferro com brasa; chanfro e lados = ouro.
    cu = bpy.data.curves.new("logo", "FONT")
    cu.body = "HORDA"
    if os.path.exists(FONT_LOGO):
        cu.font = bpy.data.fonts.load(FONT_LOGO)
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.size = 2.6
    cu.space_character = 1.08
    cu.extrude = 0.16
    cu.bevel_depth = 0.045
    cu.bevel_resolution = 2
    to = link(bpy.data.objects.new("logo", cu))
    to.location.z = 0.32
    bpy.context.view_layer.objects.active = to
    to.select_set(True)
    bpy.ops.object.convert(target="MESH")
    to = bpy.context.active_object
    to.data.materials.append(iron)
    to.data.materials.append(gold)
    for p in to.data.polygons:
        p.material_index = 0 if p.normal.z > 0.97 else 1
    dims = to.dimensions
    # Placa de lâmina atrás do texto: losango alongado com pontas, borda dourada.
    W, H = dims.x * 1.18, dims.y * 1.05
    blade = [(-W / 2 - 0.9, 0), (-W / 2 + 0.3, -H / 2), (W / 2 - 0.3, -H / 2), (W / 2 + 0.9, 0), (W / 2 - 0.3, H / 2),
             (-W / 2 + 0.3, H / 2)]
    pl = poly_mesh("plate", blade, 0.18, bevel=0.06, z=0.0)
    pl.data.materials.append(plate_iron)
    rim = [(x * 1.035 + (0.08 if x > 0 else -0.08), y * 1.12) for x, y in blade]
    rb = poly_mesh("rim", rim, 0.12, bevel=0.04, z=-0.02)
    rb.data.materials.append(gold)
    # Espetos nas pontas e rebites na placa.
    for sx in (-1, 1):
        sp = poly_mesh("spike", [(sx * (W / 2 + 0.85), 0.12), (sx * (W / 2 + 1.7), 0), (sx * (W / 2 + 0.85), -0.12)], 0.12,
                       bevel=0.02, z=0.04)
        sp.data.materials.append(gold)
        for sy in (-1, 1):
            rivet(sx * (W / 2 - 0.15), sy * (H / 2 - 0.18), 0.2, 0.09, gold)
    sc.camera.data.lens = 85
    # Enquadra: distância para caber a largura total.
    total_w = W + 3.6
    sc.camera.location = (0, -math.tan(math.radians(9)) * 30, 30)
    sc.camera.data.lens = 36 * 30 / (total_w * 1.08)
    render(os.path.join(out, "ui_logo.png"))


def build_buttons(out):
    states = {
        "normal": dict(base=(0.05, 0.045, 0.04), glow=0.0, gold=GOLD, ember=0.0),
        "hover": dict(base=(0.06, 0.045, 0.04), glow=0.55, gold=(1.0, 0.72, 0.32), ember=0.9),
        "pressed": dict(base=(0.03, 0.02, 0.02), glow=0.9, gold=(0.75, 0.45, 0.18), ember=1.4),
        "disabled": dict(base=(0.05, 0.05, 0.05), glow=0.0, gold=(0.35, 0.33, 0.3), ember=0.0),
    }
    for st, p in states.items():
        # 400x80: com os cantos em ~28 px o 9-slice encaixa em botões de 50–70 px de altura.
        sc = scene(400, 80, 6.4)
        w, h = 6.2, 1.18
        inner = mat_iron("inner_" + st, base=p["base"], ember=p["ember"], crack_scale=9.0, glow_center=p["glow"])
        gold = mat_metal("gold_" + st, p["gold"], rough=0.3, metallic=1.0 if st != "disabled" else 0.4)
        iron = mat_iron("iron_" + st, base=(0.04, 0.035, 0.032))
        face = poly_mesh("face", chamfer_rect(w - 0.3, h - 0.3, 0.16), 0.1, bevel=0.03, z=0.0)
        face.data.materials.append(inner)
        frame_ring("frame", w, h, 0.26, 0.17, 0.2, 0.0, iron)
        frame_ring("trim", w - 0.26, h - 0.26, 0.2, 0.05, 0.24, 0.0, gold)
        for sx in (-1, 1):
            for sy in (-1, 1):
                rivet(sx * (w / 2 - 0.2), sy * (h / 2 - 0.2), 0.22, 0.06, gold)
        render(os.path.join(out, "ui_button_%s.png" % st))


def build_panel(out):
    sc = scene(512, 768, 6.0)
    w, h = 3.92, 5.88
    stone = mat_iron("stone", base=(0.035, 0.032, 0.03))
    gold = mat_metal("gold", GOLD, rough=0.3)
    iron = mat_iron("iron", base=(0.045, 0.04, 0.036), ember=0.0)
    poly_mesh("back", chamfer_rect(w - 0.3, h - 0.3, 0.3), 0.05, z=0.0).data.materials.append(stone)
    frame_ring("frame", w, h, 0.42, 0.28, 0.22, 0.0, iron)
    frame_ring("trim", w - 0.4, h - 0.4, 0.3, 0.05, 0.26, 0.0, gold)
    frame_ring("trim2", w - 0.06, h - 0.06, 0.4, 0.035, 0.24, 0.0, gold)
    for sx in (-1, 1):
        for sy in (-1, 1):
            gem(sx * (w / 2 - 0.3), sy * (h / 2 - 0.3), 0.3, 0.13)
            frame_ring("gemring", 0.42, 0.42, 0.12, 0.06, 0.26, 0.0, gold).location = (sx * (w / 2 - 0.3), sy * (h / 2 - 0.3), 0)
    render(os.path.join(out, "ui_panel.png"))


def build_divider(out):
    sc = scene(640, 48, 6.4)
    gold = mat_metal("gold", GOLD, rough=0.3)
    poly_mesh("bar", [(-3.0, 0), (-0.4, -0.06), (0.4, -0.06), (3.0, 0), (0.4, 0.06), (-0.4, 0.06)], 0.06,
              z=0.0).data.materials.append(gold)
    poly_mesh("dia", [(-0.3, 0), (0, -0.2), (0.3, 0), (0, 0.2)], 0.1, bevel=0.02, z=0.0).data.materials.append(gold)
    gem(0, 0, 0.14, 0.11)
    render(os.path.join(out, "ui_divider.png"))


BUILDERS = {"logo": build_logo, "buttons": build_buttons, "panel": build_panel, "divider": build_divider}


def main():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    out = a[0] if a else "assets/ui/title"
    os.makedirs(out, exist_ok=True)
    for n in (a[1:] or list(BUILDERS)):
        BUILDERS[n](out)


if __name__ == "__main__":
    main()
