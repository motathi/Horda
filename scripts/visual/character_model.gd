class_name CharacterModel
extends Node3D
## Modelo estilizado montado a partir de primitivas + texturas pintadas à mão,
## com animação procedural (andar, atacar, sofrer dano, morrer).
## Frente do modelo = -Z (convenção do Godot / look_at).

enum Kind { HERO, ZOMBIE }

## Escala visual global (personagens "parrudos" e legíveis de longe).
const MODEL_SCALE := 1.2

var kind: Kind = Kind.HERO
var hunch: float = 0.0
var _rig: Node3D
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _meshes: Array[MeshInstance3D] = []
var _walk_phase: float = 0.0
var _attack_t: float = -1.0
var _attack_dur: float = 0.35
var _flash_t: float = 0.0
var _dead: bool = false
var _idle_t: float = 0.0
var _rest_arm_angle: float = 0.15

func build_hero() -> void:
	kind = Kind.HERO
	var skin := MaterialLib.flat(Color(0.86, 0.66, 0.5), 0.7)
	var armor := MaterialLib.textured("armor", Color(1, 1, 1), 1.5)
	var cloth := MaterialLib.textured("cloth", Color(0.45, 0.32, 0.22), 2.0)
	var red := MaterialLib.textured("cloth", Color(0.85, 0.18, 0.12), 2.0)
	var leather := MaterialLib.flat(Color(0.32, 0.2, 0.12), 0.9)
	_build_skeleton(1.0)
	_box(_torso, Vector3(0.78, 0.72, 0.46), Vector3(0, 0.38, 0), armor)
	_box(_torso, Vector3(0.82, 0.14, 0.5), Vector3(0, 0.02, 0), leather) # cinto
	_sphere(_head, 0.27, Vector3(0, 0.22, 0), skin)
	_box(_head, Vector3(0.5, 0.12, 0.5), Vector3(0, 0.38, 0), red) # bandana
	_box(_head, Vector3(0.36, 0.14, 0.12), Vector3(0, 0.08, -0.22), MaterialLib.flat(Color(0.35, 0.22, 0.12))) # barba
	# Ombreira (assimétrica, leitura estilo Dota)
	_box(_torso, Vector3(0.36, 0.2, 0.42), Vector3(-0.48, 0.74, 0), armor).rotation_degrees.z = 18.0
	_sphere(_torso, 0.16, Vector3(0.46, 0.72, 0), leather)
	for arm: Node3D in [_arm_l, _arm_r]:
		_capsule(arm, 0.13, 0.7, Vector3(0, -0.32, 0), skin)
		_box(arm, Vector3(0.26, 0.24, 0.26), Vector3(0, -0.5, 0), leather) # luva
	for leg: Node3D in [_leg_l, _leg_r]:
		_capsule(leg, 0.16, 0.9, Vector3(0, -0.42, 0), cloth)
		_box(leg, Vector3(0.3, 0.2, 0.42), Vector3(0, -0.84, -0.06), leather) # bota
	# Machado de batalha na mão direita
	var axe := Node3D.new()
	axe.position = Vector3(0, -0.6, 0)
	axe.rotation_degrees = Vector3(-90, 0, 0)
	_arm_r.add_child(axe)
	_capsule(axe, 0.05, 1.3, Vector3(0, 0.35, 0), MaterialLib.textured("bark", Color(0.8, 0.6, 0.4), 1.0))
	var blade := _box(axe, Vector3(0.08, 0.5, 0.55), Vector3(0, 0.85, -0.22), MaterialLib.textured("metal", Color(0.9, 0.9, 0.95), 1.0, true, 0.35))
	blade.rotation_degrees.x = 8.0
	_box(axe, Vector3(0.1, 0.08, 0.16), Vector3(0, 0.98, 0.12), MaterialLib.flat(Color(0.25, 0.25, 0.28)))
	# Capa
	var cape := _box(_torso, Vector3(0.7, 1.0, 0.06), Vector3(0, 0.1, 0.27), red)
	cape.rotation_degrees.x = -10.0
	_rest_arm_angle = 0.2
	scale = Vector3.ONE * MODEL_SCALE

