class_name Enemy
extends CharacterBody3D
## Inimigo genérico configurado por um EnemyDef. IA em máquina de estados com
## "pensamento" em baixa frequência (escalonado) e movimento por NavigationAgent3D.

enum State { IDLE, WANDER, CHASE, ATTACK, SIEGE, RETURN, DEAD }

const THINK_INTERVAL := 0.25
const SLEEP_DISTANCE := 75.0
const LEASH_DISTANCE := 38.0
const SEPARATION_RADIUS := 1.1
const DIRECT_CHASE_DISTANCE := 7.0

static var all: Array[Enemy] = []

@export var def: EnemyDef

var state: State = State.IDLE
var is_horde: bool = false
var is_elite: bool = false
var health: HealthComponent
var model: CharacterModel
var damage_value: float = 8.0
var speed_value: float = 3.0

var _target: Node3D = null       # herói ou estrutura sendo atacada
var _home: Vector3
var _wander_point: Vector3
var _think_left: float = 0.0
var _attack_cd: float = 0.0
var _windup: float = -1.0
var _stuck_time: float = 0.0
var _last_pos: Vector3
var _separation: Vector3 = Vector3.ZERO
var _burning: float = -1.0
var _rng := RandomNumberGenerator.new()
var _last_nav_target: Vector3 = Vector3.INF

# Especiais (explosivo / cuspidor / saltador)
const LEAP_TIME := 0.6
const LEAP_HEIGHT := 2.6
const LEAP_MIN := 3.5
const LEAP_WINDUP := 0.3
var _special_cd: float = 0.0

# Coop: no cliente o inimigo é um "fantoche" movido pelo estado do anfitrião.
var puppet: bool = false
var puppet_target: Vector3
var net_attack_count: int = 0
var _puppet_yaw: float = 0.0
var _puppet_speed: float = 0.0
var _puppet_atk: int = 0
var _exploded: bool = false
var _leap_wind: float = -1.0
var _leap_t: float = -1.0
var _leap_from: Vector3
var _leap_to: Vector3

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = Layers.ENEMIES
	collision_mask = Layers.WORLD | Layers.STRUCTURES | Layers.GATE
	_rng.randomize()
	health = $Health as HealthComponent
	model = $Model as CharacterModel
	if def:
		configure(def)
	all.append(self)

func _exit_tree() -> void:
	all.erase(self)

func configure(d: EnemyDef, hp_mult: float = 1.0, dmg_mult: float = 1.0) -> void:
	def = d
	health.setup(d.max_health * hp_mult * GameManager.diff_value("enemy_hp"), d.armor)
	damage_value = d.damage * dmg_mult * GameManager.diff_value("enemy_damage")
	speed_value = d.move_speed * _rng.randf_range(0.9, 1.1)
	if not health.died.is_connected(_on_died):
		health.died.connect(_on_died)
		health.damaged.connect(_on_damaged)
	if model.get_child_count() == 0:
		model.build_zombie(d)
	var shape := ($CollisionShape3D as CollisionShape3D).shape as CapsuleShape3D
	shape.radius = 0.4 * d.model_scale
	shape.height = 1.8 * d.model_scale
	($CollisionShape3D as CollisionShape3D).position.y = 0.9 * d.model_scale
	var bar := $HealthBar as HealthBar3D
	bar.position.y = 2.75 * d.model_scale
	bar.bind(health)
	_home = global_position
	_wander_point = _home
	_last_pos = global_position
	_think_left = _rng.randf() * THINK_INTERVAL

func make_elite() -> void:
	is_elite = true
	health.setup(health.max_health * 3.0, health.armor + 3.0)
	damage_value *= 1.6
	model.scale *= 1.3
	($HealthBar as HealthBar3D).position.y *= 1.3
	var aura := OmniLight3D.new()
	aura.light_color = Color(1.0, 0.55, 0.1)
	aura.light_energy = 2.0
	aura.omni_range = 4.0
	aura.position.y = 1.5
	add_child(aura)

var is_boss: bool = false
var _stun_left: float = 0.0

## Atordoa (para de andar e de atacar). Chefes ficam atordoados por menos tempo.
func stun(seconds: float) -> void:
	if state == State.DEAD or _leap_t >= 0.0:
		return
	if puppet:
		Coop.hit_enemy(self, 0.0, false, seconds)
		return
	_stun_left = maxf(_stun_left, seconds * (0.35 if is_boss else 1.0))

