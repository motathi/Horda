class_name HUD
extends CanvasLayer
## Interface do jogo: monta e coordena barras, painéis, avisos e menus.

var top_bar: TopBar
var bottom_bar: BottomBar
var selection: SelectionPanel
var minimap: Minimap
var time_panel: TimePanel
var objectives_panel: ObjectivesPanel
var inventory: InventoryPanel
var base_panel: BasePanel
var _feed: VBoxContainer
var _banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_tween: Tween
var _interact_box: VBoxContainer
var _interact_bar: ProgressBar
var _interact_label: Label
var _death_label: Label
var _hint: Label
var _pause: Control
var _help: Control
var _game_over: Control
var _vignette: ColorRect
var _hero: Hero
var touch_controls: TouchControls

func _ready() -> void:
	layer = 10
	add_to_group("hud")
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Vinheta vermelha ao sofrer dano / à noite
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.material = _vignette_material()
	root.add_child(_vignette)

	top_bar = TopBar.new()
	top_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top_bar.position.y = 8
	root.add_child(top_bar)

	time_panel = TimePanel.new()
	time_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	time_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	time_panel.position = Vector2(-12, 8)
	root.add_child(time_panel)

	objectives_panel = ObjectivesPanel.new()
	objectives_panel.position = Vector2(12, 10)
	root.add_child(objectives_panel)

	var mm_frame := UIStyle.panel()
	mm_frame.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mm_frame.grow_vertical = Control.GROW_DIRECTION_BEGIN
	mm_frame.position = Vector2(12, -34)
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(250, 250)
	mm_frame.add_child(minimap)
	root.add_child(mm_frame)

	bottom_bar = BottomBar.new()
	bottom_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_bar.position.y = -8
	root.add_child(bottom_bar)

	selection = SelectionPanel.new()
	selection.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	selection.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	selection.grow_vertical = Control.GROW_DIRECTION_BEGIN
	selection.position = Vector2(-12, -12)
	root.add_child(selection)

	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_feed.position = Vector2(14, -110)
	_feed.custom_minimum_size = Vector2(460, 0)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)

	_banner = VBoxContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position.y = 150
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_title = UIStyle.label("", 54, UIStyle.RED)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.add_theme_constant_override("outline_size", 10)
	_banner_sub = UIStyle.label("", 22, UIStyle.TEXT)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_title)
	_banner.add_child(_banner_sub)
	_banner.modulate.a = 0.0
	root.add_child(_banner)

	_interact_box = VBoxContainer.new()
	_interact_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_interact_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_interact_box.position.y = -190
	_interact_box.custom_minimum_size = Vector2(300, 0)
	_interact_label = UIStyle.label("", 16)
	_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_bar = UIStyle.bar(UIStyle.GOLD, 14)
	_interact_box.add_child(_interact_label)
	_interact_box.add_child(_interact_bar)
	_interact_box.visible = false
	root.add_child(_interact_box)

	_hint = UIStyle.label("F1: Controles   •   I: Inventário   •   B: Base   •   Esc: Menu", 14, UIStyle.TEXT_DIM)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.position = Vector2(14, -14)
	root.add_child(_hint)

	_death_label = UIStyle.label("", 30, UIStyle.RED)
	_death_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.visible = false
	_death_label.position.y = 110
	root.add_child(_death_label)

	inventory = InventoryPanel.new()
	_center(inventory, root)
	base_panel = BasePanel.new()
	_center(base_panel, root)
	_help = _build_help()
	_center(_help, root)
	_pause = _build_pause()
	_center(_pause, root)
	_game_over = _build_game_over()
	_center(_game_over, root)

	if Platform.touch:
		_setup_touch(root, mm_frame)

	EventBus.message.connect(_on_message)
	EventBus.banner.connect(show_banner)
	EventBus.interaction_progress.connect(_on_interaction)
	EventBus.inventory_full.connect(func(_id: StringName) -> void: _on_message("Mochila cheia! Volte à base para guardar os recursos.", Color(1, 0.55, 0.3)))
	EventBus.base_core_destroyed.connect(func() -> void: get_tree().create_timer(2.5).timeout.connect(_show_game_over))
	EventBus.hero_damaged.connect(func(_a: float) -> void: _flash_vignette())
	TimeManager.night_warning.connect(_on_night_warning)
	TimeManager.phase_changed.connect(_on_phase_changed)

