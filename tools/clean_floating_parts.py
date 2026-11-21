"""Remove peças soltas que "flutuam" longe do corpo num personagem rigado (GLB do Tripo):
separa a malha em partes desconectadas e apaga as que ficam fora da largura do corpo (eixo lateral),
mantendo esqueleto, pesos e animações. Também apaga malhas auxiliares sem material (ex.: uma esfera solta).

Uso: python3 tools/clean_floating_parts.py entrada.glb saida.glb [meia_largura_m=0.7]
Feito para o Cavaleiro (assets/models/rigged/hero_paladin.glb): a reconstrução por 4 vistas deixou dois
antebraços com glaive flutuando ao lado do corpo (presos aos ossos dos braços).
"""
import sys

import bpy  # noqa: I001
import bmesh


def main():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    src, dst = a[0], a[1]
    half = float(a[2]) if len(a) > 2 else 0.7
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in meshes:
        if not o.data.materials:
            print("apagando malha auxiliar sem material:", o.name)
            bpy.data.objects.remove(o, do_unlink=True)
    for o in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.verts.ensure_lookup_table()
        # Eixo lateral: o de maior extensão horizontal das peças (o corpo é mais estreito que a distância delas).
        seen, comps = set(), []
        for v in bm.verts:
            if v.index in seen:
                continue
            stack, ids = [v], []
            seen.add(v.index)
            while stack:
                x = stack.pop()
                ids.append(x)
                for e in x.link_edges:
                    y = e.other_vert(x)
                    if y.index not in seen:
                        seen.add(y.index)
                        stack.append(y)
            comps.append(ids)
        kill = []
        for ids in comps:
            cy = sum(v.co.y for v in ids) / len(ids)
            cx = sum(v.co.x for v in ids) / len(ids)
            if abs(cy) > half or abs(cx) > half:
                kill.extend(ids)
        n_parts = sum(1 for ids in comps if any(v in kill for v in ids[:1]))
        print(f"{o.name}: {len(comps)} partes, apagando {n_parts} partes ({len(kill)} vértices de {len(bm.verts)})")
        bmesh.ops.delete(bm, geom=list(set(kill)), context="VERTS")
        bm.to_mesh(o.data)
        bm.free()
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_yup=True, export_skins=True,
                              export_animations=True, export_animation_mode="ACTIONS", export_image_format="AUTO")
    print("salvo:", dst)


if __name__ == "__main__":
    main()
