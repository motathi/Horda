extends Control
## Menu principal: novo jogo (dificuldade + duração do ciclo), continuar, sair.

var _diff: String = "normal"
var _cycle: String = "normal"
var _new_panel: Control
var _main_panel: Control

func _ready() -> void:
	GameManager.state = GameManager.State.MENU
	TimeManager.running = false
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/menu_background.jpg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	# Layout vertical: título no topo, painéis centralizados na parte de baixo.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 70)
	add_child(margin)
	var layout := VBoxContainer.new()
	margin.add_child(layout)
	var title := UIStyle.label("HORDA", 110, UIStyle.GOLD)
	title.add_theme_constant_override("outline_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)
	var sub := UIStyle.label("Noites de Sobrevivência", 30, UIStyle.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(sub)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(spacer)
	_main_panel = _build_main()
	layout.add_child(_main_panel)
	_new_panel = _build_new_game()
	layout.add_child(_new_panel)
	var ver := UIStyle.label("Protótipo — Fase 1", 14, UIStyle.TEXT_DIM)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.position = Vector2(-16, -12)
	add_child(ver)

func _place(p: Control) -> void:
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

func _build_main() -> Control:
	var panel := UIStyle.panel()
	panel.custom_minimum_size = Vector2(360, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var cont := UIStyle.button("Continuar", 22)
	cont.disabled = not SaveManager.has_save()
	if SaveManager.has_save():
		var meta := SaveManager.peek_meta()
		cont.text = "Continuar (Dia %d)" % int(meta.get("day", 1))
	cont.pressed.connect(func() -> void: GameManager.continue_game())
	col.add_child(cont)
	var new := UIStyle.button("Novo jogo", 22)
	new.pressed.connect(func() -> void:
		_main_panel.visible = false
		_new_panel.visible = true)
	col.add_child(new)
	var quit := UIStyle.button("Sair", 22)
	quit.pressed.connect(func() -> void: get_tree().quit())
	col.add_child(quit)
	_place(panel)
	return panel

func _build_new_game() -> Control:
	var panel := UIStyle.panel()
	panel.custom_minimum_size = Vector2(520, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(UIStyle.label("Novo jogo", 28, UIStyle.GOLD))
	col.add_child(UIStyle.label("Dificuldade", 18))
	col.add_child(_choice_row({"facil": "Fácil", "normal": "Normal", "dificil": "Difícil"}, "normal", func(k: String) -> void: _diff = k))
	col.add_child(UIStyle.label("Duração do ciclo dia/noite", 18))
	col.add_child(_choice_row({"normal": "Normal (22 min)", "rapido": "Rápido (11 min)"}, "normal", func(k: String) -> void: _cycle = k))
	if SaveManager.has_save():
		col.add_child(UIStyle.label("Atenção: iniciar um novo jogo substitui o salvamento atual no próximo amanhecer.", 13, Color(1, 0.6, 0.4)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var back := UIStyle.button("Voltar", 20)
	back.pressed.connect(func() -> void:
		_new_panel.visible = false
		_main_panel.visible = true)
	var start := UIStyle.button("Começar", 20)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(func() -> void: GameManager.start_new_game(_diff, _cycle))
	row.add_child(back)
	row.add_child(start)
	col.add_child(row)
	panel.visible = false
	_place(panel)
	return panel

func _choice_row(options: Dictionary, default_key: String, on_pick: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for k: String in options:
		var b := UIStyle.button(options[k], 17)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = k == default_key
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: on_pick.call(k))
		row.add_child(b)
	return row
