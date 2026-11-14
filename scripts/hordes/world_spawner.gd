class_name WorldSpawner
extends Node
## Mantém a população diurna de inimigos espalhados pelas regiões do mapa.

const ENEMY_SCENE := preload("res://scenes/enemies/zombie.tscn")
const MIN_HERO_DISTANCE := 28.0
const BASE_SAFE_RADIUS := 30.0

## Cada região: {name, center: Vector3, radius, max, enemies: Array[EnemyDef], weights: Array[float], hp_mult}
var regions: Array[Dictionary] = []
@export var enemies_parent: NodePath
@export var check_interval: float = 4.0

var _rng := RandomNumberGenerator.new()
var _t: float = 0.0
var _parent: Node
var _alive: Dictionary = {}  # region name -> Array[Enemy]

func _ready() -> void:
	_rng.randomize()
	_parent = get_node(enemies_parent)

func populate_initial() -> void:
	for r in regions:
		for i in int(r.max * 0.7):
			_spawn_in(r, true)

func _process(delta: float) -> void:
	if not GameManager.is_playing() or TimeManager.is_night():
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = check_interval
	for r in regions:
		var list: Array = _alive.get(r.name, [])
		list = list.filter(func(e: Enemy) -> bool: return is_instance_valid(e) and not e.is_dead())
		_alive[r.name] = list
		# Regiões ficam mais perigosas com o passar dos dias.
		var cap := int(r.max) + (TimeManager.day - 1) * 2
		if list.size() < cap:
			_spawn_in(r, false)

func _spawn_in(r: Dictionary, ignore_hero: bool) -> void:
	var hero := GameManager.hero
	for attempt in 8:
		var ang := _rng.randf() * TAU
		var dist := sqrt(_rng.randf()) * float(r.radius)
		var pos: Vector3 = r.center + Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		if pos.length() < BASE_SAFE_RADIUS or absf(pos.x) > 112.0 or absf(pos.z) > 112.0:
			continue
		if not ignore_hero and hero and hero.global_position.distance_to(pos) < MIN_HERO_DISTANCE:
			continue
		var def := _pick(r)
		var e := ENEMY_SCENE.instantiate() as Enemy
		_parent.add_child(e)
		e.global_position = pos
		e.configure(def, float(r.get("hp_mult", 1.0)) * (1.0 + 0.05 * (TimeManager.day - 1)), 1.0)
		var list: Array = _alive.get(r.name, [])
		list.append(e)
		_alive[r.name] = list
		return

func _pick(r: Dictionary) -> EnemyDef:
	var defs: Array = r.enemies
	var weights: Array = r.weights
	var sum := 0.0
	for w: float in weights:
		sum += w
	var x := _rng.randf() * sum
	for i in defs.size():
		x -= float(weights[i])
		if x <= 0.0:
			return defs[i]
	return defs[0]
