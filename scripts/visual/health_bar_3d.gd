class_name HealthBar3D
extends MeshInstance3D
## Barra de vida flutuante (billboard), ligada a um HealthComponent.

const SHADER := preload("res://assets/effects/shaders/health_bar.gdshader")

@export var bar_width: float = 1.2
@export var color: Color = Color(0.85, 0.15, 0.1)
@export var hide_when_full: bool = true

var _health: HealthComponent
var _material: ShaderMaterial

func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	var q := QuadMesh.new()
	q.size = Vector2(bar_width, bar_width * 0.13)
	mesh = q
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.set_shader_parameter("fill_color", color)

func bind(h: HealthComponent) -> void:
	_health = h
	h.changed.connect(_on_changed)
	_on_changed(h.current, h.max_health)

func _on_changed(cur: float, maxv: float) -> void:
	var r := cur / maxv if maxv > 0.0 else 0.0
	_material.set_shader_parameter("ratio", r)
	visible = r > 0.0 and (not hide_when_full or r < 0.999)
