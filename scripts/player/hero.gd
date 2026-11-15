class_name Hero
extends CharacterBody3D
## Herói controlado pelo jogador: movimento (WASD / clique direito), ataque corpo a
## corpo em arco, coleta, interação, consumíveis, morte e renascimento na base.

signal attack_cooldown_changed(ratio: float)
signal stats_changed
signal leveled_up(level: int)

@export_group("Atributos")
@export var max_health: float = 220.0
@export var armor: float = 2.0
@export var base_damage: float = 24.0
@export var attacks_per_second: float = 1.15
@export var crit_chance: float = 0.12
@export var crit_multiplier: float = 1.8
@export var move_speed: float = 6.8
@export var attack_range: float = 2.6
@export_range(10.0, 360.0) var attack_arc_degrees: float = 120.0
@export var health_regen: float = 2.0
@export var interact_range: float = 2.8
@export var respawn_time: float = 10.0

const SHARPEN_BONUS := 4.0
## Ganho por nível (a árvore de atributos completa vem na Fase 2).
const LEVEL_HP := 25.0
const LEVEL_DAMAGE := 3.0

var level: int = 1
var xp: int = 0

var weapon_level: int = 0
## Modo toque (celular): ataque pelo botão, mira automática, toque no mundo = mover/atacar.
var touch_mode: bool = false
var touch_attack_held: bool = false
## Durante o modo de construção, cliques/toques posicionam a construção.
var build_mode: bool = false
var health: HealthComponent
var model: CharacterModel
var _camera: Camera3D
var _attack_timer: float = 0.0
var _pending_hit: float = -1.0
var _aim_point: Vector3
var _move_target: Vector3
var _has_move_target: bool = false
var _target_enemy: Enemy = null
var _interact_target: Lootable = null
var _interact_time: float = 0.0
var _respawn_left: float = 0.0
var _rng := RandomNumberGenerator.new()
var _home: Vector3 = Vector3.ZERO

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
	add_to_group("hero")
	add_to_group("allies")
	collision_layer = Layers.HERO
	collision_mask = Layers.WORLD | Layers.STRUCTURES
	health = $Health as HealthComponent
	health.setup(max_health, armor)
	health.regen_per_second = health_regen
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	model = $Model as CharacterModel
	model.build_hero()
	($HealthBar as HealthBar3D).bind(health)
	_home = global_position
	GameManager.hero = self
	touch_mode = Platform.touch
	EventBus.enemy_killed.connect(_on_enemy_killed)
	# Lanterna: luz quente ao redor do herói durante a noite (grupo night_lights).
	var lantern := OmniLight3D.new()
	lantern.light_color = Color(1.0, 0.75, 0.45)
	lantern.light_energy = 1.4
	lantern.omni_range = 10.0
	lantern.position = Vector3(0, 2.6, 0)
	lantern.visible = false
	add_child(lantern)
	add_to_group("night_lights")

func set_camera(cam: Camera3D) -> void:
	_camera = cam

func set_home(p: Vector3) -> void:
	_home = p

func damage() -> float:
	return base_damage + weapon_level * SHARPEN_BONUS + (level - 1) * LEVEL_DAMAGE

func xp_to_next() -> int:
	return 60 + (level - 1) * 45

func add_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		health.max_health = max_health + (level - 1) * LEVEL_HP
		health.heal(health.max_health)
		leveled_up.emit(level)
		EventBus.banner.emit("NÍVEL %d!" % level, "+%d de vida máxima • +%d de dano" % [int(LEVEL_HP), int(LEVEL_DAMAGE)], UIStyle.GOLD)
		AudioManager.play(&"dawn")
	stats_changed.emit()

func _on_enemy_killed(_e: Node3D, def: EnemyDef, killer: Node) -> void:
	if killer == self and def:
		var mult := 1
		if _e is Enemy:
			mult = 15 if (_e as Enemy).is_boss else (4 if (_e as Enemy).is_elite else 1)
		add_xp(def.xp_reward * mult)

func is_dead() -> bool:
	return health.dead

