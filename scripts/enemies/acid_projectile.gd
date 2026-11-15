class_name AcidProjectile
extends Node3D
## Cusparada de ácido do Cuspidor: voa em arco até o ponto-alvo, fere estruturas
## no impacto e deixa uma poça que corrói aliados (herói/soldados) que pisarem nela.

const FLIGHT_SPEED := 14.0
const ARC_HEIGHT := 3.0

var source: Node3D
var damage: float = 10.0
var structure_mult: float = 1.0
var puddle_radius: float = 1.8
var puddle_time: float = 4.0
var color: Color = Color(0.5, 1.0, 0.2)
## Coop (cliente): só o efeito visual; o dano é do anfitrião.
var visual_only: bool = false
var _from: Vector3
var _to: Vector3
var _t: float = 0.0
var _dur: float = 0.5

static func launch(parent: Node, from: Vector3, to: Vector3, src: Node3D, dmg: float, def: EnemyDef) -> AcidProjectile:
	var p := AcidProjectile.new()
	p.source = src
	p.damage = dmg
	p.structure_mult = def.structure_damage_mult
	p.puddle_radius = def.special_radius
	p.puddle_time = def.special_time
	p.color = def.special_color
	parent.add_child(p)
	p._from = from
	p._to = Vector3(to.x, 0.05, to.z)
	p._dur = clampf(from.distance_to(to) / FLIGHT_SPEED, 0.25, 1.2)
	p.global_position = from
	return p

## Define a trajetória (uso direto, sem launch).
func setup(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = Vector3(to.x, 0.05, to.z)
	_dur = clampf(from.distance_to(to) / FLIGHT_SPEED, 0.25, 1.2)
	global_position = from

func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.28
	sph.height = 0.56
	sph.radial_segments = 10
	sph.rings = 6
	mi.mesh = sph
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _physics_process(delta: float) -> void:
	_t += delta / _dur
	if _t >= 1.0:
		_impact()
		return
	var p := _from.lerp(_to, _t)
	p.y += sin(_t * PI) * ARC_HEIGHT
	global_position = p
	if fmod(_t, 0.25) < delta / _dur:
		EffectsHub.spawn_debris(p, true)

func _impact() -> void:
	set_physics_process(false)
	AudioManager.play_3d(&"acid", _to, -2.0)
	if visual_only:
		AcidPuddle.spawn(get_parent(), _to, puddle_radius, 4.0, 0.0, color, null)
		queue_free()
		return
	# Estruturas atingidas diretamente.
	for n: Node in get_tree().get_nodes_in_group("structures"):
		var s := n as Structure
		if s == null or s.is_dead():
			continue
		var cp := s.closest_point(_to)
		if Vector2(cp.x - _to.x, cp.z - _to.z).length() <= puddle_radius:
			var info := DamageInfo.make(damage, source)
			info.structure_multiplier = structure_mult
			s.take_damage(info)
	AcidPuddle.spawn(get_parent(), _to, puddle_radius, puddle_time, damage * 0.35, color, source)
	queue_free()
