class_name Soldier
extends CharacterBody3D
## Soldado do exército (recrutado no Quartel). Obedece à ordem do Army:
## defender um posto na base, seguir um herói ou caçar zumbis perto da base.

enum State { IDLE, MOVE, ENGAGE, DEAD }

const THINK_INTERVAL := 0.25
const SEPARATION := 1.2
const DIRECT_DISTANCE := 6.0

static var all: Array[Soldier] = []

var def: SoldierDef
var army: Army
var level_mult: float = 1.0
var state: State = State.IDLE
var health: HealthComponent
var model: CharacterModel
var post: Vector3 = Vector3.ZERO
## Coop: no cliente o soldado é um fantoche (estado vindo do anfitrião).
var puppet: bool = false
var net_attack_count: int = 0

var _target: Enemy = null
var _goal: Vector3
var _think_left: float = 0.0
var _attack_cd: float = 0.0
var _windup: float = -1.0
var _rng := RandomNumberGenerator.new()
var _last_nav: Vector3 = Vector3.INF
var _sep: Vector3 = Vector3.ZERO
var _p_target: Vector3
var _p_yaw: float = 0.0
var _p_speed: float = 0.0
var _p_atk: int = 0
var _detour: Vector3 = Vector3.ZERO
var _detour_t: float = 0.0
var _blocked_t: float = 0.0

@onready var nav: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
	add_to_group("allies")
	add_to_group("soldiers")
	collision_layer = Layers.HERO
	collision_mask = Layers.WORLD | Layers.STRUCTURES
	_rng.randomize()
	health = $Health as HealthComponent
	health.setup(def.max_health * level_mult, def.armor)
	health.regen_per_second = 2.5
	health.died.connect(_on_died)
	health.damaged.connect(func(_i: DamageInfo, _a: float) -> void: model.flash())
	model = $Model as CharacterModel
	model.build_hero(def.skin)
	model.scale *= 0.88
	($HealthBar as HealthBar3D).bind(health)
	_add_team_ring()
	_goal = global_position
	_p_target = global_position
	_think_left = _rng.randf() * THINK_INTERVAL
	all.append(self)

func _exit_tree() -> void:
	all.erase(self)

func _add_team_ring() -> void:
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.42
	t.outer_radius = 0.55
	t.rings = 16
	t.ring_segments = 4
	ring.mesh = t
	ring.scale = Vector3(1, 0.15, 1)
	ring.position.y = 0.06
	ring.material_override = MaterialLib.unshaded(Color(0.3, 0.65, 1.0, 0.8))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

func is_dead() -> bool:
	return state == State.DEAD

func get_radius() -> float:
	return 0.45

func damage() -> float:
	return def.damage * level_mult * (1.0 + Tech.bonus("hero_damage_pct") * 0.5)

func take_damage(info: DamageInfo) -> void:
	if state == State.DEAD or puppet:
		return
	health.take_damage(info)
	# Revida contra quem atacou.
	if info.source is Enemy and not (info.source as Enemy).is_dead() and _target == null:
		_target = info.source as Enemy

