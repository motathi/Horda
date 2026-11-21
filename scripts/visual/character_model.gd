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
## Velocidade real no chão (m/s). Quando >= 0 (herói), a cadência das animações de andar/correr é ajustada
## ao passo medido do esqueleto, sem "patinar"; -1 usa a razão de velocidade antiga (inimigos).
var ground_speed: float = -1.0
## Andando de costas (o arqueiro recua mirando): toca o passo ao contrário.
var backpedal: bool = false
var _stride: Dictionary = {}  # "walk"/"run" -> m/s do pé de apoio com a animação em velocidade 1
static var _stride_cache: Dictionary = {}  # modelo -> {"walk": m/s por metro de altura, "run": ...}

func build_hero(skin_id: String = "") -> void:
	kind = Kind.HERO
	var sk := HeroSkins.get_skin(skin_id if skin_id != "" else GameManager.hero_skin)
	if sk["id"] != HeroSkins.DEFAULT and rigged_path(sk["model"]) != "":
		_build_rigged(sk["model"], sk["height"])
		if sk.has("tint"):
			_tint_meshes(sk["tint"])
		return
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
	var mid := String(def.model_id) if def.model_id != &"" else String(def.id)
	if rigged_path(mid) != "":
		_build_rigged(mid, 2.0 * def.model_scale)
		_run_threshold = 0.5 if def.behavior in [EnemyDef.Behavior.CHARGER, EnemyDef.Behavior.LEAPER, EnemyDef.Behavior.STALKER] else 0.85
		if def.model_tint != Color.WHITE:
			_tint_meshes(def.model_tint)
		add_glow_eyes(def.eye_color, 2.0 * def.model_scale)
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

## Modelo riggado: .glb (Tripo) ou .scn (montado por tools/bake_kaykit.gd). "" se não houver.
static func rigged_path(model_name: String) -> String:
	for ext in [".glb", ".scn"]:
		if ResourceLoader.exists(RIGGED_DIR + model_name + ext):
			return RIGGED_DIR + model_name + ext
	return ""

func _build_rigged(model_name: String, height: float) -> void:
	_rigged = true
	_rig = Node3D.new()
	add_child(_rig)
	var inst := (load(rigged_path(model_name)) as PackedScene).instantiate() as Node3D
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
	if not _stride_cache.has(model_name):
		_stride_cache[model_name] = _measure_stride(inst, height)
	for k: String in _stride_cache[model_name]:
		_stride[k] = float(_stride_cache[model_name][k]) * height
	# Pausa a animação quando fora da tela (hordas grandes).
	var vis := VisibleOnScreenNotifier3D.new()
	vis.aabb = AABB(Vector3(-1, 0, -1), Vector3(2, height, 2))
	add_child(vis)
	vis.screen_entered.connect(func() -> void: _anim.process_mode = Node.PROCESS_MODE_INHERIT)
	vis.screen_exited.connect(func() -> void: _anim.process_mode = Node.PROCESS_MODE_DISABLED)
	_play("idle", 0.0)

## Mede quão rápido o pé de apoio (o mais baixo) recua em relação ao corpo em cada ciclo de andar/correr:
## é a velocidade em que o personagem precisa se mover para o pé "grudar" no chão.
func _measure_stride(inst: Node3D, height: float) -> Dictionary:
	var out := {}
	var sks := inst.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty() or _anim == null:
		return out
	var sk := sks[0] as Skeleton3D
	var lf := sk.find_bone("L_Foot")
	var rf := sk.find_bone("R_Foot")
	if lf < 0 or rf < 0:
		return out
	# Transformação do esqueleto até o modelo (sem depender da árvore de cena).
	var xf := Transform3D.IDENTITY
	var n: Node = sk
	while n != null and n != _rig:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	for key: String in ["walk", "run"]:
		if not _anim_names.has(key):
			continue
		var a := _anim.get_animation(_anim_names[key])
		_anim.play(_anim_names[key])
		_anim.speed_scale = 1.0
		const N := 48
		var prev: Array = []
		var speeds: Array[float] = []
		for k in N + 1:
			_anim.seek(a.length * k / N, true)
			var cur := [xf * sk.get_bone_global_pose(lf).origin, xf * sk.get_bone_global_pose(rf).origin]
			if not prev.is_empty():
				var i := 0 if (prev[0] as Vector3).y < (prev[1] as Vector3).y else 1
				var d: Vector3 = cur[i] - prev[i]
				speeds.append(Vector2(d.x, d.z).length() / (a.length / N))
			prev = cur
		speeds.sort()
		var med: float = speeds[speeds.size() / 2]
		if med > 0.05:
			out[key] = med / height
	_anim.stop()
	_current = ""
	return out

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
	if ground_speed >= 0.0 and _stride.has("walk"):
		_animate_stride()
	elif speed_ratio > _run_threshold and _anim_names.has("run"):
		_play("run", 0.15, clampf(speed_ratio, 0.8, 1.4))
	elif speed_ratio > 0.05:
		_play("walk", 0.15, clampf(speed_ratio / maxf(0.1, _run_threshold), 0.6, 1.5))
	else:
		_play("idle", 0.25)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_set_overlay(null)

