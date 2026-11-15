class_name ObjectivesPanel
extends PanelContainer
## "Objetivos do Dia" (canto superior esquerdo), com caixas de seleção.

var objectives: DailyObjectives
var _list: VBoxContainer

func _ready() -> void:
	var st := UIStyle.panel_style(Color(0.04, 0.04, 0.05, 0.6), Color(0, 0, 0, 0), 0, 6)
	add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	add_child(col)
	col.add_child(UIStyle.label("Objetivos do Dia", 20, UIStyle.TEXT))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	col.add_child(_list)
	EventBus.objectives_changed.connect(_refresh)

func bind(o: DailyObjectives) -> void:
	objectives = o
	_refresh()

func _refresh() -> void:
	if objectives == null:
		return
	for c in _list.get_children():
		c.queue_free()
	for o in objectives.objectives:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var box := UIStyle.label("☑" if o.done else "☐", 18, UIStyle.GREEN if o.done else UIStyle.TEXT_DIM)
		row.add_child(box)
		var txt := String(o.text)
		if int(o.target) > 1:
			txt += " (%d/%d)" % [int(o.progress), int(o.target)]
		var l := UIStyle.label(txt, 15, UIStyle.TEXT_DIM if o.done else UIStyle.TEXT)
		row.add_child(l)
		row.tooltip_text = "Recompensa: " + ResourceManager.cost_to_string(o.reward)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		_list.add_child(row)
