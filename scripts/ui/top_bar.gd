class_name TopBar
extends HBoxContainer
## Recursos no topo (armazém + mochila) em "pílulas" com ícone e botão "+".
## O "+" abre o menu da base (reparos e fabricação).

signal plus_pressed

const SHOWN: Array[StringName] = [&"wood", &"stone", &"scrap", &"cloth", &"herbs"]
const ICONS := {&"wood": "wood", &"stone": "stone", &"scrap": "scrap", &"cloth": "cloth", &"herbs": "herbs"}

var _labels: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id in SHOWN:
		add_child(_pill(id))

func _pill(id: StringName) -> Control:
	var def := ResourceManager.get_def(id)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(112, 50)
	holder.tooltip_text = "%s (armazém + mochila)\n%s" % [def.display_name, def.description] if def else ""
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	var bg := Panel.new()
	var st := UIStyle.hud_panel_style(Color(0.06, 0.06, 0.08, 0.88), 9)
	st.set_border_width_all(2)
	bg.add_theme_stylebox_override("panel", st)
	bg.position = Vector2(16, 7)
	bg.size = Vector2(96, 38)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bg)
	var tex := UIStyle.hud_icon(ICONS.get(id, String(id)))
	var ic := UIStyle.icon(tex if tex else (def.icon if def else null), 48)
	ic.position = Vector2(0, 1)
	ic.size = Vector2(48, 48)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ic)
	var l := UIStyle.label("0", 22, Color.WHITE)
	l.position = Vector2(46, 9)
	l.size = Vector2(38, 32)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	holder.add_child(l)
	_labels[id] = l
	var plus := Button.new()
	plus.text = "+"
	plus.flat = true
	plus.focus_mode = Control.FOCUS_NONE
	plus.add_theme_font_size_override("font_size", 24)
	plus.add_theme_color_override("font_color", UIStyle.GOLD)
	plus.add_theme_color_override("font_hover_color", Color.WHITE)
	plus.add_theme_color_override("font_outline_color", Color.BLACK)
	plus.add_theme_constant_override("outline_size", 4)
	plus.position = Vector2(86, 5)
	plus.size = Vector2(26, 40)
	plus.tooltip_text = "Menu da base: reparos e fabricação (B)"
	plus.pressed.connect(func() -> void: plus_pressed.emit())
	holder.add_child(plus)
	return holder

func _process(_delta: float) -> void:
	for id: StringName in _labels:
		(_labels[id] as Label).text = str(ResourceManager.available(id))
