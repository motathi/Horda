class_name HordeConfig
extends Resource
## Progressão das 100 hordas (orientada a dados). A dificuldade cresce em
## quantidade, força, variedade, elites, chefes e direções de ataque.

@export var entries: Array[HordeSpawnEntry] = []
@export_group("Quantidade")
## total = (base + linear * h + quad * h²) * dificuldade
@export var base_count: float = 6.0
@export var count_linear: float = 2.6
@export var count_quadratic: float = 0.012
@export var max_alive: int = 110
@export var max_alive_mobile: int = 60
@export_group("Força")
## vida = 1 + hp_linear*(h-1) + hp_quadratic*(h-1)²
@export var hp_linear: float = 0.05
@export var hp_quadratic: float = 0.0004
@export var damage_linear: float = 0.03
@export var speed_bonus_max: float = 0.25
@export_group("Ritmo")
## Segundos para liberar a horda inteira (por zumbi), com limites.
@export var seconds_per_enemy: float = 0.55
@export var min_spawn_window: float = 15.0
@export var max_spawn_window: float = 110.0
## Levas por horda (pausa curta entre elas).
@export var waves: int = 3
@export_group("Eventos especiais")
## A cada N hordas aparece um elite (aura dourada, 3x vida).
@export var elite_every: int = 5
## A cada N hordas: CHEFE + ataque de todas as direções.
@export var boss_every: int = 10

func is_boss_wave(h: int) -> bool:
	return boss_every > 0 and h % boss_every == 0

## Mantido por compatibilidade: lua de sangue = horda de chefe.
func is_blood_moon(h: int) -> bool:
	return is_boss_wave(h)

func elite_count(h: int) -> int:
	if elite_every <= 0 or h < elite_every:
		return 0
	var n := 1 if h % elite_every == 0 else 0
	return n + h / 25

func boss_count(h: int) -> int:
	return (1 + h / 50) if is_boss_wave(h) else 0

func total_count(h: int) -> int:
	var c := base_count + count_linear * h + count_quadratic * h * h
	return int(round(c * GameManager.diff_value("horde_count")))

func hp_multiplier(h: int) -> float:
	var x := float(h - 1)
	return 1.0 + hp_linear * x + hp_quadratic * x * x

func damage_multiplier(h: int) -> float:
	return 1.0 + damage_linear * (h - 1)

func speed_multiplier(h: int) -> float:
	return 1.0 + speed_bonus_max * clampf((h - 1) / 99.0, 0.0, 1.0)

func alive_cap() -> int:
	return max_alive_mobile if Platform.low_end else max_alive

func spawn_window(h: int) -> float:
	return clampf(total_count(h) * seconds_per_enemy, min_spawn_window, max_spawn_window)

## Composição da horda: Array de EnemyDef (embaralhado), incluindo garantidos.
func compose(h: int, rng: RandomNumberGenerator) -> Array[EnemyDef]:
	var total := total_count(h)
	var out: Array[EnemyDef] = []
	var counts := {}
	var pool: Array[HordeSpawnEntry] = []
	for e in entries:
		if h >= e.unlock_night:
			pool.append(e)
			for i in e.guaranteed:
				if out.size() < total:
					out.append(e.enemy)
					counts[e] = int(counts.get(e, 0)) + 1
	if pool.is_empty():
		return out
	var guard := 0
	while out.size() < total and guard < total * 10:
		guard += 1
		var sum := 0.0
		for e in pool:
			sum += _weight(e, h)
		var r := rng.randf() * sum
		for e in pool:
			r -= _weight(e, h)
			if r <= 0.0:
				if e.max_per_night > 0 and int(counts.get(e, 0)) >= e.max_per_night:
					break
				out.append(e.enemy)
				counts[e] = int(counts.get(e, 0)) + 1
				break
	out.shuffle()
	return out

func _weight(e: HordeSpawnEntry, h: int) -> float:
	return e.weight + e.weight_growth * (h - e.unlock_night)

## Inimigo mais forte disponível (base de elites e chefes).
func strongest(h: int) -> EnemyDef:
	var best: EnemyDef = null
	for e in entries:
		if h >= e.unlock_night and (best == null or e.enemy.max_health > best.max_health):
			best = e.enemy
	return best
