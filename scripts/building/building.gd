class_name Building
extends Structure
## Construção posicionada pelo jogador. Reaproveita Structure (vida, dano,
## destruição, reparo) e acrescenta níveis, torre automática e armadilha.

const DEFS_DIR := "res://data/buildings/"

var def: BuildingDef
var level: int = 1
var _cooldown: float = 0.0
var _trap_t: float = 0.0
var _rng := RandomNumberGenerator.new()

static func load_def(id: StringName) -> BuildingDef:
	return load(DEFS_DIR + String(id) + ".tres") as BuildingDef

static func all_defs() -> Array[BuildingDef]:
	var out: Array[BuildingDef] = []
	for id in [&"barricade", &"stone_wall", &"iron_wall", &"spikes", &"archer_tower", &"ballista", &"cannon", &"tesla"]:
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
	return "%s (nv. %d)" % [def.display_name, level]

func _build() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_visual.add_child(Building.make_visual(def, level))
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

static func make_visual(d: BuildingDef, lvl: int = 1) -> Node3D:
	var root := Node3D.new()
	var s := 1.0 + 0.06 * (lvl - 1)
	match d.id:
		&"stone_wall":
			if ModelLibrary.has("wall"):
				root.add_child(ModelLibrary.instance_width("wall", d.footprint.x * 1.05))
			else:
				_box(root, Vector3(d.footprint.x, d.height, d.footprint.y), Vector3(0, d.height * 0.5, 0), MaterialLib.textured("rock", Color.WHITE, 0.6))
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
	return def.tower_damage * (1.0 + 0.4 * (level - 1)) * _eng_dmg() * (1.0 + Tech.bonus("tower_damage_pct"))

func tower_range() -> float:
	return (def.tower_range + 1.5 * (level - 1)) * (1.0 + Tech.bonus("tower_range_pct"))

func trap_damage() -> float:
	return def.trap_damage * (1.0 + 0.4 * (level - 1)) * _eng_dmg() * (1.0 + Tech.bonus("tower_damage_pct"))

func _process(delta: float) -> void:
	if health.dead or def == null:
		return
	match def.category:
		BuildingDef.Category.TOWER:
			_process_tower(delta)
		BuildingDef.Category.TRAP:
			_process_trap(delta)

