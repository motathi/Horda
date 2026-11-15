extends SceneTree
## Monta sobreviventes (NPCs da base) com os pacotes CC0 da Quaternius:
## cabeça do Universal Base Character + roupa do Modular Character Outfits + cabelo,
## tudo no mesmo Skeleton3D, com animações do Universal Animation Library.
##   godot --headless --script res://tools/bake_npcs.gd

const BASE := "res://assets/third_party/quaternius_base/"
const OUTFITS := "res://assets/third_party/quaternius_outfits/"
const ANIMS := "res://assets/third_party/quaternius_anims/UAL1_Standard.glb"
const OUT := "res://assets/models/rigged/"
# Ossos cuja malha do corpo base é mantida (o resto fica coberto pela roupa).
const HEAD_BONES: Array[String] = ["head", "neck_01", "neck_02", "neck_03"]

# id -> [corpo base, roupa, cabelos...]
const JOBS := {
	"npc_peasant_m": ["Superhero_Male_FullBody", "Male_Peasant", "Hair_SimpleParted", "Hair_Beard", "Eyebrows_Regular"],
	"npc_peasant_f": ["Superhero_Female_FullBody", "Female_Peasant", "Hair_Buns", "Eyebrows_Female"],
	"npc_ranger_m": ["Superhero_Male_FullBody", "Male_Ranger", "Hair_Beard", "Eyebrows_Regular"],
	"npc_ranger_f": ["Superhero_Female_FullBody", "Female_Ranger", "Hair_Long", "Eyebrows_Female"],
}
# Cor do cabelo (as texturas de cabelo são em tons de cinza, feitas para tingir).
const HAIR := {"npc_peasant_m": Color(0.36, 0.22, 0.12), "npc_peasant_f": Color(0.62, 0.3, 0.14),
	"npc_ranger_m": Color(0.12, 0.09, 0.07), "npc_ranger_f": Color(0.85, 0.7, 0.42)}
const MAP := {
	"idle": "Idle", "walk": "Walk", "run": "Jog_Fwd", "hurt": "Death01", "work": "Fixing_Kneeling",
	"talk": "Idle_Talking", "torch": "Idle_Torch", "sit": "Sitting_Idle", "interact": "Interact", "slash": "Sword_Attack",
}

func _init() -> void:
	var lib_src := (load(ANIMS) as PackedScene).instantiate()
	var src_ap := lib_src.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	# Biblioteca de animações compartilhada por todos os sobreviventes.
	var shared := AnimationLibrary.new()
	for key: String in MAP:
		if not src_ap.has_animation(MAP[key]):
			push_warning("animação ausente: " + MAP[key])
			continue
		var a0 := src_ap.get_animation(MAP[key]).duplicate(true) as Animation
		a0.loop_mode = Animation.LOOP_NONE if key in ["hurt", "slash", "interact"] else Animation.LOOP_LINEAR
		shared.add_animation(key, a0)
	ResourceSaver.save(shared, OUT + "npc_anims.res")
	shared = load(OUT + "npc_anims.res") as AnimationLibrary
	for id: String in JOBS:
		var job: Array = JOBS[id]
		var root := Node3D.new()
		root.name = id
		var body := (load(BASE + job[0] + ".gltf") as PackedScene).instantiate() as Node3D
		body.rotation.y = PI * 0.5  # frente em +X, como os demais modelos riggados
		root.add_child(body)
		var sk := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", false, false):
			if mi.name.begins_with("SuperHero") or mi.name.begins_with("Superhero"):
				mi.mesh = _keep_bones(mi, sk, HEAD_BONES)
		for part: String in job.slice(1):
			var path := (OUTFITS if ResourceLoader.exists(OUTFITS + part + ".gltf") else BASE) + part + ".gltf"
			var scene := (load(path) as PackedScene).instantiate()
			for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
				mi.get_parent().remove_child(mi)
				sk.add_child(mi)
				mi.skeleton = NodePath("..")
				if part.begins_with("Hair") or part.begins_with("Eyebrows"):
					_tint(mi, HAIR[id])
			scene.free()
		var ap := AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		body.add_child(ap)
		ap.add_animation_library("", shared)
		_own(root, root)
		var ps := PackedScene.new()
		ps.pack(root)
		print(id, " -> ", OUT + id + ".scn (", error_string(ResourceSaver.save(ps, OUT + id + ".scn")), ")")
		root.free()
	lib_src.free()
	quit()

## Copia da malha só com os triângulos dominados pelos ossos indicados (cabeça/pescoço).
func _keep_bones(mi: MeshInstance3D, sk: Skeleton3D, bones: Array[String]) -> ArrayMesh:
	var src := mi.mesh as ArrayMesh
	var skin := mi.skin
	var keep_idx := {}
	for i in skin.get_bind_count():
		var bn := String(skin.get_bind_name(i))
		if bn == "" and skin.get_bind_bone(i) >= 0:
			bn = sk.get_bone_name(skin.get_bind_bone(i))
		if bn in bones:
			keep_idx[i] = true
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var bw: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var ww: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bw.size() / maxi(1, (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		var new_idx := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var ok := true
			for k in 3:
				var v := idx[t + k]
				var best := 0
				for j in range(1, per):
					if ww[v * per + j] > ww[v * per + best]:
						best = j
				if not keep_idx.has(bw[v * per + best]):
					ok = false
					break
			if ok:
				new_idx.append_array([idx[t], idx[t + 1], idx[t + 2]])
		if new_idx.is_empty():
			continue
		arr[Mesh.ARRAY_INDEX] = new_idx
		for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arr[c] = null
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(s))
	return out

func _tint(mi: MeshInstance3D, c: Color) -> void:
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if m is BaseMaterial3D:
			var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
			d.albedo_color = c
			mi.set_surface_override_material(s, d)

func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.scene_file_path = ""
		c.owner = owner_node
		_own(c, owner_node)
