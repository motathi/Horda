"""Modela no Blender (bpy) as formas dos efeitos visuais das habilidades dos heróis e exporta um GLB:
  assets/models/blender/skill_fx.glb  (um objeto por forma; o jogo pega a malha pelo nome)

Formas (unidade = 1 m; o jogo escala pelo raio/alcance da habilidade):
  SlashSweep    rastro curvo de lâmina girando 300° em espiral (Golpe Giratório)
  GroundCrack   rachaduras radiais irregulares no chão (Giratório, Explosão Arcana, Armadilha)
  Shockwave     coroa de choque: faixa circular com a borda de cima em pontas (Grito de Guerra)
  LightPillar   coluna de luz aberta, mais estreita em cima (Grito de Guerra, Explosão Arcana)
  RuneCircle    círculo mágico: anéis, hexagrama e runas angulosas (Explosão Arcana, Grito)
  TargetCircle  mira da Chuva de Flechas: anéis, setas apontando para o centro e marcas
  Dome          cúpula de energia (Explosão Arcana)
  SpeedLines    linhas de velocidade em cruz, para trás do corpo (Investida)
  ChargeWedge   escudo de vento curvo à frente do corpo (Investida)
  ArrowGlow     flecha de energia: haste, ponta larga e penas (Tiro Múltiplo, Chuva de Flechas)
  ArrowTrail    rastro afinando atrás da flecha (cruzado, aparece de cima)
  Feather       pena (Águia)
  Shard         cristal alongado (Explosão Arcana, Armadilha)
  SparkStar     estrela de 8 pontas achatada (estalo da Armadilha, impacto da Águia)

UV: U = ao longo (0 = cauda/centro/base, 1 = cabeça/ponta/topo), V = de um lado ao outro (0..1); o shader
assets/effects/shaders/skill_fx.gdshader usa isso para o brilho no meio da faixa e o rastro que corre.
Uso:  python3 tools/blender_skill_fx.py assets/models/blender [--render pasta]   (módulo bpy do PyPI)
Convenção: frente em +Y e topo em +Z no Blender (vira -Z/+Y no Godot)."""
import math
import os
import random
import sys

import bpy  # noqa: I001
import bmesh
from mathutils import Vector

R = random.Random(42)


def args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    out = a[0] if a else "assets/models/blender"
    render = a[a.index("--render") + 1] if "--render" in a else ""
    os.makedirs(out, exist_ok=True)
    return out, render


def new_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    m = bpy.data.materials.get("fx") or bpy.data.materials.new("fx")
    me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


