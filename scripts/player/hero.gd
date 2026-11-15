class_name Hero
extends CharacterBody3D
## Herói controlado pelo jogador: movimento (WASD / clique direito), ataque corpo a
## corpo em arco, coleta, interação, consumíveis, morte e renascimento na base.

signal attack_cooldown_changed(ratio: float)
signal stats_changed
signal leveled_up(level: int)
signal ability_cast(index: int)
signal gear_changed

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

# --- Habilidades ---------------------------------------------------------------
const ABILITY_IDS: Array[StringName] = [&"whirlwind", &"dash", &"warcry", &"nova"]
const DASH_SPEED := 34.0
var abilities: Array[AbilityDef] = []
var max_energy: float = 100.0
var energy: float = 100.0
var energy_regen: float = 6.0
var _cd: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _armor_buff_left: float = 0.0
var _armor_buff: float = 0.0
var _dash_left: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _dash_hit: Dictionary = {}
var _dash_power: float = 1.0
var _dash_def: AbilityDef

var weapon_level: int = 0

# Atributos distribuídos pelo jogador (3 pontos por nível; bônus em data/config/attributes.tres).
const ATTRIBUTES_PATH := "res://data/config/attributes.tres"
var attr_cfg: AttributeConfig
var attributes: Dictionary = {}  # StringName -> int
var attr_points: int = 0

# Equipamento: espaço (EquipmentDef.Slot) -> GearItem, e bolsa de itens não equipados.
var equipment: Dictionary = {}

# Coop: herói de outro jogador (movido pelo estado recebido pela rede).
var is_puppet: bool = false
var net_peer: int = 1
var skin_override: String = ""
## Conta golpes/habilidades: os outros jogadores tocam a animação quando muda.
var net_attack_count: int = 0
var _net_target: Vector3
var _net_yaw: float = 0.0
var _net_speed: float = 0.0
var _net_atk: int = 0
var _net_has_state: bool = false
var gear_bag: Array[GearItem] = []
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
var _step_t: float = 0.0
var _stuck_t: float = 0.0
var _overlap_t: float = 0.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
	add_to_group("hero")
	add_to_group("allies")
	collision_layer = Layers.HERO
	collision_mask = Layers.WORLD | Layers.STRUCTURES
	health = $Health as HealthComponent
	attr_cfg = load(ATTRIBUTES_PATH) as AttributeConfig
	for id in AttributeConfig.IDS:
		attributes[id] = 0
	health.setup(max_health, armor)
	health.regen_per_second = health_regen
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	model = $Model as CharacterModel
	model.build_hero(skin_override)
	($HealthBar as HealthBar3D).bind(health)
	_home = global_position
	if is_puppet:
		_setup_puppet()
	else:
		GameManager.hero = self
		net_peer = Net.my_id()
	touch_mode = Platform.touch
	EventBus.enemy_killed.connect(_on_enemy_killed)
	for id in ABILITY_IDS:
		abilities.append(load("res://data/skills/%s.tres" % id) as AbilityDef)
	# Lanterna: luz quente ao redor do herói durante a noite (grupo night_lights).
	var lantern := OmniLight3D.new()
	lantern.light_color = Color(1.0, 0.75, 0.45)
	lantern.light_energy = 1.4
	lantern.omni_range = 10.0
	lantern.position = Vector3(0, 2.6, 0)
	lantern.visible = false
	add_child(lantern)
	add_to_group("night_lights")
	# Equipamento inicial: um machado comum.
	var axe := Gear.get_def(&"axe")
	if axe and equipment.is_empty():
		equipment[axe.slot] = Gear.make_item(axe, 0, 1, _rng)
	_recalc_stats(false)

func set_camera(cam: Camera3D) -> void:
	_camera = cam

func set_home(p: Vector3) -> void:
	_home = p

func damage() -> float:
	return (base_damage + gear(&"damage") + weapon_level * SHARPEN_BONUS + (level - 1) * LEVEL_DAMAGE) * (1.0 + attr(&"strength") * attr_cfg.str_damage_pct + Tech.bonus("hero_damage_pct"))

## Alcance do golpe (lança aumenta).
func reach() -> float:
	return attack_range + gear(&"reach")

## Chamado pelo Tech ao concluir uma pesquisa.
func refresh_tech() -> void:
	_recalc_stats(true)

# --- Equipamento ----------------------------------------------------------

## Soma de um atributo em todos os itens equipados.
func gear(stat: StringName) -> float:
	var t := 0.0
	for it: GearItem in equipment.values():
		if it:
			t += it.stat(String(stat))
	return t

