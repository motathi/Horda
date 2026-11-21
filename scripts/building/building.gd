class_name Building
extends Structure
## Construção posicionada pelo jogador. Reaproveita Structure (vida, dano,
## destruição, reparo) e acrescenta níveis, torre automática e armadilha.

const DEFS_DIR := "res://data/buildings/"
const BLENDER_DIR := "res://assets/models/blender/"

var def: BuildingDef
var level: int = 1
## Especialização da torre a partir do nível 4 ("a" ou "b"; "" = nenhuma).
var branch: String = ""
var _cooldown: float = 0.0
var _trap_t: float = 0.0
var _rng := RandomNumberGenerator.new()

static func load_def(id: StringName) -> BuildingDef:
	return load(DEFS_DIR + String(id) + ".tres") as BuildingDef

static func all_defs() -> Array[BuildingDef]:
	var out: Array[BuildingDef] = []
	for id in [&"barricade", &"stone_wall", &"iron_wall", &"spikes", &"brazier", &"archer_tower", &"ballista", &"cannon", &"tesla", &"barracks"]:
		out.append(load_def(id))
	return out

func setup(d: BuildingDef, lvl: int = 1) -> void:
	def = d
	level = lvl
	kind = Kind.WALL_WOOD

func _ready() -> void:
	super._ready()
	add_to_group("buildings")
	_rng.randomize()
	_cooldown = _rng.randf() * 0.5

# --- Ganchos de Structure ---------------------------------------------------------

func _max_hp() -> float:
	var tech := 1.0 + (Tech.bonus("wall_hp_pct") if def.category == BuildingDef.Category.WALL else 0.0)
	return def.max_health * (1.0 + 0.5 * (level - 1)) * _eng_hp() * tech

## Bônus de Engenharia do herói (atributo).
static func _eng_hp() -> float:
	var h := GameManager.hero as Hero
	return h.building_hp_mult() if is_instance_valid(h) and h.attr_cfg else 1.0

static func _eng_dmg() -> float:
	var h := GameManager.hero as Hero
	return h.building_damage_mult() if is_instance_valid(h) and h.attr_cfg else 1.0


func _armor() -> float:
	return def.armor + (level - 1)

func _layer() -> int:
	# Armadilhas não bloqueiam a passagem (só podem ser selecionadas).
	return Layers.INTERACTABLES if def.category == BuildingDef.Category.TRAP else Layers.STRUCTURES

func _bar_height() -> float:
	return def.height + 0.7

func display_name() -> String:
	var t := TowerPaths.tier(def.id, branch, level)
	return "%s (nv. %d)" % [t.get("name", def.display_name), level]

# --- Árvore de evolução (TowerPaths) ----------------------------------------------
var _m: Dictionary = {}
var _shots: int = 0

func _refresh_mods() -> void:
	_m = TowerPaths.mods(def.id, branch, level) if def else {}

func mod(key: String, default: Variant = 1.0) -> Variant:
	return _m.get(key, default)

## Nível usado no crescimento linear (as especializações multiplicam sobre o nível 3).
func _lin() -> int:
	return mini(level, 3)

## Texto do card com os valores reais (nível, especialização e pesquisas).
func info_text() -> String:
	var rate := def.attacks_per_second * (1.0 + 0.15 * (_lin() - 1)) * float(mod("rate"))
	var t := "Vida %d • Dano %d\nAlcance %d m • %.1f tiros/s" % [int(health.max_health), int(tower_damage()), int(base_tower_range()), rate]
	var tier := TowerPaths.tier(def.id, branch, level)
	if not tier.is_empty():
		t += "\n" + String(tier["desc"])
	elif needs_branch():
		t += "\nNível 3: escolha uma especialização abaixo."
	else:
		match def.tower_kind:
			BuildingDef.TowerKind.PIERCE: t += "\nAtravessa a fila inteira"
			BuildingDef.TowerKind.SPLASH: t += "\nExplosão de %.1f m" % (def.splash_radius * (1.0 + 0.1 * (_lin() - 1)))
			BuildingDef.TowerKind.CHAIN: t += "\nRaio salta em %d alvos" % (def.chain_count + _lin() - 1)
		t += "\nNível 3 abre duas especializações."
	return t

func has_paths() -> bool:
	return def != null and TowerPaths.has_paths(def.id)

## Nível 3 sem especialização: o jogador precisa escolher o caminho.
func needs_branch() -> bool:
	return has_paths() and level == 3 and branch == "" and not health.dead

## "" se pode especializar agora; senão o motivo.
func branch_block_reason() -> String:
	if TimeManager.wave() < TowerPaths.unlock_wave(4):
		return "Especialização libera na horda %d" % TowerPaths.unlock_wave(4)
	if health.dead:
		return "Repare antes"
	var c := TowerPaths.cost(def, 4)
	if not ResourceManager.can_afford(c):
		return "Faltam: " + ResourceManager.cost_to_string(c)
	return ""

func choose_branch(br: String) -> String:
	if Coop.is_client():
		Coop.request("tower_branch", [String(name), br])
		return "Pedido enviado ao anfitrião."
	if not needs_branch():
		return "Escolha indisponível."
	var why := branch_block_reason()
	if why != "":
		return why
	ResourceManager.spend(TowerPaths.cost(def, 4))
	branch = br
	_level_up_to(4)
	return "%s: %s!" % [def.display_name, TowerPaths.tier(def.id, br, 4).get("name", "")]