func _physics_process(delta: float) -> void:
	if health.dead:
		_process_respawn(delta)
		return
	if not GameManager.is_playing():
		velocity = Vector3.ZERO
		model.animate(delta, 0.0)
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	attack_cooldown_changed.emit(_attack_timer * attacks_per_second)
	var dir := _input_direction()
	if dir != Vector3.ZERO:
		_has_move_target = false
		_target_enemy = null
	var want_attack: bool
	if build_mode:
		want_attack = false
	elif touch_mode:
		want_attack = touch_attack_held
		if want_attack:
			_auto_aim(dir)
	else:
		_update_aim()
		want_attack = Input.is_action_pressed("attack") and not _mouse_over_ui()
		if touch_attack_held:
			want_attack = true
			_auto_aim(dir)
	if want_attack:
		_target_enemy = null
		_has_move_target = false

	# Perseguir alvo selecionado (clique direito em inimigo)
	if _target_enemy != null:
		if not is_instance_valid(_target_enemy) or _target_enemy.is_dead():
			_target_enemy = null
		else:
			var to := _target_enemy.global_position - global_position
			to.y = 0.0
			if to.length() <= attack_range * 0.9:
				_aim_point = _target_enemy.global_position
				want_attack = true
			else:
				_set_move_target(_target_enemy.global_position)

	if _has_move_target and dir == Vector3.ZERO:
		dir = _follow_path()

	var speed := move_speed * (0.55 if _pending_hit >= 0.0 else 1.0)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 30.0 * delta
	move_and_slide()
	global_position.y = maxf(global_position.y, 0.0)

	if dir != Vector3.ZERO:
		_cancel_interaction()
	if want_attack:
		_face(_aim_point, delta, 30.0)
		if _attack_timer <= 0.0:
			_start_attack()
	elif dir != Vector3.ZERO:
		_face(global_position + dir, delta, 14.0)

	if _pending_hit >= 0.0:
		_pending_hit -= delta
		if _pending_hit < 0.0:
			_apply_hit()

	_process_interaction(delta)
	model.animate(delta, Vector2(velocity.x, velocity.z).length() / move_speed)

func _input_direction() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down", 0.12)
	if v == Vector2.ZERO or _camera == null:
		return Vector3.ZERO
	var basis := _camera.global_transform.basis
	var fwd := -basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := basis.x
	right.y = 0.0
	right = right.normalized()
	return (right * v.x - fwd * v.y).normalized()

func _unhandled_input(event: InputEvent) -> void:
	if health.dead or not GameManager.is_playing() or build_mode:
		return
	if event.is_action_pressed("command") or (touch_mode and event.is_action_pressed("attack")):
		# No celular, tocar no mundo funciona como o clique direito do PC.
		_on_command_click()
	elif event.is_action_pressed("attack"):
		var hit := _raycast_mouse(Layers.ENEMIES | Layers.STRUCTURES | Layers.INTERACTABLES | Layers.WORLD)
		if hit and _selectable(hit):
			EventBus.object_selected.emit(hit)
	elif event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("use_slot_1"):
		use_consumable(&"meat")
	elif event.is_action_pressed("use_slot_2"):
		use_consumable(&"bandage")

func _selectable(n: Node) -> bool:
	return n.is_in_group("enemies") or n.is_in_group("structures") or n.is_in_group("interactable") or n.is_in_group("harvestable")

func _on_command_click() -> void:
	var hit := _raycast_mouse(Layers.ENEMIES | Layers.STRUCTURES | Layers.INTERACTABLES | Layers.WORLD)
	if hit and _selectable(hit):
		EventBus.object_selected.emit(hit)
		if hit.is_in_group("enemies"):
			_target_enemy = hit as Enemy
			return
		if hit is Lootable:
			_set_move_target((hit as Node3D).global_position)
			_interact_target = hit as Lootable
			return
	var p: Variant = _mouse_ground_point()
	if p != null:
		_target_enemy = null
		_set_move_target(p)
		EffectsHub.spawn_marker(p)

func _set_move_target(p: Vector3) -> void:
	if not _has_move_target or _move_target.distance_squared_to(p) > 0.25:
		nav_agent.target_position = p
	_move_target = p
	_has_move_target = true