func build_zombie(def: EnemyDef) -> void:
	kind = Kind.ZOMBIE
	hunch = def.hunch
	var skin := MaterialLib.textured("zombie_skin", def.skin_tint, 1.2)
	var cloth := MaterialLib.textured("cloth", def.cloth_tint, 1.8)
	var dark := MaterialLib.flat(def.cloth_tint.darkened(0.5))
	var eye := MaterialLib.flat(Color(1.0, 0.85, 0.2), 0.5, 4.0) if def.behavior != EnemyDef.Behavior.CHARGER else MaterialLib.flat(Color(1, 0.15, 0.1), 0.5, 4.0)
	var bulk := 1.35 if def.behavior == EnemyDef.Behavior.BRUTE else 1.0
	_build_skeleton(bulk)
	_box(_torso, Vector3(0.7 * bulk, 0.7, 0.42 * bulk), Vector3(0, 0.36, 0), cloth)
	_box(_torso, Vector3(0.5 * bulk, 0.3, 0.3 * bulk), Vector3(0.05, 0.6, -0.08), skin) # peito exposto
	_sphere(_head, 0.25, Vector3(0, 0.2, -0.05), skin)
	_box(_head, Vector3(0.2, 0.08, 0.1), Vector3(0, 0.08, -0.26), dark) # mandíbula
	_sphere(_head, 0.05, Vector3(-0.09, 0.25, -0.24), eye)
	_sphere(_head, 0.05, Vector3(0.09, 0.25, -0.24), eye)
	if def.behavior == EnemyDef.Behavior.BRUTE:
		var plate := MaterialLib.textured("metal", Color(0.7, 0.7, 0.75), 1.0, true, 0.4)
		_box(_torso, Vector3(0.95, 0.35, 0.55), Vector3(0, 0.6, 0), plate).rotation_degrees.z = -6.0
		_box(_head, Vector3(0.42, 0.18, 0.42), Vector3(0, 0.38, 0), plate)
	for arm: Node3D in [_arm_l, _arm_r]:
		_capsule(arm, 0.11 * bulk, 0.78, Vector3(0, -0.36, 0), skin)
		_box(arm, Vector3(0.2, 0.12, 0.26), Vector3(0, -0.74, -0.04), dark) # garras
	for leg: Node3D in [_leg_l, _leg_r]:
		_capsule(leg, 0.14 * bulk, 0.9, Vector3(0, -0.42, 0), cloth)
	_torso.rotation.x = -hunch * 0.9
	_head.rotation.x = hunch * 0.6
	_rest_arm_angle = deg_to_rad(75.0)
	scale = Vector3.ONE * def.model_scale * MODEL_SCALE

func _build_skeleton(bulk: float) -> void:
	_rig = Node3D.new()
	add_child(_rig)
	_hips = _node(_rig, Vector3(0, 0.92, 0))
	_torso = _node(_hips, Vector3.ZERO)
	_head = _node(_torso, Vector3(0, 0.8, 0))
	_arm_l = _node(_torso, Vector3(-0.47 * bulk, 0.68, 0))
	_arm_r = _node(_torso, Vector3(0.47 * bulk, 0.68, 0))
	_leg_l = _node(_hips, Vector3(-0.18 * bulk, 0, 0))
	_leg_r = _node(_hips, Vector3(0.18 * bulk, 0, 0))

func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	_meshes.append(mi)
	return mi

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _add_mesh(parent, m, pos, mat)

func _sphere(parent: Node3D, r: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	return _add_mesh(parent, m, pos, mat)

func _capsule(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 4
	return _add_mesh(parent, m, pos, mat)

## speed_ratio: 0 parado .. 1 velocidade máxima.
func animate(delta: float, speed_ratio: float) -> void:
	if _dead or _rig == null:
		return
	_idle_t += delta
	var moving := speed_ratio > 0.05
	if moving:
		_walk_phase += delta * (7.0 + 5.0 * speed_ratio) * (0.75 if kind == Kind.ZOMBIE else 1.0)
	var amp := 0.7 * clampf(speed_ratio, 0.0, 1.0)
	var s := sin(_walk_phase)
	_leg_l.rotation.x = s * amp
	_leg_r.rotation.x = -s * amp
	_hips.position.y = 0.92 + absf(cos(_walk_phase)) * 0.06 * amp + sin(_idle_t * 2.0) * 0.012
	var arm_swing := s * amp * (0.25 if kind == Kind.ZOMBIE else 0.6)
	_arm_l.rotation.x = _rest_arm_angle - arm_swing
	if kind == Kind.ZOMBIE:
		_hips.rotation.z = sin(_walk_phase * 0.5) * 0.08
		_arm_l.rotation.x += sin(_idle_t * 3.1) * 0.08
	if _attack_t >= 0.0:
		_attack_t += delta
		var t := clampf(_attack_t / _attack_dur, 0.0, 1.0)
		# Levanta (0-35%) e golpeia (35-100%).
		var a: float
		if t < 0.35:
			a = lerpf(_rest_arm_angle, deg_to_rad(165.0), t / 0.35)
		else:
			a = lerpf(deg_to_rad(165.0), deg_to_rad(10.0), ease((t - 0.35) / 0.65, 0.4))
		_arm_r.rotation.x = a
		_torso.rotation.y = lerpf(0.0, -0.5, sin(t * PI))
		if kind == Kind.ZOMBIE:
			_arm_l.rotation.x = a
		if t >= 1.0:
			_attack_t = -1.0
			_torso.rotation.y = 0.0
	else:
		_arm_r.rotation.x = _rest_arm_angle + arm_swing
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_set_overlay(null)

func play_attack(duration: float) -> void:
	_attack_dur = maxf(0.15, duration)
	_attack_t = 0.0

func flash() -> void:
	_flash_t = 0.09
	_set_overlay(MaterialLib.flash())

func _set_overlay(m: Material) -> void:
	for mi in _meshes:
		mi.material_overlay = m

func play_death() -> void:
	_dead = true
	_set_overlay(null)
	var tw := create_tween()
	tw.tween_property(_rig, "rotation:x", deg_to_rad(85.0), 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_rig, "position:y", -0.15, 0.45)
	tw.tween_interval(1.2)
	tw.tween_property(_rig, "position:y", -1.6, 1.0)

func reset_pose() -> void:
	_dead = false
	_rig.rotation = Vector3.ZERO
	_rig.position = Vector3.ZERO
	_attack_t = -1.0
