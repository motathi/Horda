class_name ObjectivesPanel
extends PanelContainer
## "Objetivos do Dia" com selo de alerta e caixas de seleção.

var objectives: DailyObjectives
var _list: VBoxContainer

func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.hud_panel_style(Color(0.06, 0.06, 0.08, 0.82), 10))
	custom_minimum_size = Vector2(320, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var badge := UIStyle.icon(UIStyle.hud_icon("alert"), 34)
	head.add_child(badge)
	var t := UIStyle.label("Objetivos da Rodada", 20, Color.WHITE)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(t)
	col.add_child(head)
	var sep := ColorRect.new()
	sep.color = Color(UIStyle.GOLD_EDGE, 0.5)
	sep.custom_minimum_size = Vector2(0, 2)
	col.add_child(sep)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
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
		row.add_theme_constant_override("separation", 10)
		var box := Panel.new()
		box.custom_minimum_size = Vector2(22, 22)
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var st := StyleBoxFlat.new()
		st.bg_color = UIStyle.GREEN if o.done else Color(0.02, 0.02, 0.03, 0.9)
		st.border_color = UIStyle.GOLD_EDGE
		st.set_border_width_all(2)
		st.set_corner_radius_all(4)
		box.add_theme_stylebox_override("panel", st)
		row.add_child(box)
		var txt := String(o.text)
		if int(o.target) > 1:
			txt += " (%d/%d)" % [int(o.progress), int(o.target)]
		var l := UIStyle.label(txt, 17, UIStyle.TEXT_DIM if o.done else Color.WHITE)
		row.add_child(l)
		row.tooltip_text = "Recompensa: " + ResourceManager.cost_to_string(o.reward)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		_list.add_child(row)
