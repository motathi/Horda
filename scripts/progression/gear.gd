class_name Gear
## Regras de equipamento: raridades, bônus sorteados, criação de itens e catálogo.

const DIR := "res://data/equipment/"
const RARITY_NAMES: Array[String] = ["Comum", "Incomum", "Raro", "Épico", "Lendário"]
const RARITY_COLORS: Array[Color] = [Color(0.82, 0.82, 0.82), Color(0.35, 0.9, 0.35), Color(0.3, 0.6, 1.0), Color(0.75, 0.4, 1.0), Color(1.0, 0.6, 0.12)]
const RARITY_MULT: Array[float] = [1.0, 1.2, 1.45, 1.75, 2.1]
const RARITY_AFFIXES: Array[int] = [0, 1, 2, 3, 4]
const RARITY_WEIGHTS: Array[float] = [60.0, 25.0, 10.0, 4.0, 1.0]
## Cada horda de nível do item soma 3% nos atributos base.
const LEVEL_SCALE := 0.03
const BAG_SIZE := 16

## Bônus sorteáveis: stat -> [mínimo, máximo] no nível 1 (crescem com o nível do item).
const AFFIXES := {
	"damage": [2.0, 6.0], "attack_speed_pct": [0.04, 0.1], "crit": [0.02, 0.05], "armor": [1.0, 4.0],
	"max_hp": [15.0, 40.0], "move_speed_pct": [0.03, 0.06], "health_regen": [0.5, 1.5], "energy": [8.0, 20.0],
	"ability_power_pct": [0.05, 0.12], "lifesteal_pct": [0.02, 0.05],
}
const STAT_ORDER: Array[String] = ["damage", "attack_speed_pct", "crit", "reach", "lifesteal_pct", "armor", "max_hp",
	"health_regen", "move_speed_pct", "energy", "ability_power_pct", "cdr_pct"]
const STAT_LABELS := {
	"damage": "Dano", "attack_speed_pct": "Vel. de ataque", "crit": "Crítico", "reach": "Alcance", "lifesteal_pct": "Roubo de vida",
	"armor": "Armadura", "max_hp": "Vida", "health_regen": "Vida/s", "move_speed_pct": "Movimento", "energy": "Energia",
	"ability_power_pct": "Poder das habilidades", "cdr_pct": "Recarga",
}
const PCT_STATS: Array[String] = ["attack_speed_pct", "crit", "lifesteal_pct", "move_speed_pct", "ability_power_pct", "cdr_pct"]

static var _defs: Array[EquipmentDef] = []

static func defs() -> Array[EquipmentDef]:
	if _defs.is_empty():
		var dir := DirAccess.open(DIR)
		if dir:
			for f in dir.get_files():
				var file := f.trim_suffix(".remap")
				if file.ends_with(".tres"):
					var d := load(DIR + file) as EquipmentDef
					if d:
						_defs.append(d)
		_defs.sort_custom(func(a: EquipmentDef, b: EquipmentDef) -> bool: return a.slot < b.slot or (a.slot == b.slot and a.min_wave < b.min_wave))
	return _defs

static func get_def(id: StringName) -> EquipmentDef:
	for d in defs():
		if d.id == id:
			return d
	return null

static func format_stat(k: String, v: float) -> String:
	var sign := "+" if v >= 0.0 else ""
	if k == "cdr_pct":
		return "%s -%d%%" % [STAT_LABELS[k], roundi(absf(v) * 100)]
	if k in PCT_STATS:
		return "%s %s%d%%" % [STAT_LABELS[k], sign, roundi(v * 100)]
	if k == "reach":
		return "%s %s%.1f m" % [STAT_LABELS[k], sign, v]
	if k == "health_regen":
		return "%s %s%.1f" % [STAT_LABELS[k], sign, v]
	return "%s %s%d" % [STAT_LABELS[k], sign, roundi(v)]

## Sorteia a raridade. luck desloca o peso para as raras (0 = normal; 1 = muito sortudo).
static func roll_rarity(rng: RandomNumberGenerator, luck: float = 0.0, min_rarity: int = 0) -> int:
	var w: Array[float] = []
	var total := 0.0
	for i in RARITY_WEIGHTS.size():
		var x := RARITY_WEIGHTS[i] * pow(1.0 + luck * 2.0, i) if i >= min_rarity else 0.0
		w.append(x)
		total += x
	var r := rng.randf() * total
	for i in w.size():
		r -= w[i]
		if r <= 0.0:
			return i
	return w.size() - 1

static func make_item(d: EquipmentDef, rarity: int, ilvl: int, rng: RandomNumberGenerator) -> GearItem:
	var g := GearItem.new()
	g.def = d
	g.rarity = rarity
	g.item_level = maxi(1, ilvl)
	var pool := AFFIXES.keys()
	pool.shuffle()
	var lvl_mult := 1.0 + LEVEL_SCALE * (g.item_level - 1)
	for i in mini(RARITY_AFFIXES[rarity], pool.size()):
		var k: String = pool[i]
		var rr: Array = AFFIXES[k]
		var v := rng.randf_range(rr[0], rr[1]) * lvl_mult
		g.affixes[k] = snappedf(v, 0.001 if k in PCT_STATS else 0.1)
	return g

## Item aleatório (saque). slot = -1 para qualquer.
static func random_item(rng: RandomNumberGenerator, ilvl: int, luck: float = 0.0, min_rarity: int = 0, slot: int = -1) -> GearItem:
	var pool: Array[EquipmentDef] = []
	for d in defs():
		if (slot < 0 or d.slot == slot) and d.min_wave <= maxi(ilvl, 1) + 2:
			pool.append(d)
	if pool.is_empty():
		pool = defs()
	var d := pool[rng.randi() % pool.size()]
	return make_item(d, roll_rarity(rng, luck, min_rarity), ilvl, rng)

## Saque de inimigos: chefes sempre largam Raro+, elites às vezes, os demais raramente.
static func enemy_drop(rng: RandomNumberGenerator, is_boss: bool, is_elite: bool, special: bool) -> GearItem:
	var wave := TimeManager.wave()
	if is_boss:
		return random_item(rng, wave, 0.6, 2)
	if is_elite:
		return random_item(rng, wave, 0.3, 1) if rng.randf() < 0.45 else null
	return random_item(rng, wave) if rng.randf() < (0.025 if special else 0.012) else null

## Chance de equipamento em contêineres saqueáveis (por nome).
static func container_chance(label: String) -> float:
	if label.contains("Esconderijo") or label.contains("Contamin"):
		return 0.3
	if label.contains("Armário"):
		return 0.14
	if label.contains("Carro") or label.contains("Carroça"):
		return 0.1
	return 0.1
