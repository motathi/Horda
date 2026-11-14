extends Node
## Economia: catálogo de itens (carregado de res://data/items), mochila do herói
## e armazém da base. Toda movimentação de recursos passa por aqui.

const ITEMS_DIR := "res://data/items"
const HERO_CAPACITY := 60

var items: Dictionary = {}  # StringName -> ItemDef
var hero_inventory := Inventory.new(HERO_CAPACITY)
var storage := Inventory.new(0)

func _ready() -> void:
	_load_items()

func _load_items() -> void:
	var dir := DirAccess.open(ITEMS_DIR)
	if dir == null:
		push_error("Pasta de itens ausente: " + ITEMS_DIR)
		return
	for f in dir.get_files():
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var def := load(ITEMS_DIR + "/" + file) as ItemDef
		if def:
			items[def.id] = def

func reset() -> void:
	hero_inventory = Inventory.new(HERO_CAPACITY)
	storage = Inventory.new(0)

func get_def(id: StringName) -> ItemDef:
	return items.get(id) as ItemDef

func item_name(id: StringName) -> String:
	var d := get_def(id)
	return d.display_name if d else String(id)

func item_weight(id: StringName) -> int:
	var d := get_def(id)
	return d.weight if d else 1

## Coloca na mochila do herói; retorna o que coube.
func give_hero(id: StringName, amount: int) -> int:
	var added := hero_inventory.add(id, amount)
	if added > 0:
		EventBus.item_picked_up.emit(id, added)
	if added < amount:
		EventBus.inventory_full.emit(id)
	return added

## Move os recursos da mochila para o armazém (itens consumíveis — carne,
## curativos — ficam com o herói para uso em campo).
func deposit_all() -> Dictionary:
	var summary := {}
	for id: StringName in hero_inventory.items():
		var def := get_def(id)
		if def and def.is_usable():
			continue
		var n := hero_inventory.count(id)
		storage.add(id, n)
		hero_inventory.remove(id, n)
		summary[id] = n
	if not summary.is_empty():
		EventBus.resources_deposited.emit(summary)
	return summary

func has_depositable() -> bool:
	for id: StringName in hero_inventory.items():
		var def := get_def(id)
		if def == null or not def.is_usable():
			return true
	return false

## Total disponível somando armazém + mochila (gastos na base usam os dois).
func available(id: StringName) -> int:
	return storage.count(id) + hero_inventory.count(id)

func can_afford(cost: Dictionary) -> bool:
	for id: StringName in cost:
		if available(id) < int(cost[id]):
			return false
	return true

## Gasta do armazém primeiro, depois da mochila.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for id: StringName in cost:
		var left := int(cost[id])
		left -= storage.remove(id, left)
		if left > 0:
			hero_inventory.remove(id, left)
	return true

func cost_to_string(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id: StringName in cost:
		parts.append("%d %s" % [int(cost[id]), item_name(id)])
	return ", ".join(parts)