func is_stunned() -> bool:
	return _stun_left > 0.0

## Chefe das hordas 10, 20, ...: gigante, muito resistente e com aura vermelha.
func make_boss() -> void:
	is_boss = true
	is_elite = true
	health.setup(health.max_health * 12.0, health.armor + 6.0)
	damage_value *= 2.2
	speed_value *= 0.85
	model.scale *= 1.7
	($HealthBar as HealthBar3D).position.y *= 1.7
	(($CollisionShape3D as CollisionShape3D).shape as CapsuleShape3D).radius *= 1.6
	var aura := OmniLight3D.new()
	aura.light_color = Color(1.0, 0.15, 0.1)
	aura.light_energy = 3.0
	aura.omni_range = 6.0
	aura.position.y = 2.5
	add_child(aura)

func start_siege() -> void:
	is_horde = true
	state = State.SIEGE

func display_name() -> String:
	return ("Chefe: " if is_boss else ("Elite: " if is_elite else "")) + def.display_name

func is_dead() -> bool:
	return state == State.DEAD

func get_radius() -> float:
	return 0.45 * (def.model_scale if def else 1.0)

func take_damage(info: DamageInfo) -> void:
	if state == State.DEAD:
		return
	if puppet:
		# Cliente: o anfitrião aplica o dano; aqui só o retorno visual imediato.
		if info.source is Hero and not (info.source as Hero).is_puppet:
			Coop.hit_enemy(self, info.amount, info.is_crit)
			model.flash()
			EffectsHub.spawn_blood(global_position + Vector3.UP * 1.1 * def.model_scale, info.is_crit)
			EffectsHub.float_text(global_position + Vector3.UP * 2.4 * def.model_scale, str(int(info.amount)), Color(1.0, 0.85, 0.3) if info.is_crit else Color.WHITE, 40 if info.is_crit else 32)
		return
	health.take_damage(info)
	# Revida contra quem o atacou (se for o herói/aliado e estiver perto).
	if state != State.DEAD and info.source is Node3D and (info.source as Node3D).is_in_group("allies"):
		var src := info.source as Node3D
		if src.global_position.distance_to(global_position) < def.aggro_range * 1.5:
			_target = src
			if state != State.ATTACK:
				state = State.CHASE

# --- Laço principal -------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if puppet:
		_puppet_process(delta)
		return
	if _burning >= 0.0:
		_process_burn(delta)
	if _stun_left > 0.0:
		_stun_left -= delta
		velocity = Vector3.ZERO
		_windup = -1.0
		model.animate(delta, 0.0)
		return
	var hero := nearest_hero()
	# Inimigos diurnos muito longe do herói "dormem" (economia de CPU).
	if not is_horde and hero and hero.global_position.distance_to(global_position) > SLEEP_DISTANCE:
		return
	_special_cd = maxf(0.0, _special_cd - delta)
	if _leap_wind >= 0.0 or _leap_t >= 0.0:
		_process_leap(delta)
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = THINK_INTERVAL
		_think()

	var move_dir := Vector3.ZERO
	var speed := speed_value
	match state:
		State.WANDER, State.RETURN:
			move_dir = _nav_direction(_wander_point if state == State.WANDER else _home)
			speed *= 0.45
		State.CHASE:
			if _target_valid():
				var td := _dist_to(_target)
				if def.behavior == EnemyDef.Behavior.LEAPER and _special_cd <= 0.0 and td > LEAP_MIN and td <= def.special_range:
					_begin_leap(_target.global_position)
					return
				if td <= def.attack_range + _target_radius():
					# Chegou ao alcance: para já neste quadro (sem esperar o "pensar").
					state = State.ATTACK
					_try_attack()
				elif td < DIRECT_CHASE_DISTANCE:
					# De perto, persegue em linha reta (o caminho da navegação atrasa).
					var to := _target.global_position - global_position
					to.y = 0.0
					move_dir = to.normalized()
				else:
					move_dir = _nav_direction(_target.global_position)
				if def.behavior == EnemyDef.Behavior.CHARGER and td < 7.0:
					speed *= 1.35
		State.SIEGE:
			if GameManager.base_core:
				move_dir = _nav_direction(GameManager.base_core.global_position)
		State.ATTACK:
			if _target_valid():
				_face(_target.global_position, delta)
				# Cuspidor mantém distância do herói (recua enquanto cospe).
				if def.behavior == EnemyDef.Behavior.SPITTER and _target is Hero and _dist_to(_target) < def.special_range:
					var away := global_position - _target.global_position
					away.y = 0.0
					move_dir = away.normalized()
					speed *= 0.8
	if _windup >= 0.0:
		_windup -= delta
		speed *= 0.2
		if _windup < 0.0:
			_resolve_attack()

	var sep_w := 0.25 if state == State.ATTACK else 0.6
	var v := (move_dir + _separation * sep_w)
	if v.length() > 1.0:
		v = v.normalized()
	velocity.x = v.x * speed
	velocity.z = v.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 30.0 * delta
	move_and_slide()
	if move_dir != Vector3.ZERO and state != State.ATTACK:
		_face(global_position + move_dir, delta)
	_check_blockers()
	model.animate(delta, Vector2(velocity.x, velocity.z).length() / maxf(0.1, def.move_speed))