## Escolhe andar/correr pela velocidade real e toca a animação no ritmo do passo medido.
func _animate_stride() -> void:
	var walk_nat: float = _stride["walk"]
	var run_nat: float = _stride.get("run", walk_nat * 2.6)
	var gs := ground_speed
	if gs < 0.2:
		_play("idle", 0.25)
		return
	if gs > walk_nat * 1.7 and _anim_names.has("run"):
		_play("run", 0.18, clampf(gs / run_nat, 0.6, 2.0))
	else:
		_play("walk", 0.18, clampf(gs / walk_nat, 0.5, 2.2))
	if backpedal:
		_anim.speed_scale = -absf(_anim.speed_scale)

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
	_aim_left = maxf(0.0, _aim_left - delta)
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

# --- Arco do Caçador (feito no Blender) e pose de mira procedural ------------------

const BOW_SCENE := "res://assets/models/blender/bow.glb"
const BOW_SCALE := 1.3
var _bow: Node3D
var _skel: Skeleton3D
var _bones: Dictionary = {}
var _aim_left: float = 0.0
var _aim_total: float = 0.0
var _aim_target: Vector3

## Arco na mão esquerda (o machado do modelo fica na direita, para coletar).
func attach_bow() -> void:
	if not _rigged or _bow != null or not ResourceLoader.exists(BOW_SCENE):
		return
	var sks := _rig.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	_skel = sks[0] as Skeleton3D
	for n in ["L_Upperarm", "L_Forearm", "L_Hand", "R_Upperarm", "R_Forearm", "R_Hand"]:
		_bones[n] = _skel.find_bone(n)
	if int(_bones["L_Hand"]) < 0:
		return
	_bow = (load(BOW_SCENE) as PackedScene).instantiate() as Node3D
	_bow.name = "Bow"
	_bow.top_level = true
	add_child(_bow)
	if _anim:
		_anim.mixer_applied.connect(_after_anim)

## Espada longa na mão direita (Cavaleiro): presa ao osso da mão, gira junto com o pulso nos golpes.
var _sword: Node3D

func attach_sword() -> void:
	if not _rigged or _sword != null:
		return
	var sks := _rig.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk := sks[0] as Skeleton3D
	var hand := sk.find_bone("R_Hand")
	if hand < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "R_Hand"
	sk.add_child(att)
	_sword = _make_sword()
	_sword.visible = false
	att.add_child(_sword)
	# A pose de empunhadura é medida na primeira atualização da animação (a mão já na pose de "parado").
	if _anim:
		_anim.mixer_applied.connect(_fit_sword.bind(sk, hand), CONNECT_ONE_SHOT | CONNECT_DEFERRED)
	else:
		_fit_sword(sk, hand)

func _fit_sword(sk: Skeleton3D, hand: int) -> void:
	if not is_instance_valid(_sword):
		return
	# Empunhada à frente, lâmina para cima e um pouco para fora (pronta para o golpe).
	var hand_g := sk.global_transform * sk.get_bone_global_pose(hand)
	var fwd := -global_transform.basis.z.normalized()
	var right := global_transform.basis.x.normalized()
	var blade := (Vector3.UP * 0.8 + fwd * 0.5 + right * 0.2).normalized()
	var side := blade.cross(fwd).normalized()
	var want := Transform3D(Basis(side, blade, side.cross(blade).normalized()), hand_g.origin - blade * 0.02)
	_sword.transform = hand_g.affine_inverse() * want
	_sword.visible = true

