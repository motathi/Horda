class_name ResourcePickup
extends Node3D
## Item no chão (saque de inimigos). Atraído pelo herói quando próximo.

const MAGNET_RANGE := 3.2
const COLLECT_RANGE := 0.7
const LIFETIME := 150.0

var item_id: StringName
var amount: int = 1
var _t: float = 0.0
var _flying: bool = false
var _full_warned: float = 0.0
var _vel: Vector3 = Vector3.ZERO
var _sprite: Sprite3D
var _gem: MeshInstance3D
var _label: Label3D
var _claimed: bool = false

func _ready() -> void:
	_gem = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.18
	m.height = 0.36
	m.radial_segments = 8
	m.rings = 4
	_gem.mesh = m
	add_child(_gem)
	_sprite = Sprite3D.new()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.pixel_size = 0.0028
	_sprite.position.y = 0.75
	_sprite.no_depth_test = false
	_sprite.shaded = false
	add_child(_sprite)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.outline_size = 10
	_label.pixel_size = 0.006
	_label.position = Vector3(0.45, 0.5, 0)
	add_child(_label)

func activate(pos: Vector3, id: StringName, amt: int) -> void:
	if has_meta(&"net_id"):
		remove_meta(&"net_id")
	visible = true
	_claimed = false
	item_id = id
	amount = amt
	_t = 0.0
	_flying = false
	var def := ResourceManager.get_def(id)
	_sprite.texture = def.icon if def else null
	_gem.material_override = MaterialLib.flat(def.color if def else Color.WHITE, 0.3, 1.5)
	_label.text = "x%d" % amt
	global_position = pos + Vector3(0, 0.3, 0)
	# Pequeno "pulo" ao cair
	_vel = Vector3(randf_range(-1.5, 1.5), 4.5, randf_range(-1.5, 1.5))

func _process(delta: float) -> void:
	_t += delta
	if _vel != Vector3.ZERO:
		_vel.y -= 14.0 * delta
		global_position += _vel * delta
		if global_position.y <= 0.3:
			global_position.y = 0.3
			_vel = Vector3.ZERO
		return
	_sprite.position.y = 0.75 + sin(_t * 3.0) * 0.08
	_gem.rotation.y += delta * 2.0
	if _t > LIFETIME:
		_release()
		return
	if _claimed:
		return
	var hero := GameManager.hero as Hero
	if hero == null or hero.is_dead():
		return
	var to := hero.global_position + Vector3.UP * 0.8 - global_position
	var d := to.length()
	_full_warned -= delta
	if d < MAGNET_RANGE or _flying:
		if ResourceManager.hero_inventory.room_for(item_id) <= 0:
			_flying = false
			if _full_warned <= 0.0:
				_full_warned = 4.0
				EventBus.inventory_full.emit(item_id)
			return
		_flying = true
		global_position += to.normalized() * minf(d, delta * 14.0)
		if d < COLLECT_RANGE and has_meta(&"net_id"):
			# Coop: saque compartilhado — o anfitrião decide quem leva.
			if not _claimed:
				_claimed = true
				visible = false
				Coop.claim_pickup(self)
			return
		if d < COLLECT_RANGE:
			var got := ResourceManager.give_hero(item_id, amount)
			if got > 0:
				EffectsHub.float_text(hero.global_position + Vector3.UP * 2.4, "+%d %s" % [got, ResourceManager.item_name(item_id)], ResourceManager.get_def(item_id).color)
				AudioManager.play_3d(&"pickup", global_position, -6.0)
			amount -= got
			if amount <= 0:
				_release()
			else:
				_label.text = "x%d" % amount
				_flying = false

## Coop: removido pelo anfitrião (alguém pegou).
func release_net() -> void:
	if has_meta(&"net_id"):
		remove_meta(&"net_id")
	_release()

func _release() -> void:
	var pool := get_meta("pool", null) as ObjectPool
	if pool:
		pool.release(self)
	else:
		queue_free()

func to_save() -> Dictionary:
	return {"id": String(item_id), "n": amount, "pos": [global_position.x, global_position.z]}