func _think() -> void:
	_update_separation()
	if (state == State.CHASE or state == State.SIEGE) and _rng.randf() < 0.025:
		var h := GameManager.hero as Node3D
		if h and h.global_position.distance_to(global_position) < 22.0 and not Coop.is_host():
			AudioManager.play_3d(&"skeleton" if _is_skeleton() else &"groan", global_position, -8.0, 1.0 / maxf(0.7, def.model_scale), 600)
	var hero := nearest_hero()
	var hero_ok := hero != null and not hero.is_dead()
	var hero_d := _dist_to(hero) if hero_ok else INF

	# Ataque em andamento: continua enquanto o alvo estiver ao alcance.
	if state == State.ATTACK:
		if not _target_valid() or _dist_to(_target) > def.attack_range + _target_radius() + 0.6:
			_target = null
			state = State.SIEGE if is_horde else State.CHASE
		else:
			_try_attack()
			return

	# Alvos vivos próximos têm prioridade.
	if hero_ok and hero_d <= def.aggro_range:
		_target = hero
		state = State.CHASE
	elif state == State.CHASE:
		if not _target_valid() or (_target is Hero and hero_d > def.aggro_range * 1.8):
			_target = null
			state = State.SIEGE if is_horde else State.RETURN
		elif not is_horde and global_position.distance_to(_home) > LEASH_DISTANCE:
			_target = null
			state = State.RETURN

	match state:
		State.IDLE:
			if _rng.randf() < 0.3:
				_wander_point = _home + Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-8, 8))
				state = State.WANDER
		State.WANDER:
			if global_position.distance_to(_wander_point) < 1.5 or _rng.randf() < 0.05:
				state = State.IDLE
		State.RETURN:
			if global_position.distance_to(_home) < 3.0:
				state = State.IDLE
		State.CHASE:
			if _target_valid() and _dist_to(_target) <= def.attack_range + _target_radius():
				state = State.ATTACK
				_try_attack()
		State.SIEGE:
			var core := GameManager.base_core
			if core and _dist_to(core) <= def.attack_range + _target_radius_of(core):
				_target = core
				state = State.ATTACK
			_update_stuck()

func _try_attack() -> void:
	if _attack_cd > 0.0 or _windup >= 0.0:
		return
	if def.behavior == EnemyDef.Behavior.EXPLODER:
		_start_fuse()
		net_attack_count += 1
		return
	_attack_cd = def.attack_cooldown
	_windup = minf(0.45, def.attack_cooldown * 0.4)
	model.play_attack(_windup + 0.2)
	net_attack_count += 1

func _resolve_attack() -> void:
	if def.behavior == EnemyDef.Behavior.EXPLODER:
		_explode(true, self)
		return
	if not _target_valid():
		return
	if _dist_to(_target) > def.attack_range + _target_radius() + 0.8:
		return
	if def.behavior == EnemyDef.Behavior.SPITTER:
		var to := (_target as Structure).closest_point(global_position) if _target is Structure else _target.global_position
		var fwd := (to - global_position)
		fwd.y = 0.0
		var from := global_position + Vector3.UP * 1.6 * def.model_scale + fwd.normalized() * 0.5
		AcidProjectile.launch(get_parent(), from, to, self, damage_value * def.special_mult, def)
		Coop.fx("acid", from, to, def.special_radius, def.special_color)
		AudioManager.play_3d(&"spit", global_position, -2.0)
		return
	var info := DamageInfo.make(damage_value, self)
	info.structure_multiplier = def.structure_damage_mult
	_target.call(&"take_damage", info)
	AudioManager.play_3d(&"zombie_hit", global_position, -6.0)