func _build() -> void:
	_refresh_mods()
	_visual = Node3D.new()
	add_child(_visual)
	_visual.add_child(Building.make_visual(def, level, branch))
	if def.category == BuildingDef.Category.TOWER and def.tower_kind == BuildingDef.TowerKind.LIGHT:
		add_to_group("reveal_lights")
		set_meta(&"reveal_radius", base_tower_range())
	_rubble = Node3D.new()
	_rubble.visible = false
	add_child(_rubble)
	half_extents = Vector3(def.footprint.x * 0.5, def.height * 0.5, def.footprint.y * 0.5)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(def.footprint.x, maxf(def.height, 0.5), def.footprint.y)
	col.shape = box
	col.position.y = box.size.y * 0.5
	add_child(col)
	_build_rubble()

# --- Visual (também usado pela prévia de posicionamento) --------------------------

static func make_visual(d: BuildingDef, lvl: int = 1, br: String = "") -> Node3D:
	var root := Node3D.new()
	var s := 1.0 + 0.06 * (lvl - 1)
	match d.id:
		&"stone_wall" when ResourceLoader.exists(BLENDER_DIR + "stone_wall.glb"):
			_blender_levels(root, "stone_wall", lvl)
		&"stone_wall":
			if ModelLibrary.has("wall"):
				root.add_child(ModelLibrary.instance_width("wall", d.footprint.x * 1.05))
			else:
				_box(root, Vector3(d.footprint.x, d.height, d.footprint.y), Vector3(0, d.height * 0.5, 0), MaterialLib.textured("rock", Color.WHITE, 0.6))
		&"ballista", &"cannon", &"tesla", &"archer_tower" when ResourceLoader.exists(BLENDER_DIR + String(d.id) + ".glb"):
			_blender_levels(root, String(d.id), lvl, br)
			_tier_extras(root, d.id, lvl, br)
			if d.id == &"tesla" and lvl < 4:
				var orb := MeshInstance3D.new()
				var sph := SphereMesh.new()
				sph.radius = 0.26
				sph.height = 0.52
				orb.mesh = sph
				orb.material_override = MaterialLib.flat(Color(0.4, 0.75, 1.0), 0.3, 3.0)
				orb.position.y = 5.42
				root.add_child(orb)
		&"ballista", &"cannon", &"tesla":
			if ModelLibrary.has(String(d.id)):
				root.add_child(ModelLibrary.instance_height(String(d.id), d.height))
			else:
				_box(root, Vector3(d.footprint.x, d.height * 0.5, d.footprint.y), Vector3(0, d.height * 0.25, 0), MaterialLib.textured("rock", Color.WHITE, 0.6))
				_box(root, Vector3(d.footprint.x * 0.5, d.height * 0.5, d.footprint.y * 0.5), Vector3(0, d.height * 0.75, 0), MaterialLib.textured("metal", Color(0.6, 0.6, 0.65), 1.0, true, 0.4))
			if d.id == &"tesla":
				var orb := MeshInstance3D.new()
				var sph := SphereMesh.new()
				sph.radius = 0.3
				sph.height = 0.6
				orb.mesh = sph
				orb.material_override = MaterialLib.flat(Color(0.4, 0.75, 1.0), 0.3, 3.0)
				orb.position.y = d.height + 0.2
				root.add_child(orb)
		&"barracks":
			if ModelLibrary.has("barracks"):
				root.add_child(ModelLibrary.instance_footprint("barracks", maxf(d.footprint.x, d.footprint.y) * 1.05))
			else:
				_box(root, Vector3(d.footprint.x, 2.6, d.footprint.y), Vector3(0, 1.3, 0), MaterialLib.textured("planks", Color.WHITE))
				_box(root, Vector3(d.footprint.x + 0.4, 0.5, d.footprint.y + 0.4), Vector3(0, 2.9, 0), MaterialLib.flat(Color(0.2, 0.35, 0.8)))
			var flag := _box(root, Vector3(0.05, 0.9, 1.2), Vector3(d.footprint.x * 0.5 - 0.2, 4.2, 0), MaterialLib.textured("cloth", Color(0.2, 0.35, 0.9), 1.0))
			flag.rotation_degrees.y = 90
		&"iron_wall" when ResourceLoader.exists(BLENDER_DIR + "iron_wall.glb"):
			_blender_levels(root, "iron_wall", lvl)
		&"iron_wall":
			if ModelLibrary.has("iron_wall"):
				# A malha gerada é comprida no eixo Z: gira 90° e ajusta a altura à do muro.
				var iw := ModelLibrary.instance_footprint("iron_wall", d.footprint.x * 1.05)
				iw.rotation.y = PI * 0.5
				iw.scale.y = d.height / ModelLibrary.size_of("iron_wall").y
				root.add_child(iw)
			else:
				_box(root, Vector3(d.footprint.x, d.height, d.footprint.y), Vector3(0, d.height * 0.5, 0), MaterialLib.textured("metal", Color(0.45, 0.45, 0.5), 1.0, true, 0.4))
		&"archer_tower":
			if ModelLibrary.has("tower"):
				root.add_child(ModelLibrary.instance_height("tower", d.height))
			else:
				_box(root, Vector3(d.footprint.x, d.height, d.footprint.y), Vector3(0, d.height * 0.5, 0), MaterialLib.textured("planks", Color.WHITE))
			var flag := _box(root, Vector3(0.05, 0.6, 0.9), Vector3(0.1, d.height + 0.8, 0.45), MaterialLib.textured("cloth", Color(0.2, 0.35, 0.9) if lvl < 3 else Color(1.0, 0.8, 0.3), 1.0))
			flag.rotation_degrees.y = 90
			_box(root, Vector3(0.06, 1.6, 0.06), Vector3(0, d.height + 0.4, 0), MaterialLib.textured("bark", Color.WHITE))
		&"brazier":
			_make_brazier(root, d)
		&"barricade" when ResourceLoader.exists(BLENDER_DIR + "barricade.glb"):
			_blender_levels(root, "barricade", lvl)
		&"barricade":
			var bark := MaterialLib.textured("bark", Color(0.95, 0.82, 0.68), 1.0)
			var n := int(d.footprint.x / 0.9)
			for i in n:
				var x := -d.footprint.x * 0.5 + (i + 0.5) * d.footprint.x / n
				for sgn: float in [-1.0, 1.0]:
					var lg := CylinderMesh.new()
					lg.top_radius = 0.0
					lg.bottom_radius = 0.13
					lg.height = 2.0
					lg.radial_segments = 6
					var m := MeshInstance3D.new()
					m.mesh = lg
					m.material_override = bark
					m.position = Vector3(x, 0.75, 0)
					m.rotation_degrees = Vector3(sgn * 38.0, 0, sgn * 12.0)
					root.add_child(m)
			var beam := CylinderMesh.new()
			beam.top_radius = 0.12
			beam.bottom_radius = 0.12
			beam.height = d.footprint.x
			var bm := MeshInstance3D.new()
			bm.mesh = beam
			bm.material_override = bark
			bm.position = Vector3(0, 0.7, 0)
			bm.rotation_degrees.z = 90
			root.add_child(bm)
		&"spikes" when ResourceLoader.exists(BLENDER_DIR + "spikes.glb"):
			_blender_levels(root, "spikes", lvl)
		&"spikes":
			_box(root, Vector3(d.footprint.x, 0.12, d.footprint.y), Vector3(0, 0.06, 0), MaterialLib.textured("planks", Color(0.8, 0.7, 0.6), 1.0))
			var iron := MaterialLib.textured("metal", Color(0.75, 0.75, 0.8), 1.0, true, 0.35)
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.09
			cone.height = 0.45
			cone.radial_segments = 5
			for gx in 4:
				for gz in 4:
					var m2 := MeshInstance3D.new()
					m2.mesh = cone
					m2.material_override = iron
					m2.position = Vector3(-0.75 + gx * 0.5, 0.33, -0.75 + gz * 0.5)
					root.add_child(m2)
	root.scale = Vector3.ONE * s
	return root

