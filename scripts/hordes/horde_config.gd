class_name HordeConfig
extends Resource
## Parâmetros de progressão das hordas noturnas (100% orientado a dados).

@export var entries: Array[HordeSpawnEntry] = []
@export_group("Quantidade")
@export var base_count: int = 10
@export var count_per_night: float = 6.0
## Crescimento exponencial suave após a noite 6.
@export var late_growth: float = 1.12
@export var max_alive: int = 140
@export_group("Força")
## Bônus de vida/dano por noite (0.08 = +8% por noite).
@export var hp_growth_per_night: float = 0.08
@export var damage_growth_per_night: float = 0.05
@export_group("Ritmo")
## Fração da noite usada para liberar a horda (o resto é para limpar).
@export_range(0.1, 1.0) var spawn_window: float = 0.6
## Ondas por noite (inimigos chegam em levas).
@export var waves: int = 3
@export_group("Eventos especiais")
## Noites com um inimigo de elite (aura dourada, 3x vida).
@export var elite_nights: PackedInt32Array = PackedInt32Array([3, 5, 7, 9])
## A partir desta noite, todas as noites têm elites (1 a cada `elite_every` noites a mais).
@export var elite_every_after: int = 10
## Noites de "lua de sangue": horda 50% maior vinda de todas as direções.
@export var blood_moon_every: int = 7

func is_blood_moon(night: int) -> bool:
	return blood_moon_every > 0 and night % blood_moon_every == 0

func elite_count(night: int) -> int:
	var n := 1 if elite_nights.has(night) else 0
	if night >= elite_every_after:
		n += 1 + (night - elite_every_after) / 3
	return n

func total_count(night: int) -> int:
	var c := base_count + count_per_night * (night - 1)
	if night > 6:
		c *= pow(late_growth, night - 6)
	if is_blood_moon(night):
		c *= 1.5
	return int(round(c * GameManager.diff_value("horde_count")))

func hp_multiplier(night: int) -> float:
	return 1.0 + hp_growth_per_night * (night - 1)

func damage_multiplier(night: int) -> float:
	return 1.0 + damage_growth_per_night * (night - 1)

## Composição da noite: Array de EnemyDef (embaralhado), incluindo garantidos.
func compose(night: int, rng: RandomNumberGenerator) -> Array[EnemyDef]:
	var total := total_count(night)
	var out: Array[EnemyDef] = []
	var counts := {}
	var pool: Array[HordeSpawnEntry] = []
	for e in entries:
		if night >= e.unlock_night:
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
			sum += _weight(e, night)
		var r := rng.randf() * sum
		for e in pool:
			r -= _weight(e, night)
			if r <= 0.0:
				if e.max_per_night > 0 and int(counts.get(e, 0)) >= e.max_per_night:
					break
				out.append(e.enemy)
				counts[e] = int(counts.get(e, 0)) + 1
				break
	out.shuffle()
	return out

func _weight(e: HordeSpawnEntry, night: int) -> float:
	return e.weight + e.weight_growth * (night - e.unlock_night)

## Inimigo mais forte disponível (usado para elites).
func strongest(night: int) -> EnemyDef:
	var best: EnemyDef = null
	for e in entries:
		if night >= e.unlock_night and (best == null or e.enemy.max_health > best.max_health):
			best = e.enemy
	return best