# --- Muros e bloqueios ----------------------------------------------------

## Se esbarrar em uma estrutura (muro, portão), passa a atacá-la — o Saltador pula por cima.
func _check_blockers() -> void:
	if state == State.ATTACK or state == State.DEAD:
		return
	if state != State.SIEGE and state != State.CHASE:
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i).get_collider() as Node
		if col and col.is_in_group("structures") and not col.call(&"is_dead"):
			if def.behavior == EnemyDef.Behavior.LEAPER and _special_cd <= 0.0 and col != GameManager.base_core and _leap_over_wall():
				return
			_target = col as Node3D
			state = State.ATTACK
			return

func _update_stuck() -> void:
	if global_position.distance_to(_last_pos) < 0.4:
		_stuck_time += THINK_INTERVAL
	else:
		_stuck_time = 0.0
	_last_pos = global_position
	if _stuck_time > 1.5:
		_stuck_time = 0.0
		var s := _nearest_structure(4.0)
		if s:
			_target = s
			state = State.ATTACK

func _nearest_structure(max_d: float) -> Node3D:
	var best: Node3D = null
	var bd := max_d
	for n: Node in get_tree().get_nodes_in_group("structures"):
		var s := n as Node3D
		if s.call(&"is_dead"):
			continue
		var d := _dist_to(s) - _target_radius_of(s)
		if d < bd:
			bd = d
			best = s
	return best

# --- Navegação ------------------------------------------------------------

func _nav_direction(target: Vector3) -> Vector3:
	if _last_nav_target.distance_squared_to(target) > 1.0:
		nav_agent.target_position = target
		_last_nav_target = target
	if nav_agent.is_navigation_finished():
		var d := target - global_position
		d.y = 0.0
		return d.normalized() if d.length() > 0.3 else Vector3.ZERO
	var next := nav_agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	return dir.normalized() if dir.length() > 0.05 else Vector3.ZERO

func _update_separation() -> void:
	var push := Vector3.ZERO
	var p := global_position
	for o in all:
		if o == self or o.state == State.DEAD:
			continue
		var d := p - o.global_position
		d.y = 0.0
		var l := d.length()
		var r := SEPARATION_RADIUS * (def.model_scale + o.def.model_scale) * 0.5
		if l < r and l > 0.001:
			push += d / l * (1.0 - l / r)
	# Não entra "dentro" do herói: mantém o raio dele + o próprio.
	var hero := nearest_hero()
	if hero and not hero.is_dead():
		var dh := p - hero.global_position
		dh.y = 0.0
		var lh := dh.length()
		var rh := hero.get_radius() + get_radius() + 0.35
		if lh < rh and lh > 0.001:
			push += dh / lh * (1.0 - lh / rh) * 2.0
	_separation = push

func _face(point: Vector3, delta: float) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-to.x, -to.z), clampf(delta * 10.0, 0.0, 1.0))

func _target_valid() -> bool:
	return _target != null and is_instance_valid(_target) and not _target.call(&"is_dead")

func _dist_to(n: Node3D) -> float:
	var tp := (n as Structure).closest_point(global_position) if n is Structure else n.global_position
	var d := tp - global_position
	d.y = 0.0
	return d.length()

func _target_radius() -> float:
	return _target_radius_of(_target) if _target_valid() else 0.0

func _target_radius_of(n: Node3D) -> float:
	return float(n.call(&"get_radius"))

# --- Morte / amanhecer ----------------------------------------------------

func _on_damaged(info: DamageInfo, _amount: float) -> void:
	model.flash()
	EffectsHub.spawn_blood(global_position + Vector3.UP * 1.1 * def.model_scale, info.is_crit)