func equipped(slot: int) -> GearItem:
	return equipment.get(slot) as GearItem

## Equipa um item da bolsa (o antigo volta para a bolsa).
func equip(item: GearItem) -> String:
	if item == null or not gear_bag.has(item):
		return "Item não está na bolsa."
	gear_bag.erase(item)
	var old := equipped(item.def.slot)
	if old:
		gear_bag.append(old)
	equipment[item.def.slot] = item
	_recalc_stats(true)
	AudioManager.play(&"upgrade", -4.0)
	gear_changed.emit()
	return "Equipado: %s (%s)" % [item.display_name(), item.rarity_name()]

func unequip(slot: int) -> String:
	var it := equipped(slot)
	if it == null:
		return ""
	if gear_bag.size() >= Gear.BAG_SIZE:
		return "Bolsa de equipamentos cheia."
	equipment.erase(slot)
	gear_bag.append(it)
	_recalc_stats(true)
	gear_changed.emit()
	return "Removido: " + it.display_name()

## Adiciona à bolsa; false se estiver cheia.
func add_gear(item: GearItem) -> bool:
	if gear_bag.size() >= Gear.BAG_SIZE:
		return false
	gear_bag.append(item)
	gear_changed.emit()
	return true

## Desmonta um item da bolsa em recursos (vão para o armazém).
func salvage(item: GearItem) -> String:
	if not gear_bag.has(item):
		return "Só itens da bolsa podem ser desmontados."
	gear_bag.erase(item)
	var got := item.salvage_value()
	for id: StringName in got:
		ResourceManager.store(id, int(got[id]))
	AudioManager.play(&"break", -4.0)
	gear_changed.emit()
	return "Desmontado: %s → %s" % [item.display_name(), ResourceManager.cost_to_string(got)]

func _gear_save() -> Dictionary:
	var eq := {}
	for slot: int in equipment:
		if equipment[slot]:
			eq[str(slot)] = (equipment[slot] as GearItem).to_dict()
	return {"equipped": eq, "bag": gear_bag.map(func(g: GearItem) -> Dictionary: return g.to_dict())}

func _gear_load(d: Dictionary) -> void:
	equipment.clear()
	gear_bag.clear()
	var eq: Dictionary = d.get("equipped", {})
	for k: String in eq:
		var g := GearItem.from_dict(eq[k])
		if g:
			equipment[g.def.slot] = g
	for gd: Dictionary in d.get("bag", []):
		var g2 := GearItem.from_dict(gd)
		if g2:
			gear_bag.append(g2)

# --- Atributos ------------------------------------------------------------

func attr(id: StringName) -> int:
	return int(attributes.get(id, 0))

func attack_speed() -> float:
	return attacks_per_second * maxf(0.3, 1.0 + attr(&"agility") * attr_cfg.agi_attack_speed_pct + gear(&"attack_speed_pct"))

func current_move_speed() -> float:
	return move_speed * maxf(0.5, 1.0 + minf(attr(&"agility") * attr_cfg.agi_move_speed_pct, attr_cfg.agi_move_speed_cap) + gear(&"move_speed_pct"))

func crit() -> float:
	return minf(0.75, crit_chance + attr(&"agility") * attr_cfg.agi_crit + gear(&"crit"))

func ability_power() -> float:
	return 1.0 + attr(&"intelligence") * attr_cfg.int_power_pct + gear(&"ability_power_pct")

func cooldown_mult() -> float:
	return 1.0 - minf(attr(&"intelligence") * attr_cfg.int_cdr_pct + gear(&"cdr_pct") + Tech.bonus("cdr_pct"), attr_cfg.int_cdr_cap)

func total_max_health() -> float:
	return max_health + (level - 1) * LEVEL_HP + attr(&"vitality") * attr_cfg.vit_hp + gear(&"max_hp") + Tech.bonus("hero_hp")

## Armadura total: base + equipamento + Grito de Guerra.
func total_armor() -> float:
	return armor + gear(&"armor") + _armor_buff

func carry_capacity() -> int:
	return ResourceManager.HERO_CAPACITY + attr(&"strength") * attr_cfg.str_carry + int(Tech.bonus("carry"))

func building_hp_mult() -> float:
	return 1.0 + attr(&"engineering") * attr_cfg.eng_building_hp_pct

func building_damage_mult() -> float:
	return 1.0 + attr(&"engineering") * attr_cfg.eng_building_dmg_pct