## Defesa modelada no Blender (tools/blender_defenses.py): os objetos Lv2/Lv3 aparecem
## a partir do nível 2/3 (chapas e sacos de areia, depois arame farpado etc.).
## Brilhos e fogo das especializações (o atlas do Blender não tem emissão): braseiros das Flechas
## Flamejantes, esfera e cristal da Bobina de Tempestade, emissor da antena do Pulso.
static func _tier_extras(root: Node3D, id: StringName, lvl: int, br: String) -> void:
	if lvl < 4:
		return
	var glow := func(r: float, pos: Vector3, color: Color, energy: float) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 12
		sm.rings = 6
		mi.mesh = sm
		mi.material_override = MaterialLib.flat(color, 0.3, energy)
		mi.position = pos
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		return mi
	match [id, br]:
		[&"archer_tower", "b"]:
			if lvl >= 5:
				for sx in [-1.0, 1.0]:
					var f := EffectsHub.make_fire_particles(0.8)
					f.position = Vector3(sx * 1.65, 5.05, 0.55)
					root.add_child(f)
					var l := OmniLight3D.new()
					l.light_color = Color(1.0, 0.55, 0.2)
					l.light_energy = 1.4
					l.omni_range = 4.0
					l.position = f.position + Vector3.UP * 0.4
					root.add_child(l)
		[&"tesla", "a"]:
			glow.call(0.2, Vector3(0, 6.55, 0), Color(0.45, 0.8, 1.0), 4.0)
			if lvl >= 5:
				# Cristal flutuante girando sobre o para-raios.
				var c := MeshInstance3D.new()
				var pm := PrismMesh.new()
				pm.size = Vector3(0.45, 0.8, 0.45)
				c.mesh = pm
				c.material_override = MaterialLib.flat(Color(0.55, 0.85, 1.0), 0.2, 5.0)
				c.position = Vector3(0, 8.0, 0)
				c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(c)
				var tw := c.create_tween().set_loops()
				tw.tween_property(c, "rotation:y", TAU, 3.0).from(0.0)
				var tw2 := c.create_tween().set_loops()
				tw2.tween_property(c, "position:y", 8.25, 1.2).set_trans(Tween.TRANS_SINE)
				tw2.tween_property(c, "position:y", 7.85, 1.2).set_trans(Tween.TRANS_SINE)
		[&"tesla", "b"]:
			glow.call(0.13, Vector3(0, 6.06, 0), Color(0.5, 0.9, 1.0), 4.5)
			if lvl >= 5:
				var l2 := OmniLight3D.new()
				l2.light_color = Color(0.45, 0.8, 1.0)
				l2.light_energy = 1.6
				l2.omni_range = 5.0
				l2.position = Vector3(0, 1.4, 0)
				root.add_child(l2)

