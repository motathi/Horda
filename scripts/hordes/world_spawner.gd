class_name WorldSpawner
extends Node
## Mantém a população diurna de inimigos espalhados pelas regiões do mapa.

const ENEMY_SCENE := preload("res://scenes/enemies/zombie.tscn")
const MIN_HERO_DISTANCE := 28.0
const BASE_SAFE_RADIUS := 30.0

## Cada região: {name, center: Vector3, radius, max, enemies: Array[EnemyDef], weights: Array[float], hp_mult}
var regions: Array[Dictionary] = []
## Guardiões (chefes do mapa): {id, pos: Vector3, def: EnemyDef, title, hp_mult}. Renascem dias depois.
var guardians: Array[Dictionary] = []
const GUARDIAN_RESPAWN_DAYS := 3
## Celular fraco: menos inimigos espalhados (o mapa continua cheio, mas leve).
const LOW_END_DENSITY := 0.6
var _guardian_alive: Dictionary = {}  # id -> Enemy
var _guardian_dead_day: Dictionary = {}  # id -> dia em que morreu
@export var enemies_parent: NodePath
@export var check_interval: float = 4.0

var _rng := RandomNumberGenerator.new()
var _t: float = 0.0
var _parent: Node
var _alive: Dictionary = {}  # region name -> Array[Enemy]

## Celular: no máximo isto de inimigos espalhados durante a horda (cada personagem animado tem uma cópia da
## malha na placa de vídeo; somados à horda, estouravam a memória do navegador lá pela 5ª horda).
const LOW_END_NIGHT_BUDGET := 40

func _ready() -> void:
	_rng.randomize()
	_parent = get_node(enemies_parent)
	TimeManager.phase_changed.connect(func(phase: int, _day: int) -> void:
		if phase == TimeManager.Phase.NIGHT and Platform.low_end:
			_trim_for_night())

## Ao começar a horda no celular, some com os inimigos espalhados mais distantes do herói (voltam de dia).
func _trim_for_night() -> void:
	if Coop.is_client():
		return
	var hero := GameManager.hero
	var list: Array[Enemy] = []
	for r in regions:
		for e in _alive.get(r.name, []):
			if is_instance_valid(e) and not (e as Enemy).is_dead():
				list.append(e)
	if list.size() <= LOW_END_NIGHT_BUDGET:
		return
	var from := hero.global_position if hero else Vector3.ZERO
	list.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.global_position.distance_squared_to(from) > b.global_position.distance_squared_to(from))
	for i in list.size() - LOW_END_NIGHT_BUDGET:
		var e := list[i]
		if e.global_position.distance_to(from) < 45.0:
			break  # nunca some na frente do jogador
		Coop.enemy_removed(e)
		e.queue_free()

func populate_initial() -> void:
	if Coop.is_client():
		return  # inimigos vêm do anfitrião
	# Os inimigos ficam em grupos de 2 a 4 (matilhas), não espalhados um a um.
	for r in regions:
		var target := _region_cap(r, false)
		var n := 0
		var guard := 0
		while n < target and guard < target * 3:
			guard += 1
			n += _spawn_in(r, true, mini(_rng.randi_range(2, 4), target - n))
	for g in guardians:
		_spawn_guardian(g)

func _region_cap(r: Dictionary, grow: bool) -> int:
	var k := LOW_END_DENSITY if Platform.low_end else 1.0
	# Regiões ficam mais perigosas com o passar dos dias (no celular a quantidade fica fixa: memória).
	return int(round(float(r.max) * k)) + (mini(TimeManager.day - 1, 8) if grow and not Platform.low_end else 0)

func _spawn_guardian(g: Dictionary) -> void:
	var e := ENEMY_SCENE.instantiate() as Enemy
	_parent.add_child(e)
	e.global_position = g.pos
	e.configure(g.def, float(g.get("hp_mult", 1.0)) * (1.0 + 0.06 * (TimeManager.day - 1)), 1.0 + 0.03 * (TimeManager.day - 1))
	e.make_guardian(String(g.title))
	_guardian_alive[g.id] = e
	_guardian_dead_day.erase(g.id)

## Guardiões mortos voltam alguns dias depois (longe do herói, para não surgir na cara dele).
func _check_guardians() -> void:
	var hero := GameManager.hero
	for g in guardians:
		var e: Variant = _guardian_alive.get(g.id)
		if e != null and is_instance_valid(e) and not (e as Enemy).is_dead():
			continue
		if not _guardian_dead_day.has(g.id):
			_guardian_dead_day[g.id] = TimeManager.day
			_guardian_alive.erase(g.id)
			continue
		if TimeManager.day >= int(_guardian_dead_day[g.id]) + GUARDIAN_RESPAWN_DAYS and (hero == null or hero.global_position.distance_to(g.pos) > 45.0):
			_spawn_guardian(g)

func guardian_alive(id: String) -> bool:
	var e: Variant = _guardian_alive.get(id)
	return e != null and is_instance_valid(e) and not (e as Enemy).is_dead()

func _process(delta: float) -> void:
	if Coop.is_client() or not GameManager.is_playing() or TimeManager.is_night():
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = check_interval
	_check_guardians()
	for r in regions:
		var list: Array = _alive.get(r.name, [])
		list = list.filter(func(e) -> bool: return is_instance_valid(e) and not (e as Enemy).is_dead())
		_alive[r.name] = list
		var cap := _region_cap(r, true)
		if list.size() < cap:
			_spawn_in(r, false, mini(_rng.randi_range(1, 3), cap - list.size()))

## Cria um grupo de `count` inimigos ao redor de um ponto sorteado na região. Retorna quantos nasceram.
func _spawn_in(r: Dictionary, ignore_hero: bool, count: int = 1) -> int:
	var hero := GameManager.hero
	for attempt in 8:
		var ang := _rng.randf() * TAU
		var dist := sqrt(_rng.randf()) * float(r.radius)
		var pos: Vector3 = r.center + Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		if not _valid_spot(pos):
			continue
		if not ignore_hero and hero and hero.global_position.distance_to(pos) < MIN_HERO_DISTANCE:
			continue
		var made := 0
		for i in count:
			var p := pos if i == 0 else pos + Vector3(_rng.randf_range(-3.5, 3.5), 0, _rng.randf_range(-3.5, 3.5))
			if not _valid_spot(p):
				continue
			var e := ENEMY_SCENE.instantiate() as Enemy
			_parent.add_child(e)
			e.global_position = p
			e.configure(_pick(r), float(r.get("hp_mult", 1.0)) * (1.0 + 0.05 * (TimeManager.day - 1)), 1.0)
			var list: Array = _alive.get(r.name, [])
			list.append(e)
			_alive[r.name] = list
			made += 1
		return made
	return 0

func _valid_spot(p: Vector3) -> bool:
	return p.length() >= BASE_SAFE_RADIUS and absf(p.x) <= 112.0 and absf(p.z) <= 112.0

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