func spent_points() -> int:
	var n := 0
	for id in AttributeConfig.IDS:
		n += attr(id)
	return n

## Gasta um ponto no atributo. Retorna "" ou o motivo da recusa.
func add_attribute(id: StringName) -> String:
	if not attributes.has(id):
		return "Atributo desconhecido."
	if attr_points <= 0:
		return "Sem pontos de atributo. Suba de nível para ganhar mais."
	attr_points -= 1
	attributes[id] = attr(id) + 1
	_recalc_stats(true)
	AudioManager.play(&"deposit", -4.0)
	return ""

func respec_cost() -> Dictionary:
	return {&"scrap": maxi(attr_cfg.respec_min_scrap, spent_points() * attr_cfg.respec_scrap_per_point)}

## Devolve todos os pontos gastos (custa sucata).
func respec() -> String:
	if spent_points() == 0:
		return "Nenhum ponto distribuído."
	var cost := respec_cost()
	if not ResourceManager.spend(cost):
		return "Recursos insuficientes: " + ResourceManager.cost_to_string(cost)
	attr_points += spent_points()
	for id in AttributeConfig.IDS:
		attributes[id] = 0
	_recalc_stats(true)
	return ""

## Recalcula vida, energia, regenerações e carga a partir de nível + atributos.
func _recalc_stats(keep_ratio: bool) -> void:
	var hp_ratio := health.ratio() if keep_ratio and health.max_health > 0.0 else -1.0
	var old_max := health.max_health
	health.max_health = total_max_health()
	if hp_ratio >= 0.0:
		# Ganhar vida máxima também cura a diferença; perder não mata.
		health.current = clampf(health.current + maxf(0.0, health.max_health - old_max), 1.0, health.max_health)
	else:
		health.current = minf(health.current, health.max_health)
	health.regen_per_second = health_regen + attr(&"vitality") * attr_cfg.vit_regen + gear(&"health_regen") + Tech.bonus("health_regen")
	health.armor = total_armor()
	health.changed.emit(health.current, health.max_health)
	max_energy = 100.0 + attr(&"intelligence") * attr_cfg.int_energy + gear(&"energy")
	energy_regen = 6.0 + attr(&"intelligence") * attr_cfg.int_energy_regen + Tech.bonus("energy_regen")
	energy = minf(energy, max_energy)
	if is_puppet:
		return
	ResourceManager.hero_inventory.capacity = carry_capacity()
	if is_inside_tree():
		get_tree().call_group("buildings", "refresh_stats")
	stats_changed.emit()

func xp_to_next() -> int:
	return 60 + (level - 1) * 45

func add_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		attr_points += attr_cfg.points_per_level
		_recalc_stats(false)
		health.heal(health.max_health)
		leveled_up.emit(level)
		EventBus.banner.emit("NÍVEL %d!" % level, "+%d pontos de atributo — toque no retrato (P)" % attr_cfg.points_per_level, UIStyle.GOLD)
		AudioManager.play(&"levelup", -2.0)
	stats_changed.emit()

func _on_enemy_killed(_e: Node3D, def: EnemyDef, killer: Node) -> void:
	if killer == self and def and not is_puppet:
		var mult := 1
		if _e is Enemy:
			mult = 15 if (_e as Enemy).is_boss else (4 if (_e as Enemy).is_elite else 1)
		add_xp(def.xp_reward * mult)

func is_dead() -> bool:
	return health.dead

func _physics_process(delta: float) -> void:
	if is_puppet:
		_puppet_process(delta)
		return
	if health.dead:
		_process_respawn(delta)
		return
	if not GameManager.is_playing():
		velocity = Vector3.ZERO
		model.animate(delta, 0.0)
		return
	_tick_abilities(delta)
	if _dash_left > 0.0:
		_process_dash(delta)
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	attack_cooldown_changed.emit(_attack_timer * attack_speed())
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
			if to.length() <= reach() * 0.9:
				_aim_point = _target_enemy.global_position
				want_attack = true
			else:
				_set_move_target(_target_enemy.global_position)

	if _has_move_target and dir == Vector3.ZERO:
		dir = _follow_path()

	var speed := current_move_speed() * (0.55 if _pending_hit >= 0.0 else 1.0)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 30.0 * delta
	var before := global_position
	move_and_slide()
	global_position.y = maxf(global_position.y, 0.0)
	_check_stuck(delta, dir, speed, before)

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
	var planar := Vector2(velocity.x, velocity.z).length()
	model.animate(delta, planar / current_move_speed())
	_footsteps(delta, planar)

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
	if is_puppet or health.dead or not GameManager.is_playing() or build_mode:
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
	else:
		for i in 4:
			if event.is_action_pressed("ability_%d" % (i + 1)):
				var why := cast_ability(i)
				if why != "":
					EventBus.notify(why, Color(1, 0.6, 0.45))

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