## Layout para celular: joystick/botões, painéis reposicionados e menores.
func _setup_touch(root: Control, mm_frame: Control) -> void:
	_hint.visible = false
	bottom_bar.set_compact()
	minimap.custom_minimum_size = Vector2(112, 112)
	time_panel.set_compact()
	mm_frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mm_frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mm_frame.grow_vertical = Control.GROW_DIRECTION_END
	mm_frame.offset_right = -12
	mm_frame.offset_left = -12 - 134
	mm_frame.offset_top = 124
	mm_frame.offset_bottom = 124 + 130
	objectives_panel.position = Vector2(8, 64)
	objectives_panel.scale = Vector2.ONE * 0.85
	selection.set_anchors_preset(Control.PRESET_CENTER_TOP)
	selection.grow_vertical = Control.GROW_DIRECTION_END
	selection.position.y = 64
	_feed.position = Vector2(10, -60)
	touch_controls = TouchControls.new()
	root.add_child(touch_controls)
	root.move_child(touch_controls, 1)
	touch_controls.toggle_inventory.connect(func() -> void:
		inventory.visible = not inventory.visible
		base_panel.visible = false)
	touch_controls.toggle_base.connect(func() -> void:
		base_panel.visible = not base_panel.visible
		inventory.visible = false)
	var menu_btn := UIStyle.button("II", 24)
	menu_btn.custom_minimum_size = Vector2(58, 58)
	menu_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	menu_btn.position = Vector2(8, 4)
	menu_btn.pressed.connect(_toggle_pause)
	root.add_child(menu_btn)
	objectives_panel.position = Vector2(8, 66)

func is_menu_paused() -> bool:
	return _pause.visible

func _center(c: Control, root: Control) -> void:
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(c)

func bind(hero: Hero, services: BaseServices, regions: Array[Dictionary], lootables: Dictionary, objectives: DailyObjectives) -> void:
	_hero = hero
	objectives_panel.bind(objectives)
	if touch_controls:
		touch_controls.hero = hero
	bottom_bar.bind(hero)
	base_panel.services = services
	base_panel.hero = hero
	minimap.regions = regions
	minimap.lootables = lootables

# --- Entrada -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if inventory.visible or base_panel.visible or _help.visible:
			inventory.visible = false
			base_panel.visible = false
			_help.visible = false
		elif not _game_over.visible:
			_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if not GameManager.is_playing() or get_tree().paused:
		return
	if event.is_action_pressed("inventory"):
		inventory.visible = not inventory.visible
		base_panel.visible = false
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("base_menu"):
		base_panel.visible = not base_panel.visible
		inventory.visible = false
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("help"):
		_help.visible = not _help.visible
	elif event.is_action_pressed("quick_save"):
		_quick_save()
	elif event.is_action_pressed("skip_phase"):
		TimeManager.advance_phase()
		_on_message("[Depuração] Período avançado para: %s" % TimeManager.phase_name(), UIStyle.TEXT_DIM)

func _quick_save() -> void:
	if SaveManager.save_game():
		_on_message("Jogo salvo.", UIStyle.GREEN)
	else:
		_on_message("Não é possível salvar durante a noite.", UIStyle.RED)

# --- Atualização -------------------------------------------------------------

func _process(_delta: float) -> void:
	if _hero and _hero.is_dead() and GameManager.is_playing():
		_death_label.visible = true
		_death_label.text = "Você caiu!\nRenascendo em %d..." % ceili(_hero.respawn_seconds_left())
	else:
		_death_label.visible = false
	var night := 1.0 - TimeManager.daylight()
	var mat := _vignette.material as ShaderMaterial
	var flash: float = mat.get_shader_parameter("flash")
	mat.set_shader_parameter("flash", maxf(0.0, flash - _delta * 2.0))
	mat.set_shader_parameter("night", night * 0.55)

func _flash_vignette() -> void:
	(_vignette.material as ShaderMaterial).set_shader_parameter("flash", 0.8)

func _vignette_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float flash = 0.0;
uniform float night = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	float v = smoothstep(0.35, 0.75, d);
	vec3 col = mix(vec3(0.0, 0.0, 0.05), vec3(0.6, 0.0, 0.0), clamp(flash, 0.0, 1.0));
	COLOR = vec4(col, v * clamp(night + flash, 0.0, 0.9));
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("flash", 0.0)
	return m

func _on_message(text: String, color: Color) -> void:
	var l := UIStyle.label(text, 16, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(460, 0)
	_feed.add_child(l)
	while _feed.get_child_count() > 7:
		_feed.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)

func show_banner(title: String, sub: String, color: Color) -> void:
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", color)
	_banner_sub.text = sub
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.4)
	_banner_tween.tween_interval(3.5)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 1.0)

func _on_interaction(label: String, ratio: float) -> void:
	_interact_box.visible = ratio >= 0.0
	_interact_label.text = label
	_interact_bar.value = ratio * 100.0

func _on_night_warning(seconds: float) -> void:
	show_banner("A NOITE SE APROXIMA", "A horda chega em %d segundos. Volte para a base!" % int(seconds), Color(1.0, 0.55, 0.2))
	AudioManager.play(&"bell")

