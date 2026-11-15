class_name Projectile
extends Node3D
## Flecha teleguiada disparada pelas torres. Reciclada por ObjectPool.

var _target: Enemy
var _info: DamageInfo
var _speed: float = 30.0
var _last_pos: Vector3
var _life: float = 0.0

func _ready() -> void:
	var shaft := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.025
	c.bottom_radius = 0.025
	c.height = 0.9
	c.radial_segments = 4
	shaft.mesh = c
	shaft.rotation_degrees.x = 90
	shaft.material_override = MaterialLib.flat(Color(0.55, 0.38, 0.2))
	add_child(shaft)
	var tip := MeshInstance3D.new()
	var t := CylinderMesh.new()
	t.top_radius = 0.0
	t.bottom_radius = 0.06
	t.height = 0.16
	t.radial_segments = 4
	tip.mesh = t
	tip.rotation_degrees.x = -90
	tip.position.z = -0.5
	tip.material_override = MaterialLib.flat(Color(0.85, 0.85, 0.9), 0.3)
	add_child(tip)
	var trail := MeshInstance3D.new()
	var q := BoxMesh.new()
	q.size = Vector3(0.03, 0.03, 1.4)
	trail.mesh = q
	trail.position.z = 0.9
	trail.material_override = MaterialLib.unshaded(Color(1.0, 0.9, 0.6, 0.35))
	add_child(trail)

func activate(from: Vector3, target: Enemy, info: DamageInfo, speed: float) -> void:
	global_position = from
	_target = target
	_info = info
	_speed = speed
	_last_pos = target.global_position + Vector3.UP
	_life = 0.0

func _process(delta: float) -> void:
	_life += delta
	if _target and is_instance_valid(_target) and not _target.is_dead():
		_last_pos = _target.global_position + Vector3.UP * 1.0 * (_target.def.model_scale if _target.def else 1.0)
	var to := _last_pos - global_position
	var dist := to.length()
	if dist < 0.5 or _life > 3.0:
		if _target and is_instance_valid(_target) and not _target.is_dead() and dist < 1.2:
			_target.take_damage(_info)
		_release()
		return
	var step := minf(dist, _speed * delta)
	look_at(_last_pos, Vector3.UP)
	global_position += to / dist * step

func _release() -> void:
	_target = null
	(get_meta("pool") as ObjectPool).release(self)