## Passos: pedra dentro da base, grama fora; cadência acompanha a velocidade.
func _footsteps(delta: float, planar_speed: float) -> void:
	if planar_speed < 0.8:
		_step_t = 0.0
		return
	_step_t -= delta * planar_speed / 6.8
	if _step_t <= 0.0:
		_step_t = 0.42
		var stone := global_position.length() < 14.0
		AudioManager.play_3d(&"step_stone" if stone else &"step_grass", global_position, -14.0, 1.0, 120)

# --- Combate -------------------------------------------------------------

func _start_attack() -> void:
	net_attack_count += 1
	var dur := 1.0 / attack_speed()
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
		if _in_arc(en.global_position, fwd, half_arc, reach() + en.get_radius()):
			var crit := _rng.randf() < crit()
			var info := DamageInfo.make(damage() * (crit_multiplier if crit else 1.0), self, crit)
			en.take_damage(info)
			hit_any = true
			var ls := gear(&"lifesteal_pct")
			if ls > 0.0:
				health.heal(info.amount * ls)
			AudioManager.play_3d(&"hit", en.global_position, -2.0 if crit else -5.0, 0.85 if crit else 1.0)
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
	if is_puppet:
		# O dono deste herói aplica o dano (armadura e vida são dele).
		if not health.dead:
			Coop.forward_hero_hit(net_peer, info)
		return
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
	energy = max_energy
	model.reset_pose()
	collision_layer = Layers.HERO
	add_to_group("allies")
	EventBus.hero_respawned.emit()
	EventBus.notify("O herói voltou à base.", Color(0.6, 0.9, 1.0))

# --- Habilidades ----------------------------------------------------------

func _tick_abilities(delta: float) -> void:
	energy = minf(max_energy, energy + energy_regen * delta)
	for i in 4:
		_cd[i] = maxf(0.0, _cd[i] - delta)
	if _armor_buff_left > 0.0:
		_armor_buff_left -= delta
		if _armor_buff_left <= 0.0:
			_armor_buff = 0.0
			health.armor = total_armor()
			stats_changed.emit()

func is_unlocked(i: int) -> bool:
	return level >= abilities[i].unlock_level

func cooldown_left(i: int) -> float:
	return _cd[i]

func cooldown_ratio(i: int) -> float:
	return _cd[i] / maxf(0.01, abilities[i].cooldown * cooldown_mult())

## "" se pode usar; senão o motivo.
func ability_block_reason(i: int) -> String:
	var a := abilities[i]
	if health.dead:
		return "Herói caído."
	if not is_unlocked(i):
		return "%s libera no nível %d." % [a.display_name, a.unlock_level]
	if _cd[i] > 0.0:
		return "%s em recarga (%.0fs)." % [a.display_name, ceil(_cd[i])]
	if energy < a.energy_cost:
		return "Energia insuficiente para %s." % a.display_name
	return ""

func cast_ability(i: int) -> String:
	if i < 0 or i >= abilities.size() or build_mode or not GameManager.is_playing():
		return ""
	var why := ability_block_reason(i)
	if why != "":
		AudioManager.play(&"ui_error", -6.0)
		return why
	var a := abilities[i]
	energy -= a.energy_cost
	_cd[i] = a.cooldown * cooldown_mult()
	match a.kind:
		AbilityDef.Kind.WHIRLWIND: _cast_whirlwind(a)
		AbilityDef.Kind.DASH: _cast_dash(a)
		AbilityDef.Kind.WARCRY: _cast_warcry(a)
		AbilityDef.Kind.NOVA: _cast_nova(a)
	ability_cast.emit(i)
	net_attack_count += 1
	return ""

