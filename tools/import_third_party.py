#!/usr/bin/env python3
"""Copia para assets/third_party/ somente os modelos escolhidos dos pacotes CC0 baixados
do itch.io (tools/itch_fetch.py), com os .bin e texturas que cada glTF referencia.
Texturas maiores que MAX_TEX são reduzidas (peso do build web).
Uso: python3 tools/import_third_party.py <pasta_com_pacotes_extraidos>"""
import json, os, shutil, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets/third_party")
MAX_TEX = 512

# pacote -> (pasta de origem relativa, autor, página, modelos)
PACKS = {
    "quaternius_nature": ("stylized-nature-megakit/glTF", "Quaternius", "https://quaternius.itch.io/stylized-nature-megakit", [
        "CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5",
        "Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5", "DeadTree_1", "DeadTree_2", "DeadTree_3",
        "Bush_Common", "Bush_Common_Flowers", "Fern_1", "Grass_Common_Tall", "Grass_Wispy_Tall",
        "Flower_3_Group", "Flower_4_Group", "Mushroom_Common", "Mushroom_Laetiporus",
        "Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3", "Plant_1_Big", "Plant_7_Big", "Clover_1",
        "Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3"]),
    "kaykit_halloween": ("halloween-bits/KayKit_HalloweenBits_1.0_FREE/Assets/gltf", "Kay Lousberg", "https://kaylousberg.itch.io/halloween-bits", [
        "grave_A", "grave_B", "gravestone", "gravemarker_A", "gravemarker_B", "crypt", "fence", "fence_broken",
        "fence_pillar", "coffin", "ribcage", "skull", "bone_A", "lantern_standing", "post_skull", "arch_gate",
        "shrine_candles", "tree_dead_large", "tree_dead_medium"]),
    "quaternius_props": ("fantasy-props-megakit/Exports/glTF", "Quaternius", "https://quaternius.itch.io/fantasy-props-megakit", [
        "Barrel", "Barrel_Apples", "Crate_Wooden", "Crate_Metal", "Cauldron", "Anvil", "Workbench",
        "Stall_Cart_Empty", "Stall_Empty", "Banner_1", "Banner_2", "Torch_Metal", "WeaponStand", "Chest_Wood",
        "Bucket_Wooden_1", "FarmCrate_Apple", "Dummy", "Rope_1"]),
    "quaternius_village": ("medieval-village-megakit/Medieval Village MegaKit[Standard]/glTF", "Quaternius", "https://quaternius.itch.io/medieval-village-megakit", [
        "Prop_Wagon", "Prop_WoodenFence_Single", "Prop_WoodenFence_Extension1", "Prop_Crate", "Prop_MetalFence_Ornament"]),
    "kaykit_skeletons": ("kaykit-skeletons/KayKit_Skeletons_1.1_FREE", "Kay Lousberg", "https://kaylousberg.itch.io/kaykit-skeletons", [
        "characters/gltf/Skeleton_Minion.glb", "characters/gltf/Skeleton_Warrior.glb", "characters/gltf/Skeleton_Rogue.glb",
        "characters/gltf/Skeleton_Mage.glb", "assets/gltf/Skeleton_Axe.gltf", "assets/gltf/Skeleton_Blade.gltf",
        "assets/gltf/Skeleton_Staff.gltf", "assets/gltf/Skeleton_Shield_Small_A.gltf", "assets/gltf/Skeleton_Crossbow.gltf",
        "Animations/gltf/Rig_Medium/Rig_Medium_General.glb", "Animations/gltf/Rig_Medium/Rig_Medium_MovementBasic.glb"]),
    "kaykit_animations": ("kaykit-character-animations/KayKit_Character_Animations_1.1/Animations/gltf/Rig_Medium", "Kay Lousberg", "https://kaylousberg.itch.io/kaykit-character-animations", [
        "Rig_Medium_CombatMelee.glb", "Rig_Medium_CombatRanged.glb"]),
    "kaykit_adventurers": ("kaykit-adventurers/KayKit_Adventurers_2.0_FREE", "Kay Lousberg", "https://kaylousberg.itch.io/kaykit-adventurers", [
        "Characters/gltf/Knight.glb", "Characters/gltf/Barbarian.glb", "Characters/gltf/Mage.glb", "Characters/gltf/Ranger.glb",
        "Characters/gltf/Rogue.glb", "Characters/gltf/Rogue_Hooded.glb", "Assets/gltf/sword_1handed.gltf", "Assets/gltf/axe_2handed.gltf",
        "Assets/gltf/shield_badge_color.gltf", "Assets/gltf/shield_round_barbarian.gltf", "Assets/gltf/staff.gltf",
        "Assets/gltf/dagger.gltf", "Assets/gltf/spellbook_open.gltf", "Assets/gltf/quiver.gltf", "Assets/gltf/smokebomb.gltf"]),
    "kaykit_dungeon": ("kaykit-dungeon-pack/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf", "Kay Lousberg", "https://kaylousberg.itch.io/kaykit-dungeon-pack", [
        "wall_broken", "wall_cracked", "wall_half", "wall_arched", "wall_corner", "pillar", "pillar_decorated", "column",
        "rubble_large", "rubble_half", "barrier", "barrier_column", "torch_lit", "torch_mounted", "barrel_large",
        "barrel_small_stack", "keg", "crates_stacked", "box_stacked", "chest", "chest_gold", "banner_red",
        "banner_patternA_red", "banner_shield_red", "sword_shield", "sword_shield_broken", "table_long_broken", "stool",
        "trunk_large_A", "stairs"]),
    "quaternius_outfits": ("modular-character-outfits-fantasy/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits", "Quaternius", "https://quaternius.itch.io/modular-character-outfits-fantasy", [
        "Male_Peasant", "Female_Peasant", "Male_Ranger", "Female_Ranger"]),
    "quaternius_base": ("universal-base-characters/Universal Base Characters[Standard]", "Quaternius", "https://quaternius.itch.io/universal-base-characters", [
        "Base Characters/Godot - UE/Superhero_Male_FullBody", "Base Characters/Godot - UE/Superhero_Female_FullBody",
        "Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_SimpleParted", "Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_Beard",
        "Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_Buns", "Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_Long",
        "Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Eyebrows_Regular", "Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Eyebrows_Female"]),
    "quaternius_anims": ("universal-animation-library/Universal Animation Library[Standard]/Unreal-Godot", "Quaternius", "https://quaternius.itch.io/universal-animation-library", [
        "UAL1_Standard.glb"]),
}

