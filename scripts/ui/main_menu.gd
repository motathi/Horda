extends Control
## Menu principal: novo jogo (dificuldade + duração do ciclo), continuar, sair.

var _diff: String = "normal"
var _cycle: String = "normal"
var _new_panel: Control
var _main_panel: Control
var _coop_panel: CoopPanel
var _settings_panel: SettingsPanel

func _ready() -> void:
	GameManager.state = GameManager.State.MENU
	TimeManager.running = false
	if OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search", true)).contains("autostart=1"):
		GameManager.start_new_game.call_deferred("normal", "normal")
		return
	# Depuração do coop no navegador: ?autocoop=host  ou  ?autocoop=join&sala=CODIGO
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("window.location.search", true))
		if q.contains("autocoop=host"):
			Net.host_room.call_deferred("Anfitriao")
			Net.status_changed.connect(func(t: String) -> void: print("[coop-ui] ", t))
			Net.lobby_changed.connect(func() -> void:
				print("[coop-ui] jogadores: ", Net.players.size())
				if Net.players.size() >= 2 and not Net.in_game:
					Net.start_game.call_deferred("normal"))
		elif q.contains("autocoop=join"):
			var i := q.find("sala=")
			Net.join_room.call_deferred(q.substr(i + 5, 5), "Convidado")
			Net.status_changed.connect(func(t: String) -> void: print("[coop-ui] ", t))
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
	_settings_panel = SettingsPanel.new()
	_settings_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	layout.add_child(_settings_panel)
	_settings_panel.closed.connect(func() -> void: _main_panel.visible = true)
	_coop_panel = CoopPanel.new()
	_coop_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	layout.add_child(_coop_panel)
	_coop_panel.add_hero_picker(_hero_picker())
	_coop_panel.back_pressed.connect(func() -> void:
		_coop_panel.visible = false
		_main_panel.visible = true)
	if _coop_panel.open_with_code():
		_main_panel.visible = false
		_coop_panel.visible = true
	if GameManager.menu_message != "":
		EventBus.notify(GameManager.menu_message, UIStyle.RED)
		var msg := UIStyle.label(GameManager.menu_message, 18, UIStyle.RED)
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		layout.add_child(msg)
		layout.move_child(msg, 2)
		GameManager.menu_message = ""
	var ver := UIStyle.label("Horda v1.0", 14, UIStyle.TEXT_DIM)
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
		cont.text = "Continuar (Horda %d)" % int(meta.get("day", 1))
	cont.pressed.connect(func() -> void: GameManager.continue_game())
	col.add_child(cont)
	var new := UIStyle.button("Novo jogo", 22)
	new.pressed.connect(func() -> void:
		_main_panel.visible = false
		_new_panel.visible = true)
	col.add_child(new)
	var coop := UIStyle.button("Jogar em grupo (coop)", 22)
	coop.pressed.connect(func() -> void:
		_main_panel.visible = false
		_coop_panel.visible = true)
	col.add_child(coop)
	var cfgb := UIStyle.button("Configurações", 22)
	cfgb.pressed.connect(func() -> void:
		_main_panel.visible = false
		_settings_panel.visible = true)
	col.add_child(cfgb)
	if OS.has_feature("web"):
		var fs := UIStyle.button("Tela cheia", 22)
		fs.pressed.connect(func() -> void: Platform.toggle_fullscreen())
		col.add_child(fs)
	else:
		var quit := UIStyle.button("Sair", 22)
		quit.pressed.connect(func() -> void: get_tree().quit())
		col.add_child(quit)
	_place(panel)
	return panel

func _build_new_game() -> Control:
	var panel := UIStyle.panel()
	panel.custom_minimum_size = Vector2(640, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(UIStyle.label("Novo jogo", 28, UIStyle.GOLD))
	col.add_child(UIStyle.label("Herói", 18))
	col.add_child(_hero_picker())
	col.add_child(UIStyle.label("Dificuldade", 18))
	col.add_child(_choice_row({"facil": "Fácil", "normal": "Normal", "dificil": "Difícil"}, "normal", func(k: String) -> void: _diff = k))
	col.add_child(UIStyle.label("100 hordas • 2 minutos de preparação antes de cada uma", 16, UIStyle.GOLD))
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

## Retratos clicáveis das aparências do herói (lembra a última escolha).
func _hero_picker() -> Control:
	var cfg := ConfigFile.new()
	cfg.load(AudioManager.SETTINGS)
	GameManager.hero_skin = str(cfg.get_value("game", "hero_skin", GameManager.hero_skin))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for sk: Dictionary in HeroSkins.LIST:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = sk["id"] == GameManager.hero_skin
		b.custom_minimum_size = Vector2(84, 98)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = sk["name"]
		var st := UIStyle.hud_panel_style(Color(0.08, 0.07, 0.07, 0.95), 8)
		st.border_color = Color(0.3, 0.26, 0.2)
		var on := st.duplicate() as StyleBoxFlat
		on.border_color = UIStyle.GOLD
		on.set_border_width_all(3)
		on.bg_color = Color(0.2, 0.16, 0.08, 0.98)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", on)
		b.add_theme_stylebox_override("pressed", on)
		var c := VBoxContainer.new()
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.offset_left = 4
		c.offset_right = -4
		c.offset_top = 4
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tr := TextureRect.new()
		tr.texture = HeroSkins.portrait(sk["id"])
		tr.custom_minimum_size = Vector2(74, 64)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(tr)
		var l := UIStyle.label(sk["name"], 12, Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(l)
		b.add_child(c)
		var id: String = sk["id"]
		b.pressed.connect(func() -> void:
			GameManager.hero_skin = id
			var c2 := ConfigFile.new()
			c2.load(AudioManager.SETTINGS)
			c2.set_value("game", "hero_skin", id)
			c2.save(AudioManager.SETTINGS))
		row.add_child(b)
	return row

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
