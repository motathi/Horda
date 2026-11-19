class_name Eagle
extends Node3D
## Águia do Caçador (modelo e animações feitos no Blender: assets/models/blender/eagle.glb).
## Circula sobre o dono e mergulha nos inimigos próximos; seus olhos revelam Espreitadores.
## No coop, os outros jogadores veem uma cópia só visual (visual_only).

const SCENE := "res://assets/models/blender/eagle.glb"
const ORBIT_RADIUS := 4.5
const ORBIT_HEIGHT := 6.0
const ORBIT_SPEED := 1.4
const DIVE_SPEED := 24.0
const ATTACK_EVERY := 1.1

enum State { ORBIT, DIVE, CLIMB }

var owner_hero: Node3D
var damage: float = 30.0
var hunt_radius: float = 14.0
var reveal_radius: float = 8.0
var lifetime: float = 20.0
var visual_only: bool = false
var state: State = State.ORBIT
var _target: Enemy
var _angle: float = 0.0
var _attack_cd: float = 0.6
var _ap: AnimationPlayer
var _anim: String = ""
var _climb_from: Vector3
var _climb_t: float = 0.0
var _screech_t: float = 0.0

func _ready() -> void:
	add_to_group(&"eagles")
	# Visão de águia: revela Espreitadores perto dela.
	add_to_group(&"reveal_lights")
	set_meta(&"reveal_radius", reveal_radius)
	if ResourceLoader.exists(SCENE):
		var m := (load(SCENE) as PackedScene).instantiate() as Node3D
		m.scale = Vector3.ONE * 1.3
		add_child(m)
		var aps := m.find_children("*", "AnimationPlayer", true, false)
		if aps.size() > 0:
			_ap = aps[0] as AnimationPlayer
			for n in _ap.get_animation_list():
				_ap.get_animation(n).loop_mode = Animation.LOOP_NONE if n == "dive" else Animation.LOOP_LINEAR
	_play("fly")
	_angle = randf() * TAU
	if is_instance_valid(owner_hero):
		global_position = owner_hero.global_position + Vector3(0, ORBIT_HEIGHT + 4.0, 0)
	_screech()

func _play(n: String) -> void:
	if _ap and _anim != n and _ap.has_animation(n):
		_anim = n
		_ap.play(n, 0.15)

func _screech() -> void:
	AudioManager.play_3d(&"crow", global_position, 2.0, 0.62, 300)

func _process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0 or not is_instance_valid(owner_hero):
		_leave()
		return
	_attack_cd -= delta
	_screech_t -= delta
	match state:
		State.ORBIT:
			_orbit(delta)
			if _attack_cd <= 0.0:
				_target = _pick_target()
				if _target:
					state = State.DIVE
					_play("dive")
					if _screech_t <= 0.0:
						_screech_t = 4.0
						_screech()
		State.DIVE:
			if not is_instance_valid(_target) or _target.is_dead():
				_begin_climb()
				return
			var aim := _target.global_position + Vector3.UP * 1.0 * (_target.def.model_scale if _target.def else 1.0)
			var to := aim - global_position
			if to.length() < 0.9:
				_strike()
				return
			_move_towards(aim, DIVE_SPEED, delta)
		State.CLIMB:
			_climb_t += delta / 0.7
			var home := _orbit_point()
			var p := _climb_from.lerp(home, smoothstep(0.0, 1.0, minf(_climb_t, 1.0)))
			_face_dir(p - global_position, delta)
			global_position = p
			if _climb_t >= 1.0:
				state = State.ORBIT
				_play("glide" if randf() < 0.4 else "fly")

func _orbit_point() -> Vector3:
	var c := owner_hero.global_position
	return c + Vector3(cos(_angle) * ORBIT_RADIUS, ORBIT_HEIGHT + sin(_angle * 2.0) * 0.4, sin(_angle) * ORBIT_RADIUS)

func _orbit(delta: float) -> void:
	_angle += ORBIT_SPEED * delta
	_move_towards(_orbit_point(), 14.0, delta)

func _move_towards(p: Vector3, speed: float, delta: float) -> void:
	var to := p - global_position
	var step := minf(to.length(), speed * delta)
	if to.length() > 0.001:
		_face_dir(to, delta)
		global_position += to.normalized() * step

func _face_dir(d: Vector3, delta: float) -> void:
	if d.length_squared() < 0.0001:
		return
	var target := Transform3D().looking_at(d.normalized(), Vector3.UP).basis
	basis = basis.orthonormalized().slerp(target.orthonormalized(), clampf(delta * 8.0, 0.0, 1.0))

func _pick_target() -> Enemy:
	var best: Enemy = null
	var bd := hunt_radius
	var c := owner_hero.global_position
	for e in Enemy.all:
		if not is_instance_valid(e) or e.is_dead() or e.is_leaping():
			continue
		var d := Vector2(e.global_position.x - c.x, e.global_position.z - c.z).length()
		# Prefere quem está atacando o dono (mais perto dele).
		if d < bd:
			bd = d
			best = e
	return best

func _strike() -> void:
	_attack_cd = ATTACK_EVERY
	EffectsHub.spawn_blood(_target.global_position + Vector3.UP * 1.2, false)
	AudioManager.play_3d(&"hit", global_position, -2.0, 1.3)
	if not visual_only:
		var src: Node = owner_hero if is_instance_valid(owner_hero) else null
		_target.take_damage(DamageInfo.make(damage, src, randf() < 0.2))
		_target.stun(0.25)
	_begin_climb()

func _begin_climb() -> void:
	state = State.CLIMB
	_climb_from = global_position
	_climb_t = 0.0
	_play("fly")

func _leave() -> void:
	set_process(false)
	remove_from_group(&"reveal_lights")
	_play("fly")
	var tw := create_tween()
	tw.tween_property(self, "global_position", global_position + Vector3(0, 14, 0), 1.2)
	tw.tween_callback(queue_free)
