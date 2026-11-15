class_name GearPickup
extends Node3D
## Equipamento no chão: feixe de luz na cor da raridade, ícone girando e nome.
## Atraído pelo herói quando perto; vai para a bolsa de equipamentos.

const MAGNET_RANGE := 3.0
const COLLECT_RANGE := 0.8
const LIFETIME := 300.0

var item: GearItem
var _t: float = 0.0
var _vel: Vector3
var _flying: bool = false
var _warned: float = 0.0
var _icon: Sprite3D

static func spawn(parent: Node, pos: Vector3, it: GearItem) -> GearPickup:
	var p := GearPickup.new()
	p.item = it
	parent.add_child(p)
	p.global_position = pos + Vector3(0, 0.4, 0)
	p._vel = Vector3(randf_range(-1.2, 1.2), 5.0, randf_range(-1.2, 1.2))
	return p

func _ready() -> void:
	var c := item.color()
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.16
	cyl.height = 3.0 + item.rarity * 0.8
	cyl.radial_segments = 8
	beam.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(c.r, c.g, c.b, 0.55)
	beam.material_override = m
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = cyl.height * 0.5
	add_child(beam)
	_icon = Sprite3D.new()
	_icon.texture = item.def.icon()
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.pixel_size = 0.0045
	_icon.shaded = false
	_icon.position.y = 0.7
	add_child(_icon)
	var lbl := Label3D.new()
	lbl.text = item.display_name()
	lbl.modulate = c
	lbl.font_size = 34
	lbl.outline_size = 10
	lbl.pixel_size = 0.006
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position.y = 1.45
	add_child(lbl)
	if item.rarity >= 2:
		AudioManager.play_3d(&"levelup", global_position, -6.0, 1.3)

func _process(delta: float) -> void:
	_t += delta
	if _vel != Vector3.ZERO:
		_vel.y -= 14.0 * delta
		global_position += _vel * delta
		if global_position.y <= 0.05:
			global_position.y = 0.05
			_vel = Vector3.ZERO
		return
	_icon.position.y = 0.7 + sin(_t * 3.0) * 0.1
	if _t > LIFETIME:
		queue_free()
		return
	var hero := GameManager.hero as Hero
	if hero == null or hero.is_dead():
		return
	var to := hero.global_position + Vector3.UP * 0.8 - global_position
	var d := to.length()
	_warned -= delta
	if d < MAGNET_RANGE or _flying:
		if hero.gear_bag.size() >= Gear.BAG_SIZE:
			_flying = false
			if _warned <= 0.0:
				_warned = 5.0
				EventBus.notify("Bolsa de equipamentos cheia! Desmonte itens no painel do personagem (P).", Color(1, 0.55, 0.3))
			return
		_flying = true
		global_position += to.normalized() * minf(d, delta * 12.0)
		if d < COLLECT_RANGE and hero.add_gear(item):
			EffectsHub.float_text(hero.global_position + Vector3.UP * 2.6, "%s %s" % [item.display_name(), item.rarity_name()], item.color(), 40)
			EventBus.notify("Novo equipamento: %s (%s) — veja no personagem (P)." % [item.display_name(), item.rarity_name()], item.color())
			AudioManager.play(&"objective", -2.0)
			queue_free()
