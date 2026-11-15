class_name Lootable
extends StaticBody3D
## Estrutura saqueável (caixa de suprimentos, carro destruído, armário).
## Interação com canal (tecla E); reabastece após alguns dias.

@export var display_label: String = "Caixa de Suprimentos"
@export var loot: LootTable
@export var duration: float = 1.5
## Dias até reabastecer (0 = nunca).
@export var restock_days: int = 3

var node_id: String = ""
var looted: bool = false
var restock_day: int = -1
var _rng := RandomNumberGenerator.new()
var _glow: OmniLight3D
var _visual: Node3D

func _ready() -> void:
	add_to_group("interactable")
	collision_layer = Layers.WORLD | Layers.INTERACTABLES
	collision_mask = 0
	_rng.randomize()
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.85, 0.4)
	_glow.light_energy = 0.8
	_glow.omni_range = 2.5
	_glow.position.y = 1.2
	add_child(_glow)

func setup_visual(v: Node3D) -> void:
	_visual = v
	add_child(v)

func display_name() -> String:
	return display_label

func info_text() -> String:
	return "Saqueado" if looted else "Pressione E para saquear"

func can_interact() -> bool:
	return not looted

func interact_duration() -> float:
	return duration

func interact_label() -> String:
	return "Saqueando " + display_label

func interact(_hero: Hero) -> void:
	if looted:
		return
	var drops := loot.roll(_rng, 1.0 + Tech.bonus("loot_mult")) if loot else {}
	if drops.is_empty():
		EventBus.notify("%s estava vazio." % display_label, Color(0.8, 0.8, 0.8))
	var y := 2.0
	for id: StringName in drops:
		var amount: int = drops[id]
		var got := ResourceManager.give_hero(id, amount)
		if got > 0:
			EffectsHub.float_text(global_position + Vector3.UP * y, "+%d %s" % [got, ResourceManager.item_name(id)], ResourceManager.get_def(id).color)
			y += 0.45
		if got < amount:
			EffectsHub.drop_item(global_position, id, amount - got)
	if _rng.randf() < Gear.container_chance(display_label) + Tech.bonus("gear_chance"):
		EffectsHub.drop_gear(global_position + Vector3.UP * 0.5, Gear.random_item(_rng, TimeManager.wave(), 0.1))
	AudioManager.play_3d(&"loot", global_position)
	EventBus.container_looted.emit(self)
	_set_looted(true)
	restock_day = TimeManager.day + restock_days if restock_days > 0 else -1

func _set_looted(v: bool) -> void:
	looted = v
	_glow.visible = not v
	if _visual:
		for c in _visual.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).transparency = 0.0
		_visual.scale = Vector3(1, 0.85, 1) if v else Vector3.ONE

func try_restock(day: int) -> void:
	if looted and restock_day >= 0 and day >= restock_day:
		restock_day = -1
		_set_looted(false)

func restore_looted(rday: int) -> void:
	_set_looted(true)
	restock_day = rday
