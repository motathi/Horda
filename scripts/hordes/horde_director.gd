class_name HordeDirector
extends Node
## Calcula e executa a horda de cada noite: composição, ondas, pontos de surgimento,
## elites, lua de sangue e limpeza ao amanhecer.

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
	_queue = config.compose(night, _rng)
	_total = _queue.size()
	_elites_left = config.elite_count(night)
	_alive.clear()
	var blood := config.is_blood_moon(night)
	# Direções de ataque: 1-2 no início, mais com o passar das noites; todas na lua de sangue.
	_active_points.clear()
	var pts := spawn_points.duplicate()
	pts.shuffle()
	var n_dirs := pts.size() if blood else clampi(1 + night / 3, 1, pts.size())
	for i in n_dirs:
		_active_points.append(pts[i])
	var waves := maxi(1, config.waves)
	_per_wave = ceili(float(_total) / waves)
	_spawned_in_wave = 0
	var window := TimeManager.config.night_duration * config.spawn_window
	_spawn_interval = clampf(window / maxf(1.0, _total + waves * 4.0), 0.15, 3.0)
	_spawn_left = 2.0
	_wave_pause_left = 0.0
	var subtitle := "%d inimigos se aproximam" % (_total + _elites_left)
	if blood:
		subtitle = "LUA DE SANGUE! " + subtitle + " de todas as direções"
	elif _elites_left > 0:
		subtitle += " — um ELITE lidera a horda!"
	EventBus.banner.emit("NOITE %d" % night, subtitle, Color(0.9, 0.15, 0.1))
	EventBus.horde_started.emit(night, _total + _elites_left)
	AudioManager.play(&"horn")

func end_night() -> void:
	if not _night_active:
		return
	_night_active = false
	_queue.clear()
	var burned := 0
	for e in _alive:
		if is_instance_valid(e) and not e.is_dead():
			e.burn()
			burned += 1
	_alive.clear()
	var night := TimeManager.day - 1
	EventBus.horde_ended.emit(night)
	EventBus.night_survived.emit(night)
	var sub := "O sol queima os mortos-vivos restantes." if burned > 0 else "A horda foi derrotada."
	EventBus.banner.emit("NOITE %d SOBREVIVIDA" % night, sub, Color(1.0, 0.8, 0.3))
	AudioManager.play(&"dawn")

func _process(delta: float) -> void:
	if not _night_active or not GameManager.is_playing():
		return
	_prune()
	if _queue.is_empty() and _elites_left <= 0:
		return
	if _wave_pause_left > 0.0:
		_wave_pause_left -= delta
		return
	_spawn_left -= delta
	if _spawn_left > 0.0 or _alive.size() >= config.max_alive:
		return
	_spawn_left = _spawn_interval
	var night := TimeManager.night_number()
	var def: EnemyDef
	var elite := false
	# Elites chegam no meio da horda.
	if _elites_left > 0 and (_queue.size() <= _total / 2 or _queue.is_empty()):
		def = config.strongest(night)
		elite = true
		_elites_left -= 1
	else:
		def = _queue.pop_back()
	_spawn(def, night, elite)
	_spawned_in_wave += 1
	if _spawned_in_wave >= _per_wave:
		_spawned_in_wave = 0
		_wave_pause_left = 12.0

func _spawn(def: EnemyDef, night: int, elite: bool) -> void:
	if def == null or _active_points.is_empty():
		return
	var base: Vector3 = _active_points[_rng.randi() % _active_points.size()]
	var pos := base + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6))
	var e := ENEMY_SCENE.instantiate() as Enemy
	_parent.add_child(e)
	e.global_position = pos
	e.configure(def, config.hp_multiplier(night), config.damage_multiplier(night))
	if elite:
		e.make_elite()
		EventBus.notify("Um %s de elite surgiu!" % def.display_name, Color(1.0, 0.6, 0.2))
	e.start_siege()
	_alive.append(e)

func _prune() -> void:
	var before := _alive.size()
	_alive = _alive.filter(func(e) -> bool: return is_instance_valid(e) and not (e as Enemy).is_dead())
	if _alive.size() != before:
		EventBus.horde_progress.emit(remaining(), _total + config.elite_count(TimeManager.night_number()))

func remaining() -> int:
	return _alive.size() + _queue.size() + _elites_left

func is_active() -> bool:
	return _night_active