# --- IA -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if puppet:
		_puppet_process(delta)
		return
	if not GameManager.is_playing():
		model.animate(delta, 0.0)
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = THINK_INTERVAL
		_think()
	var move := Vector3.ZERO
	var speed := def.move_speed
	if _target_ok():
		var d := _flat_dist(_target.global_position)
		var reach := def.attack_range + _target.get_radius()
		if d <= reach:
			state = State.ENGAGE
			_face(_target.global_position, delta)
			_try_attack()
		else:
			state = State.MOVE
			move = _dir_to(_target.global_position, d)
	else:
		var gd := _flat_dist(_goal)
		if gd > 1.2:
			state = State.MOVE
			move = _dir_to(_goal, gd)
			if gd < 3.0:
				speed *= 0.6
			elif gd > 8.0 and army and army.order == Army.Order.FOLLOW:
				speed *= 1.5  # corre para alcançar o herói
		else:
			state = State.IDLE
	if _windup >= 0.0:
		_windup -= delta
		speed *= 0.2
		if _windup < 0.0:
			_resolve_attack()
	# Desvio: construções não estão na malha de navegação; se emperrar, contorna.
	if _detour_t > 0.0 and move != Vector3.ZERO:
		_detour_t -= delta
		move = (_detour * 0.8 + move * 0.2).normalized()
	var v := move + _sep * 0.5
	if v.length() > 1.0:
		v = v.normalized()
	velocity.x = v.x * speed
	velocity.z = v.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 30.0 * delta
	var before := global_position
	move_and_slide()
	if move != Vector3.ZERO and _detour_t <= 0.0 and Vector2(global_position.x - before.x, global_position.z - before.z).length() < speed * delta * 0.25:
		_blocked_t += delta
		if _blocked_t > 0.3:
			_blocked_t = 0.0
			_start_detour(move)
	else:
		_blocked_t = 0.0
	global_position.y = maxf(global_position.y, 0.0)
	if move != Vector3.ZERO and state != State.ENGAGE:
		_face(global_position + move, delta)
	model.animate(delta, Vector2(velocity.x, velocity.z).length() / def.move_speed)

func _think() -> void:
	_update_separation()
	var order := army.order if army else Army.Order.DEFEND
	var anchor := army.anchor_for(self) if army else global_position
	_goal = anchor
	var leash := 18.0
	var search_from := global_position
	match order:
		Army.Order.DEFEND:
			search_from = post
			leash = 16.0
		Army.Order.FOLLOW:
			search_from = anchor
			leash = 14.0
		Army.Order.HUNT:
			leash = 65.0
			search_from = Vector3.ZERO
	# Larga o alvo se morreu ou se afastou demais da área da ordem.
	if _target and (not _target_ok() or _flat(_target.global_position, search_from) > leash):
		_target = null
	if _target == null:
		var radius := def.aggro_range if order != Army.Order.HUNT else leash
		_target = _nearest_enemy(search_from, radius)

func _nearest_enemy(from: Vector3, radius: float) -> Enemy:
	var best: Enemy = null
	var bd := radius * radius
	for e in Enemy.all:
		if not is_instance_valid(e) or e.is_dead() or not e.is_targetable():
			continue
		var d := Vector2(e.global_position.x - from.x, e.global_position.z - from.z).length_squared()
		# Dentro da área da ordem, vai no que estiver mais perto do próprio soldado.
		if d <= bd and (best == null or global_position.distance_squared_to(e.global_position) < global_position.distance_squared_to(best.global_position)):
			best = e
	return best

func _target_ok() -> bool:
	return _target != null and is_instance_valid(_target) and not _target.is_dead()

func _try_attack() -> void:
	if _attack_cd > 0.0 or _windup >= 0.0:
		return
	_attack_cd = def.attack_cooldown
	_windup = minf(0.35, def.attack_cooldown * 0.35)
	model.play_attack(_windup + 0.25)
	net_attack_count += 1

func _resolve_attack() -> void:
	if not _target_ok():
		return
	var crit := _rng.randf() < 0.1
	var info := DamageInfo.make(damage() * (1.7 if crit else 1.0), self, crit)
	var from := global_position + Vector3.UP * 1.4
	match def.attack:
		SoldierDef.Attack.MELEE:
			if _flat_dist(_target.global_position) <= def.attack_range + _target.get_radius() + 0.6:
				_target.take_damage(info)
				AudioManager.play_3d(&"hit", _target.global_position, -6.0)
		SoldierDef.Attack.ARROW:
			EffectsHub.spawn_arrow(from, _target, info, 30.0)
			Coop.fx("arrow", from, _target.global_position + Vector3.UP)
			AudioManager.play_3d(&"arrow", from, -8.0, 1.3, 90)
		SoldierDef.Attack.MAGIC:
			var to := _target.global_position
			to.y = 0.2
			var r := def.splash_radius
			var dmg := info.amount
			var dur := clampf(from.distance_to(to) / 18.0, 0.3, 1.0)
			AudioManager.play_3d(&"ab_nova", from, -8.0, 1.4)
			Coop.fx("lob", from, to, dur)
			EffectsHub.spawn_lob(from, to, dur, 2.5, func() -> void:
				EffectsHub.spawn_explosion(to, r, Color(0.55, 0.35, 1.0))
				for e in Enemy.all.duplicate():
					if is_instance_valid(e) and not e.is_dead() and _flat(e.global_position, to) <= r + e.get_radius():
						e.take_damage(DamageInfo.make(dmg, self if is_instance_valid(self) else null)))

