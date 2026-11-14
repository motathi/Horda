class_name Structure
extends StaticBody3D
## Construção destrutível e reparável (muro, portão, núcleo da base).
## Zumbis que esbarram nela passam a atacá-la.

enum Kind { WALL_WOOD, GATE, CORE }

const KIND_NAMES := {Kind.WALL_WOOD: "Paliçada de Madeira", Kind.GATE: "Portão", Kind.CORE: "Núcleo da Base"}
const KIND_HP := {Kind.WALL_WOOD: 450.0, Kind.GATE: 600.0, Kind.CORE: 1500.0}
const KIND_ARMOR := {Kind.WALL_WOOD: 2.0, Kind.GATE: 3.0, Kind.CORE: 4.0}

@export var kind: Kind = Kind.WALL_WOOD
@export var length: float = 4.0

var structure_id: String = ""
var health: HealthComponent
var half_extents: Vector3 = Vector3(2, 1.25, 0.4)
var _visual: Node3D
var _rubble: Node3D
var _gate_doors: Array[Node3D] = []
var _gate_open: float = 0.0

func _ready() -> void:
	add_to_group("structures")
	collision_layer = Layers.GATE if kind == Kind.GATE else Layers.STRUCTURES
	collision_mask = 0
	health = HealthComponent.new()
	health.name = "Health"
	health.is_structure = true
	add_child(health)
	health.setup(KIND_HP[kind], KIND_ARMOR[kind])
	health.died.connect(_on_destroyed)
	health.damaged.connect(_on_damaged)
	_build()
	var bar := HealthBar3D.new()
	bar.bar_width = 2.6 if kind == Kind.CORE else 1.8
	bar.color = Color(0.95, 0.75, 0.2) if kind != Kind.CORE else Color(0.3, 0.75, 1.0)
	bar.hide_when_full = kind != Kind.CORE
	bar.position.y = 4.6 if kind == Kind.CORE else 3.0
	add_child(bar)
	bar.bind(health)
	if kind == Kind.CORE:
		GameManager.base_core = self

func display_name() -> String:
	return KIND_NAMES[kind]

func is_dead() -> bool:
	return health.dead

func get_radius() -> float:
	return 0.0

func take_damage(info: DamageInfo) -> void:
	health.take_damage(info)

## Ponto da superfície da estrutura mais próximo de `p` (para alcance de ataque).
func closest_point(p: Vector3) -> Vector3:
	var local := to_local(p)
	local.x = clampf(local.x, -half_extents.x, half_extents.x)
	local.z = clampf(local.z, -half_extents.z, half_extents.z)
	local.y = 0.0
	return to_global(local)

func missing_health() -> float:
	return health.max_health - health.current

func repair(amount: float) -> void:
	if health.dead:
		health.revive(0.0)
		_set_destroyed(false)
	health.heal(amount)
	if health.current <= 0.0:
		health.current = 1.0

# --- Visual ----------------------------------------------------------------

func _build() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_rubble = Node3D.new()
	_rubble.visible = false
	add_child(_rubble)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	match kind:
		Kind.WALL_WOOD:
			half_extents = Vector3(length * 0.5, 1.3, 0.45)
			_build_palisade()
		Kind.GATE:
			half_extents = Vector3(length * 0.5, 1.5, 0.45)
			_build_gate()
		Kind.CORE:
			half_extents = Vector3(1.9, 2.0, 1.9)
			_build_core()
	box.size = half_extents * 2.0
	col.shape = box
	col.position.y = half_extents.y
	add_child(col)
	_build_rubble()

func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _build_palisade() -> void:
	var bark := MaterialLib.textured("bark", Color(0.95, 0.8, 0.65), 1.0)
	var planks := MaterialLib.textured("planks", Color(0.9, 0.8, 0.7), 1.0)
	var n := int(length / 0.42)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	for i in n:
		var x := -length * 0.5 + (i + 0.5) * length / n
		var h := rng.randf_range(2.3, 2.8)
		var lg := CylinderMesh.new()
		lg.top_radius = 0.2
		lg.bottom_radius = 0.22
		lg.height = h
		lg.radial_segments = 8
		_mesh(_visual, lg, Vector3(x, h * 0.5, rng.randf_range(-0.05, 0.05)), bark, Vector3(0, 0, rng.randf_range(-3, 3)))
		var tip := CylinderMesh.new()
		tip.top_radius = 0.0
		tip.bottom_radius = 0.2
		tip.height = 0.4
		tip.radial_segments = 8
		_mesh(_visual, tip, Vector3(x, h + 0.2, 0), bark)
	var beam := BoxMesh.new()
	beam.size = Vector3(length, 0.22, 0.12)
	_mesh(_visual, beam, Vector3(0, 1.7, -0.26), planks)
	_mesh(_visual, beam, Vector3(0, 0.7, -0.26), planks)

func _build_gate() -> void:
	var bark := MaterialLib.textured("bark", Color(0.85, 0.7, 0.55), 1.0)
	var planks := MaterialLib.textured("planks", Color(1, 0.9, 0.8), 0.7)
	var metal := MaterialLib.textured("metal", Color(0.6, 0.6, 0.65), 1.0, true, 0.4)
	for sx: float in [-1.0, 1.0]:
		var post := CylinderMesh.new()
		post.top_radius = 0.3
		post.bottom_radius = 0.34
		post.height = 3.6
		_mesh(_visual, post, Vector3(sx * (length * 0.5 + 0.1), 1.8, 0), bark)
		var hinge := Node3D.new()
		hinge.position = Vector3(sx * length * 0.5, 0, 0)
		_visual.add_child(hinge)
		var door := BoxMesh.new()
		door.size = Vector3(length * 0.5, 2.6, 0.2)
		_mesh(hinge, door, Vector3(-sx * length * 0.25, 1.4, 0), planks)
		var band := BoxMesh.new()
		band.size = Vector3(length * 0.5, 0.18, 0.24)
		_mesh(hinge, band, Vector3(-sx * length * 0.25, 0.7, 0), metal)
		_mesh(hinge, band, Vector3(-sx * length * 0.25, 2.1, 0), metal)
		hinge.set_meta("side", sx)
		_gate_doors.append(hinge)
	var top := BoxMesh.new()
	top.size = Vector3(length + 0.9, 0.35, 0.5)
	_mesh(_visual, top, Vector3(0, 3.4, 0), planks)