func _on_died(info: DamageInfo) -> void:
	Coop.enemy_died(self, info.source if info else null)
	var was_leaping := _leap_t >= 0.0
	state = State.DEAD
	_leap_wind = -1.0
	_leap_t = -1.0
	if was_leaping:
		global_position.y = 0.0
	# Explosivo abatido explode (fere também os zumbis próximos).
	if def.behavior == EnemyDef.Behavior.EXPLODER and not _exploded and _burning < 0.0:
		_explode.call_deferred(false, info.source if info else null)
	collision_layer = 0
	collision_mask = Layers.WORLD
	velocity = Vector3.ZERO
	remove_from_group("enemies")
	($HealthBar as HealthBar3D).visible = false
	model.play_death()
	AudioManager.play_3d(&"skeleton" if _is_skeleton() else &"zombie_death", global_position, -3.0, 1.0 / maxf(0.7, def.model_scale))
	var burned := _burning >= 0.0
	if not burned and def.loot:
		var drops := def.loot.roll(_rng, 8.0 if is_boss else (2.5 if is_elite else 1.0))
		for id: StringName in drops:
			EffectsHub.drop_item(global_position, id, drops[id])
		var gi := Gear.enemy_drop(_rng, is_boss, is_elite, def.special_radius > 0.0 or def.behavior >= EnemyDef.Behavior.EXPLODER)
		if gi:
			EffectsHub.drop_gear(global_position, gi)
	EventBus.enemy_killed.emit(self, def, info.source if info else null)
	get_tree().create_timer(3.0).timeout.connect(queue_free)

## Ao amanhecer, os zumbis da horda queimam sob a luz do sol.
func burn() -> void:
	if state == State.DEAD or _burning >= 0.0:
		return
	_burning = 0.0
	var fire := EffectsHub.attach_fire(self)
	fire.position.y = 1.0 * def.model_scale

func _process_burn(delta: float) -> void:
	_burning += delta
	if fmod(_burning, 0.5) < delta:
		var info := DamageInfo.make(health.max_health * 0.12, null)
		info.type = DamageInfo.Type.TRUE
		health.take_damage(info)

# --- Especiais ------------------------------------------------------------

## Explosivo: incha e brilha durante o pavio, depois explode.
func _start_fuse() -> void:
	_attack_cd = 999.0
	_windup = def.special_time
	model.play_attack(def.special_time)
	var glow := OmniLight3D.new()
	glow.light_color = def.special_color
	glow.light_energy = 0.0
	glow.omni_range = def.special_radius
	glow.position.y = 1.2 * def.model_scale
	add_child(glow)
	var tw := create_tween()
	tw.tween_property(glow, "light_energy", 5.0, def.special_time)
	tw.parallel().tween_property(model, "scale", model.scale * 1.25, def.special_time)
	AudioManager.play_3d(&"fuse", global_position, 2.0)

## full = explodiu por conta própria (dano cheio e morre); senão foi abatido
## (dano menor ao herói, mas fere os zumbis ao redor — crédito para quem o matou).
func _explode(full: bool, credit: Node) -> void:
	if _exploded:
		return
	_exploded = true
	var r := def.special_radius
	var center := global_position
	center.y = 0.0
	EffectsHub.spawn_explosion(center, r, def.special_color)
	Coop.fx("explosion", center, Vector3.ZERO, r, def.special_color)
	AudioManager.play_3d(&"explosion", center, 4.0)
	var dmg := damage_value * def.special_mult * (1.0 if full else 0.6)
	for n: Node in get_tree().get_nodes_in_group("allies"):
		var a := n as Node3D
		if a and not a.call(&"is_dead") and _flat_dist(a.global_position, center) <= r + float(a.call(&"get_radius")):
			a.call(&"take_damage", DamageInfo.make(dmg, self))
	for n: Node in get_tree().get_nodes_in_group("structures"):
		var st := n as Structure
		if st and not st.is_dead() and _flat_dist(st.closest_point(center), center) <= r:
			var info := DamageInfo.make(dmg, self)
			info.structure_multiplier = def.structure_damage_mult
			st.take_damage(info)
	if not full:
		for e in all.duplicate():
			if e != self and is_instance_valid(e) and not e.is_dead() and _flat_dist(e.global_position, center) <= r:
				e.take_damage(DamageInfo.make(dmg * 1.5, credit if is_instance_valid(credit) else null))
	if full and state != State.DEAD:
		var kill := DamageInfo.make(health.current + 9999.0, null)
		kill.type = DamageInfo.Type.TRUE
		health.take_damage(kill)