class Builder:
    """Acumula faixas (ribbons) com UV num único bmesh."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def quad(self, a, b, c, d, ua, ub, uc, ud):
        vs = [self.bm.verts.new(p) for p in (a, b, c, d)]
        f = self.bm.faces.new(vs)
        for loop, uv in zip(f.loops, (ua, ub, uc, ud)):
            loop[self.uv].uv = uv
        return f

    def ribbon(self, centers, sides, widths, u0=0.0, u1=1.0):
        """Faixa: centros[i] ± sides[i] * widths[i] / 2. U de u0 a u1 ao longo, V de 0 a 1 de lado a lado."""
        n = len(centers)
        for i in range(n - 1):
            c0, c1 = Vector(centers[i]), Vector(centers[i + 1])
            s0 = Vector(sides[i]).normalized() * widths[i] * 0.5
            s1 = Vector(sides[i + 1]).normalized() * widths[i + 1] * 0.5
            t0 = u0 + (u1 - u0) * i / (n - 1)
            t1 = u0 + (u1 - u0) * (i + 1) / (n - 1)
            self.quad(c0 - s0, c1 - s1, c1 + s1, c0 + s0, (t0, 0), (t1, 0), (t1, 1), (t0, 1))

    def done(self, name):
        return new_obj(name, self.bm)


def slash_sweep():
    b = Builder()
    n = 72
    cs, ss, ws = [], [], []
    for i in range(n + 1):
        t = i / n
        a = math.radians(-150 + 300 * t)
        r = 0.78 + 0.22 * t
        c = Vector((math.cos(a) * r, math.sin(a) * r, 0.15 + 0.35 * t))
        radial = Vector((math.cos(a), math.sin(a), 0))
        side = (radial * 0.75 + Vector((0, 0, 1)) * 0.65).normalized()
        w = 0.06 + 0.55 * (t ** 1.4) * (1.0 - t) ** 0.25
        cs.append(c)
        ss.append(side)
        ws.append(w)
    b.ribbon(cs, ss, ws)
    # Segundo fio, mais fino e um pouco por dentro (dá volume ao golpe).
    cs2 = [Vector((c.x * 0.86, c.y * 0.86, c.z + 0.1)) for c in cs]
    b.ribbon(cs2, ss, [w * 0.45 for w in ws])
    return b.done("SlashSweep")


def ground_crack():
    b = Builder()
    for k in range(16):
        a0 = k / 16 * math.tau + R.uniform(-0.12, 0.12)
        length = R.uniform(0.62, 1.0)
        pts, sides, ws = [], [], []
        a = a0
        steps = 9
        for i in range(steps + 1):
            t = i / steps
            r = 0.12 + (length - 0.12) * t
            a += R.uniform(-0.09, 0.09)
            p = Vector((math.cos(a) * r, math.sin(a) * r, 0.02))
            pts.append(p)
            sides.append(Vector((-math.sin(a), math.cos(a), 0)))
            ws.append(0.07 * (1.0 - t) ** 0.8 + 0.008)
            # Galhos curtos.
            if i in (3, 6) and R.random() < 0.7:
                ba = a + R.choice((-1, 1)) * R.uniform(0.35, 0.6)
                q0 = p
                q1 = p + Vector((math.cos(ba), math.sin(ba), 0)) * R.uniform(0.1, 0.2)
                sd = Vector((-math.sin(ba), math.cos(ba), 0))
                b.ribbon([q0, q1], [sd, sd], [0.035, 0.006], t, 1.0)
        b.ribbon(pts, sides, ws)
    return b.done("GroundCrack")


def shockwave():
    b = Builder()
    n = 64
    for i in range(n):
        a0, a1 = i / n * math.tau, (i + 1) / n * math.tau
        h0 = 0.55 + (0.45 if i % 2 == 0 else 0.0) * R.uniform(0.6, 1.0)
        h1 = 0.55 + (0.45 if (i + 1) % 2 == 0 else 0.0) * R.uniform(0.6, 1.0)
        p0 = Vector((math.cos(a0), math.sin(a0), 0))
        p1 = Vector((math.cos(a1), math.sin(a1), 0))
        out0, out1 = p0 * 1.12, p1 * 1.12  # abre para fora em cima (coroa)
        b.quad(p0, p1, out1 + Vector((0, 0, h1)), out0 + Vector((0, 0, h0)),
               (i / n, 0), ((i + 1) / n, 0), ((i + 1) / n, 1), (i / n, 1))
    return b.done("Shockwave")


def light_pillar():
    b = Builder()
    n = 28
    for i in range(n):
        a0, a1 = i / n * math.tau, (i + 1) / n * math.tau
        p0 = Vector((math.cos(a0), math.sin(a0), 0))
        p1 = Vector((math.cos(a1), math.sin(a1), 0))
        b.quad(p0, p1, p1 * 0.62 + Vector((0, 0, 1)), p0 * 0.62 + Vector((0, 0, 1)),
               (i / n, 0), ((i + 1) / n, 0), ((i + 1) / n, 1), (i / n, 1))
    return b.done("LightPillar")


def ring(b, r, w, n=96, z=0.01, u=1.0):
    cs, ss, ws = [], [], []
    for i in range(n + 1):
        a = i / n * math.tau
        cs.append(Vector((math.cos(a) * r, math.sin(a) * r, z)))
        ss.append(Vector((math.cos(a), math.sin(a), 0)))
        ws.append(w)
    b.ribbon(cs, ss, ws, u, u)


def stroke(b, p, q, w, z=0.012, u=1.0):
    p, q = Vector((p[0], p[1], z)), Vector((q[0], q[1], z))
    d = (q - p).normalized()
    side = Vector((-d.y, d.x, 0))
    b.ribbon([p, q], [side, side], [w, w], u, u)


def rune_circle():
    b = Builder()
    ring(b, 0.985, 0.03)
    ring(b, 0.885, 0.018)
    ring(b, 0.56, 0.022)
    ring(b, 0.2, 0.02, 48)
    # Hexagrama (dois triângulos) inscrito no anel do meio.
    for rot in (0.0, math.pi / 3):
        pts = [(math.cos(rot + k * math.tau / 3 + math.pi / 2) * 0.885, math.sin(rot + k * math.tau / 3 + math.pi / 2) * 0.885) for k in range(3)]
        for k in range(3):
            stroke(b, pts[k], pts[(k + 1) % 3], 0.022)
    # Runas angulosas entre os anéis de fora (12 grupos de 2-3 traços).
    for k in range(12):
        a = k / 12 * math.tau
        base = Vector((math.cos(a), math.sin(a)))
        tang = Vector((-math.sin(a), math.cos(a)))
        c = base * 0.935
        for _s in range(R.randint(2, 3)):
            p = c + tang * R.uniform(-0.05, 0.05) + base * R.uniform(-0.03, 0.03)
            q = p + (tang * R.uniform(-1, 1) + base * R.uniform(-1, 1)).normalized() * R.uniform(0.03, 0.055)
            stroke(b, p, q, 0.012)
    # Raios curtos no anel interno.
    for k in range(24):
        a = k / 24 * math.tau
        stroke(b, (math.cos(a) * 0.22, math.sin(a) * 0.22), (math.cos(a) * (0.3 if k % 2 else 0.38), math.sin(a) * (0.3 if k % 2 else 0.38)), 0.012)
    return b.done("RuneCircle")


def target_circle():
    b = Builder()
    ring(b, 0.99, 0.035)
    ring(b, 0.92, 0.012)
    ring(b, 0.42, 0.02, 64)
    for k in range(4):
        a = k / 4 * math.tau + math.pi / 4
        base = Vector((math.cos(a), math.sin(a)))
        tang = Vector((-math.sin(a), math.cos(a)))
        tip = base * 0.52
        for sgn in (-1, 1):
            stroke(b, tip, tip + base * 0.2 + tang * sgn * 0.14, 0.035)
        stroke(b, base * 0.6, base * 0.86, 0.02)
    for k in range(36):
        a = k / 36 * math.tau
        r1 = 0.8 if k % 3 == 0 else 0.86
        stroke(b, (math.cos(a) * r1, math.sin(a) * r1), (math.cos(a) * 0.9, math.sin(a) * 0.9), 0.01)
    return b.done("TargetCircle")


def dome():
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    segs, rings_n = 32, 12
    verts = []
    for j in range(rings_n + 1):
        el = j / rings_n * math.pi / 2
        row = []
        for i in range(segs + 1):
            az = i / segs * math.tau
            row.append(bm.verts.new((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el))))
        verts.append(row)
    for j in range(rings_n):
        for i in range(segs):
            f = bm.faces.new((verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]))
            for loop, (uu, vv) in zip(f.loops, ((i / segs, j / rings_n), ((i + 1) / segs, j / rings_n), ((i + 1) / segs, (j + 1) / rings_n), (i / segs, (j + 1) / rings_n))):
                loop[uv].uv = (uu, vv)
    return new_obj("Dome", bm)


def speed_lines():
    b = Builder()
    for _k in range(11):
        x = R.uniform(-0.65, 0.65)
        z = R.uniform(0.25, 1.9)
        length = R.uniform(0.6, 1.0)
        w = R.uniform(0.03, 0.07)
        cs = [Vector((x, -length * t, z + 0.05 * math.sin(t * 3))) for t in (0, 0.33, 0.66, 1.0)]
        for side in (Vector((1, 0, 0)), Vector((0, 0, 1))):
            # U = 1 na frente (cabeça), 0 atrás.
            b.ribbon(cs, [side] * 4, [w, w * 0.8, w * 0.5, w * 0.15], 1.0, 0.0)
    return b.done("SpeedLines")


def charge_wedge():
    b = Builder()
    n = 24
    for j in range(5):
        z0, z1 = 0.15 + j * 0.38, 0.15 + (j + 1) * 0.38
        for i in range(n):
            t0, t1 = i / n, (i + 1) / n
            def pt(t, z):
                x = (t - 0.5) * 1.9
                y = 0.75 - 0.9 * (x * x) - 0.08 * abs(z - 1.0)
                return Vector((x, y, z))
            # V ao longo da largura (meio brilhante), U ao longo da altura.
            b.quad(pt(t0, z0), pt(t1, z0), pt(t1, z1), pt(t0, z1),
                   (z0 / 2.05, t0), (z0 / 2.05, t1), (z1 / 2.05, t1), (z1 / 2.05, t0))
    return b.done("ChargeWedge")


def arrow_glow():
    b = Builder()
    # Haste (cruz de duas faixas) de y=-0.7 a 0.3, ponta larga em losango, penas atrás.
    for side in (Vector((1, 0, 0)), Vector((0, 0, 1))):
        b.ribbon([Vector((0, -0.7, 0)), Vector((0, 0.3, 0))], [side, side], [0.035, 0.035])
        b.ribbon([Vector((0, 0.25, 0)), Vector((0, 0.4, 0)), Vector((0, 0.55, 0))], [side] * 3, [0.05, 0.16, 0.0])
        b.ribbon([Vector((0, -0.72, 0)), Vector((0, -0.58, 0)), Vector((0, -0.45, 0))], [side] * 3, [0.2, 0.17, 0.04])
    return b.done("ArrowGlow")


def arrow_trail():
    b = Builder()
    n = 10
    cs = [Vector((0, -i / n * 1.0, 0)) for i in range(n + 1)]
    ws = [0.14 * (1 - i / n) ** 1.2 + 0.01 for i in range(n + 1)]
    for side in (Vector((1, 0, 0)), Vector((0, 0, 1))):
        b.ribbon(cs, [side] * (n + 1), ws, 1.0, 0.0)
    return b.done("ArrowTrail")


def feather():
    b = Builder()
    n = 10
    cs, ss, ws = [], [], []
    for i in range(n + 1):
        t = i / n
        cs.append(Vector((0.03 * math.sin(t * 2.5), t * 0.5 - 0.25, 0.04 * math.sin(t * math.pi))))
        ss.append(Vector((1, 0, 0.15)))
        ws.append(0.16 * math.sin(math.pi * min(1.0, t * 1.15)) ** 0.7 + 0.004)
    b.ribbon(cs, ss, ws)
    stroke(b, (0, -0.32), (0, 0.25), 0.01, 0.05)
    return b.done("Feather")


def shard():
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    top = bm.verts.new((0, 0, 0.5))
    bot = bm.verts.new((0, 0, -0.18))
    mid = [bm.verts.new((math.cos(a) * 0.1 * (1.0 + 0.3 * (k % 2)), math.sin(a) * 0.1, 0.05)) for k, a in enumerate([i * math.tau / 5 for i in range(5)])]
    for i in range(5):
        j = (i + 1) % 5
        for f, us in ((bm.faces.new((mid[i], mid[j], top)), ((0, 0), (0, 1), (1, 0.5))), (bm.faces.new((mid[j], mid[i], bot)), ((0.3, 1), (0.3, 0), (0, 0.5)))):
            for loop, u in zip(f.loops, us):
                loop[uv].uv = u
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_obj("Shard", bm)


def spark_star():
    b = Builder()
    for k in range(8):
        a = k / 8 * math.tau
        length = 1.0 if k % 2 == 0 else 0.6
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0))
        b.ribbon([d * 0.05 + Vector((0, 0, 0.02)), d * length * 0.45 + Vector((0, 0, 0.02)), d * length + Vector((0, 0, 0.02))], [side] * 3, [0.14, 0.08, 0.0])
    return b.done("SparkStar")


BUILDERS = [slash_sweep, ground_crack, shockwave, light_pillar, rune_circle, target_circle, dome, speed_lines,
            charge_wedge, arrow_glow, arrow_trail, feather, shard, spark_star]


def render_sheet(objs, path):
    """Folha de prévia (Cycles na CPU): cada forma emissiva lado a lado, vista de cima em perspectiva."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 16
    sc.cycles.device = "CPU"
    sc.render.resolution_x, sc.render.resolution_y = 1400, 700
    mat = bpy.data.materials.get("fx")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 3.0
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (1.0, 0.25, 0.02, 1)
    ramp.color_ramp.elements[1].color = (1.0, 0.95, 0.7, 1)
    nt.links.new(tc.outputs["UV"], sep.inputs[0])
    nt.links.new(sep.outputs["X"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    for i, o in enumerate(objs):
        o.location = ((i % 7) * 2.6 - 7.8, -(i // 7) * 2.8 + 1.4, 0)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    cam.location = (0, -9.5, 12)
    cam.rotation_euler = (math.radians(38), 0, 0)
    sc.camera = cam
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.02, 0.02, 0.03, 1)
    sc.world = w
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    out, rdir = args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objs = [f() for f in BUILDERS]
    path = os.path.join(out, "skill_fx.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
                              export_materials="NONE")
    print("exportado:", path, sum(len(o.data.polygons) for o in objs), "faces em", len(objs), "formas")
    if rdir:
        os.makedirs(rdir, exist_ok=True)
        render_sheet(objs, os.path.join(rdir, "skill_fx.png"))


if __name__ == "__main__":
    main()