func _enemies_in_radius(center: Vector3, r: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in Enemy.all:
		if is_instance_valid(e) and not e.is_dead():
			var d := e.global_position - center
			d.y = 0.0
			if d.length() <= r + e.get_radius():
				out.append(e)
	return out

func _cast_whirlwind(a: AbilityDef) -> void:
	model.play_spin(0.4)
	AudioManager.play_3d(&"ab_whirl", global_position, 0.0)
	EffectsHub.spawn_ring(global_position + Vector3.UP * 0.9, a.radius, Color(1.0, 0.6, 0.2), 0.35)
	for e in _enemies_in_radius(global_position, a.radius):
		var crit := _rng.randf() < crit()
		e.take_damage(DamageInfo.make(damage() * a.power * ability_power() * (crit_multiplier if crit else 1.0), self, crit))

func _cast_dash(a: AbilityDef) -> void:
	var dir := _input_direction()
	if dir == Vector3.ZERO:
		dir = facing()
	_dash_dir = dir
	_dash_left = a.distance / DASH_SPEED
	_dash_hit.clear()
	_dash_def = a
	_has_move_target = false
	_target_enemy = null
	health.invulnerable = true
	_face(global_position + dir, 1.0, 100.0)
	model.play_attack(0.3)
	AudioManager.play_3d(&"ab_dash", global_position, 0.0)

func _process_dash(delta: float) -> void:
	_dash_left -= delta
	velocity = _dash_dir * DASH_SPEED
	move_and_slide()
	global_position.y = maxf(global_position.y, 0.0)
	EffectsHub.spawn_debris(global_position + Vector3.UP * 0.3, true)
	for e in _enemies_in_radius(global_position, _dash_def.radius):
		if _dash_hit.has(e):
			continue
		_dash_hit[e] = true
		e.take_damage(DamageInfo.make(damage() * _dash_def.power * ability_power(), self))
		e.stun(_dash_def.duration)
	model.animate(delta, 1.0)
	if _dash_left <= 0.0:
		velocity = Vector3.ZERO
		health.invulnerable = false

func _cast_warcry(a: AbilityDef) -> void:
	health.heal_over_time(health.max_health * a.power * ability_power(), 3.0)
	if _armor_buff_left <= 0.0:
		_armor_buff = 6.0
		health.armor = total_armor()
	_armor_buff_left = a.duration
	EffectsHub.spawn_ring(global_position + Vector3.UP * 0.2, 3.5, Color(1.0, 0.85, 0.3), 0.6)
	EffectsHub.spawn_heal(global_position)
	AudioManager.play_3d(&"ab_warcry", global_position, 0.0, 1.15)
	stats_changed.emit()

func _cast_nova(a: AbilityDef) -> void:
	# Alvo: o inimigo (dentro do alcance) com mais vizinhos — o centro do grupo.
	var best: Enemy = null
	var best_n := -1
	for e in _enemies_in_radius(global_position, a.distance):
		var n := _enemies_in_radius(e.global_position, a.radius).size()
		if n > best_n:
			best_n = n
			best = e
	var center := best.global_position if best else global_position + facing() * 6.0
	center.y = 0.0
	EffectsHub.spawn_ring(center + Vector3.UP * 0.1, a.radius, Color(0.75, 0.35, 1.0), 0.55)
	model.play_attack(0.5)
	var timer := get_tree().create_timer(0.55)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		EffectsHub.spawn_explosion(center, a.radius)
		AudioManager.play_3d(&"explosion", center, 2.0, 1.2)
		for e in _enemies_in_radius(center, a.radius):
			e.take_damage(DamageInfo.make(damage() * a.power * ability_power(), self, true))
			e.stun(a.duration))

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
	var hm := 1.0 + Tech.bonus("heal_mult")
	if def.heal_instant > 0.0:
		health.heal(def.heal_instant * hm)
	if def.heal_over_time > 0.0:
		health.heal_over_time(def.heal_over_time * hm, def.heal_duration)
	EffectsHub.spawn_heal(global_position)
	AudioManager.play_3d(&"heal", global_position)

# --- Interação ------------------------------------------------------------

## Mira automática (celular): inimigo mais próximo, depois recurso, senão para frente.
func _auto_aim(move_dir: Vector3) -> void:
	var best: Node3D = null
	var best_d := reach() + 3.0
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
	return {"pos": [global_position.x, global_position.y, global_position.z], "hp": health.current, "weapon_level": weapon_level, "level": level, "xp": xp, "attributes": _attr_save(), "attr_points": attr_points, "gear": _gear_save()}

func _attr_save() -> Dictionary:
	var d := {}
	for id in AttributeConfig.IDS:
		d[String(id)] = attr(id)
	return d

