class_name HUD
extends CanvasLayer
## Interface do jogo: monta e coordena barras, painéis, avisos e menus.

var top_bar: TopBar
var hero_panel: HeroPanel
var selection: SelectionPanel
var minimap: Minimap
var time_panel: TimePanel
var objectives_panel: ObjectivesPanel
var inventory: InventoryPanel
var character: CharacterPanel
var base_panel: BasePanel
var actions: HudActions
var build_panel: BuildPanel
var placement_bar: PlacementBar
var build_manager: BuildManager
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
var _hit_flash: float = 0.0
var _beat_t: float = 0.0
var _pulse: float = 0.0
var _hero: Hero

## Ancora `c` num canto/borda com deslocamento fixo; o contêiner cresce para dentro da tela.
func _anchor(c: Control, preset: Control.LayoutPreset, off: Vector2, gh: Control.GrowDirection, gv: Control.GrowDirection) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = off.x
	c.offset_right = off.x
	c.offset_top = off.y
	c.offset_bottom = off.y
	c.grow_horizontal = gh
	c.grow_vertical = gv

func _ready() -> void:
	layer = 10
	add_to_group("hud")
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIStyle.theme()
	add_child(root)
	# Vinheta vermelha ao sofrer dano / à noite
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.material = _vignette_material()
	root.add_child(_vignette)

	# Botões de ação (e joystick no celular) ficam atrás dos painéis/menus.
	actions = HudActions.new()
	actions.touch_enabled = Platform.touch
	root.add_child(actions)

	# Canto superior esquerdo: herói + objetivos
	hero_panel = HeroPanel.new()
	hero_panel.position = Vector2(12, 10)
	root.add_child(hero_panel)
	hero_panel.portrait_pressed.connect(_toggle_character)

	objectives_panel = ObjectivesPanel.new()
	_anchor(objectives_panel, Control.PRESET_TOP_LEFT, Vector2(16, 160), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END)
	root.add_child(objectives_panel)

	# Topo central: recursos
	top_bar = TopBar.new()
	_anchor(top_bar, Control.PRESET_TOP_LEFT, Vector2(354, 10), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END)
	root.add_child(top_bar)
	top_bar.plus_pressed.connect(_toggle_base)

	# Canto superior direito: ciclo dia/noite + minimapa
	time_panel = TimePanel.new()
	_anchor(time_panel, Control.PRESET_TOP_RIGHT, Vector2(-14, 10), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	root.add_child(time_panel)
	time_panel.pressed.connect(_toggle_pause)

	var mm_holder := Control.new()
	mm_holder.custom_minimum_size = Vector2(196, 196)
	_anchor(mm_holder, Control.PRESET_TOP_RIGHT, Vector2(-14, 172), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	mm_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mm_holder)
	var mm_frame := PanelContainer.new()
	var mm_style := UIStyle.hud_panel_style(Color(0.04, 0.05, 0.03, 0.92), 8)
	mm_style.set_content_margin_all(6)
	mm_frame.add_theme_stylebox_override("panel", mm_style)
	mm_frame.position = Vector2(0, 12)
	mm_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(172, 172)
	mm_frame.add_child(minimap)
	mm_holder.add_child(mm_frame)
	var north := _NorthBadge.new()
	north.position = Vector2(92, 12)
	mm_holder.add_child(north)

	selection = SelectionPanel.new()
	_anchor(selection, Control.PRESET_CENTER_BOTTOM, Vector2(0, -14), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	root.add_child(selection)

	_feed = VBoxContainer.new()
	_anchor(_feed, Control.PRESET_TOP_LEFT, Vector2(16, 330), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END)
	_feed.custom_minimum_size = Vector2(440, 0)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)

	_banner = VBoxContainer.new()
	_anchor(_banner, Control.PRESET_CENTER_TOP, Vector2(0, 150), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
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
	_anchor(_interact_box, Control.PRESET_CENTER_BOTTOM, Vector2(0, -150), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	_interact_box.custom_minimum_size = Vector2(300, 0)
	_interact_label = UIStyle.label("", 16)
	_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_bar = UIStyle.bar(UIStyle.GOLD, 14)
	_interact_box.add_child(_interact_label)
	_interact_box.add_child(_interact_bar)
	_interact_box.visible = false
	root.add_child(_interact_box)

	_hint = UIStyle.label("F1: Controles  •  P: Personagem  •  I: Inventário  •  B: Base  •  Esc: Menu", 14, UIStyle.TEXT_DIM)
	_anchor(_hint, Control.PRESET_BOTTOM_LEFT, Vector2(14, -10), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	_hint.visible = not Platform.touch
	root.add_child(_hint)

	_death_label = UIStyle.label("", 30, UIStyle.RED)
	_anchor(_death_label, Control.PRESET_CENTER, Vector2(0, 110), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.visible = false
	root.add_child(_death_label)

	_research_pill = _build_research_pill()
	_anchor(_research_pill, Control.PRESET_CENTER_TOP, Vector2(0, 62), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	root.add_child(_research_pill)
	Tech.researched.connect(func(_d: TechDef) -> void: _research_pill.visible = false)

	placement_bar = PlacementBar.new()
	_anchor(placement_bar, Control.PRESET_CENTER_BOTTOM, Vector2(0, -14), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	root.add_child(placement_bar)

	inventory = InventoryPanel.new()
	_center(inventory, root)
	character = CharacterPanel.new()
	_center(character, root)
	character.inventory_requested.connect(_toggle_inventory)
	build_panel = BuildPanel.new()
	_center(build_panel, root)
	actions.build_pressed.connect(_toggle_build)
	base_panel = BasePanel.new()
	_center(base_panel, root)
	_help = _build_help()
	_center(_help, root)
	_pause = _build_pause()
	_center(_pause, root)
	_settings = SettingsPanel.new()
	_center(_settings, root)
	_settings.closed.connect(func() -> void: _pause.visible = true)
	_game_over = _build_game_over()
	_center(_game_over, root)

	EventBus.message.connect(_on_message)
	EventBus.banner.connect(show_banner)
	EventBus.interaction_progress.connect(_on_interaction)
	EventBus.inventory_full.connect(func(_id: StringName) -> void: _on_message("Mochila cheia! Volte à base para guardar os recursos.", Color(1, 0.55, 0.3)))
	EventBus.base_core_destroyed.connect(func() -> void: get_tree().create_timer(2.5).timeout.connect(_show_game_over))
	EventBus.victory.connect(func() -> void: get_tree().create_timer(3.0).timeout.connect(_show_game_over.bind(true)))
	EventBus.hero_damaged.connect(func(_a: float) -> void: _flash_vignette())
	TimeManager.night_warning.connect(_on_night_warning)
	TimeManager.phase_changed.connect(_on_phase_changed)

func _toggle_inventory() -> void:
	inventory.visible = not inventory.visible
	base_panel.visible = false
	build_panel.visible = false
	character.visible = false

func _toggle_character() -> void:
	character.visible = not character.visible
	inventory.visible = false
	base_panel.visible = false
	build_panel.visible = false

func _toggle_base() -> void:
	base_panel.visible = not base_panel.visible
	inventory.visible = false
	build_panel.visible = false
	character.visible = false

func _toggle_build() -> void:
	if build_manager and build_manager.is_active():
		build_manager.cancel()
		return
	build_panel.visible = not build_panel.visible
	inventory.visible = false
	base_panel.visible = false
	character.visible = false

var _research_pill: PanelContainer
var _research_pill_label: Label
var _research_pill_bar: ProgressBar
var _research_pill_icon: TextureRect

## Pílula no topo: pesquisa em andamento (ícone, nome e progresso).
func _build_research_pill() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIStyle.hud_panel_style(UIStyle.PANEL_BG, 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	_research_pill_icon = TextureRect.new()
	_research_pill_icon.custom_minimum_size = Vector2(28, 28)
	_research_pill_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_research_pill_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(_research_pill_icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	_research_pill_label = UIStyle.label("", 12, Color(0.6, 0.85, 1.0))
	v.add_child(_research_pill_label)
	_research_pill_bar = UIStyle.hud_bar(Color(0.35, 0.75, 1.0), 6)
	_research_pill_bar.custom_minimum_size = Vector2(150, 6)
	v.add_child(_research_pill_bar)
	p.visible = false
	return p

func _process_research_pill() -> void:
	var d := Tech.active_def()
	_research_pill.visible = d != null and GameManager.is_playing()
	if d:
		_research_pill_icon.texture = d.icon()
		_research_pill_label.text = "%s  %ds" % [d.display_name, ceili(d.research_time - Tech.progress)]
		_research_pill_bar.value = Tech.ratio() * 100.0

## Selo "N" (norte) no topo do minimapa.
class _NorthBadge extends Control:
	func _draw() -> void:
		UIStyle.draw_badge(self, Vector2.ZERO, 12.0, "N", 15)

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
	actions.hero = hero
	hero_panel.hero = hero
	character.hero = hero
	base_panel.services = services
	base_panel.hero = hero
	minimap.regions = regions
	minimap.lootables = lootables

var army: Army
var _army_pill: Button

## Exército: aba no menu da base + pílula no topo (toque troca a ordem; tecla V).
func bind_army(a: Army) -> void:
	army = a
	base_panel.army = a
	_army_pill = Button.new()
	_army_pill.focus_mode = Control.FOCUS_NONE
	_army_pill.icon = UIStyle.hud_icon("army")
	_army_pill.expand_icon = false
	_army_pill.add_theme_constant_override("icon_max_width", 28)
	_army_pill.add_theme_font_size_override("font_size", 14)
	_army_pill.add_theme_stylebox_override("normal", UIStyle.hud_panel_style(UIStyle.PANEL_BG, 8))
	_army_pill.add_theme_stylebox_override("hover", UIStyle.hud_panel_style(Color(0.15, 0.13, 0.1, 0.95), 8))
	_army_pill.add_theme_stylebox_override("pressed", UIStyle.hud_panel_style(Color(0.15, 0.13, 0.1, 0.95), 8))
	_army_pill.tooltip_text = "Toque para trocar a ordem do exército (V)"
	_army_pill.pressed.connect(func() -> void: _on_message(army.cycle_order(), Color(0.55, 0.85, 1.0)))
	_anchor(_army_pill, Control.PRESET_CENTER_TOP, Vector2(0, 100), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	_research_pill.get_parent().add_child(_army_pill)
	# Fica atrás dos painéis (menus abrem por cima).
	_army_pill.get_parent().move_child(_army_pill, _research_pill.get_index() + 1)
	_army_pill.visible = false
	a.changed.connect(_update_army_pill)

func _update_army_pill() -> void:
	if _army_pill == null:
		return
	var n := army.alive_count()
	_army_pill.visible = n > 0 or not army.queue.is_empty()
	_army_pill.text = "Exército %d/%d — %s" % [n, army.capacity(), Army.ORDER_NAMES[army.order]]

func bind_build(m: BuildManager) -> void:
	build_manager = m
	placement_bar.bind(m)
	build_panel.chosen.connect(func(d: BuildingDef) -> void: m.start(d))
	m.mode_changed.connect(func(a: bool) -> void:
		if a:
			selection.visible = false)

# --- Entrada -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _settings and _settings.visible:
			_settings.visible = false
			_pause.visible = true
		elif inventory.visible or base_panel.visible or _help.visible or build_panel.visible or character.visible:
			character.visible = false
			inventory.visible = false
			base_panel.visible = false
			build_panel.visible = false
			_help.visible = false
		elif not _game_over.visible:
			_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if not GameManager.is_playing() or get_tree().paused:
		return
	if event.is_action_pressed("build_menu"):
		_toggle_build()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		_toggle_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("character"):
		_toggle_character()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("army_order") and army:
		_on_message(army.cycle_order(), Color(0.55, 0.85, 1.0))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("base_menu"):
		_toggle_base()
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
	if _research_pill:
		_process_research_pill()
	if _army_pill and Engine.get_process_frames() % 15 == 0:
		_update_army_pill()
	if _hero and _hero.is_dead() and GameManager.is_playing():
		_death_label.visible = true
		_death_label.text = "Você caiu!\nRenascendo em %d..." % ceili(_hero.respawn_seconds_left())
	else:
		_death_label.visible = false
	_update_screen_fx(_delta)

## Efeitos de tela de terror: vinheta escura à noite, granulado de filme, borda
## vermelha na lua de sangue, clarão dos relâmpagos e pulso vermelho com batimento
## cardíaco quando a vida está baixa.
func _update_screen_fx(delta: float) -> void:
	var night := 1.0 - TimeManager.daylight()
	var mat := _vignette.material as ShaderMaterial
	_hit_flash = maxf(0.0, _hit_flash - delta * 2.0)
	var dnv := DayNightVisuals.current
	var low := 0.0
	if _hero and not _hero.is_dead() and GameManager.is_playing():
		low = clampf(1.0 - _hero.health.ratio() / 0.35, 0.0, 1.0)
	# Batimento cardíaco: mais rápido quanto menor a vida.
	_beat_t -= delta
	_pulse = maxf(0.0, _pulse - delta * 2.5)
	if low > 0.0 and _beat_t <= 0.0:
		_beat_t = lerpf(1.15, 0.55, low)
		_pulse = 1.0
		AudioManager.play(&"heartbeat_fast" if low > 0.6 else &"heartbeat", lerpf(-8.0, 0.0, low))
	mat.set_shader_parameter("flash", _hit_flash)
	mat.set_shader_parameter("night", 0.2 + night * 0.45)
	mat.set_shader_parameter("low_hp", low * (0.55 + 0.45 * _pulse))
	mat.set_shader_parameter("blood", dnv._blood_tint if dnv else 0.0)
	mat.set_shader_parameter("lightning", dnv.lightning_flash() * 0.35 if dnv else 0.0)
	mat.set_shader_parameter("grain", 0.05 + night * 0.05 if Settings.quality > 0 else 0.0)

func _flash_vignette() -> void:
	_hit_flash = 0.8

func _vignette_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float flash = 0.0;      // dano recebido
uniform float night = 0.0;      // escuridão das bordas
uniform float low_hp = 0.0;     // vida baixa (pulsa com o coração)
uniform float blood = 0.0;      // lua de sangue
uniform float lightning = 0.0;  // clarão do relâmpago
uniform float grain = 0.0;      // granulado de filme

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 q = UV - vec2(0.5);
	q.x *= 1.25;
	float d = length(q);
	float v = smoothstep(0.28, 0.78, d);
	// Escuridão nas bordas (avermelhada na lua de sangue).
	vec3 col = mix(vec3(0.0, 0.0, 0.02), vec3(0.18, 0.0, 0.0), blood);
	float a = v * clamp(night, 0.0, 0.92);
	// Vermelho de dano e de vida baixa por cima.
	float red = clamp(max(flash, low_hp), 0.0, 1.0);
	float rv = smoothstep(0.2, 0.7, d);
	col = mix(col, vec3(0.55, 0.0, 0.0), red * rv);
	a = max(a, rv * red * 0.85);
	// Granulado (ruído que muda a cada quadro).
	float n = hash(floor(FRAGCOORD.xy / 2.0) + fract(TIME * 13.0) * 97.0) - 0.5;
	col += vec3(n * grain * 4.0);
	a = max(a, abs(n) * grain * 2.0);
	// Clarão do relâmpago: branco azulado na tela toda.
	col = mix(col, vec3(0.85, 0.9, 1.0), lightning);
	a = max(a, lightning);
	COLOR = vec4(col, a);
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
	show_banner("A HORDA SE APROXIMA", "Horda %d chega em %d segundos. Volte para a base!" % [TimeManager.wave(), int(seconds)], Color(1.0, 0.55, 0.2))
	AudioManager.play(&"bell")

func _on_phase_changed(phase: int, day: int) -> void:
	if phase == TimeManager.Phase.DUSK:
		_on_message("O sol está morrendo... algo se move na névoa. Volte e prepare as defesas.", Color(1.0, 0.45, 0.3))
	elif phase == TimeManager.Phase.DAWN and day > 1:
		_on_message("Preparação: a horda %d chega em 2 minutos. Colete, construa e melhore!" % day, Color(1.0, 0.9, 0.5))

# --- Menus -------------------------------------------------------------------

var _settings: SettingsPanel
var tutorial: Tutorial

## Tutorial da primeira partida: ocupa o lugar dos objetivos enquanto ativo.
func start_tutorial() -> void:
	if not Tutorial.should_run():
		return
	tutorial = Tutorial.new()
	_anchor(tutorial, Control.PRESET_TOP_LEFT, Vector2(16, 160), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END)
	objectives_panel.get_parent().add_child(tutorial)
	objectives_panel.get_parent().move_child(tutorial, objectives_panel.get_index() + 1)
	objectives_panel.visible = false
	tutorial.visibility_changed.connect(func() -> void:
		if not tutorial.visible:
			objectives_panel.visible = true)
	tutorial.begin(_hero)

func _toggle_pause() -> void:
	if Coop.active():
		# Coop: o menu abre por cima, mas o mundo continua (os outros jogadores seguem).
		_pause.visible = not _pause.visible
		return
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
		var was := get_tree().paused
		get_tree().paused = false
		if ok:
			SaveManager.save_game()
		get_tree().paused = was
		_on_message("Jogo salvo." if ok else ("Partidas coop não são salvas." if Coop.active() else "Não é possível salvar durante a noite."), UIStyle.GREEN if ok else UIStyle.RED))
	col.add_child(save)
	var help := UIStyle.button("Controles (F1)")
	help.pressed.connect(func() -> void: _help.visible = not _help.visible)
	col.add_child(help)
	var cfg := UIStyle.button("Configurações (som, gráficos)")
	cfg.pressed.connect(func() -> void:
		_settings.visible = true
		panel.visible = false)
	col.add_child(cfg)
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
		["P", "Personagem: pontos de atributo (toque no retrato)"],
		["V", "Exército: trocar a ordem (defender / seguir / caçar)"],
		["I ou Tab", "Inventário (mochila e armazém)"],
		["B", "Menu da base: reparar muros/núcleo, afiar arma, fabricar curativos"],
		["G", "Construir: muros, barricadas, torres de arqueiros e armadilhas (T gira, clique constrói)"],
		["Q / F / R / T", "Habilidades: Golpe Giratório, Investida, Grito de Guerra, Explosão Arcana"],
		["Roda do mouse", "Zoom"],
		["Z / X ou botão do meio", "Girar câmera"],
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
		col.add_child(UIStyle.label("Celular: joystick à esquerda para andar • botão das espadas ataca (mira automática)\nToque no chão para ir até lá, num inimigo para atacá-lo • E saqueia • 1/2 curam • pinça = zoom", 15, UIStyle.GOLD))
	col.add_child(UIStyle.label("Retrato do herói = inventário • \"+\" nos recursos = menu da base • painel do dia = pausar", 15, UIStyle.GOLD))
	var goal := UIStyle.label("Objetivo: sobreviver a 100 hordas. Antes de cada uma há 2 minutos de preparação\n(colete, construa, melhore — ou toque em \"Chamar agora\"). A horda acaba quando o último zumbi cai.", 15, UIStyle.TEXT_DIM)
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

func _show_game_over(won: bool = false) -> void:
	var col := _game_over.get_node("Col") as VBoxContainer
	for c in col.get_children():
		c.queue_free()
	if won:
		AudioManager.play(&"gong", 0.0, 0.9)
		AudioManager.play(&"levelup")
	var t := UIStyle.label("VITÓRIA!" if won else "A BASE CAIU", 36, UIStyle.GOLD if won else UIStyle.RED)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var s := GameManager.stats
	col.add_child(UIStyle.label("Hordas vencidas: %d / %d" % [int(s.nights_survived), TimeManager.TOTAL_WAVES], 18))
	if _hero:
		col.add_child(UIStyle.label("Nível do herói: %d" % _hero.level, 18))
	col.add_child(UIStyle.label("Zumbis eliminados: %d" % int(s.kills), 18))
	col.add_child(UIStyle.label("Recursos coletados: %d" % int(s.items_collected), 18))
	var again := UIStyle.button("Jogar novamente")
	again.pressed.connect(func() -> void: GameManager.start_new_game(GameManager.difficulty))
	col.add_child(again)
	var menu := UIStyle.button("Menu principal")
	menu.pressed.connect(func() -> void: GameManager.return_to_menu())
	col.add_child(menu)
	_game_over.visible = true
