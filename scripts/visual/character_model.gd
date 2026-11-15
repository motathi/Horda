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
# Modo "modelo gerado": malha única (sem esqueleto) animada pelo corpo inteiro.
var _model_mode: bool = false
var _body_mesh: MeshInstance3D
var _body_base_scale: Vector3 = Vector3.ONE
var _weapon_pivot: Node3D
var _height: float = 2.0
var _lean: float = 0.0
# Modo "personagem rigado": cena GLB com esqueleto + AnimationPlayer (Tripo).
const RIGGED_DIR := "res://assets/models/rigged/"
var _rigged: bool = false
var _anim: AnimationPlayer
var _anim_names: Dictionary = {}  # "walk" -> nome real da animação
var _skinned: Array[MeshInstance3D] = []
var _current: String = ""
var _run_threshold: float = 0.7

func build_hero() -> void:
	kind = Kind.HERO
	if ResourceLoader.exists(RIGGED_DIR + "hero.glb"):
		_build_rigged("hero", 2.2)
		return
	if ModelLibrary.has("hero"):
		_build_from_model("hero", 2.2, Color.WHITE)
		_attach_axe(Vector3(0.42, 1.45, 0.0))
		return
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
	if ResourceLoader.exists(RIGGED_DIR + String(def.id) + ".glb"):
		_build_rigged(String(def.id), 2.0 * def.model_scale)
		_run_threshold = 0.5 if def.behavior in [EnemyDef.Behavior.CHARGER, EnemyDef.Behavior.LEAPER] else 0.85
		return
	if ModelLibrary.has(String(def.id)):
		# Tons diferentes por indivíduo para a horda não parecer clonada.
		var v := randf_range(0.85, 1.05)
		_build_from_model(String(def.id), 2.0 * def.model_scale, Color(v, v * randf_range(0.95, 1.05), v))
		return
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

func _build_rigged(model_name: String, height: float) -> void:
	_rigged = true
	_rig = Node3D.new()
	add_child(_rig)
	var inst := (load(RIGGED_DIR + model_name + ".glb") as PackedScene).instantiate() as Node3D
	_rig.add_child(inst)
	var aabb := AABB()
	var first := true
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		_skinned.append(mi)
		_meshes.append(mi)
		var b := mi.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	var s := height / maxf(0.01, aabb.size.y)
	inst.scale = Vector3.ONE * s
	inst.position.y = -aabb.position.y * s
	inst.rotation.y = PI * 0.5  # modelos Tripo olham para +X; o jogo usa -Z
	var players := inst.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	_anim = players[0] as AnimationPlayer
	for n in _anim.get_animation_list():
		_strip_root_motion(_anim.get_animation(n))
	for n in _anim.get_animation_list():
		var key := String(n).to_lower().get_slice("|", String(n).get_slice_count("|") - 1)
		for k: String in ["idle", "walk", "run", "slash", "hurt"]:
			if key.ends_with(k):
				_anim_names[k] = n
				if k in ["idle", "walk", "run"]:
					_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	# Pausa a animação quando fora da tela (hordas grandes).
	var vis := VisibleOnScreenNotifier3D.new()
	vis.aabb = AABB(Vector3(-1, 0, -1), Vector3(2, height, 2))
	add_child(vis)
	vis.screen_entered.connect(func() -> void: _anim.process_mode = Node.PROCESS_MODE_INHERIT)
	vis.screen_exited.connect(func() -> void: _anim.process_mode = Node.PROCESS_MODE_DISABLED)
	_play("idle", 0.0)

## As animações da Tripo deslocam o quadril para frente (root motion): o modelo
## "andava" para longe do personagem e voltava de repente a cada ciclo. Aqui a
## deriva linear do quadril é removida, mantendo o balanço natural do passo.
static func _strip_root_motion(a: Animation) -> void:
	if a == null or a.has_meta("root_fixed"):
		return
	a.set_meta("root_fixed", true)
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var path := String(a.track_get_path(t))
		if not (path.ends_with(":Hip") or path.ends_with(":Root") or path.ends_with(":Hips")):
			continue
		var n := a.track_get_key_count(t)
		if n < 2:
			continue
		var t0 := a.track_get_key_time(t, 0)
		var t1 := a.track_get_key_time(t, n - 1)
		var v0: Vector3 = a.track_get_key_value(t, 0)
		var v1: Vector3 = a.track_get_key_value(t, n - 1)
		var drift := v1 - v0
		for k in n:
			var v: Vector3 = a.track_get_key_value(t, k)
			var f := (a.track_get_key_time(t, k) - t0) / maxf(0.0001, t1 - t0)
			a.track_set_key_value(t, k, v - drift * f)

func _play(key: String, blend: float = 0.15, speed: float = 1.0) -> void:
	if _anim == null or not _anim_names.has(key):
		return
	_anim.speed_scale = speed
	if _current == key:
		return
	_current = key
	_anim.play(_anim_names[key], blend)

func _animate_rigged(delta: float, speed_ratio: float) -> void:
	if _attack_t >= 0.0:
		_attack_t += delta
		if _attack_t >= _attack_dur:
			_attack_t = -1.0
			_current = ""
		else:
			return
	if speed_ratio > _run_threshold and _anim_names.has("run"):
		_play("run", 0.15, clampf(speed_ratio, 0.8, 1.4))
	elif speed_ratio > 0.05:
		_play("walk", 0.15, clampf(speed_ratio / maxf(0.1, _run_threshold), 0.6, 1.5))
	else:
		_play("idle", 0.25)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_set_overlay(null)

