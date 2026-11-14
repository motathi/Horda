class_name CameraRig
extends Node3D
## Câmera isométrica estilo RTS/RPG: segue o herói, zoom na roda do mouse,
## rotação opcional (Q/R ou botão do meio arrastando) e C para recentralizar.

@export var target_path: NodePath
@export var pitch_degrees: float = 56.0
@export var min_distance: float = 12.0
@export var max_distance: float = 42.0
@export var distance: float = 20.0
@export var follow_speed: float = 8.0
@export var rotate_speed: float = 1.8

var _target: Node3D
var _yaw: float = deg_to_rad(45.0)
var _zoom_target: float
var _dragging: bool = false
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	_zoom_target = distance
	if not target_path.is_empty():
		_target = get_node(target_path)
	camera.fov = 45.0
	camera.far = 400.0
	_apply()

func set_target(t: Node3D) -> void:
	_target = t
	global_position = t.global_position

func _unhandled_input(event: InputEvent) -> void:
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

func _process(delta: float) -> void:
	if Input.is_action_pressed("camera_rotate_left"):
		_yaw += rotate_speed * delta
	if Input.is_action_pressed("camera_rotate_right"):
		_yaw -= rotate_speed * delta
	distance = lerpf(distance, _zoom_target, clampf(delta * 10.0, 0.0, 1.0))
	if _target and is_instance_valid(_target):
		global_position = global_position.lerp(_target.global_position, clampf(delta * follow_speed, 0.0, 1.0))
	_apply()

func _apply() -> void:
	rotation = Vector3(0, _yaw, 0)
	var pitch := deg_to_rad(pitch_degrees)
	camera.position = Vector3(0, sin(pitch) * distance, cos(pitch) * distance)
	camera.rotation = Vector3(-pitch, 0, 0)