func _make_sword() -> Node3D:
	var root := Node3D.new()
	root.name = "Sword"
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.72, 0.74, 0.78)
	steel.metallic = 0.85
	steel.roughness = 0.32
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.85, 0.62, 0.24)
	gold.metallic = 0.9
	gold.roughness = 0.35
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.16, 0.1, 0.07)
	leather.roughness = 0.85
	var parts := [
		[_sw_box(Vector3(0.075, 0.95, 0.018)), Vector3(0, 0.6, 0), steel],
		[_sw_box(Vector3(0.02, 0.9, 0.024)), Vector3(0, 0.6, 0), steel],
		[_sw_box(Vector3(0.3, 0.045, 0.06)), Vector3(0, 0.1, 0), gold],
		[_sw_box(Vector3(0.04, 0.2, 0.04)), Vector3(0, -0.02, 0), leather],
		[_sw_ball(0.035), Vector3(0, -0.14, 0), gold],
	]
	for p: Array in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.position = p[1]
		mi.material_override = p[2]
		root.add_child(mi)
	# Ponta da lâmina.
	var tip := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.075, 0.14, 0.018)
	tip.mesh = pm
	tip.position = Vector3(0, 1.145, 0)
	tip.material_override = steel
	root.add_child(tip)
	return root

static func _sw_box(sz: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = sz
	return bm

static func _sw_ball(r: float) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	return sm

func has_bow() -> bool:
	return _bow != null

## Puxa a corda e mira no ponto (mundo) por `duration` segundos.
func aim_bow(target: Vector3, duration: float) -> void:
	_aim_target = target
	_aim_total = maxf(0.05, duration)
	_aim_left = _aim_total
	if _anim and _anim.process_mode == Node.PROCESS_MODE_DISABLED:
		_anim.process_mode = Node.PROCESS_MODE_INHERIT

## Depois da animação de cada quadro: sobrepõe os braços na pose de arqueiro e posiciona o arco.
func _after_anim() -> void:
	if _bow == null or _skel == null:
		return
	var w := 0.0
	if _aim_left > 0.0 and not _dead:
		var t := 1.0 - _aim_left / _aim_total
		w = smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.72, 1.0, t))
	if w > 0.01:
		_apply_aim(w)
	var hand := _skel.global_transform * _skel.get_bone_global_pose(int(_bones["L_Hand"])).origin
	var basis := Basis(Vector3.UP, rotation.y)
	# Mirando: o arco inclina um pouco; parado: pendurado ao lado, sem enterrar no chão.
	basis = basis * Basis(Vector3(0, 0, 1), deg_to_rad(-12.0) * w)
	var pos := hand
	pos.y = maxf(pos.y, global_position.y + lerpf(0.85, 0.0, w))
	_bow.global_transform = Transform3D(basis.scaled(Vector3.ONE * BOW_SCALE), pos)

func _apply_aim(w: float) -> void:
	var inv := _skel.global_transform.affine_inverse()
	var shoulder := _skel.get_bone_global_pose(int(_bones["L_Upperarm"])).origin
	var fwd := (inv * _aim_target) - shoulder
	var up_s := (inv.basis * Vector3.UP).normalized()
	# Mira quase horizontal (o alvo está no chão; o braço não aponta para os pés).
	fwd = fwd - up_s * fwd.dot(up_s) * 0.8
	if fwd.length_squared() < 1e-6:
		return
	fwd = fwd.normalized()
	var right := fwd.cross(up_s).normalized()
	_aim_bone("L_Upperarm", "L_Forearm", fwd, w)
	_aim_bone("L_Forearm", "L_Hand", fwd, w)
	# Braço da corda: cotovelo para trás e para o lado, mão volta até o queixo.
	_aim_bone("R_Upperarm", "R_Forearm", (-fwd * 0.45 + right * 0.9).normalized(), w)
	_aim_bone("R_Forearm", "R_Hand", (fwd * 0.6 - right * 0.8 + up_s * 0.15).normalized(), w)

func _aim_bone(bone: String, child: String, dir: Vector3, w: float) -> void:
	var b := int(_bones.get(bone, -1))
	var c := int(_bones.get(child, -1))
	if b < 0 or c < 0:
		return
	var g := _skel.get_bone_global_pose(b)
	var cur := _skel.get_bone_global_pose(c).origin - g.origin
	if cur.length_squared() < 1e-10:
		return
	var q := Quaternion.IDENTITY.slerp(Quaternion(cur.normalized(), dir), w)
	var new_basis := Basis(q) * g.basis
	var p := _skel.get_bone_parent(b)
	var pb := _skel.get_bone_global_pose(p).basis if p >= 0 else Basis()
	_skel.set_bone_pose_rotation(b, (pb.inverse() * new_basis).get_rotation_quaternion())

# --- Terror: tingimento, olhos brilhantes e transparência --------------------------

static var _tint_cache: Dictionary = {}
static var _eye_mats: Dictionary = {}  # cor -> material compartilhado
static var _eye_mesh: QuadMesh
static var eye_intensity: float = 0.0

