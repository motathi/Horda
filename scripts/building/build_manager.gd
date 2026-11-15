class_name BuildManager
extends Node3D
## Modo de construção: prévia transparente seguindo o cursor (PC) ou o ponto
## tocado (celular), validação (área da base, espaço livre, recursos),
## rotação e posicionamento da construção.

signal mode_changed(active: bool)
signal preview_changed

const BUILD_RADIUS := 36.0
const CORE_CLEARANCE := 5.5
const GRID := 0.5

var active_def: BuildingDef
var rotation_y: float = 0.0
var valid: bool = false
var reason: String = ""
var parent_root: Node3D
var _ghost: Node3D
var _ghost_mats: Array[StandardMaterial3D] = []
var _target: Vector3 = Vector3.ZERO
var _camera: Camera3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(root: Node3D, cam: Camera3D) -> void:
	parent_root = root
	_camera = cam

func is_active() -> bool:
	return active_def != null

func start(d: BuildingDef) -> void:
	cancel()
	active_def = d
	var hero := GameManager.hero as Hero
	_target = hero.global_position + hero.facing() * 4.0 if hero else Vector3.ZERO
	_ghost = Building.make_visual(d)
	_ghost_mats.clear()
	_apply_ghost_material(_ghost)
	add_child(_ghost)
	if hero:
		hero.build_mode = true
	mode_changed.emit(true)
	_update_preview()

func cancel() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	var was := active_def != null
	active_def = null
	var hero := GameManager.hero as Hero
	if hero:
		hero.build_mode = false
	if was:
		mode_changed.emit(false)

func rotate_preview() -> void:
	rotation_y = fmod(rotation_y + PI * 0.25, TAU)
	_update_preview()

func _apply_ghost_material(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.3, 0.9, 1.0, 0.45)
			(c as MeshInstance3D).material_override = m
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ghost_mats.append(m)
		_apply_ghost_material(c)

# --- Entrada ------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("command"):
		cancel()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_T:
		rotate_preview()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack"):
		# PC: clique constrói no cursor. Celular: toque move a prévia.
		var p: Variant = _mouse_ground()
		if p != null:
			_target = p
			_update_preview()
			if not Platform.touch:
				confirm()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not is_active():
		return
	if not Platform.touch:
		var p: Variant = _mouse_ground()
		if p != null:
			_target = p
	_update_preview()

func _mouse_ground() -> Variant:
	if _camera == null:
		return null
	var mp := get_viewport().get_mouse_position()
	return Plane(Vector3.UP, 0.0).intersects_ray(_camera.project_ray_origin(mp), _camera.project_ray_normal(mp))

# --- Validação ----------------------------------------------------------------------

func _snapped(p: Vector3) -> Vector3:
	return Vector3(snappedf(p.x, GRID), 0.0, snappedf(p.z, GRID))

func _update_preview() -> void:
	if _ghost == null:
		return
	var pos := _snapped(_target)
	_ghost.global_position = pos
	_ghost.rotation.y = rotation_y
	var r := check(active_def, pos, rotation_y)
	valid = r.is_empty()
	reason = r
	for m in _ghost_mats:
		m.albedo_color = Color(0.3, 1.0, 0.45, 0.45) if valid else Color(1.0, 0.25, 0.2, 0.45)
	preview_changed.emit()

## Retorna "" se pode construir; senão o motivo.
func check(d: BuildingDef, pos: Vector3, rot: float) -> String:
	var core := GameManager.base_core
	var center := core.global_position if core else Vector3.ZERO
	var dist := Vector2(pos.x - center.x, pos.z - center.z).length()
	if dist > BUILD_RADIUS:
		return "Longe demais da base (máx. %d m)" % int(BUILD_RADIUS)
	if dist < CORE_CLEARANCE:
		return "Perto demais da fortaleza"
	if not ResourceManager.can_afford(d.cost):
		return "Faltam recursos: " + ResourceManager.cost_to_string(d.cost)
	var shape := BoxShape3D.new()
	var h := maxf(d.height, 0.6)
	shape.size = Vector3(d.footprint.x - 0.1, h - 0.1, d.footprint.y - 0.1)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(Vector3.UP, rot), pos + Vector3(0, h * 0.5 + 0.08, 0))
	q.collision_mask = Layers.WORLD | Layers.STRUCTURES | Layers.GATE | Layers.HERO | Layers.INTERACTABLES
	q.collide_with_areas = false
	var hits := get_world_3d().direct_space_state.intersect_shape(q, 4)
	for h2 in hits:
		var c := h2.get("collider") as Node
		if c is Hero:
			return "O herói está no caminho"
		return "Espaço ocupado"
	return ""

func confirm() -> bool:
	if not is_active():
		return false
	_update_preview()
	if not valid:
		EventBus.notify(reason, Color(1, 0.55, 0.4))
		AudioManager.play(&"ui_error")
		return false
	var b := place(active_def, _ghost.global_position, rotation_y)
	if b and not ResourceManager.can_afford(active_def.cost):
		cancel()
	return b != null

## Constrói diretamente (também usado pelo carregamento do save e pelos testes).
func place(d: BuildingDef, pos: Vector3, rot: float, pay: bool = true, lvl: int = 1) -> Building:
	if pay and not ResourceManager.spend(d.cost):
		return null
	var b := Building.new()
	b.setup(d, lvl)
	b.name = "B_%s_%d" % [d.id, Time.get_ticks_usec()]
	parent_root.add_child(b)
	b.global_position = _snapped(pos)
	b.rotation.y = rot
	if pay:
		EffectsHub.spawn_debris(b.global_position + Vector3.UP, false)
		AudioManager.play_3d(&"chop", b.global_position)
		EventBus.notify("%s construída." % d.display_name, UIStyle.GREEN)
		EventBus.building_placed.emit(b)
	return b