func _build_from_model(model_name: String, height: float, tint: Color) -> void:
	_model_mode = true
	_height = height
	_rig = Node3D.new()
	add_child(_rig)
	_body_mesh = ModelLibrary.instance_height(model_name, height, tint)
	_body_base_scale = _body_mesh.scale
	_rig.add_child(_body_mesh)
	_meshes.append(_body_mesh)

## Machado procedural na mão direita (o modelo gerado não trouxe a arma).
func _attach_axe(shoulder: Vector3) -> void:
	_weapon_pivot = Node3D.new()
	_weapon_pivot.position = shoulder
	_rig.add_child(_weapon_pivot)
	var axe := Node3D.new()
	axe.position = Vector3(0, -0.75, -0.1)
	axe.rotation_degrees = Vector3(-80, 0, 0)
	_weapon_pivot.add_child(axe)
	_capsule(axe, 0.05, 1.4, Vector3(0, 0.35, 0), MaterialLib.textured("bark", Color(0.75, 0.55, 0.38), 1.0))
	var blade := _box(axe, Vector3(0.08, 0.55, 0.6), Vector3(0, 0.9, -0.24), MaterialLib.textured("metal", Color(0.85, 0.88, 0.95), 1.0, true, 0.3))
	blade.rotation_degrees.x = 8.0
	_box(axe, Vector3(0.11, 0.09, 0.18), Vector3(0, 1.05, 0.12), MaterialLib.flat(Color(0.2, 0.2, 0.24)))
	_weapon_pivot.rotation.x = 0.25

func _animate_model(delta: float, speed_ratio: float) -> void:
	_idle_t += delta
	var amp := clampf(speed_ratio, 0.0, 1.0)
	if amp > 0.05:
		_walk_phase += delta * (8.0 + 5.0 * amp) * (0.7 if kind == Kind.ZOMBIE else 1.0)
	var s := sin(_walk_phase)
	var sway := 0.13 if kind == Kind.ZOMBIE else 0.05
	var base_lean := -hunch * 0.35 if kind == Kind.ZOMBIE else 0.0
	_lean = lerpf(_lean, base_lean - 0.12 * amp, clampf(delta * 8.0, 0.0, 1.0))
	var pos := Vector3(0, absf(s) * 0.09 * amp, 0)
	var rot := Vector3(_lean, 0, s * sway * amp + (sin(_idle_t * 1.7) * 0.03 if kind == Kind.ZOMBIE else 0.0))
	# Respiração / passos (leve squash & stretch)
	var breathe := 1.0 + sin(_idle_t * 2.2) * 0.012 + absf(s) * 0.03 * amp
	_body_mesh.scale = _body_base_scale * Vector3(1.0 / sqrt(breathe), breathe, 1.0 / sqrt(breathe))
	if _attack_t >= 0.0:
		_attack_t += delta
		var t := clampf(_attack_t / _attack_dur, 0.0, 1.0)
		if t < 0.35:
			var k := t / 0.35
			rot.x += 0.18 * k
			if _weapon_pivot:
				_weapon_pivot.rotation.x = lerpf(0.25, deg_to_rad(170.0), k)
		else:
			var k2 := ease((t - 0.35) / 0.65, 0.4)
			var strike := sin(k2 * PI)
			rot.x += 0.18 * (1.0 - k2) - 0.35 * strike
			pos.z -= 0.45 * strike
			if _weapon_pivot:
				_weapon_pivot.rotation.x = lerpf(deg_to_rad(170.0), deg_to_rad(-15.0), k2)
		if t >= 1.0:
			_attack_t = -1.0
	elif _weapon_pivot:
		_weapon_pivot.rotation.x = lerpf(_weapon_pivot.rotation.x, 0.25 + s * 0.3 * amp, clampf(delta * 10.0, 0.0, 1.0))
	_rig.position = pos
	_rig.rotation = rot
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_set_overlay(null)

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
	if _rigged:
		_animate_rigged(delta, speed_ratio)
		return
	if _model_mode:
		_animate_model(delta, speed_ratio)
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
	if _rigged and _anim and _anim_names.has("slash"):
		var a := _anim.get_animation(_anim_names["slash"])
		_current = "slash"
		_anim.play(_anim_names["slash"], 0.08)
		_anim.seek(0.0, true)
		_anim.speed_scale = a.length / _attack_dur

## Giro completo do corpo (Golpe Giratório).
func play_spin(duration: float) -> void:
	if _rig == null:
		return
	play_attack(duration)
	var tw := create_tween()
	_rig.rotation.y = 0.0
	tw.tween_property(_rig, "rotation:y", TAU, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _rig.rotation.y = 0.0)

func flash() -> void:
	_flash_t = 0.09
	_set_overlay(MaterialLib.flash())

func _set_overlay(m: Material) -> void:
	for mi in _meshes:
		mi.material_overlay = m

func play_death() -> void:
	_dead = true
	_set_overlay(null)
	if _rigged and _anim and _anim_names.has("hurt"):
		# "hurt" do Tripo é uma queda completa: serve como animação de morte.
		_current = "hurt"
		_anim.speed_scale = 1.3
		_anim.get_animation(_anim_names["hurt"]).loop_mode = Animation.LOOP_NONE
		_anim.play(_anim_names["hurt"], 0.05)
		_anim.process_mode = Node.PROCESS_MODE_INHERIT
		var t2 := create_tween()
		t2.tween_interval(2.0)
		t2.tween_property(_rig, "position:y", -1.6, 1.0)
		return
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
	if _body_mesh:
		_body_mesh.scale = _body_base_scale
	if _rigged:
		_current = ""
		_play("idle", 0.0)