## Peças por nível: "Lv1".."Lv3" aparecem até o nível; "Lv4a"/"Lv5b" só na especialização certa. A arma
## "Turret_a"/"Turret_b" (se existir) troca a "Turret" comum a partir do nível 4.
static func _blender_levels(root: Node3D, model: String, lvl: int, br: String = "") -> void:
	var inst := (load(BLENDER_DIR + model + ".glb") as PackedScene).instantiate() as Node3D
	root.add_child(inst)
	for n in inst.find_children("Lv*", "", true, false):
		var nm := String(n.name)
		var want := int(nm.substr(2, 1))
		var tag := nm.substr(3, 1) if nm.length() > 3 else ""
		(n as Node3D).visible = want <= lvl and (tag == "" or (tag == br and lvl >= 4))
	var special: Node3D = null
	if br != "" and lvl >= 4:
		special = inst.find_child("Turret_%s%d" % [br, lvl], true, false) as Node3D
		if special == null:
			special = inst.find_child("Turret_" + br, true, false) as Node3D
	for t in inst.find_children("Turret*", "", true, false):
		var tn := String(t.name)
		if tn == "Turret":
			(t as Node3D).visible = special == null
			if special:
				t.name = "TurretOff"  # a torre gira só a arma visível
		elif tn.begins_with("Turret_"):
			(t as Node3D).visible = t == special
			if t == special:
				t.name = "Turret"

## Braseiro: pedestal de pedra, cesto de ferro com fogo alto e luz quente forte.
static func _make_brazier(root: Node3D, d: BuildingDef) -> void:
	var rock := MaterialLib.textured("rock", Color(0.8, 0.78, 0.75), 0.6)
	var iron := MaterialLib.textured("metal", Color(0.35, 0.33, 0.32), 1.0, true, 0.5)
	var base := CylinderMesh.new()
	base.top_radius = 0.55
	base.bottom_radius = 0.75
	base.height = 0.5
	base.radial_segments = 8
	var m0 := MeshInstance3D.new()
	m0.mesh = base
	m0.material_override = rock
	m0.position.y = 0.25
	root.add_child(m0)
	var col := CylinderMesh.new()
	col.top_radius = 0.28
	col.bottom_radius = 0.38
	col.height = 1.2
	col.radial_segments = 8
	var m1 := MeshInstance3D.new()
	m1.mesh = col
	m1.material_override = rock
	m1.position.y = 1.1
	root.add_child(m1)
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.75
	bowl.bottom_radius = 0.35
	bowl.height = 0.45
	bowl.radial_segments = 10
	var m2 := MeshInstance3D.new()
	m2.mesh = bowl
	m2.material_override = iron
	m2.position.y = 1.9
	root.add_child(m2)
	for i in 4:
		var a := i * TAU / 4.0 + PI * 0.25
		var spike := _box(root, Vector3(0.08, 0.5, 0.08), Vector3(cos(a) * 0.72, 2.25, sin(a) * 0.72), iron)
		spike.rotation = Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35)
	var embers := CylinderMesh.new()
	embers.top_radius = 0.62
	embers.bottom_radius = 0.62
	embers.height = 0.1
	embers.radial_segments = 10
	var m3 := MeshInstance3D.new()
	m3.mesh = embers
	m3.material_override = MaterialLib.flat(Color(0.9, 0.22, 0.04), 0.9, 1.2)
	m3.position.y = 2.08
	root.add_child(m3)
	var fire := EffectsHub.make_fire_particles(1.6)
	fire.position.y = 2.15
	root.add_child(fire)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.28)
	light.light_energy = 4.0
	light.omni_range = d.tower_range + 3.0
	light.omni_attenuation = 0.8
	light.position.y = 3.2
	root.add_child(light)

static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = mat
	parent.add_child(m)
	return m

# --- Comportamento ----------------------------------------------------------------

func tower_damage() -> float:
	return def.tower_damage * (1.0 + 0.4 * (_lin() - 1)) * float(mod("dmg")) * _eng_dmg() * (1.0 + Tech.bonus("tower_damage_pct"))

func tower_range() -> float:
	return base_tower_range() * DayNightVisuals.range_mult()

## Alcance sem a névoa (o braseiro ilumina sempre o mesmo raio).
func base_tower_range() -> float:
	return (def.tower_range + 1.5 * (_lin() - 1)) * float(mod("range")) * (1.0 + Tech.bonus("tower_range_pct"))

func trap_damage() -> float:
	return def.trap_damage * (1.0 + 0.4 * (level - 1)) * _eng_dmg() * (1.0 + Tech.bonus("tower_damage_pct"))

## Arma giratória (objeto "Turret" dos modelos do Blender) mirando o inimigo mais próximo.
var _turret: Node3D
var _turret_yaw: float = 0.0
var _turret_want: float = 0.0
var _turret_scan: float = 0.0

func _update_turret(delta: float) -> void:
	if _turret == null or not is_instance_valid(_turret):
		_turret = _visual.find_child("Turret", true, false) as Node3D if _visual else null
		if _turret == null:
			return
		_turret_yaw = global_rotation.y
		_turret_want = _turret_yaw
	_turret_scan -= delta
	if _turret_scan <= 0.0:
		_turret_scan = 0.2
		var t := _find_target(tower_range())
		if t:
			var dir := t.global_position - global_position
			_turret_want = atan2(-dir.x, -dir.z)
	_turret_yaw = lerp_angle(_turret_yaw, _turret_want, clampf(delta * 6.0, 0.0, 1.0))
	var tr := _turret.global_transform
	tr.basis = Basis(Vector3.UP, _turret_yaw).scaled(tr.basis.get_scale())
	_turret.global_transform = tr