static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## Saltador: agacha e salta em arco até o ponto (ignora muros no ar).
func _begin_leap(to: Vector3) -> void:
	var d := to - global_position
	d.y = 0.0
	if d.length() > def.special_range:
		d = d.normalized() * def.special_range
	_leap_from = global_position
	_leap_to = global_position + d
	_leap_to.y = 0.0
	_leap_wind = LEAP_WINDUP
	_special_cd = def.special_time
	_windup = -1.0
	velocity = Vector3.ZERO
	model.play_attack(LEAP_WINDUP + LEAP_TIME * 0.5)

## Durante o cerco, ao bater num muro, salta na direção do núcleo.
func _leap_over_wall() -> bool:
	var core := GameManager.base_core
	if core == null:
		return false
	var to := core.global_position - global_position
	to.y = 0.0
	var dist := minf(def.special_range, to.length() - 2.5)
	if dist < LEAP_MIN:
		return false
	_begin_leap(global_position + to.normalized() * dist)
	return true

func _process_leap(delta: float) -> void:
	if _leap_wind >= 0.0:
		_leap_wind -= delta
		velocity = Vector3.ZERO
		_face(_leap_to, delta * 3.0)
		model.animate(delta, 0.0)
		if _leap_wind < 0.0:
			_leap_t = 0.0
			collision_mask = Layers.WORLD
			AudioManager.play_3d(&"leap", global_position, -1.0)
		return
	_leap_t += delta / LEAP_TIME
	var t := minf(_leap_t, 1.0)
	var p := _leap_from.lerp(_leap_to, t)
	p.y = sin(t * PI) * LEAP_HEIGHT
	global_position = p
	model.animate(delta, 1.0)
	if _leap_t < 1.0:
		return
	_leap_t = -1.0
	global_position.y = 0.0
	collision_mask = Layers.WORLD | Layers.STRUCTURES | Layers.GATE
	EffectsHub.spawn_ring(global_position + Vector3.UP * 0.1, def.special_radius, def.special_color, 0.35)
	Coop.fx("ring", global_position + Vector3.UP * 0.1, Vector3.ZERO, def.special_radius, def.special_color)
	EffectsHub.spawn_debris(global_position + Vector3.UP * 0.3, false)
	for n: Node in get_tree().get_nodes_in_group("allies"):
		var a := n as Node3D
		if a and not a.call(&"is_dead") and _flat_dist(a.global_position, global_position) <= def.special_radius + float(a.call(&"get_radius")):
			a.call(&"take_damage", DamageInfo.make(damage_value * def.special_mult, self))
	_attack_cd = minf(_attack_cd, 0.4)
	_stuck_time = 0.0

func _is_skeleton() -> bool:
	return def != null and String(def.id).begins_with("skeleton")

# --- Coop -------------------------------------------------------------------

## Herói vivo mais próximo (local ou de outro jogador); senão qualquer um.
func nearest_hero() -> Hero:
	var best: Hero = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("hero"):
		var h := n as Hero
		if h == null:
			continue
		var d := h.global_position.distance_squared_to(global_position) + (1.0e6 if h.is_dead() else 0.0)
		if d < bd:
			bd = d
			best = h
	return best

func apply_net_state(pos: Vector3, yaw: float, hp: float, speed: float, atk: int) -> void:
	puppet_target = pos
	_puppet_yaw = yaw
	_puppet_speed = speed
	health.current = clampf(hp, 1.0, health.max_health)
	health.changed.emit(health.current, health.max_health)
	if atk != _puppet_atk:
		_puppet_atk = atk
		model.play_attack(0.55)

func _puppet_process(delta: float) -> void:
	var d := puppet_target - global_position
	if d.length() > 10.0:
		global_position = puppet_target
	else:
		global_position = global_position.lerp(puppet_target, clampf(delta * 10.0, 0.0, 1.0))
	model.rotation.y = lerp_angle(model.rotation.y, _puppet_yaw, clampf(delta * 10.0, 0.0, 1.0))
	model.animate(delta, _puppet_speed)

## Cliente: o anfitrião avisou que morreu (sem saque; o anfitrião replica os itens).
func puppet_die(killer: Node) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	collision_layer = 0
	remove_from_group("enemies")
	($HealthBar as HealthBar3D).visible = false
	model.play_death()
	AudioManager.play_3d(&"skeleton" if _is_skeleton() else &"zombie_death", global_position, -3.0)
	EventBus.enemy_killed.emit(self, def, killer)
	get_tree().create_timer(3.0).timeout.connect(queue_free)