func _build_core() -> void:
	var planks := MaterialLib.textured("planks", Color.WHITE, 0.6)
	var stone := MaterialLib.textured("rock", Color(0.9, 0.9, 0.95), 0.8)
	var cloth := MaterialLib.textured("cloth", Color(0.75, 0.2, 0.15), 1.0)
	# Plataforma de pedra
	var base := CylinderMesh.new()
	base.top_radius = 2.2
	base.bottom_radius = 2.5
	base.height = 0.6
	base.radial_segments = 10
	_mesh(_visual, base, Vector3(0, 0.3, 0), stone)
	# Fogueira central protegida por um abrigo de madeira (o "coração" da base)
	var pit := TorusMesh.new()
	pit.inner_radius = 0.55
	pit.outer_radius = 0.9
	_mesh(_visual, pit, Vector3(0, 0.7, 0), stone)
	for i in 4:
		var lg := CylinderMesh.new()
		lg.top_radius = 0.1
		lg.bottom_radius = 0.12
		lg.height = 1.2
		_mesh(_visual, lg, Vector3(0, 0.85, 0), MaterialLib.textured("bark", Color.WHITE), Vector3(70, i * 45.0, 0))
	for corner in [Vector3(-1.6, 0, -1.6), Vector3(1.6, 0, -1.6), Vector3(-1.6, 0, 1.6), Vector3(1.6, 0, 1.6)]:
		var post := CylinderMesh.new()
		post.top_radius = 0.14
		post.bottom_radius = 0.16
		post.height = 3.4
		_mesh(_visual, post, corner + Vector3(0, 2.0, 0), planks)
	var roof := PrismMesh.new()
	roof.size = Vector3(4.2, 1.4, 4.2)
	_mesh(_visual, roof, Vector3(0, 4.3, 0), planks)
	# Estandarte
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.06
	pole.height = 3.0
	_mesh(_visual, pole, Vector3(0, 6.2, 0), planks)
	var flag := BoxMesh.new()
	flag.size = Vector3(1.2, 0.7, 0.04)
	_mesh(_visual, flag, Vector3(0.62, 7.3, 0), cloth)
	# Luz e fogo permanentes
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.25)
	light.light_energy = 3.0
	light.omni_range = 12.0
	light.shadow_enabled = true
	light.position = Vector3(0, 1.6, 0)
	_visual.add_child(light)
	var fire := EffectsHub.make_fire_particles(1.4)
	fire.position = Vector3(0, 0.8, 0)
	_visual.add_child(fire)

func _build_rubble() -> void:
	var mat := MaterialLib.textured("bark", Color(0.4, 0.32, 0.28), 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var count := 6 if kind != Kind.CORE else 12
	for i in count:
		var b := BoxMesh.new()
		b.size = Vector3(rng.randf_range(0.3, 1.2), 0.25, rng.randf_range(0.2, 0.4))
		_mesh(_rubble, b, Vector3(rng.randf_range(-half_extents.x, half_extents.x), 0.12, rng.randf_range(-0.6, 0.6)), mat, Vector3(0, rng.randf_range(0, 180), rng.randf_range(-15, 15)))

func _process(delta: float) -> void:
	if kind != Kind.GATE or health.dead:
		return
	# Portão abre (visualmente) para aliados próximos — zumbis continuam bloqueados.
	var hero := GameManager.hero as Hero
	var want := 0.0
	if hero and not hero.is_dead() and hero.global_position.distance_to(global_position) < 4.5:
		want = 1.0
	_gate_open = move_toward(_gate_open, want, delta * 2.5)
	for d in _gate_doors:
		d.rotation.y = float(d.get_meta("side")) * _gate_open * deg_to_rad(-100.0)

func _on_damaged(_info: DamageInfo, _amount: float) -> void:
	EventBus.structure_damaged.emit(self)
	if randf() < 0.5:
		EffectsHub.spawn_debris(global_position + Vector3(0, 1.2, 0))

func _on_destroyed(_info: DamageInfo) -> void:
	_set_destroyed(true)
	EventBus.structure_destroyed.emit(self)
	AudioManager.play_3d(&"break", global_position)
	if kind == Kind.CORE:
		EventBus.base_core_destroyed.emit()
	else:
		EventBus.notify("%s foi destruída!" % display_name(), Color(1, 0.45, 0.3))

func _set_destroyed(d: bool) -> void:
	_visual.visible = not d
	_rubble.visible = d
	collision_layer = 0 if d else (Layers.GATE if kind == Kind.GATE else Layers.STRUCTURES)

func to_save() -> Dictionary:
	return {"hp": health.current, "dead": health.dead}

func from_save(d: Dictionary) -> void:
	var hp := float(d.get("hp", health.max_health))
	if bool(d.get("dead", false)):
		health.current = 0.0
		health.dead = true
		_set_destroyed(true)
	else:
		health.current = clampf(hp, 1.0, health.max_health)
	health.changed.emit(health.current, health.max_health)
