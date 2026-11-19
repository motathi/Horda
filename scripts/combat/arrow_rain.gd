class_name ArrowRain
extends Node3D
## Chuva de Flechas do Caçador: flechas caem numa área por alguns segundos, ferindo e
## deixando os inimigos mais lentos. No coop, os outros veem uma cópia só visual.

const TICK := 0.4
const ARROWS_PER_SECOND := 26.0

var owner_hero: Node3D
var radius: float = 4.5
var duration: float = 3.5
var tick_damage: float = 14.0
var visual_only: bool = false
var _t: float = 0.0
var _tick_left: float = 0.15
var _spawn_acc: float = 0.0
static var _arrow_mesh: Mesh
static var _arrow_mat: Material

func _ready() -> void:
	EffectsHub.spawn_ring(global_position + Vector3.UP * 0.05, radius, Color(1.0, 0.55, 0.15, 0.18), duration)
	AudioManager.play_3d(&"arrow", global_position, 2.0, 0.8)

func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	_spawn_acc += delta * ARROWS_PER_SECOND
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		_spawn_falling_arrow()
	if visual_only:
		return
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = TICK
		var src: Node = owner_hero if is_instance_valid(owner_hero) else null
		for e: Enemy in Enemy.all.duplicate():
			if not is_instance_valid(e) or e.is_dead():
				continue
			var d := e.global_position - global_position
			d.y = 0.0
			if d.length() <= radius + e.get_radius():
				e.take_damage(DamageInfo.make(tick_damage, src))
				e.apply_fear(TICK + 0.2)
		if randf() < 0.5:
			AudioManager.play_3d(&"hit", global_position, -8.0, 1.2, 120)

func _spawn_falling_arrow() -> void:
	if _arrow_mesh == null:
		var c := CylinderMesh.new()
		c.top_radius = 0.02
		c.bottom_radius = 0.02
		c.height = 0.9
		c.radial_segments = 4
		_arrow_mesh = c
		_arrow_mat = MaterialLib.flat(Color(0.55, 0.38, 0.2))
	var a := randf() * TAU
	var r := sqrt(randf()) * radius
	var land := global_position + Vector3(cos(a) * r, 0.25, sin(a) * r)
	var arrow := MeshInstance3D.new()
	arrow.mesh = _arrow_mesh
	arrow.material_override = _arrow_mat
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(arrow)
	arrow.global_position = land + Vector3(-1.2, 11.0, 0.6)
	arrow.rotation_degrees = Vector3(0, 0, -6)
	var tw := arrow.create_tween()
	tw.tween_property(arrow, "global_position", land, 0.32).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.5)
	tw.tween_callback(arrow.queue_free)