func _process(delta: float) -> void:
	if not health.dead and def and def.category == BuildingDef.Category.TOWER:
		_update_turret(delta)
	if health.dead or def == null or Coop.is_client():
		return  # no coop, torres e armadilhas só agem no anfitrião
	match def.category:
		BuildingDef.Category.TOWER:
			_process_tower(delta)
		BuildingDef.Category.TRAP:
			_process_trap(delta)

func _process_tower(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	if def.tower_kind == BuildingDef.TowerKind.LIGHT:
		_process_light()
		return
	var target := _find_target(tower_range())
	if target == null:
		_cooldown = 0.25
		return
	_cooldown = 1.0 / (def.attacks_per_second * (1.0 + 0.15 * (_lin() - 1)) * float(mod("rate")) * (1.0 + Tech.bonus("tower_speed_pct")))
	var from := global_position + Vector3(0, def.height * 0.85, 0)
	_shots += 1
	match def.tower_kind:
		BuildingDef.TowerKind.PIERCE:
			if float(mod("harpoon", 0.0)) > 0.0:
				_fire_harpoon(from, target)
			else:
				_fire_bolt(from, target)
		BuildingDef.TowerKind.SPLASH:
			_fire_cannon(from, target)
		BuildingDef.TowerKind.CHAIN:
			if float(mod("pulse", 0.0)) > 0.0:
				_fire_pulse(from)
			else:
				_fire_chain(from, target)
				var every := int(mod("storm", 0))
				if every > 0 and _shots % every == 0:
					_call_storm()
		_:
			_fire_arrows(from, target)

## Braseiro: zumbis comuns dentro da luz do fogo ficam mais lentos (medo do fogo).
func _process_light() -> void:
	_cooldown = 0.5
	var r := base_tower_range()
	for e in Enemy.all:
		if is_instance_valid(e) and not e.is_dead() and e.global_position.distance_to(global_position) <= r:
			e.apply_fear(0.7)

## Balista: virote em linha reta que fere todos os inimigos no caminho.
func _fire_bolt(from: Vector3, target: Enemy) -> void:
	var aim := target.global_position + Vector3.UP
	var dir := aim - from
	dir.y = 0.0
	dir = dir.normalized()
	var reach := tower_range() + 2.0
	var to := Vector3(from.x, 1.0, from.z) + dir * reach
	EffectsHub.spawn_bolt(from, to, def.projectile_speed)
	Coop.fx("bolt", from, to, def.projectile_speed)
	AudioManager.play_3d(&"bolt", from, -2.0)
	var origin := Vector2(global_position.x, global_position.z)
	var d2 := Vector2(dir.x, dir.z)
	var hits: Array[Enemy] = []
	for e in Enemy.all:
		if not is_instance_valid(e) or e.is_dead():
			continue
		var rel := Vector2(e.global_position.x, e.global_position.z) - origin
		var along := rel.dot(d2)
		if along < 0.0 or along > reach:
			continue
		if absf(rel.cross(d2)) <= def.splash_radius + float(mod("width", 0.0)) + e.get_radius():
			hits.append(e)
	var dmg := tower_damage()
	var push := float(mod("knockback", 0.0))
	get_tree().create_timer(0.12).timeout.connect(func() -> void:
		for e in hits:
			if is_instance_valid(e) and not e.is_dead():
				e.take_damage(DamageInfo.make(dmg, self))
				EffectsHub.spawn_debris(e.global_position + Vector3.UP, true)
				if push > 0.0 and not e.is_boss and not e.is_dead():
					var dest := e.global_position + dir * push
					e.create_tween().tween_property(e, "global_position", Vector3(dest.x, e.global_position.y, dest.z), 0.2).set_ease(Tween.EASE_OUT)
					e.stun(0.3))

## Canhão: bala em arco até a posição do alvo; explode em área e atordoa.
func _fire_cannon(from: Vector3, target: Enemy) -> void:
	var to := target.global_position
	to.y = 0.2
	var dur := clampf(from.distance_to(to) / maxf(1.0, def.projectile_speed), 0.4, 1.4)
	var dmg := tower_damage()
	var r := def.splash_radius * (1.0 + 0.1 * (_lin() - 1)) * float(mod("splash"))
	var stun_t := def.stun_time
	var pool_t := float(mod("fire_pool", 0.0))
	var cluster := int(mod("cluster", 0))
	AudioManager.play_3d(&"cannon", from, 0.0, 0.7)
	EffectsHub.spawn_debris(from, false)
	Coop.fx("lob", from, to, dur)
	EffectsHub.spawn_lob(from, to, dur, 4.0, func() -> void:
		EffectsHub.spawn_explosion(to, r, Color(1.0, 0.55, 0.15))
		AudioManager.play_3d(&"explosion", to, 0.0)
		for e: Enemy in Enemy.all.duplicate():
			if is_instance_valid(e) and not e.is_dead():
				var dd: Vector3 = e.global_position - to
				if Vector2(dd.x, dd.z).length() <= r + e.get_radius():
					e.take_damage(DamageInfo.make(dmg, self if is_instance_valid(self) else null))
					if stun_t > 0.0:
						e.stun(stun_t)
		if pool_t > 0.0:
			Building.fire_pool(to, r * 0.8, dmg * 0.35, pool_t, null)
		if cluster > 0:
			for k in cluster:
				var a := k * TAU / cluster + randf_range(-0.3, 0.3)
				var p2 := to + Vector3(cos(a), 0, sin(a)) * randf_range(1.8, 3.0)
				EffectsHub.spawn_lob(to + Vector3.UP * 0.5, p2, 0.35, 1.5, func() -> void:
					EffectsHub.spawn_explosion(p2, r * 0.55, Color(1.0, 0.7, 0.25))
					for e2: Enemy in Enemy.all.duplicate():
						if is_instance_valid(e2) and not e2.is_dead() and e2.global_position.distance_to(p2) <= r * 0.55 + e2.get_radius():
							e2.take_damage(DamageInfo.make(dmg * 0.45, null))))

## Chão em chamas (Bombarda Incendiária): fere quem pisa a cada 0,5 s.
static func fire_pool(center: Vector3, radius: float, dps: float, duration: float, src: Node) -> void:
	var hub := EffectsHub.instance()
	if hub == null:
		return
	var holder := Node3D.new()
	hub.add_child(holder)
	holder.global_position = center
	for k in 4:
		var f := EffectsHub.make_fire_particles(0.9)
		holder.add_child(f)
		var a := k * TAU / 4.0
		f.position = Vector3(cos(a), 0.2, sin(a)) * radius * (0.4 if k > 0 else 0.0)
	SkillFx.fire_ground(center, radius, duration)
	var left := [duration]
	var tick := func(self_ref: Callable) -> void:
		left[0] -= 0.5
		if left[0] <= 0.0 or not is_instance_valid(holder):
			if is_instance_valid(holder):
				holder.queue_free()
			return
		for e: Enemy in Enemy.all.duplicate():
			if is_instance_valid(e) and not e.is_dead() and e.global_position.distance_to(center) <= radius + e.get_radius():
				var info := DamageInfo.make(dps * 0.5, src if is_instance_valid(src) else null)
				info.type = DamageInfo.Type.FIRE
				e.take_damage(info)
		holder.get_tree().create_timer(0.5).timeout.connect(self_ref.bind(self_ref))
	holder.get_tree().create_timer(0.5).timeout.connect(tick.bind(tick))

## Torre elétrica: raio que salta para os inimigos mais próximos, atordoando.
func _fire_chain(from: Vector3, target: Enemy) -> void:
	var pts := PackedVector3Array([from])
	var hit := {}
	var cur := target
	var dmg := tower_damage()
	var n := def.chain_count + (_lin() - 1) + int(mod("chain_add", 0))
	var jump := float(mod("jump", 5.5))
	for i in n:
		if cur == null:
			break
		hit[cur] = true
		pts.append(cur.global_position + Vector3.UP * 1.1 * cur.def.model_scale)
		cur.take_damage(DamageInfo.make(dmg * pow(0.85, i), self))
		if def.stun_time > 0.0:
			cur.stun(def.stun_time)
		var nxt: Enemy = null
		var best := jump
		for e in Enemy.all:
			if not is_instance_valid(e) or e.is_dead() or hit.has(e) or not e.is_targetable():
				continue
			var dd := e.global_position.distance_to(cur.global_position)
			if dd < best:
				best = dd
				nxt = e
		cur = nxt
	EffectsHub.spawn_lightning(pts)
	for k in pts.size() - 1:
		Coop.fx("lightning", pts[k], pts[k + 1])
	AudioManager.play_3d(&"zap", from, -3.0)

## Arqueiros: crítico, abate (Olho da Morte), várias flechas (Saraivada) e fogo (Flechas Flamejantes).
func _fire_arrows(from: Vector3, target: Enemy) -> void:
	var targets: Array[Enemy] = [target]
	var n := int(mod("multi", 1))
	if n > 1:
		var r := tower_range()
		var others := Enemy.all.filter(func(e: Enemy) -> bool: return is_instance_valid(e) and e != target and e.is_targetable() and e.global_position.distance_to(global_position) <= r)
		others.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position))
		for e in others.slice(0, n - 1):
			targets.append(e)
	var crit_chance := float(mod("crit", 0.1))
	var crit_mult := float(mod("crit_mult", 1.8))
	var execute := float(mod("execute", 0.0))
	var burn := float(mod("burn", 0.0))
	for t in targets:
		var info := DamageInfo.make(tower_damage(), self, _rng.randf() < crit_chance)
		if info.is_crit:
			info.amount *= crit_mult
		if execute > 0.0 and _rng.randf() < execute:
			info.is_crit = true
			info.amount = t.health.current + 1.0 if not t.is_boss else info.amount * 3.0
			EffectsHub.float_text(t.global_position + Vector3.UP * 2.8, "Abate!" if not t.is_boss else "x3!", Color(1.0, 0.3, 0.25), 38)
		EffectsHub.spawn_arrow(from, t, info, def.projectile_speed * (1.6 if crit_mult > 2.0 else 1.0), burn > 0.0)
		Coop.fx("arrow", from, t.global_position + Vector3.UP)
		if burn > 0.0:
			var dps := info.amount * burn
			var tt := t
			get_tree().create_timer(0.25).timeout.connect(func() -> void: Building.ignite(tt, dps, 3.0, self))
	AudioManager.play_3d(&"arrow", from, -12.0 + (3.0 if n > 1 else 0.0), 1.35 if crit_mult < 2.0 else 0.85, 90)

