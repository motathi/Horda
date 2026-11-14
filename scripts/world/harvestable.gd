class_name Harvestable
extends StaticBody3D
## Nó de recurso do mundo (árvore, rocha). Cada golpe do herói rende itens;
## esgotado, some e renasce alguns dias depois.

enum Kind { TREE, ROCK }

const RESPAWN_DAYS := 2

@export var kind: Kind = Kind.TREE
@export var item_id: StringName = &"wood"
@export var hits: int = 5
@export var yield_min: int = 1
@export var yield_max: int = 2

var node_id: String = ""
var respawn_day: int = -1
var _hits_left: int
var _visual: Node3D
var _rng := RandomNumberGenerator.new()
var _shake: float = 0.0

func _ready() -> void:
	add_to_group("harvestable")
	collision_layer = Layers.WORLD
	collision_mask = 0
	_hits_left = hits
	_rng.seed = hash(node_id)

func setup_visual(v: Node3D) -> void:
	_visual = v
	add_child(v)

func display_name() -> String:
	return "Árvore" if kind == Kind.TREE else "Rocha"

func info_text() -> String:
	return "Golpeie para coletar %s (%d/%d)" % [ResourceManager.item_name(item_id), _hits_left, hits]

func is_depleted() -> bool:
	return _hits_left <= 0

func harvest(hero: Hero) -> void:
	if _hits_left <= 0:
		return
	_hits_left -= 1
	var amount := _rng.randi_range(yield_min, yield_max)
	var got := ResourceManager.give_hero(item_id, amount)
	if got > 0:
		EffectsHub.float_text(global_position + Vector3.UP * 2.0, "+%d %s" % [got, ResourceManager.item_name(item_id)], ResourceManager.get_def(item_id).color)
	elif amount > 0:
		EffectsHub.drop_item(global_position + (hero.global_position - global_position).normalized() * 1.2, item_id, amount)
	_shake = 0.25
	AudioManager.play_3d(&"chop" if kind == Kind.TREE else &"mine", global_position, -3.0)
	EffectsHub.spawn_debris(global_position + Vector3.UP * 1.2, kind == Kind.ROCK)
	if _hits_left <= 0:
		_deplete(true)

func _deplete(animated: bool) -> void:
	respawn_day = TimeManager.day + RESPAWN_DAYS
	collision_layer = 0
	remove_from_group("harvestable")
	if animated and kind == Kind.TREE:
		var tw := create_tween()
		tw.tween_property(_visual, "rotation:z", deg_to_rad(88.0), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(_visual, "position:y", -3.0, 1.2)
		tw.tween_callback(func() -> void: _visual.visible = false)
	elif animated:
		var tw2 := create_tween()
		tw2.tween_property(_visual, "scale", Vector3.ONE * 0.05, 0.4)
		tw2.tween_callback(func() -> void: _visual.visible = false)
	else:
		_visual.visible = false

func try_respawn(day: int) -> void:
	if respawn_day < 0 or day < respawn_day:
		return
	respawn_day = -1
	_hits_left = hits
	_visual.visible = true
	_visual.rotation = Vector3.ZERO
	_visual.position = Vector3.ZERO
	_visual.scale = Vector3.ONE
	collision_layer = Layers.WORLD
	add_to_group("harvestable")

func restore_depleted(resp_day: int) -> void:
	_hits_left = 0
	_deplete(false)
	respawn_day = resp_day

func _process(delta: float) -> void:
	if _shake > 0.0 and _visual:
		_shake -= delta
		_visual.rotation.z = sin(_shake * 60.0) * 0.04 * (_shake / 0.25) if _hits_left > 0 else _visual.rotation.z