def copy_model(src_dir, rel, dst_dir):
    src = os.path.join(src_dir, rel if "." in os.path.basename(rel) else rel + ".gltf")
    os.makedirs(dst_dir, exist_ok=True)
    dst = os.path.join(dst_dir, os.path.basename(src))
    shutil.copy2(src, dst)
    if not src.endswith(".gltf"):
        return 1
    n = 1
    data = json.load(open(src))
    for item in data.get("buffers", []) + data.get("images", []):
        uri = item.get("uri", "")
        if not uri or uri.startswith("data:"):
            continue
        uri = uri.replace("%20", " ")
        s = os.path.join(os.path.dirname(src), uri)
        d = os.path.join(dst_dir, uri)
        if os.path.exists(d) or not os.path.exists(s):
            continue
        os.makedirs(os.path.dirname(d), exist_ok=True)
        if uri.lower().endswith(".png"):
            im = Image.open(s)
            if max(im.size) > MAX_TEX:
                im.thumbnail((MAX_TEX, MAX_TEX), Image.LANCZOS)
            im.save(d, optimize=True)
        else:
            shutil.copy2(s, d)
        n += 1
    return n

def license_file(src_root):
    for dp, _, fs in os.walk(src_root):
        for f in fs:
            if f.lower().startswith("license"):
                return os.path.join(dp, f)
    return None

def main(base):
    credits = ["# Créditos de terceiros", "",
               "Modelos baixados do itch.io, todos sob **CC0 1.0** (domínio público; crédito opcional, mas registrado aqui).",
               "Baixados com `tools/itch_fetch.py` e copiados com `tools/import_third_party.py`.", ""]
    for pack, (rel, author, url, models) in PACKS.items():
        src_dir = os.path.join(base, rel)
        dst_dir = os.path.join(OUT, pack)
        files = sum(copy_model(src_dir, m, dst_dir) for m in models)
        lic = license_file(os.path.join(base, rel.split("/")[0]))
        if lic:
            shutil.copy2(lic, os.path.join(dst_dir, "LICENSE.txt"))
        credits.append(f"- **{pack}** — {author}, {url} — {len(models)} modelos ({files} arquivos), CC0 1.0")
        print(f"{pack}: {len(models)} modelos, {files} arquivos", flush=True)
    open(os.path.join(OUT, "CREDITS.md"), "w").write("\n".join(credits) + "\n")

if __name__ == "__main__":
    main(sys.argv[1])