## Fogo (Flechas Flamejantes): dano por segundo, chamas no corpo enquanto dura.
static func ignite(e: Enemy, dps: float, duration: float, src: Node) -> void:
	if not is_instance_valid(e) or e.is_dead():
		return
	var now := Time.get_ticks_msec()
	var had := e.has_meta(&"burn_until") and int(e.get_meta(&"burn_until")) > now
	e.set_meta(&"burn_until", now + int(duration * 1000.0))
	e.set_meta(&"burn_dps", maxf(dps, float(e.get_meta(&"burn_dps", 0.0))) if had else dps)
	if had:
		return
	var fire := EffectsHub.attach_fire(e)
	fire.position.y = 1.0 * (e.def.model_scale if e.def else 1.0)
	var tick := func(self_ref: Callable) -> void:
		if not is_instance_valid(e) or e.is_dead() or Time.get_ticks_msec() > int(e.get_meta(&"burn_until", 0)):
			if is_instance_valid(fire):
				fire.queue_free()
			if is_instance_valid(e) and e.has_meta(&"burn_until"):
				e.remove_meta(&"burn_until")
			return
		var info := DamageInfo.make(float(e.get_meta(&"burn_dps", 0.0)) * 0.5, src if is_instance_valid(src) else null)
		info.type = DamageInfo.Type.FIRE
		e.take_damage(info)
		e.get_tree().create_timer(0.5).timeout.connect(self_ref.bind(self_ref))
	e.get_tree().create_timer(0.5).timeout.connect(tick.bind(tick))

