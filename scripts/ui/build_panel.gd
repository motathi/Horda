class_name BuildPanel
extends PanelContainer
## Menu "Construir": cartões com ícone, nome, custo e atributos. Escolher um
## cartão inicia o posicionamento.

signal chosen(def: BuildingDef)

var _grid: GridContainer
var _t: float = 0.0

func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.hud_panel_style(Color(0.06, 0.06, 0.08, 0.95), 12))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_child(UIStyle.icon(UIStyle.hud_icon("build"), 40))
	var title := UIStyle.label("Construir", 26, Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UIStyle.button("X", 18)
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)
	col.add_child(head)
	col.add_child(UIStyle.label("Construa até %d m da fortaleza. Zumbis atacam o que estiver no caminho." % int(BuildManager.BUILD_RADIUS), 14, UIStyle.TEXT_DIM))
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	col.add_child(_grid)
	visible = false
	visibility_changed.connect(_rebuild)

func _process(delta: float) -> void:
	if not visible:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.5
		_rebuild()

func _rebuild() -> void:
	if not visible:
		return
	for c in _grid.get_children():
		c.queue_free()
	for d in Building.all_defs():
		_grid.add_child(_card(d))

func _card(d: BuildingDef) -> Control:
	var unlocked := d.is_unlocked()
	var afford := unlocked and ResourceManager.can_afford(d.cost)
	var b := Button.new()
	b.custom_minimum_size = Vector2(190, 218)
	b.focus_mode = Control.FOCUS_NONE
	var st := UIStyle.hud_panel_style(Color(0.1, 0.09, 0.08, 0.95), 10)
	st.border_color = UIStyle.GOLD_EDGE if afford else Color(0.35, 0.3, 0.25)
	var hv := st.duplicate() as StyleBoxFlat
	hv.bg_color = Color(0.18, 0.15, 0.1, 0.98)
	hv.border_color = UIStyle.GOLD
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("focus", st)
	b.tooltip_text = d.description
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 8
	col.offset_right = -8
	col.offset_top = 8
	col.offset_bottom = -8
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var ic := UIStyle.icon(d.icon(), 76)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.modulate = Color.WHITE if afford else Color(0.55, 0.55, 0.55)
	col.add_child(ic)
	var n := UIStyle.label(d.display_name, 17, Color.WHITE)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(n)
	var stats := UIStyle.label(d.stats_text() if unlocked else "Libera na horda %d" % d.unlock_wave, 12, UIStyle.TEXT_DIM if unlocked else UIStyle.GOLD)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(stats)
	var cost := HBoxContainer.new()
	cost.alignment = BoxContainer.ALIGNMENT_CENTER
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id: StringName in d.cost:
		var need := int(d.cost[id])
		var have := ResourceManager.available(id)
		var ci := UIStyle.icon(UIStyle.hud_icon(String(id)) if UIStyle.hud_icon(String(id)) else ResourceManager.get_def(id).icon, 24)
		ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost.add_child(ci)
		cost.add_child(UIStyle.label(str(need), 15, UIStyle.GREEN if have >= need else UIStyle.RED))
	col.add_child(cost)
	b.disabled = not unlocked
	b.add_theme_stylebox_override("disabled", st)
	b.pressed.connect(func() -> void:
		visible = false
		chosen.emit(d))
	return b
