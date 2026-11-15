class_name SettingsPanel
extends PanelContainer
## Configurações (menu principal e pausa): gráficos, desempenho, som e jogo.

signal closed

var _note: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_stylebox_override("panel", UIStyle.panel_style(UIStyle.BG, UIStyle.GOLD))
	custom_minimum_size = Vector2(600, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UIStyle.label("Configurações", 24, UIStyle.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UIStyle.button("X", 16)
	close.custom_minimum_size = Vector2(44, 40)
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	head.add_child(close)
	# Conteúdo com rolagem (cabe em telas baixas; arrastar funciona no celular).
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var outer := col
	col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	# --- Gráficos ---
	col.add_child(UIStyle.label("Gráficos", 18, UIStyle.GOLD))
	col.add_child(_choice("Qualidade", Settings.QUALITY_NAMES, Settings.quality, func(i: int) -> void:
		Settings.set_value("quality", i)
		_note.text = "Sombras, nitidez e resolução mudaram. Grama e decoração mudam na próxima partida."))
	var fps_names: Array[String] = ["30", "60", "Sem limite"]
	col.add_child(_choice("Limite de FPS", fps_names, maxi(0, Settings.FPS_OPTIONS.find(Settings.fps_limit)), func(i: int) -> void:
		Settings.set_value("fps_limit", Settings.FPS_OPTIONS[i])))
	col.add_child(_toggle("Mostrar FPS", Settings.show_fps, func(on: bool) -> void: Settings.set_value("show_fps", on)))
	_note = UIStyle.label("Baixa: sem sombras e resolução 3D menor (mais leve no celular). 30 FPS economiza bateria.", 13, UIStyle.TEXT_DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(540, 0)
	col.add_child(_note)
	col.add_child(HSeparator.new())
	# --- Som ---
	col.add_child(UIStyle.label("Som", 18, UIStyle.GOLD))
	for pair: Array in [["Música", "Music"], ["Efeitos", "SFX"], ["Ambiente", "Ambient"], ["Interface", "UI"]]:
		col.add_child(_volume_row(pair[0], pair[1]))
	col.add_child(HSeparator.new())
	# --- Jogo ---
	col.add_child(UIStyle.label("Jogo", 18, UIStyle.GOLD))
	col.add_child(_toggle("Números de dano", Settings.damage_numbers, func(on: bool) -> void: Settings.set_value("damage_numbers", on)))
	var tut := UIStyle.button("Refazer o tutorial na próxima partida", 15)
	tut.custom_minimum_size = Vector2(0, 40)
	tut.pressed.connect(func() -> void:
		Settings.set_value("tutorial_done", false)
		_note.text = "O tutorial vai aparecer na próxima partida solo.")
	col.add_child(tut)
	outer.add_child(UIStyle.label("Horda v1.0 — role para ver todas as opções", 12, UIStyle.TEXT_DIM))
	visible = false

func _row(label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := UIStyle.label(label, 15)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	return row

func _choice(label: String, names: Array[String], current: int, on_pick: Callable) -> Control:
	var row := _row(label)
	var group := ButtonGroup.new()
	for i in names.size():
		var b := UIStyle.button(names[i], 15)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == current
		b.custom_minimum_size = Vector2(0, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: on_pick.call(i))
		row.add_child(b)
	return row

func _toggle(label: String, on: bool, on_change: Callable) -> Control:
	var row := _row(label)
	var group := ButtonGroup.new()
	for i in 2:
		var b := UIStyle.button(["Ligado", "Desligado"][i], 15)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = (i == 0) == on
		b.custom_minimum_size = Vector2(0, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: on_change.call(i == 0))
		row.add_child(b)
	return row

func _volume_row(label: String, bus: String) -> Control:
	var row := _row(label)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = float(AudioManager.volumes.get(bus, 1.0))
	sl.custom_minimum_size = Vector2(220, 32)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sl)
	var pct := UIStyle.label("%d%%" % roundi(sl.value * 100), 14, UIStyle.TEXT_DIM)
	pct.custom_minimum_size = Vector2(46, 0)
	row.add_child(pct)
	sl.value_changed.connect(func(v: float) -> void:
		AudioManager.set_volume(bus, v)
		pct.text = "%d%%" % roundi(v * 100))
	sl.drag_ended.connect(func(_c: bool) -> void:
		AudioManager.save_settings()
		if bus == "SFX" or bus == "UI":
			AudioManager.play_ui(&"ui_click"))
	return row