## Multiplica a cor das malhas (materiais tingidos compartilhados entre indivíduos).
func _tint_meshes(tint: Color) -> void:
	for mi in _meshes:
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i) as BaseMaterial3D
			if m == null:
				continue
			var key := "%d_%s" % [m.get_instance_id(), tint.to_html()]
			if not _tint_cache.has(key):
				var d := m.duplicate() as BaseMaterial3D
				d.albedo_color = m.albedo_color * tint
				_tint_cache[key] = d
			mi.set_surface_override_material(i, _tint_cache[key])

## Dois pontos de luz presos ao osso da cabeça; acendem à noite (eye_intensity).
func add_glow_eyes(color: Color, height: float) -> void:
	if _rig == null or not is_inside_tree():
		return
	var sks := _rig.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk := sks[0] as Skeleton3D
	var head := -1
	for i in sk.get_bone_count():
		var bn := sk.get_bone_name(i).to_lower()
		if bn == "head" or bn.ends_with(":head") or bn.ends_with("_head"):
			head = i
			break
	if head < 0:
		for i in sk.get_bone_count():
			if sk.get_bone_name(i).to_lower().contains("head"):
				head = i
				break
	if head < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = sk.get_bone_name(head)
	sk.add_child(att)
	# Ponto dos olhos no espaço do modelo: um pouco acima e à frente da base da cabeça.
	var bone_g := sk.global_transform * sk.get_bone_global_rest(head)
	var eye_g := bone_g.origin + global_transform.basis * (Vector3(0, 0.16, -0.17) * height / 2.0) / global_transform.basis.get_scale()
	var eye := MeshInstance3D.new()
	eye.name = "Eyes"
	eye.mesh = _eyes_quad()
	eye.material_override = eye_material(color)
	eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	eye.scale = Vector3.ONE * clampf(height / 2.0, 0.8, 2.2)
	att.add_child(eye)
	eye.position = bone_g.affine_inverse() * eye_g

static func _eyes_quad() -> QuadMesh:
	if _eye_mesh == null:
		_eye_mesh = QuadMesh.new()
		_eye_mesh.size = Vector2(0.62, 0.26)
	return _eye_mesh

static func eye_material(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not _eye_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = _eye_shader()
		m.set_shader_parameter("tex", _eyes_texture())
		m.set_shader_parameter("color", color)
		m.set_shader_parameter("intensity", eye_intensity)
		_eye_mats[key] = m
	return _eye_mats[key]

static var _eye_sh: Shader
## Billboard aditivo puxado 0,35 m em direção à câmera: a câmera alta vê os olhos
## mesmo com a cabeça inclinada (sem atravessar paredes, que estão bem mais longe).
static func _eye_shader() -> Shader:
	if _eye_sh == null:
		_eye_sh = Shader.new()
		_eye_sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear;
uniform vec4 color : source_color = vec4(1.0, 0.25, 0.1, 1.0);
uniform float intensity = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.z += 0.35;
	POSITION = PROJECTION_MATRIX * vp;
}
void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = color.rgb * (1.4 + 2.0 * t.r);
	ALPHA = t.a * intensity;
}
"""
	return _eye_sh

## Brilho dos olhos de todos os inimigos (0 de dia .. 1 à noite).
static func set_eye_intensity(k: float) -> void:
	if absf(k - eye_intensity) < 0.01:
		return
	eye_intensity = k
	for key: String in _eye_mats:
		(_eye_mats[key] as ShaderMaterial).set_shader_parameter("intensity", k)

static var _eye_tex: ImageTexture
static func _eyes_texture() -> ImageTexture:
	if _eye_tex == null:
		var w := 64
		var h := 24
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				# Dois pontos fortes com um halo suave em volta.
				var a := 0.0
				var halo := 0.0
				for cx: float in [21.0, 43.0]:
					var d := Vector2((x - cx) / 4.5, (y - 12.0) / 3.2).length()
					a = maxf(a, clampf(1.0 - d, 0.0, 1.0))
					halo = maxf(halo, clampf(1.0 - d / 3.2, 0.0, 1.0))
				var core := clampf(a * 1.8, 0.0, 1.0)
				img.set_pixel(x, y, Color(core, core, core, maxf(core, halo * halo * 0.55)))
		_eye_tex = ImageTexture.create_from_image(img)
	return _eye_tex

## 0 = opaco, 1 = invisível (Espreitador fora da luz).
func set_transparency(t: float) -> void:
	# Os olhos não estão em _meshes: continuam visíveis no escuro.
	for mi in _meshes:
		mi.transparency = t
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if t > 0.5 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

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
