"""Retextura um modelo do jogo no Blender (Cycles) num estilo sombrio pós-apocalíptico:
pega a textura original e "assa" (bake) uma nova no mesmo mapa UV, com:
  - pedra dessaturada e escurecida (tons frios de cinza-marrom)
  - telhados/peças azuis -> metal enferrujado e chamuscado
  - brilhos azuis (janelas, cristais) -> brasa alaranjada fraca
  - fuligem nas reentrâncias (oclusão de ambiente), escorridos de sujeira verticais,
    manchas de queimado, cinza sobre as superfícies voltadas para cima e sangue seco na base
Uso:
  python3 tools/blender_retexture.py modelo.glb textura_original.jpg saida.jpg [tamanho]
  (com o módulo `bpy` do PyPI, ou: blender --background --python tools/blender_retexture.py -- ...)
O modelo precisa ter as mesmas UVs da malha do jogo (ex.: assets/models/raw/<nome>.glb
depois do tools/fix_glb.py; a textura do jogo é assets/models/textures/<nome>.jpg)."""
import sys

import bpy  # noqa: I001


def args() -> list:
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]


def node(nt, kind, loc=(0, 0), **props):
    n = nt.nodes.new(kind)
    n.location = loc
    for k, v in props.items():
        setattr(n, k, v)
    return n


def math_node(nt, op, a=None, b=None, loc=(0, 0), clamp=False):
    n = node(nt, "ShaderNodeMath", loc, operation=op, use_clamp=clamp)
    for i, v in enumerate((a, b)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = v
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def mix(nt, fac, a, b, blend="MIX", loc=(0, 0)):
    n = node(nt, "ShaderNodeMix", loc, data_type="RGBA", blend_type=blend)
    n.clamp_factor = True
    for sock, v in ((n.inputs[0], fac), (n.inputs[6], a), (n.inputs[7], b)):
        if isinstance(v, (int, float)):
            sock.default_value = v
        elif isinstance(v, tuple):
            sock.default_value = (*v, 1.0) if len(v) == 3 else v
        else:
            nt.links.new(v, sock)
    return n.outputs[2]


def ramp(nt, fac, stops, loc=(0, 0)):
    n = node(nt, "ShaderNodeValToRGB", loc)
    els = n.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], (*stops[0][1], 1.0)
    els[1].position, els[1].color = stops[-1][0], (*stops[-1][1], 1.0)
    for pos, col in stops[1:-1]:
        e = els.new(pos)
        e.color = (*col, 1.0)
    nt.links.new(fac, n.inputs[0])
    return n.outputs[0]


def noise(nt, vec, scale, detail=6.0, rough=0.6, loc=(0, 0)):
    n = node(nt, "ShaderNodeTexNoise", loc)
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    n.inputs["Roughness"].default_value = rough
    nt.links.new(vec, n.inputs["Vector"])
    return n.outputs["Fac"]


