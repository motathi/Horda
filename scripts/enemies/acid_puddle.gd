class_name AcidPuddle
extends Node3D
## Poça de ácido: a cada 0,5 s fere aliados (herói/soldados) dentro do raio.

const TICK := 0.5

var radius: float = 1.8
var life: float = 4.0
var tick_damage: float = 4.0
var color: Color = Color(0.5, 1.0, 0.2)
var source: Node3D
var _tick: float = 0.0
var _mat: StandardMaterial3D

static var active: Array[AcidPuddle] = []

static func spawn(parent: Node, pos: Vector3, r: float, seconds: float, dmg: float, c: Color, src: Node3D) -> AcidPuddle:
	var p := AcidPuddle.new()
	p.radius = r
	p.life = seconds
	p.tick_damage = dmg
	p.color = c
	p.source = src
	parent.add_child(p)
	p.global_position = Vector3(pos.x, 0.06, pos.z)
	return p

func _ready() -> void:
	active.append(self)
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.04
	cyl.radial_segments = 20
	cyl.rings = 1
	mi.mesh = cyl
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	scale = Vector3(0.3, 1, 0.3)
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.2)

func _exit_tree() -> void:
	active.erase(self)

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if life < 0.6:
		_mat.albedo_color.a = 0.55 * life / 0.6
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	if tick_damage <= 0.0:
		return
	for n: Node in get_tree().get_nodes_in_group("allies"):
		var a := n as Node3D
		if a == null or a.call(&"is_dead"):
			continue
		var d := a.global_position - global_position
		if Vector2(d.x, d.z).length() <= radius + float(a.call(&"get_radius")) * 0.5:
			var info := DamageInfo.make(tick_damage, source if is_instance_valid(source) else null)
			info.type = DamageInfo.Type.TRUE
			a.call(&"take_damage", info)