func _process_tower(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var target := _find_target(tower_range())
	if target == null:
		_cooldown = 0.25
		return
	_cooldown = 1.0 / (def.attacks_per_second * (1.0 + 0.15 * (level - 1)) * (1.0 + Tech.bonus("tower_speed_pct")))
	var from := global_position + Vector3(0, def.height * 0.85, 0)
	match def.tower_kind:
		BuildingDef.TowerKind.PIERCE:
			_fire_bolt(from, target)
		BuildingDef.TowerKind.SPLASH:
			_fire_cannon(from, target)
		BuildingDef.TowerKind.CHAIN:
			_fire_chain(from, target)
		_:
			var info := DamageInfo.make(tower_damage(), self, _rng.randf() < 0.1)
			if info.is_crit:
				info.amount *= 1.8
			EffectsHub.spawn_arrow(from, target, info, def.projectile_speed)
			AudioManager.play_3d(&"arrow", from, -12.0, 1.35, 90)

## Balista: virote em linha reta que fere todos os inimigos no caminho.
func _fire_bolt(from: Vector3, target: Enemy) -> void:
	var aim := target.global_position + Vector3.UP
	var dir := aim - from
	dir.y = 0.0
	dir = dir.normalized()
	var reach := tower_range() + 2.0
	var to := Vector3(from.x, 1.0, from.z) + dir * reach
	EffectsHub.spawn_bolt(from, to, def.projectile_speed)
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
		if absf(rel.cross(d2)) <= def.splash_radius + e.get_radius():
			hits.append(e)
	var dmg := tower_damage()
	get_tree().create_timer(0.12).timeout.connect(func() -> void:
		for e in hits:
			if is_instance_valid(e) and not e.is_dead():
				e.take_damage(DamageInfo.make(dmg, self))
				EffectsHub.spawn_debris(e.global_position + Vector3.UP, true))

## Canhão: bala em arco até a posição do alvo; explode em área e atordoa.
func _fire_cannon(from: Vector3, target: Enemy) -> void:
	var to := target.global_position
	to.y = 0.2
	var dur := clampf(from.distance_to(to) / maxf(1.0, def.projectile_speed), 0.4, 1.4)
	var dmg := tower_damage()
	var r := def.splash_radius * (1.0 + 0.1 * (level - 1))
	var stun_t := def.stun_time
	AudioManager.play_3d(&"cannon", from, 0.0, 0.7)
	EffectsHub.spawn_debris(from, false)
	EffectsHub.spawn_lob(from, to, dur, 4.0, func() -> void:
		EffectsHub.spawn_explosion(to, r, Color(1.0, 0.55, 0.15))
		AudioManager.play_3d(&"explosion", to, 0.0)
		for e: Enemy in Enemy.all.duplicate():
			if is_instance_valid(e) and not e.is_dead():
				var dd: Vector3 = e.global_position - to
				if Vector2(dd.x, dd.z).length() <= r + e.get_radius():
					e.take_damage(DamageInfo.make(dmg, self if is_instance_valid(self) else null))
					if stun_t > 0.0:
						e.stun(stun_t))

## Torre elétrica: raio que salta para os inimigos mais próximos, atordoando.
func _fire_chain(from: Vector3, target: Enemy) -> void:
	var pts := PackedVector3Array([from])
	var hit := {}
	var cur := target
	var dmg := tower_damage()
	var n := def.chain_count + (level - 1)
	for i in n:
		if cur == null:
			break
		hit[cur] = true
		pts.append(cur.global_position + Vector3.UP * 1.1 * cur.def.model_scale)
		cur.take_damage(DamageInfo.make(dmg * pow(0.85, i), self))
		if def.stun_time > 0.0:
			cur.stun(def.stun_time)
		var nxt: Enemy = null
		var best := 5.5
		for e in Enemy.all:
			if not is_instance_valid(e) or e.is_dead() or hit.has(e):
				continue
			var dd := e.global_position.distance_to(cur.global_position)
			if dd < best:
				best = dd
				nxt = e
		cur = nxt
	EffectsHub.spawn_lightning(pts)
	AudioManager.play_3d(&"zap", from, -3.0)

func _find_target(radius: float) -> Enemy:
	var best: Enemy = null
	var best_d := radius
	for e in Enemy.all:
		if not is_instance_valid(e) or e.is_dead():
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
	return level < def.max_level and not health.dead

func next_upgrade_cost() -> Dictionary:
	return def.upgrade_cost(level + 1)

func upgrade() -> String:
	if not can_upgrade():
		return "Nível máximo." if level >= def.max_level else "Repare antes de melhorar."
	var cost := next_upgrade_cost()
	if not ResourceManager.spend(cost):
		return "Recursos insuficientes: " + ResourceManager.cost_to_string(cost)
	var ratio := health.ratio()
	level += 1
	health.max_health = _max_hp()
	health.armor = _armor()
	health.current = health.max_health * maxf(ratio, 0.5)
	health.changed.emit(health.current, health.max_health)
	for c in _visual.get_children():
		c.queue_free()
	_visual.add_child(Building.make_visual(def, level))
	EffectsHub.spawn_heal(global_position)
	AudioManager.play_3d(&"upgrade", global_position)
	EventBus.building_changed.emit(self)
	return "%s melhorada para o nível %d!" % [def.display_name, level]

## Total investido (construção + melhorias) — base do reembolso.
func invested() -> Dictionary:
	var total := def.cost.duplicate()
	for l in range(2, level + 1):
		var c := def.upgrade_cost(l)
		for id: StringName in c:
			total[id] = int(total.get(id, 0)) + int(c[id])
	return total

func demolish() -> Dictionary:
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
	queue_free()
	return back

func to_save() -> Dictionary:
	return {"id": String(def.id), "pos": [global_position.x, global_position.z], "rot": rotation.y, "level": level, "hp": health.current, "dead": health.dead}