func _follow_path() -> Vector3:
	if nav_agent.is_navigation_finished():
		_has_move_target = false
		if _interact_target and is_instance_valid(_interact_target):
			_begin_interaction(_interact_target)
		return Vector3.ZERO
	var next := nav_agent.get_next_path_position()
	var d := next - global_position
	d.y = 0.0
	if d.length() < 0.05:
		return Vector3.ZERO
	return d.normalized()

func _face(point: Vector3, delta: float, speed: float) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-to.x, -to.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_yaw, clampf(delta * speed, 0.0, 1.0))

func facing() -> Vector3:
	return Vector3(-sin(model.rotation.y), 0.0, -cos(model.rotation.y))

# --- Combate -------------------------------------------------------------

func _start_attack() -> void:
	var dur := 1.0 / attacks_per_second
	_attack_timer = dur
	_pending_hit = dur * 0.3
	model.play_attack(dur * 0.85)
	AudioManager.play_3d(&"swing", global_position, -6.0)

func _apply_hit() -> void:
	var fwd := facing()
	var half_arc := deg_to_rad(attack_arc_degrees * 0.5)
	var hit_any := false
	for e: Node in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en == null or en.is_dead():
			continue
		if _in_arc(en.global_position, fwd, half_arc, attack_range + en.get_radius()):
			var crit := _rng.randf() < crit_chance
			var info := DamageInfo.make(damage() * (crit_multiplier if crit else 1.0), self, crit)
			en.take_damage(info)
			hit_any = true
	for h: Node in get_tree().get_nodes_in_group("harvestable"):
		var hv := h as Harvestable
		if hv and _in_arc(hv.global_position, fwd, half_arc, attack_range + 0.8):
			hv.harvest(self)
			hit_any = true
	if hit_any:
		EffectsHub.spawn_slash(global_position + Vector3.UP * 1.0 + fwd * 1.3, model.rotation.y)

func _in_arc(p: Vector3, fwd: Vector3, half_arc: float, reach: float) -> bool:
	var to := p - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > reach:
		return false
	if dist < 0.6:
		return true
	return fwd.angle_to(to / dist) <= half_arc

func take_damage(info: DamageInfo) -> void:
	health.take_damage(info)

func get_radius() -> float:
	return 0.45

func _on_damaged(_info: DamageInfo, amount: float) -> void:
	model.flash()
	EventBus.hero_damaged.emit(amount)
	AudioManager.play_3d(&"hero_hurt", global_position, -4.0)

func _on_died(_info: DamageInfo) -> void:
	_cancel_interaction()
	_target_enemy = null
	_has_move_target = false
	velocity = Vector3.ZERO
	model.play_death()
	collision_layer = 0
	remove_from_group("allies")
	_respawn_left = respawn_time * (1.5 if TimeManager.is_night() else 1.0)
	# A mochila cai no chão onde o herói morreu.
	var bag := ResourceManager.hero_inventory.items()
	ResourceManager.hero_inventory.clear()
	for id: StringName in bag:
		EffectsHub.drop_item(global_position, id, bag[id])
	EventBus.hero_died.emit()
	EventBus.banner.emit("VOCÊ CAIU", "Renascendo na base em %d segundos..." % int(_respawn_left), Color(0.85, 0.2, 0.15))

func respawn_seconds_left() -> float:
	return _respawn_left

func _process_respawn(delta: float) -> void:
	if not GameManager.is_playing():
		return
	_respawn_left -= delta
	if _respawn_left <= 0.0:
		respawn()

func respawn() -> void:
	global_position = _home
	velocity = Vector3.ZERO
	health.revive(1.0)
	model.reset_pose()
	collision_layer = Layers.HERO
	add_to_group("allies")
	EventBus.hero_respawned.emit()
	EventBus.notify("O herói voltou à base.", Color(0.6, 0.9, 1.0))

# --- Consumíveis ----------------------------------------------------------