# --- Movimento -------------------------------------------------------------------

func _dir_to(p: Vector3, dist: float) -> Vector3:
	if dist < DIRECT_DISTANCE:
		var to := p - global_position
		to.y = 0.0
		return to.normalized()
	if _last_nav.distance_squared_to(p) > 1.0:
		nav.target_position = p
		_last_nav = p
	if nav.is_navigation_finished():
		var t2 := p - global_position
		t2.y = 0.0
		return t2.normalized()
	var nxt := nav.get_next_path_position() - global_position
	nxt.y = 0.0
	return nxt.normalized() if nxt.length() > 0.05 else Vector3.ZERO

func _start_detour(move: Vector3) -> void:
	var left := move.rotated(Vector3.UP, PI * 0.5)
	var right := -left
	var free_l := not test_move(global_transform, left * 1.2)
	var free_r := not test_move(global_transform, right * 1.2)
	if free_l and free_r:
		_detour = left if _rng.randf() < 0.5 else right
	elif free_l:
		_detour = left
	elif free_r:
		_detour = right
	else:
		_detour = -move
	_detour_t = 0.9

func _update_separation() -> void:
	var push := Vector3.ZERO
	for o in all:
		if o == self or o.is_dead():
			continue
		var d := global_position - o.global_position
		d.y = 0.0
		var l := d.length()
		if l < SEPARATION and l > 0.001:
			push += d / l * (1.0 - l / SEPARATION)
	_sep = push

func _face(p: Vector3, delta: float) -> void:
	var to := p - global_position
	to.y = 0.0
	if to.length_squared() > 0.0001:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-to.x, -to.z), clampf(delta * 10.0, 0.0, 1.0))

func _flat_dist(p: Vector3) -> float:
	return _flat(global_position, p)

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# --- Morte -----------------------------------------------------------------------

func _on_died(_info: DamageInfo) -> void:
	state = State.DEAD
	collision_layer = 0
	remove_from_group("allies")
	remove_from_group("soldiers")
	($HealthBar as HealthBar3D).visible = false
	model.play_death()
	AudioManager.play_3d(&"hero_hurt", global_position, -4.0, 0.85)
	if army:
		army.on_soldier_died(self)
	get_tree().create_timer(3.0).timeout.connect(queue_free)

# --- Coop (cliente) --------------------------------------------------------------

func apply_net_state(pos: Vector3, yaw: float, hp: float, speed: float, atk: int) -> void:
	_p_target = pos
	_p_yaw = yaw
	_p_speed = speed
	health.current = clampf(hp, 1.0, health.max_health)
	health.changed.emit(health.current, health.max_health)
	if atk != _p_atk:
		_p_atk = atk
		model.play_attack(0.5)

func _puppet_process(delta: float) -> void:
	if global_position.distance_to(_p_target) > 10.0:
		global_position = _p_target
	else:
		global_position = global_position.lerp(_p_target, clampf(delta * 10.0, 0.0, 1.0))
	model.rotation.y = lerp_angle(model.rotation.y, _p_yaw, clampf(delta * 10.0, 0.0, 1.0))
	model.animate(delta, _p_speed)

func puppet_die() -> void:
	if state == State.DEAD:
		return
	_on_died(null)

func to_save() -> Dictionary:
	return {"id": String(def.id), "pos": [global_position.x, global_position.z], "hp": health.current}
