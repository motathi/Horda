class_name Inventory
extends RefCounted
## Contêiner de itens empilháveis com capacidade por peso (0 = ilimitado).
## Usado tanto pela mochila do herói quanto pelo armazém da base.

signal changed

var capacity: int = 0
var _items: Dictionary = {}  # StringName -> int

func _init(cap: int = 0) -> void:
	capacity = cap

func count(id: StringName) -> int:
	return int(_items.get(id, 0))

func items() -> Dictionary:
	return _items.duplicate()

func is_empty() -> bool:
	return _items.is_empty()

func used_weight() -> int:
	var w := 0
	for id: StringName in _items:
		w += _items[id] * ResourceManager.item_weight(id)
	return w

func free_weight() -> int:
	return 999999 if capacity <= 0 else capacity - used_weight()

## Quantas unidades do item ainda cabem.
func room_for(id: StringName) -> int:
	if capacity <= 0:
		return 999999
	return maxi(0, free_weight() / maxi(1, ResourceManager.item_weight(id)))

## Adiciona até `amount`; retorna quanto foi efetivamente adicionado.
func add(id: StringName, amount: int) -> int:
	var n := mini(amount, room_for(id))
	if n <= 0:
		return 0
	_items[id] = count(id) + n
	changed.emit()
	return n

func remove(id: StringName, amount: int) -> int:
	var n := mini(amount, count(id))
	if n <= 0:
		return 0
	_items[id] = count(id) - n
	if _items[id] <= 0:
		_items.erase(id)
	changed.emit()
	return n

func has_all(cost: Dictionary) -> bool:
	for id: StringName in cost:
		if count(id) < int(cost[id]):
			return false
	return true

func clear() -> void:
	_items.clear()
	changed.emit()

func to_dict() -> Dictionary:
	var d := {}
	for id: StringName in _items:
		d[String(id)] = _items[id]
	return d

func from_dict(d: Dictionary) -> void:
	_items.clear()
	for k: String in d:
		_items[StringName(k)] = int(d[k])
	changed.emit()