def build_material(src_path: str):
    m = bpy.data.materials.new("Retex")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = node(nt, "ShaderNodeOutputMaterial", (2200, 0))
    emit = node(nt, "ShaderNodeEmission", (2000, 0))
    nt.links.new(emit.outputs[0], out.inputs["Surface"])

    uv = node(nt, "ShaderNodeUVMap", (-1600, 300))
    img = node(nt, "ShaderNodeTexImage", (-1400, 300))
    img.image = bpy.data.images.load(src_path)
    img.interpolation = "Closest"
    nt.links.new(uv.outputs[0], img.inputs[0])
    col = img.outputs["Color"]
    tc = node(nt, "ShaderNodeTexCoord", (-1600, -300))
    gen = tc.outputs["Generated"]
    geo = node(nt, "ShaderNodeNewGeometry", (-1600, -600))
    sep_n = node(nt, "ShaderNodeSeparateXYZ", (-1400, -600))
    nt.links.new(geo.outputs["Normal"], sep_n.inputs[0])
    sep_g = node(nt, "ShaderNodeSeparateXYZ", (-1400, -300))
    nt.links.new(gen, sep_g.inputs[0])
    rgb = node(nt, "ShaderNodeSeparateColor", (-1200, 300))
    nt.links.new(col, rgb.inputs[0])
    r, g, b = rgb.outputs[0], rgb.outputs[1], rgb.outputs[2]

    # Máscaras a partir da textura original.
    rg_max = math_node(nt, "MAXIMUM", r, g)
    blue_mask = math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", b, rg_max), 4.0, clamp=True)
    lum = node(nt, "ShaderNodeRGBToBW", (-1200, 100))
    nt.links.new(col, lum.inputs[0])
    lum = lum.outputs[0]
    glow_mask = math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", math_node(nt, "MINIMUM", g, b), 0.55),
                          5.0, clamp=True)

    # 1) Pedra: dessaturada, escura e fria.
    hsv = node(nt, "ShaderNodeHueSaturation", (-900, 300))
    hsv.inputs["Saturation"].default_value = 0.45
    hsv.inputs["Value"].default_value = 0.72
    nt.links.new(col, hsv.inputs["Color"])
    # Puxa para um marrom-acinzentado sujo (madeira e pedra velhas), sem clarear os pretos.
    base = mix(nt, 0.3, hsv.outputs[0], (0.32, 0.24, 0.17), "MULTIPLY")

    # 2) Telhados azuis -> metal enferrujado/chamuscado (mantém o sombreado da textura).
    rust_n = noise(nt, gen, 14.0, 8.0, 0.65)
    rust_col = ramp(nt, rust_n, [(0.3, (0.07, 0.04, 0.025)), (0.47, (0.3, 0.09, 0.025)), (0.6, (0.48, 0.17, 0.04)),
                                 (0.74, (0.08, 0.055, 0.04))])
    shade = math_node(nt, "MULTIPLY", math_node(nt, "MAXIMUM", rg_max, b), 1.25, clamp=True)
    shade_rgb = node(nt, "ShaderNodeCombineColor", (-500, -100))
    for i in range(3):
        nt.links.new(shade, shade_rgb.inputs[i])
    rust_shaded = mix(nt, 1.0, rust_col, shade_rgb.outputs[0], "MULTIPLY")
    base = mix(nt, blue_mask, base, rust_shaded)

    # 3) Brilhos azuis -> brasa fraca.
    ember = mix(nt, math_node(nt, "MULTIPLY", lum, 2.0, clamp=True), (0.6, 0.12, 0.02), (1.0, 0.5, 0.12))
    base = mix(nt, glow_mask, base, ember)

    # 4) Fuligem nas reentrâncias (oclusão de ambiente).
    ao = node(nt, "ShaderNodeAmbientOcclusion", (-200, -400))
    ao.samples = 16
    ao.inputs["Distance"].default_value = 0.06
    ao_f = math_node(nt, "POWER", ao.outputs["AO"], 1.6)
    ao_dark = math_node(nt, "ADD", math_node(nt, "MULTIPLY", ao_f, 0.75), 0.25)
    ao_rgb = node(nt, "ShaderNodeCombineColor", (0, -400))
    for i in range(3):
        nt.links.new(ao_dark, ao_rgb.inputs[i])
    base = mix(nt, 1.0, base, ao_rgb.outputs[0], "MULTIPLY")

    # 5) Escorridos verticais de sujeira/umidade (ruído esticado no eixo Z).
    stretch = node(nt, "ShaderNodeVectorMath", (-1200, -200), operation="MULTIPLY")
    stretch.inputs[1].default_value = (9.0, 9.0, 0.7)
    nt.links.new(gen, stretch.inputs[0])
    streak = ramp(nt, noise(nt, stretch.outputs[0], 3.0, 4.0, 0.5), [(0.45, (1, 1, 1)), (0.7, (0.45, 0.42, 0.38))])
    base = mix(nt, 0.85, base, streak, "MULTIPLY")

    # 6) Manchas de queimado (grandes) e fuligem geral.
    burn_n = noise(nt, gen, 2.2, 5.0, 0.7)
    burn = ramp(nt, burn_n, [(0.52, (1, 1, 1)), (0.66, (0.35, 0.3, 0.27)), (0.78, (0.05, 0.04, 0.035))])
    base = mix(nt, 1.0, base, burn, "MULTIPLY")
    grime = ramp(nt, noise(nt, gen, 30.0, 8.0, 0.75), [(0.35, (0.55, 0.52, 0.48)), (0.65, (1, 1, 1))])
    base = mix(nt, 0.6, base, grime, "MULTIPLY")

    # 7) Cinza sobre superfícies voltadas para cima.
    up = math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", sep_n.outputs[2], 0.55), 3.0, clamp=True)
    ash_n = noise(nt, gen, 18.0, 6.0, 0.6)
    ash_f = math_node(nt, "MULTIPLY", up, math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", ash_n, 0.35), 2.2,
                                                      clamp=True))
    base = mix(nt, math_node(nt, "MULTIPLY", ash_f, 0.55), base, (0.3, 0.29, 0.27))

    # 8) Sangue seco respingado na parte de baixo das paredes.
    low = math_node(nt, "LESS_THAN", sep_g.outputs[2], 0.18)
    vor = node(nt, "ShaderNodeTexVoronoi", (-600, -800))
    vor.inputs["Scale"].default_value = 22.0
    nt.links.new(gen, vor.inputs["Vector"])
    splat = math_node(nt, "LESS_THAN", vor.outputs["Distance"], 0.12)
    blood_n = math_node(nt, "GREATER_THAN", noise(nt, gen, 5.0, 3.0, 0.5), 0.58)
    blood_f = math_node(nt, "MULTIPLY", math_node(nt, "MULTIPLY", low, splat), blood_n)
    base = mix(nt, math_node(nt, "MULTIPLY", blood_f, 0.8), base, (0.16, 0.02, 0.015))

    nt.links.new(base, emit.inputs["Color"])
    return m


def main() -> None:
    a = args()
    src_glb, src_tex, out_path = a[0], a[1], a[2]
    size = int(a[3]) if len(a) > 3 else 1024
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src_glb)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    mat = build_material(src_tex)
    target = bpy.data.images.new("RetexOut", size, size, alpha=False)
    for o in meshes:
        o.data.materials.clear()
        o.data.materials.append(mat)
    tex_node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex_node.image = target
    mat.node_tree.nodes.active = tex_node
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 16
    sc.render.bake.margin = 6
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.bake(type="EMIT", margin=6)
    target.filepath_raw = out_path
    target.file_format = "JPEG"
    sc.render.image_settings.quality = 92
    target.save()
    print("textura nova:", out_path)


if __name__ == "__main__":
    main()
