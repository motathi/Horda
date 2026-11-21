class_name CameraRig
extends Node3D
## Câmera isométrica estilo RTS/RPG: segue o herói, zoom na roda do mouse,
## rotação opcional (Q/R ou botão do meio arrastando) e C para recentralizar.

@export var target_path: NodePath
@export var pitch_degrees: float = 56.0
@export var min_distance: float = 12.0
@export var max_distance: float = 42.0
@export var distance: float = 18.0
@export var follow_speed: float = 8.0
@export var rotate_speed: float = 1.8

var _target: Node3D
var _yaw: float = deg_to_rad(45.0)
var _zoom_target: float
var _dragging: bool = false
var _touches: Dictionary = {}  # índice -> posição (pinça para zoom no celular)
var _pinch_dist: float = 0.0
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	_zoom_target = distance
	if not target_path.is_empty():
		_target = get_node(target_path)
	camera.fov = 45.0
	camera.far = 400.0
	# O "ouvido" fica no herói (centro do rig), não na câmera alta: senão golpes e
	# zumbis ficavam muito baixos por causa da distância. Gira junto com a câmera.
	var ear := AudioListener3D.new()
	ear.name = "Ear"
	ear.position = Vector3(0, 1.6, 0)
	add_child(ear)
	ear.make_current()
	_apply()

func set_target(t: Node3D) -> void:
	_target = t
	global_position = t.global_position

# --- Vista de construção (estilo city builder) ------------------------------------
const OVERVIEW_PITCH := 72.0
const OVERVIEW_DISTANCE := 54.0
const OVERVIEW_MAX := 70.0
var _overview: bool = false
var _overview_anchor: Node3D
var _saved := {}
var _pitch_target: float = -1.0

## Modo construção: câmera bem mais alta e quase de cima, centrada na base (onde se constrói).
func set_overview(on: bool, center: Vector3 = Vector3.ZERO) -> void:
	if on == _overview:
		return
	_overview = on
	if on:
		_saved = {"target": _target, "zoom": _zoom_target, "pitch": pitch_degrees, "max": max_distance}
		if _overview_anchor == null:
			_overview_anchor = Node3D.new()
			_overview_anchor.name = "OverviewAnchor"
			get_parent().add_child(_overview_anchor)
		_overview_anchor.global_position = center
		_target = _overview_anchor
		max_distance = OVERVIEW_MAX
		_zoom_target = OVERVIEW_DISTANCE
		_pitch_target = OVERVIEW_PITCH
	else:
		var t: Variant = _saved.get("target")
		_target = t if t != null and is_instance_valid(t) else _target
		max_distance = float(_saved.get("max", max_distance))
		_zoom_target = float(_saved.get("zoom", 18.0))
		_pitch_target = float(_saved.get("pitch", 56.0))

func is_overview() -> bool:
	return _overview

## Arrasta a vista de construção (teclas/joystick), sem sair de perto da base.
func pan_overview(v: Vector2, delta: float) -> void:
	if not _overview or _overview_anchor == null or v == Vector2.ZERO:
		return
	var b := Basis(Vector3.UP, _yaw)
	var move := (b.x * v.x + b.z * v.y) * delta * 30.0
	var p := _overview_anchor.global_position + Vector3(move.x, 0, move.z)
	var c := GameManager.base_core.global_position if GameManager.base_core else Vector3.ZERO
	var off := Vector2(p.x - c.x, p.z - c.z).limit_length(30.0)
	_overview_anchor.global_position = Vector3(c.x + off.x, 0, c.z + off.y)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touches.has(t.index):
			_touches.clear()  # toque antigo preso (o "soltou" se perdeu ao trocar de app)
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		_pinch_dist = _current_pinch()
		return
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _touches.has(d.index):
			_touches[d.index] = d.position
			if _touches.size() == 2:
				var nd := _current_pinch()
				if _pinch_dist > 0.0:
					_zoom_target = clampf(_zoom_target * _pinch_dist / maxf(1.0, nd), min_distance, max_distance)
				_pinch_dist = nd
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_target = maxf(min_distance, _zoom_target - 2.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_target = minf(max_distance, _zoom_target + 2.0)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= (event as InputEventMouseMotion).relative.x * 0.006
	elif event.is_action_pressed("camera_center") and _target:
		global_position = _target.global_position

func _current_pinch() -> float:
	if _touches.size() != 2:
		return 0.0
	var p: Array = _touches.values()
	return (p[0] as Vector2).distance_to(p[1])

func _process(delta: float) -> void:
	if Input.is_action_pressed("camera_rotate_left"):
		_yaw += rotate_speed * delta
	if Input.is_action_pressed("camera_rotate_right"):
		_yaw -= rotate_speed * delta
	distance = lerpf(distance, _zoom_target, clampf(delta * (4.0 if _pitch_target >= 0.0 else 10.0), 0.0, 1.0))
	if _pitch_target >= 0.0:
		pitch_degrees = lerpf(pitch_degrees, _pitch_target, clampf(delta * 4.0, 0.0, 1.0))
		if absf(pitch_degrees - _pitch_target) < 0.05:
			pitch_degrees = _pitch_target
			_pitch_target = -1.0
	if _target and is_instance_valid(_target):
		var tp: Vector3 = _target.call(&"visual_position") if _target.has_method(&"visual_position") else _target.global_position
		global_position = global_position.lerp(tp, clampf(delta * follow_speed, 0.0, 1.0))
	_apply()

func _apply() -> void:
	rotation = Vector3(0, _yaw, 0)
	var pitch := deg_to_rad(pitch_degrees)
	camera.position = Vector3(0, sin(pitch) * distance, cos(pitch) * distance)
	camera.rotation = Vector3(-pitch, 0, 0)