func _on_phase_changed(phase: int, day: int) -> void:
	if phase == TimeManager.Phase.DUSK:
		_on_message("O sol está se pondo... prepare as defesas.", Color(1.0, 0.6, 0.3))
	elif phase == TimeManager.Phase.DAY and day > 1:
		_on_message("Dia %d começou. Explore e colete recursos." % day, Color(1.0, 0.9, 0.5))

# --- Menus -------------------------------------------------------------------

func _toggle_pause() -> void:
	var p := not get_tree().paused
	GameManager.set_paused(p)
	_pause.visible = get_tree().paused

func _build_pause() -> Control:
	var panel := UIStyle.panel()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.custom_minimum_size = Vector2(340, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var t := UIStyle.label("Pausado", 30, UIStyle.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var resume := UIStyle.button("Continuar")
	resume.pressed.connect(_toggle_pause)
	col.add_child(resume)
	var save := UIStyle.button("Salvar jogo (F5)")
	save.pressed.connect(func() -> void:
		var ok := SaveManager.can_save()
		get_tree().paused = false
		if ok:
			SaveManager.save_game()
		get_tree().paused = true
		_on_message("Jogo salvo." if ok else "Não é possível salvar durante a noite.", UIStyle.GREEN if ok else UIStyle.RED))
	col.add_child(save)
	var help := UIStyle.button("Controles (F1)")
	help.pressed.connect(func() -> void: _help.visible = not _help.visible)
	col.add_child(help)
	var menu := UIStyle.button("Menu principal")
	menu.pressed.connect(func() -> void: GameManager.return_to_menu())
	col.add_child(menu)
	if not OS.has_feature("web"):
		var quit := UIStyle.button("Sair do jogo")
		quit.pressed.connect(func() -> void: get_tree().quit())
		col.add_child(quit)
	panel.visible = false
	return panel

func _build_help() -> Control:
	var panel := UIStyle.panel()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var col := VBoxContainer.new()
	panel.add_child(col)
	col.add_child(UIStyle.label("Controles", 26, UIStyle.GOLD))
	var lines := [
		["WASD", "Mover o herói"],
		["Clique direito (chão)", "Mover até o ponto"],
		["Clique direito (inimigo)", "Selecionar e atacar"],
		["Clique esquerdo / Espaço", "Atacar na direção do cursor (também corta árvores e quebra pedras)"],
		["E", "Saquear caixas, carros e armários próximos"],
		["1 / 2", "Comer carne / usar curativo"],
		["I ou Tab", "Inventário (mochila e armazém)"],
		["B", "Menu da base: reparar muros/núcleo, afiar arma, fabricar curativos"],
		["Roda do mouse", "Zoom"],
		["Q / R ou botão do meio", "Girar câmera"],
		["C", "Centralizar câmera no herói"],
		["F5", "Salvar (somente de dia)"],
		["F8", "[Depuração] Avançar período do dia"],
		["Esc", "Pausar / fechar janelas"],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	for l in lines:
		grid.add_child(UIStyle.label(l[0], 16, UIStyle.GOLD))
		grid.add_child(UIStyle.label(l[1], 16))
	col.add_child(grid)
	col.add_child(HSeparator.new())
	if Platform.touch:
		col.add_child(UIStyle.label("Celular: joystick à esquerda para andar • botão grande para atacar (mira automática)\nToque no chão para ir até lá, num inimigo para atacá-lo • E saqueia • pinça = zoom", 15, UIStyle.GOLD))
	var goal := UIStyle.label("Objetivo: explore de dia, colete recursos e volte antes do anoitecer.\nÀ noite a horda ataca a base — proteja o Núcleo até o amanhecer.", 15, UIStyle.TEXT_DIM)
	col.add_child(goal)
	var close := UIStyle.button("Fechar")
	close.pressed.connect(func() -> void: panel.visible = false)
	col.add_child(close)
	panel.visible = false
	return panel

func _build_game_over() -> Control:
	var panel := UIStyle.panel()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.custom_minimum_size = Vector2(420, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.name = "Col"
	panel.add_child(col)
	panel.visible = false
	return panel

func _show_game_over() -> void:
	var col := _game_over.get_node("Col") as VBoxContainer
	for c in col.get_children():
		c.queue_free()
	var t := UIStyle.label("A BASE CAIU", 36, UIStyle.RED)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var s := GameManager.stats
	col.add_child(UIStyle.label("Noites sobrevividas: %d" % int(s.nights_survived), 18))
	col.add_child(UIStyle.label("Zumbis eliminados: %d" % int(s.kills), 18))
	col.add_child(UIStyle.label("Recursos coletados: %d" % int(s.items_collected), 18))
	var again := UIStyle.button("Jogar novamente")
	again.pressed.connect(func() -> void: GameManager.start_new_game(GameManager.difficulty, GameManager.cycle_preset))
	col.add_child(again)
	var menu := UIStyle.button("Menu principal")
	menu.pressed.connect(func() -> void: GameManager.return_to_menu())
	col.add_child(menu)
	_game_over.visible = true
