class_name GearItem
extends RefCounted
## Um equipamento concreto: item base + raridade + nível + bônus sorteados.

var def: EquipmentDef
var rarity: int = 0
var item_level: int = 1
var affixes: Dictionary = {}  # stat -> valor extra

## Valor final de um atributo (base escalado por raridade/nível + bônus sorteado).
func stat(name: String) -> float:
	var base := float(def.stats.get(name, 0.0))
	var scale := Gear.RARITY_MULT[rarity] * (1.0 + Gear.LEVEL_SCALE * (item_level - 1))
	# Penalidades (valores negativos) não crescem com raridade/nível.
	var v := base * scale if base > 0.0 else base
	return v + float(affixes.get(name, 0.0))

func all_stats() -> Dictionary:
	var out := {}
	for k: String in def.stats:
		out[k] = stat(k)
	for k: String in affixes:
		out[k] = stat(k)
	return out

func display_name() -> String:
	return def.display_name

func color() -> Color:
	return Gear.RARITY_COLORS[rarity]

func rarity_name() -> String:
	return Gear.RARITY_NAMES[rarity]

## Texto com todos os atributos (tooltip / detalhes).
func stats_text() -> String:
	var lines: Array[String] = []
	var st := all_stats()
	for k: String in Gear.STAT_ORDER:
		if st.has(k) and absf(st[k]) > 0.001:
			lines.append(Gear.format_stat(k, st[k]) + ("  *" if affixes.has(k) else ""))
	return "\n".join(lines)

## Recursos devolvidos ao desmontar (mais em raridades altas).
func salvage_value() -> Dictionary:
	var out := {}
	var src := def.craft_cost if not def.craft_cost.is_empty() else {&"scrap": 10}
	for id: StringName in src:
		out[id] = maxi(1, int(round(int(src[id]) * 0.35 * (1.0 + rarity * 0.5))))
	return out

func to_dict() -> Dictionary:
	return {"id": String(def.id), "rarity": rarity, "ilvl": item_level, "affixes": affixes.duplicate()}

static func from_dict(d: Dictionary) -> GearItem:
	var df := Gear.get_def(StringName(d.get("id", "")))
	if df == null:
		return null
	var g := GearItem.new()
	g.def = df
	g.rarity = clampi(int(d.get("rarity", 0)), 0, Gear.RARITY_NAMES.size() - 1)
	g.item_level = maxi(1, int(d.get("ilvl", 1)))
	var a: Dictionary = d.get("affixes", {})
	for k: String in a:
		g.affixes[k] = float(a[k])
	return g