## Balista com arpão: prende o alvo, deixa lento e puxa os zumbis próximos para ele.
func _fire_harpoon(from: Vector3, target: Enemy) -> void:
	var to := target.global_position + Vector3.UP
	EffectsHub.spawn_bolt(from, to, def.projectile_speed * 1.3)
	Coop.fx("bolt", from, to, def.projectile_speed)
	AudioManager.play_3d(&"bolt", from, -2.0, 0.8)
	var dmg := tower_damage()
	var hold := float(mod("harpoon", 1.0))
	var slow := float(mod("slow", 0.0))
	var pull := int(mod("pull", 0))
	var src := self
	get_tree().create_timer(from.distance_to(to) / maxf(1.0, def.projectile_speed * 1.3)).timeout.connect(func() -> void:
		if not is_instance_valid(target) or target.is_dead():
			return
		target.take_damage(DamageInfo.make(dmg, src if is_instance_valid(src) else null))
		target.stun(hold)
		if slow > 0.0:
			target.apply_fear(slow + hold)
		if pull > 0:
			var center := target.global_position
			var near := Enemy.all.filter(func(e: Enemy) -> bool: return is_instance_valid(e) and e != target and not e.is_dead() and not e.is_boss and e.global_position.distance_to(center) < 7.0)
			near.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
			for e: Enemy in near.slice(0, pull):
				var dest := center + (e.global_position - center).normalized() * 1.1
				e.create_tween().tween_property(e, "global_position", Vector3(dest.x, e.global_position.y, dest.z), 0.25).set_ease(Tween.EASE_OUT)
				e.stun(hold * 0.6)
				EffectsHub.spawn_lightning(PackedVector3Array([center + Vector3.UP, e.global_position + Vector3.UP]))
		EffectsHub.spawn_debris(target.global_position + Vector3.UP, true))

## Tesla com pulso: choque em área em volta da torre.
func _fire_pulse(from: Vector3) -> void:
	var r := float(mod("pulse", 6.0))
	var dmg := tower_damage()
	var slow := float(mod("slow", 0.0))
	var stun_t := float(mod("pulse_stun", 0.0))
	for e: Enemy in Enemy.all.duplicate():
		if is_instance_valid(e) and not e.is_dead() and e.is_targetable() and e.global_position.distance_to(global_position) <= r + e.get_radius():
			e.take_damage(DamageInfo.make(dmg, self))
			if slow > 0.0:
				e.apply_fear(slow)
			if stun_t > 0.0:
				e.stun(stun_t)
	SkillFx.tower_pulse(global_position, r, from.y - global_position.y)
	Coop.fx("tpulse", global_position, Vector3(from.y - global_position.y, 0, 0), r)
	AudioManager.play_3d(&"zap", from, -1.0, 0.7)

## Senhor dos Raios: raios caem do céu em até 5 inimigos ao alcance.
func _call_storm() -> void:
	var r := tower_range()
	var cands := Enemy.all.filter(func(e: Enemy) -> bool: return is_instance_valid(e) and e.is_targetable() and e.global_position.distance_to(global_position) <= r)
	cands.shuffle()
	var dmg := tower_damage() * 1.5
	for e: Enemy in cands.slice(0, 5):
		var top := e.global_position + Vector3(randf_range(-1, 1), 14.0, randf_range(-1, 1))
		EffectsHub.spawn_lightning(PackedVector3Array([top, e.global_position + Vector3.UP * 0.5]))
		Coop.fx("lightning", top, e.global_position + Vector3.UP * 0.5)
		e.take_damage(DamageInfo.make(dmg, self, true))
		e.stun(0.4)
	AudioManager.play_3d(&"zap", global_position, 3.0, 0.6)

func _find_target(radius: float) -> Enemy:
	if String(mod("target", "")) == "strongest":
		var strong: Enemy = null
		for e in Enemy.all:
			if is_instance_valid(e) and not e.is_dead() and e.is_targetable() and e.global_position.distance_to(global_position) <= radius:
				if strong == null or e.health.current > strong.health.current:
					strong = e
		return strong
	var best: Enemy = null
	var best_d := radius
	for e in Enemy.all:
		if not is_instance_valid(e) or e.is_dead() or not e.is_targetable():
			continue
		var d := e.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

