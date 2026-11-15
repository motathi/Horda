class_name HordeDirector
extends Node
## Calcula e executa cada horda (1..100): composição, levas, pontos de surgimento,
## elites, chefes e fim da horda quando todos os inimigos morrem.

const ENEMY_SCENE := preload("res://scenes/enemies/zombie.tscn")

@export var config: HordeConfig
@export var enemies_parent: NodePath

var spawn_points: Array[Vector3] = []
var _queue: Array[EnemyDef] = []
var _active_points: Array[Vector3] = []
var _spawn_interval: float = 1.0
var _spawn_left: float = 0.0
var _wave_pause_left: float = 0.0
var _per_wave: int = 0
var _spawned_in_wave: int = 0
var _elites_left: int = 0
var _bosses_left: int = 0
var _grand_total: int = 0
var _cleared_t: float = -1.0
var _current: int = 0
var _total: int = 0
var _alive: Array[Enemy] = []
var _night_active: bool = false
var _rng := RandomNumberGenerator.new()
var _parent: Node

func _ready() -> void:
	_rng.randomize()
	_parent = get_node(enemies_parent)
	TimeManager.phase_changed.connect(_on_phase_changed)

func _on_phase_changed(phase: int, _day: int) -> void:
	match phase:
		TimeManager.Phase.NIGHT:
			start_night(TimeManager.night_number())
		TimeManager.Phase.DAWN:
			end_night()

func start_night(night: int) -> void:
	if _night_active:
		return
	_night_active = true
	_current = night
	_cleared_t = -1.0
	_queue = config.compose(night, _rng)
	_total = _queue.size()
	_elites_left = config.elite_count(night)
	_bosses_left = config.boss_count(night)
	_grand_total = _total + _elites_left + _bosses_left
	_alive.clear()
	var boss := config.is_boss_wave(night)
	# Direções de ataque: aumentam com as hordas; todas nas hordas de chefe.
	_active_points.clear()
	var pts := spawn_points.duplicate()
	pts.shuffle()
	var n_dirs := pts.size() if boss else clampi(1 + night / 6, 1, pts.size())
	for i in n_dirs:
		_active_points.append(pts[i])
	var waves := maxi(1, config.waves)
	_per_wave = ceili(float(_total) / waves)
	_spawned_in_wave = 0
	_spawn_interval = clampf(config.spawn_window(night) / maxf(1.0, _total), 0.12, 2.5)
	_spawn_left = 1.5
	_wave_pause_left = 0.0
	var subtitle := "%d inimigos se aproximam" % _grand_total
	if boss:
		subtitle = "CHEFE! " + subtitle + " de todas as direções"
	elif _elites_left > 0:
		subtitle += " — um ELITE lidera a horda!"
	EventBus.banner.emit("HORDA %d / %d" % [night, TimeManager.TOTAL_WAVES], subtitle, Color(0.9, 0.15, 0.1))
	EventBus.horde_started.emit(night, _grand_total)
	AudioManager.play(&"horn")
	_announce_new_enemies(night)

## Apresenta os tipos de inimigo que estreiam nesta horda.
func _announce_new_enemies(night: int) -> void:
	var delay := 3.5
	for e: HordeSpawnEntry in config.entries:
		if e.unlock_night == night and night > 1 and e.enemy:
			var d := e.enemy
			get_tree().create_timer(delay).timeout.connect(func() -> void:
				EventBus.banner.emit("NOVO INIMIGO: " + d.display_name.to_upper(), d.description, d.special_color if d.special_radius > 0.0 else Color(1.0, 0.6, 0.2)))
			delay += 4.0

func end_night() -> void:
	if not _night_active:
		return
	_night_active = false
	_queue.clear()
	_elites_left = 0
	_bosses_left = 0
	var burned := 0
	for e in _alive:
		if is_instance_valid(e) and not e.is_dead():
			e.burn()
			burned += 1
	_alive.clear()
	var wave := _current
	EventBus.horde_ended.emit(wave)
	EventBus.night_survived.emit(wave)
	AudioManager.play(&"dawn")
	if wave >= TimeManager.TOTAL_WAVES:
		GameManager.victory()
		return
	var sub := "O sol queimou os mortos-vivos restantes." if burned > 0 else "Prepare-se: a próxima horda chega em 2 minutos."
	EventBus.banner.emit("HORDA %d VENCIDA" % wave, sub, Color(1.0, 0.8, 0.3))

func _process(delta: float) -> void:
	if not _night_active or not GameManager.is_playing():
		return
	_prune()
	if _queue.is_empty() and _elites_left <= 0 and _bosses_left <= 0:
		# Horda vencida quando não resta ninguém vivo.
		if _alive.is_empty():
			if _cleared_t < 0.0:
				_cleared_t = 2.5
			_cleared_t -= delta
			if _cleared_t <= 0.0:
				TimeManager.finish_horde()
		return
	if _wave_pause_left > 0.0:
		_wave_pause_left -= delta
		return
	_spawn_left -= delta
	if _spawn_left > 0.0 or _alive.size() >= config.alive_cap():
		return
	_spawn_left = _spawn_interval
	var night := _current
	var def: EnemyDef
	var kind := 0  # 0 normal, 1 elite, 2 chefe
	if _bosses_left > 0 and (_queue.size() <= _total / 3 or _queue.is_empty()):
		def = config.strongest(night)
		kind = 2
		_bosses_left -= 1
	elif _elites_left > 0 and (_queue.size() <= _total / 2 or _queue.is_empty()):
		def = config.strongest(night)
		kind = 1
		_elites_left -= 1
	elif not _queue.is_empty():
		def = _queue.pop_back()
	else:
		return
	_spawn(def, night, kind)
	_spawned_in_wave += 1
	if _spawned_in_wave >= _per_wave:
		_spawned_in_wave = 0
		_wave_pause_left = 6.0

func _spawn(def: EnemyDef, night: int, kind: int) -> void:
	if def == null or _active_points.is_empty():
		return
	var base: Vector3 = _active_points[_rng.randi() % _active_points.size()]
	var pos := base + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6))
	var e := ENEMY_SCENE.instantiate() as Enemy
	_parent.add_child(e)
	e.global_position = pos
	e.configure(def, config.hp_multiplier(night), config.damage_multiplier(night))
	e.speed_value *= config.speed_multiplier(night)
	if kind == 1:
		e.make_elite()
		EventBus.notify("Um %s de elite surgiu!" % def.display_name, Color(1.0, 0.6, 0.2))
	elif kind == 2:
		e.make_boss()
		EventBus.banner.emit("CHEFE!", "%s gigante ataca a base" % def.display_name, Color(1.0, 0.25, 0.1))
	e.start_siege()
	_alive.append(e)

func _prune() -> void:
	var before := _alive.size()
	_alive = _alive.filter(func(e) -> bool: return is_instance_valid(e) and not (e as Enemy).is_dead())
	if _alive.size() != before:
		EventBus.horde_progress.emit(remaining(), _grand_total)

func remaining() -> int:
	return _alive.size() + _queue.size() + _elites_left + _bosses_left

func is_active() -> bool:
	return _night_active
