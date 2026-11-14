class_name FloatingText
extends Label3D
## Texto flutuante (dano, coleta). Reciclado por ObjectPool.

var _t: float = 0.0
var _life: float = 1.0
var _vel: Vector3

func _init() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = false
	pixel_size = 0.01
	outline_size = 12
	outline_modulate = Color(0, 0, 0, 0.85)
	render_priority = 10
	outline_render_priority = 9

func activate(pos: Vector3, txt: String, color: Color, size: int = 48, life: float = 1.0) -> void:
	text = txt
	modulate = color
	font_size = size
	global_position = pos
	_t = 0.0
	_life = life
	_vel = Vector3(randf_range(-0.6, 0.6), 2.6, randf_range(-0.6, 0.6))
	scale = Vector3.ONE * 1.4

func _process(delta: float) -> void:
	_t += delta
	global_position += _vel * delta
	_vel.y -= 3.0 * delta
	scale = scale.lerp(Vector3.ONE, delta * 10.0)
	modulate.a = 1.0 - smoothstep(_life * 0.6, _life, _t)
	if _t >= _life:
		(get_meta("pool") as ObjectPool).release(self)
