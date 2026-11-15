extends SceneTree
## Monta personagens KayKit (CC0) com armas e animações num único .scn compatível com
## CharacterModel._build_rigged (animações idle/walk/run/slash/hurt; frente em +X).
##   godot --headless --script res://tools/bake_kaykit.gd

const SK := "res://assets/third_party/kaykit_skeletons/"
const AN := "res://assets/third_party/kaykit_animations/"
const OUT := "res://assets/models/rigged/"

# id -> [personagem, arma mão direita, arma mão esquerda, animação de ataque]
const JOBS := {
	"skeleton_minion": ["Skeleton_Minion.glb", "Skeleton_Blade.gltf", "", "Melee_1H_Attack_Slice_Diagonal"],
	"skeleton_warrior": ["Skeleton_Warrior.glb", "Skeleton_Axe.gltf", "Skeleton_Shield_Small_A.gltf", "Melee_1H_Attack_Chop"],
	"skeleton_rogue": ["Skeleton_Rogue.glb", "Skeleton_Blade.gltf", "Skeleton_Blade.gltf", "Melee_Dualwield_Attack_Slice"],
	"skeleton_mage": ["Skeleton_Mage.glb", "Skeleton_Staff.gltf", "", "Ranged_Magic_Shoot"],
}
const MAP := {"idle": "Idle_A", "walk": "Walking_A", "run": "Running_A", "hurt": "Death_A"}

func _init() -> void:
	var src := {}
	for f in [SK + "Rig_Medium_General.glb", SK + "Rig_Medium_MovementBasic.glb", AN + "Rig_Medium_CombatMelee.glb", AN + "Rig_Medium_CombatRanged.glb"]:
		var n := (load(f) as PackedScene).instantiate()
		var ap := n.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for a in ap.get_animation_list():
			src[String(a)] = ap.get_animation(a)
		n.free()
	for id: String in JOBS:
		var job: Array = JOBS[id]
		var root := Node3D.new()
		root.name = id
		var ch := (load(SK + job[0]) as PackedScene).instantiate() as Node3D
		ch.rotation.y = PI * 0.5  # KayKit olha para +Z; o jogo espera +X (como os modelos Tripo)
		root.add_child(ch)
		var sk := ch.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var extra: Array[Node] = []
		for side in [["handslot.r", job[1]], ["handslot.l", job[2]]]:
			if side[1] == "":
				continue
			var att := BoneAttachment3D.new()
			att.bone_name = side[0]
			att.name = "Hand_" + side[0].replace(".", "_")
			sk.add_child(att)
			var w := (load(SK + side[1]) as PackedScene).instantiate()
			w.name = "Weapon"
			att.add_child(w)
			extra.append(att)
			extra.append(w)
		var ap := AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		ch.add_child(ap)
		var lib := AnimationLibrary.new()
		var wanted: Dictionary = MAP.duplicate()
		wanted["slash"] = job[3]
		for key: String in wanted:
			var a := (src[wanted[key]] as Animation).duplicate(true) as Animation
			a.loop_mode = Animation.LOOP_LINEAR if key in ["idle", "walk", "run"] else Animation.LOOP_NONE
			lib.add_animation(key, a)
		ap.add_animation_library("", lib)
		_own(root, root)
		extra.append(ap)
		for e in extra:
			e.owner = root
		var ps := PackedScene.new()
		ps.pack(root)
		var err := ResourceSaver.save(ps, OUT + id + ".scn")
		print(id, " -> ", OUT + id + ".scn", " (", error_string(err), ")")
		root.free()
	quit()

## Torna tudo local (sem referência às cenas instanciadas) para salvar armas e animações juntas.
func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.scene_file_path = ""
		c.owner = owner_node
		_own(c, owner_node)