func use_consumable(id: StringName) -> void:
	var def := ResourceManager.get_def(id)
	if def == null or health.dead:
		return
	if health.current >= health.max_health and def.heal_over_time <= 0.0:
		EventBus.notify("Vida já está cheia.", Color(0.8, 0.8, 0.8))
		return
	# Usa da mochila; dentro da base também pode usar o armazém.
	if ResourceManager.hero_inventory.remove(id, 1) == 0:
		if not (BaseZone.hero_inside and ResourceManager.storage.remove(id, 1) == 1):
			EventBus.notify("Sem %s." % def.display_name, Color(1, 0.6, 0.4))
			return
	if def.heal_instant > 0.0:
		health.heal(def.heal_instant)
	if def.heal_over_time > 0.0:
		health.heal_over_time(def.heal_over_time, def.heal_duration)
	EffectsHub.spawn_heal(global_position)
	AudioManager.play_3d(&"heal", global_position)

# --- Interação ------------------------------------------------------------

## Mira automática (celular): inimigo mais próximo, depois recurso, senão para frente.
func _auto_aim(move_dir: Vector3) -> void:
	var best: Node3D = null
	var best_d := attack_range + 3.0
	for e: Node in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en and not en.is_dead():
			var d := en.global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				best = en
	if best == null:
		best_d = attack_range + 1.2
		for h: Node in get_tree().get_nodes_in_group("harvestable"):
			var hv := h as Node3D
			var d2 := hv.global_position.distance_to(global_position)
			if d2 < best_d:
				best_d = d2
				best = hv
	if best:
		_aim_point = best.global_position
	elif move_dir != Vector3.ZERO:
		_aim_point = global_position + move_dir * 2.0
	else:
		_aim_point = global_position + facing() * 2.0

func try_interact() -> void:
	_try_interact()

func _try_interact() -> void:
	var best: Lootable = null
	var best_d := interact_range
	for n: Node in get_tree().get_nodes_in_group("interactable"):
		var it := n as Lootable
		if it == null or not it.can_interact():
			continue
		var d := it.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = it
	if best:
		_begin_interaction(best)
	else:
		EventBus.notify("Nada para saquear por perto.", Color(0.8, 0.8, 0.8))

func _begin_interaction(it: Lootable) -> void:
	_interact_target = null
	if not it.can_interact() or it.global_position.distance_to(global_position) > interact_range + 0.6:
		return
	_interact_target = it
	_interact_time = 0.0
	_face(it.global_position, 1.0, 100.0)

func _process_interaction(delta: float) -> void:
	if _interact_target == null or _has_move_target:
		return
	if not is_instance_valid(_interact_target) or not _interact_target.can_interact():
		_cancel_interaction()
		return
	_interact_time += delta
	var need := _interact_target.interact_duration()
	EventBus.interaction_progress.emit(_interact_target.interact_label(), _interact_time / need)
	if _interact_time >= need:
		var t := _interact_target
		_interact_target = null
		EventBus.interaction_progress.emit("", -1.0)
		t.interact(self)

func _cancel_interaction() -> void:
	if _interact_target != null:
		_interact_target = null
		EventBus.interaction_progress.emit("", -1.0)

# --- Mouse ----------------------------------------------------------------

func _mouse_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func _update_aim() -> void:
	var p: Variant = _mouse_ground_point()
	if p != null:
		_aim_point = p

func _mouse_ground_point() -> Variant:
	if _camera == null:
		return null
	var mp := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mp)
	var dir := _camera.project_ray_normal(mp)
	var plane := Plane(Vector3.UP, 0.0)
	return plane.intersects_ray(from, dir)

func _raycast_mouse(mask: int) -> Node:
	if _camera == null:
		return null
	var mp := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mp)
	var to := from + _camera.project_ray_normal(mp) * 300.0
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.collide_with_areas = true
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	return res.get("collider") as Node if res else null

# --- Salvamento -----------------------------------------------------------

func to_save() -> Dictionary:
	return {"pos": [global_position.x, global_position.y, global_position.z], "hp": health.current, "weapon_level": weapon_level, "level": level, "xp": xp}

func from_save(d: Dictionary) -> void:
	var p: Array = d.get("pos", [0, 0, 0])
	global_position = Vector3(p[0], p[1], p[2])
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	health.max_health = max_health + (level - 1) * LEVEL_HP
	health.current = clampf(float(d.get("hp", max_health)), 1.0, health.max_health)
	health.changed.emit(health.current, health.max_health)
	weapon_level = int(d.get("weapon_level", 0))
	stats_changed.emit()