func _process_trap(delta: float) -> void:
	_trap_t -= delta
	if _trap_t > 0.0:
		return
	_trap_t = def.trap_interval
	var reach := maxf(def.footprint.x, def.footprint.y) * 0.6 * (1.0 + 0.06 * (level - 1))
	for e in Enemy.all:
		if not is_instance_valid(e) or e.is_dead():
			continue
		var d := e.global_position - global_position
		d.y = 0.0
		if d.length() <= reach + e.get_radius():
			e.take_damage(DamageInfo.make(trap_damage(), self))
			EffectsHub.spawn_debris(e.global_position + Vector3.UP * 0.4, true)
			var wear := DamageInfo.make(def.trap_wear, null)
			wear.type = DamageInfo.Type.TRUE
			health.take_damage(wear)
			if health.dead:
				return

# --- Melhorar / demolir -----------------------------------------------------------

func can_upgrade() -> bool:
	if health.dead:
		return false
	if level < def.max_level:
		return true
	# Especialização escolhida: nível 5 depois do 4 (a partir da horda TIER5_WAVE).
	return has_paths() and branch != "" and level == 4 and TimeManager.wave() >= TowerPaths.unlock_wave(5)

func max_level() -> int:
	return 5 if has_paths() else def.max_level

func next_upgrade_cost() -> Dictionary:
	if level >= 3 and has_paths():
		return TowerPaths.cost(def, level + 1)
	return def.upgrade_cost(level + 1)

func upgrade() -> String:
	if Coop.is_client():
		Coop.request("upgrade", [String(name)])
		return "Pedido de melhoria enviado ao anfitrião."
	if needs_branch():
		return "Escolha uma especialização."
	if not can_upgrade():
		if level == 4 and has_paths() and not health.dead:
			return "Nível 5 libera na horda %d." % TowerPaths.unlock_wave(5)
		return "Nível máximo." if level >= max_level() else "Repare antes de melhorar."
	var cost := next_upgrade_cost()
	if not ResourceManager.spend(cost):
		return "Recursos insuficientes: " + ResourceManager.cost_to_string(cost)
	_level_up_to(level + 1)
	return "%s: nível %d!" % [display_name().split(" (")[0], level]

func _level_up_to(lvl: int) -> void:
	var ratio := health.ratio()
	level = lvl
	_refresh_mods()
	health.max_health = _max_hp()
	health.armor = _armor()
	health.current = health.max_health * maxf(ratio, 0.5)
	health.changed.emit(health.current, health.max_health)
	for c in _visual.get_children():
		c.queue_free()
	_turret = null
	_visual.add_child(Building.make_visual(def, level, branch))
	if is_in_group("reveal_lights"):
		set_meta(&"reveal_radius", base_tower_range())
	EffectsHub.spawn_heal(global_position)
	if level >= 4:
		SkillFx.tower_upgrade(global_position, def.height)
	AudioManager.play_3d(&"upgrade", global_position)
	EventBus.building_changed.emit(self)
	Coop.building_changed(self, false)

## Coop (cliente): aplica o nível vindo do anfitrião (sem custo).
func apply_level(lvl: int, br: String = "") -> void:
	if lvl == level and br == branch:
		return
	level = lvl
	branch = br
	_refresh_mods()
	_turret = null
	health.max_health = _max_hp()
	health.armor = _armor()
	health.changed.emit(health.current, health.max_health)
	for c in _visual.get_children():
		c.queue_free()
	_visual.add_child(Building.make_visual(def, level, branch))
	if is_in_group("reveal_lights"):
		set_meta(&"reveal_radius", base_tower_range())
	EffectsHub.spawn_heal(global_position)
	AudioManager.play_3d(&"upgrade", global_position)

## Reparo: 40% do que foi investido, proporcional ao dano (destruída = 50%).
func repair_cost() -> Dictionary:
	var miss := missing_health() / maxf(1.0, health.max_health)
	if miss <= 0.002:
		return {}
	var c := {}
	var inv := invested()
	for id: StringName in inv:
		var n := ceili(int(inv[id]) * 0.4 * (maxf(miss, 0.5) if health.dead else miss))
		if n > 0:
			c[id] = n
	return c

## Total investido (construção + melhorias) — base do reembolso.
func invested() -> Dictionary:
	var total := def.cost.duplicate()
	for l in range(2, level + 1):
		var c := TowerPaths.cost(def, l) if l >= 4 else def.upgrade_cost(l)
		for id: StringName in c:
			total[id] = int(total.get(id, 0)) + int(c[id])
	return total

func demolish() -> Dictionary:
	if Coop.is_client():
		Coop.request("demolish", [String(name)])
		return {}
	var back := {}
	var inv := invested()
	var factor := def.refund * (health.ratio() if not health.dead else 0.25)
	for id: StringName in inv:
		var n := int(floor(int(inv[id]) * factor))
		if n > 0:
			back[id] = n
			ResourceManager.storage.add(id, n)
	EffectsHub.spawn_debris(global_position + Vector3.UP, false)
	AudioManager.play_3d(&"break", global_position)
	EventBus.building_changed.emit(self)
	Coop.building_changed(self, true)
	queue_free()
	return back

func to_save() -> Dictionary:
	return {"id": String(def.id), "pos": [global_position.x, global_position.z], "rot": rotation.y, "level": level, "branch": branch, "hp": health.current, "dead": health.dead}
