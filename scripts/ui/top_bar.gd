class_name TopBar
extends PanelContainer
## Barra superior central: recursos disponíveis (armazém + mochila).

const SHOWN_RESOURCES: Array[StringName] = [&"wood", &"stone", &"scrap", &"cloth", &"herbs", &"meat"]

var _res_labels: Dictionary = {}

func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.05, 0.05, 0.06, 0.82), Color(0.25, 0.22, 0.18), 1, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	add_child(row)
	for id in SHOWN_RESOURCES:
		var def := ResourceManager.get_def(id)
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		box.tooltip_text = "%s (armazém + mochila)\n%s" % [def.display_name, def.description] if def else ""
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(UIStyle.icon(def.icon if def else null, 36))
		var l := UIStyle.label("0", 22)
		box.add_child(l)
		_res_labels[id] = l
		row.add_child(box)

func _process(_delta: float) -> void:
	for id: StringName in _res_labels:
		(_res_labels[id] as Label).text = str(ResourceManager.available(id))
