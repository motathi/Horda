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
	if _burning >= 0.0:
		_process_burn(delta)
	var hero := GameManager.hero
	# Inimigos diurnos muito longe do herói "dormem" (economia de CPU).
	if not is_horde and hero and hero.global_position.distance_to(global_position) > SLEEP_DISTANCE:
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
	if move_dir != Vector3.ZERO:
		_face(global_position + move_dir, delta)
	_check_blockers()
	model.animate(delta, Vector2(velocity.x, velocity.z).length() / maxf(0.1, def.move_speed))

func _think() -> void:
	_update_separation()
	var hero := GameManager.hero as Hero
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
	_attack_cd = def.attack_cooldown
	_windup = minf(0.45, def.attack_cooldown * 0.4)
	model.play_attack(_windup + 0.2)

func _resolve_attack() -> void:
	if not _target_valid():
		return
	if _dist_to(_target) > def.attack_range + _target_radius() + 0.8:
		return
	var info := DamageInfo.make(damage_value, self)
	info.structure_multiplier = def.structure_damage_mult
	_target.call(&"take_damage", info)
	AudioManager.play_3d(&"zombie_hit", global_position, -8.0)

# --- Muros e bloqueios ----------------------------------------------------

## Se esbarrar em uma estrutura (muro, portão), passa a atacá-la.
func _check_blockers() -> void:
	if state == State.ATTACK or state == State.DEAD:
		return
	if state != State.SIEGE and state != State.CHASE:
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i).get_collider() as Node
		if col and col.is_in_group("structures") and not col.call(&"is_dead"):
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
	var hero := GameManager.hero as Hero
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
	state = State.DEAD
	collision_layer = 0
	collision_mask = Layers.WORLD
	velocity = Vector3.ZERO
	remove_from_group("enemies")
	($HealthBar as HealthBar3D).visible = false
	model.play_death()
	AudioManager.play_3d(&"zombie_death", global_position, -4.0)
	var burned := _burning >= 0.0
	if not burned and def.loot:
		var drops := def.loot.roll(_rng, 8.0 if is_boss else (2.5 if is_elite else 1.0))
		for id: StringName in drops:
			EffectsHub.drop_item(global_position, id, drops[id])
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