func from_save(d: Dictionary) -> void:
	var p: Array = d.get("pos", [0, 0, 0])
	global_position = Vector3(p[0], p[1], p[2])
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	var saved: Dictionary = d.get("attributes", {})
	for id in AttributeConfig.IDS:
		attributes[id] = int(saved.get(String(id), 0))
	# Saves antigos (sem atributos) recebem os pontos dos níveis já conquistados.
	attr_points = int(d.get("attr_points", (level - 1) * attr_cfg.points_per_level if not d.has("attributes") else 0))
	weapon_level = int(d.get("weapon_level", 0))
	if d.has("gear"):
		_gear_load(d["gear"])
	_recalc_stats(false)
	health.current = clampf(float(d.get("hp", health.max_health)), 1.0, health.max_health)
	health.changed.emit(health.current, health.max_health)

# --- Coop: fantoche -------------------------------------------------------

func _setup_puppet() -> void:
	collision_layer = 0
	collision_mask = 0
	health.regen_per_second = 0.0
	var tag := Label3D.new()
	tag.text = Net.player_name(net_peer)
	tag.font_size = 36
	tag.outline_size = 10
	tag.pixel_size = 0.006
	tag.modulate = Color(0.55, 0.85, 1.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.position.y = 3.1
	add_child(tag)

func apply_net_state(pos: Vector3, yaw: float, speed: float, hp: float, max_hp: float, dead: bool, atk: int, lvl: int) -> void:
	if not _net_has_state:
		global_position = pos
		_net_has_state = true
	_net_target = pos
	_net_yaw = yaw
	_net_speed = speed
	level = lvl
	health.max_health = max_hp
	health.current = clampf(hp, 0.0, max_hp)
	health.changed.emit(health.current, health.max_health)
	if dead != health.dead:
		health.dead = dead
		if dead:
			model.play_death()
		else:
			model.reset_pose()
	if atk != _net_atk:
		_net_atk = atk
		if not dead:
			model.play_attack(0.4)
			AudioManager.play_3d(&"swing", global_position, -10.0)

func _puppet_process(delta: float) -> void:
	if not _net_has_state:
		return
	var d := _net_target - global_position
	if d.length() > 8.0:
		global_position = _net_target
	else:
		global_position = global_position.lerp(_net_target, clampf(delta * 12.0, 0.0, 1.0))
	model.rotation.y = lerp_angle(model.rotation.y, _net_yaw, clampf(delta * 12.0, 0.0, 1.0))
	if not health.dead:
		model.animate(delta, _net_speed)

# --- Destravar --------------------------------------------------------------

## Se o jogador tenta andar e o herói não sai do lugar (preso entre estruturas,
## dentro de uma construção feita em cima dele etc.), procura um ponto livre perto.
func _check_stuck(delta: float, dir: Vector3, speed: float, before: Vector3) -> void:
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if dir != Vector3.ZERO and moved < speed * delta * 0.15:
		_stuck_t += delta
	else:
		_stuck_t = maxf(0.0, _stuck_t - delta * 2.0)
	_overlap_t -= delta
	var overlapping := false
	if _overlap_t <= 0.0:
		_overlap_t = 0.5
		overlapping = _overlaps_at(global_position)
	if overlapping or (_stuck_t > 0.9 and _boxed_in()):
		_stuck_t = 0.0
		unstuck()
	elif _stuck_t > 0.9:
		_stuck_t = 0.0  # só está empurrando uma parede: há saída para outro lado

## true se não dá para andar em nenhuma das 8 direções (preso de verdade).
func _boxed_in() -> bool:
	for i in 8:
		var a := i * TAU / 8.0
		if not test_move(global_transform, Vector3(cos(a), 0.0, sin(a)) * 0.35):
			return false
	return true

## Teste de sobreposição da cápsula do herói com mundo/estruturas num ponto.
func _overlaps_at(p: Vector3) -> bool:
	var cs := $CollisionShape3D as CollisionShape3D
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cs.shape
	q.transform = Transform3D(Basis(), p + cs.position + Vector3.UP * 0.05)
	q.collision_mask = Layers.WORLD | Layers.STRUCTURES | Layers.GATE
	q.margin = -0.02
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

## Move o herói para o ponto livre mais próximo (anéis de 0,7 a 4 m). true se conseguiu.
func unstuck() -> bool:
	var origin := global_position
	for r: float in [0.7, 1.2, 1.8, 2.6, 3.4, 4.2]:
		for i in 16:
			var a := i * TAU / 16.0
			var p := origin + Vector3(cos(a), 0.0, sin(a)) * r
			if not _overlaps_at(p):
				global_position = p
				velocity = Vector3.ZERO
				_has_move_target = false
				EffectsHub.float_text(global_position + Vector3.UP * 2.4, "Destravado!", Color(0.6, 0.9, 1.0), 30)
				return true
	return false
