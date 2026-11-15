class_name BaseServices
extends Node
## Serviços disponíveis dentro da base: reparar muros/núcleo, afiar arma e fabricar.
## Toda ação valida recursos e localização e produz efeito real no jogo.

const RECIPES_DIR := "res://data/recipes"

@export var config: BaseServicesConfig
var recipes: Array[Recipe] = []

func _ready() -> void:
	var dir := DirAccess.open(RECIPES_DIR)
	if dir:
		for f in dir.get_files():
			var file := f.trim_suffix(".remap")
			if file.ends_with(".tres"):
				var r := load(RECIPES_DIR + "/" + file) as Recipe
				if r:
					recipes.append(r)

func _walls() -> Array[Structure]:
	var out: Array[Structure] = []
	for n in get_tree().get_nodes_in_group("structures"):
		var s := n as Structure
		if s and s.kind != Structure.Kind.CORE:
			out.append(s)
	return out

# --- Reparar muros -----------------------------------------------------------

func walls_missing_hp() -> float:
	var m := 0.0
	for s in _walls():
		m += s.missing_health()
	return m

func wall_repair_cost() -> Dictionary:
	var wood := ceili(walls_missing_hp() / config.wall_hp_per_wood)
	return {&"wood": wood} if wood > 0 else {}

## Repara o máximo possível com a madeira disponível (prioriza muros destruídos/mais danificados).
func repair_walls() -> String:
	if not BaseZone.hero_inside:
		return "Volte para a base para reparar."
	var walls := _walls()
	walls.sort_custom(func(a: Structure, b: Structure) -> bool: return a.health.ratio() < b.health.ratio())
	var wood_avail := ResourceManager.available(&"wood")
	if walls_missing_hp() <= 0.0:
		return "Os muros estão intactos."
	if wood_avail <= 0:
		return "Sem madeira para reparar."
	var used := 0
	for s in walls:
		var miss := s.missing_health()
		if miss <= 0.0:
			continue
		var need := ceili(miss / config.wall_hp_per_wood)
		var use := mini(need, wood_avail - used)
		if use <= 0:
			break
		s.repair(use * config.wall_hp_per_wood)
		used += use
	ResourceManager.spend({&"wood": used})
	AudioManager.play(&"chop")
	return "Muros reparados (-%d Madeira)." % used

# --- Reparar núcleo ----------------------------------------------------------

func core_missing_hp() -> float:
	var c := GameManager.base_core as Structure
	return c.missing_health() if c else 0.0

func core_repair_cost() -> Dictionary:
	var units := ceili(core_missing_hp() / config.core_hp_per_unit)
	return {&"stone": units, &"scrap": units} if units > 0 else {}

func repair_core() -> String:
	if not BaseZone.hero_inside:
		return "Volte para a base para reparar."
	var c := GameManager.base_core as Structure
	if c == null or c.missing_health() <= 0.0:
		return "O Núcleo está intacto."
	var need := ceili(c.missing_health() / config.core_hp_per_unit)
	var units := mini(need, mini(ResourceManager.available(&"stone"), ResourceManager.available(&"scrap")))
	if units <= 0:
		return "Precisa de Pedra e Sucata para reparar o Núcleo."
	ResourceManager.spend({&"stone": units, &"scrap": units})
	c.repair(units * config.core_hp_per_unit)
	AudioManager.play(&"mine")
	return "Núcleo reparado (-%d Pedra, -%d Sucata)." % [units, units]

# --- Afiar arma --------------------------------------------------------------

func sharpen_cost(hero: Hero) -> Dictionary:
	var lvl := hero.weapon_level + 1
	var cost := {}
	for id: StringName in config.sharpen_base_cost:
		cost[id] = int(config.sharpen_base_cost[id]) * lvl
	return cost

func can_sharpen(hero: Hero) -> bool:
	return hero.weapon_level < config.sharpen_max_level

func sharpen(hero: Hero) -> String:
	if not BaseZone.hero_inside:
		return "Volte para a base para usar a bancada."
	if not can_sharpen(hero):
		return "A arma já está no nível máximo."
	var cost := sharpen_cost(hero)
	if not ResourceManager.spend(cost):
		return "Recursos insuficientes: " + ResourceManager.cost_to_string(cost)
	hero.weapon_level += 1
	hero.stats_changed.emit()
	AudioManager.play(&"mine")
	return "Arma afiada! Dano agora: %d" % int(hero.damage())

# --- Fabricação --------------------------------------------------------------

func craft(r: Recipe) -> String:
	if not BaseZone.hero_inside:
		return "Volte para a base para fabricar."
	if ResourceManager.hero_inventory.room_for(r.output_item) < r.output_amount:
		return "Mochila cheia."
	if not ResourceManager.spend(r.inputs):
		return "Recursos insuficientes: " + ResourceManager.cost_to_string(r.inputs)
	ResourceManager.hero_inventory.add(r.output_item, r.output_amount)
	AudioManager.play(&"loot")
	return "Fabricado: %d %s" % [r.output_amount, ResourceManager.item_name(r.output_item)]

# --- Forja (equipamentos) ----------------------------------------------------

## Sorte na raridade da Forja: cada ponto de Engenharia soma 4%.
func forge_luck(hero: Hero) -> float:
	return hero.attr(&"engineering") * 0.04 if hero else 0.0

## Chance (0..1) de cada raridade na Forja para este herói.
func forge_odds(hero: Hero) -> Array[float]:
	var luck := forge_luck(hero)
	var w: Array[float] = []
	var total := 0.0
	for i in Gear.RARITY_WEIGHTS.size():
		var x := Gear.RARITY_WEIGHTS[i] * pow(1.0 + luck * 2.0, i)
		w.append(x)
		total += x
	for i in w.size():
		w[i] /= total
	return w

func forge(d: EquipmentDef, hero: Hero) -> String:
	if not BaseZone.hero_inside:
		return "Volte para a base para usar a Forja."
	if TimeManager.wave() < d.min_wave:
		return "%s libera na horda %d." % [d.display_name, d.min_wave]
	if hero.gear_bag.size() >= Gear.BAG_SIZE:
		return "Bolsa de equipamentos cheia. Desmonte algo no painel do personagem."
	if not ResourceManager.spend(d.craft_cost):
		return "Recursos insuficientes: " + ResourceManager.cost_to_string(d.craft_cost)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var item := Gear.make_item(d, Gear.roll_rarity(rng, forge_luck(hero)), TimeManager.wave(), rng)
	hero.add_gear(item)
	AudioManager.play(&"upgrade")
	if item.rarity >= 2:
		AudioManager.play(&"levelup", -4.0)
	return "Forjado: %s %s (nível %d) — equipe no personagem (P)." % [item.display_name(), item.rarity_name(), item.item_level]
