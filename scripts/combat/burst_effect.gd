class_name BurstEffect
extends GPUParticles3D
## Explosão de partículas de disparo único (sangue, lascas, cura). Reciclada por pool.

var _t: float = 0.0

func activate(pos: Vector3, color: Color = Color.WHITE, amt_scale: float = 1.0) -> void:
	global_position = pos
	modulate_color(color)
	speed_scale = 1.0
	amount_ratio = clampf(amt_scale, 0.1, 1.0)
	_t = 0.0
	restart()
	emitting = true

func modulate_color(c: Color) -> void:
	var pm := process_material as ParticleProcessMaterial
	if pm:
		pm.color = c

func _process(delta: float) -> void:
	_t += delta
	if _t > lifetime + 0.2:
		emitting = false
		(get_meta("pool") as ObjectPool).release(self)
