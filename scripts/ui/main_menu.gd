extends Control
## Tela inicial: cena 3D animada ao fundo (TitleBackdrop), logotipo de metal com brilho, botões e painéis
## com moldura de ferro e ouro (TitleStyle), entrada animada e transições entre os submenus
## (novo jogo, coop, configurações), cada um com seu enquadramento de câmera.

var _diff: String = "normal"
var _cycle: String = "normal"
var _new_panel: Control
var _main_panel: Control
var _coop_panel: CoopPanel
var _settings_panel: SettingsPanel
var _backdrop: TitleBackdrop
var _logo: Control
var _logo_tex: TextureRect
var _subtitle: Control
var _fade: ColorRect
var _current: Control
var _busy: bool = false

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
	_backdrop = TitleBackdrop.new()
	add_child(_backdrop)
	add_child(_overlay())
	_build_logo()
	# Coluna da direita: os painéis (um visível por vez), centralizados na vertical.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_right", 56)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_main_panel = _build_main()
	col.add_child(_main_panel)
	_new_panel = _build_new_game()
	col.add_child(_new_panel)
	_settings_panel = SettingsPanel.new()
	col.add_child(_settings_panel)
	_settings_panel.visible = false
	_settings_panel.closed.connect(func() -> void: _go("main"))
	_coop_panel = CoopPanel.new()
	col.add_child(_coop_panel)
	_coop_panel.visible = false
	_coop_panel.add_hero_picker(_hero_picker())
	_coop_panel.back_pressed.connect(func() -> void: _go("main"))
	for p: Control in [_main_panel, _new_panel, _settings_panel, _coop_panel]:
		_restyle(p)
	_current = _main_panel
	if GameManager.menu_message != "":
		EventBus.notify(GameManager.menu_message, UIStyle.RED)
		var msg := UIStyle.label(GameManager.menu_message, 18, UIStyle.RED)
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		(_main_panel.get_child(0) as Control).add_child(msg)
		GameManager.menu_message = ""
	var ver := UIStyle.label("Horda v1.0", 14, UIStyle.TEXT_DIM)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.position = Vector2(18, -12)
	add_child(ver)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	if _coop_panel.open_with_code():
		_main_panel.visible = false
		_coop_panel.visible = true
		_current = _coop_panel
		_backdrop.focus("coop")
	_intro()

# --------------------------------------------------------------------------- montagem

## Vinheta escura nas bordas, um toque de vermelho e grão de filme.
func _overlay() -> Control:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 q = UV - vec2(0.5);
	q.x *= 1.35;
	float v = smoothstep(0.3, 0.9, length(q));
	float grain = (h(UV * 900.0 + fract(TIME * 7.0)) - 0.5) * 0.05;
	COLOR = vec4(mix(vec3(0.0), vec3(0.09, 0.0, 0.0), v) + grain, 0.15 + v * 0.7);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	shade.material = m
	return shade

func _build_logo() -> void:
	_logo = Control.new()
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.position = Vector2(26, 8)
	_logo.size = Vector2(760, 300)
	add_child(_logo)
	_logo_tex = TextureRect.new()
	_logo_tex.texture = load(TitleStyle.DIR + "ui_logo.png") as Texture2D
	_logo_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_logo_tex.size = Vector2(760, 266)
	_logo_tex.pivot_offset = _logo_tex.size * 0.5
	_logo_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float ember = 1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// Reflexo que atravessa o metal de tempos em tempos.
	float sweep = fract(TIME * 0.14) * 3.0 - 0.8;
	float x = UV.x - UV.y * 0.4;
	float band = smoothstep(0.05, 0.0, abs(x - sweep));
	// As rachaduras em brasa (laranja forte) pulsam.
	float hot = smoothstep(0.25, 0.6, c.r - c.b) * smoothstep(0.35, 0.8, c.r);
	float pulse = 0.75 + 0.25 * sin(TIME * 2.3) * sin(TIME * 1.1 + 1.3);
	c.rgb += hot * vec3(0.55, 0.18, 0.02) * (pulse - 0.75) * 3.0 * ember;
	c.rgb += band * vec3(1.0, 0.85, 0.6) * 0.5 * c.a;
	COLOR = c;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_logo_tex.material = m
	_logo.add_child(_logo_tex)
	var sub := VBoxContainer.new()
	sub.position = Vector2(150, 236)
	sub.size = Vector2(460, 60)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := TitleStyle.title_label("NOITES  DE  SOBREVIVÊNCIA", 26)
	st.add_theme_color_override("font_color", Color(0.9, 0.82, 0.66))
	sub.add_child(st)
	sub.add_child(TitleStyle.divider(420))
	_logo.add_child(sub)
	_subtitle = sub

func _build_main() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var cont := TitleStyle.button("Continuar")
	cont.disabled = not SaveManager.has_save()
	if SaveManager.has_save():
		var meta := SaveManager.peek_meta()
		cont.text = "Continuar  (Horda %d)" % int(meta.get("day", 1))
	cont.pressed.connect(func() -> void: _leave(func() -> void: GameManager.continue_game()))
	col.add_child(cont)
	var new := TitleStyle.button("Novo jogo")
	new.pressed.connect(func() -> void: _go("new"))
	col.add_child(new)
	var coop := TitleStyle.button("Jogar em grupo")
	coop.pressed.connect(func() -> void: _go("coop"))
	col.add_child(coop)
	var cfgb := TitleStyle.button("Configurações")
	cfgb.pressed.connect(func() -> void: _go("settings"))
	col.add_child(cfgb)
	if OS.has_feature("web"):
		var fs := TitleStyle.button("Tela cheia")
		fs.pressed.connect(func() -> void: Platform.toggle_fullscreen())
		col.add_child(fs)
	else:
		var quit := TitleStyle.button("Sair")
		quit.pressed.connect(func() -> void: get_tree().quit())
		col.add_child(quit)
	return panel

func _build_new_game() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	panel.add_child(col)
	col.add_child(TitleStyle.title_label("Novo jogo", 34))
	col.add_child(TitleStyle.divider(360))
	col.add_child(UIStyle.label("Herói", 18, TitleStyle.CREAM))
	col.add_child(_hero_picker())
	col.add_child(UIStyle.label("Dificuldade", 18, TitleStyle.CREAM))
	col.add_child(_choice_row({"facil": "Fácil", "normal": "Normal", "dificil": "Difícil"}, "normal", func(k: String) -> void: _diff = k))
	col.add_child(UIStyle.label("100 hordas • 2 minutos de preparação antes de cada uma", 16, UIStyle.GOLD))
	if SaveManager.has_save():
		col.add_child(UIStyle.label("Atenção: iniciar um novo jogo substitui o salvamento atual no próximo amanhecer.", 13, Color(1, 0.6, 0.4)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var back := TitleStyle.button("Voltar", 22)
	back.custom_minimum_size.x = 180
	back.pressed.connect(func() -> void: _go("main"))
	var start := TitleStyle.button("Começar", 24)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(func() -> void: _leave(func() -> void: GameManager.start_new_game(_diff, _cycle)))
	row.add_child(back)
	row.add_child(start)
	col.add_child(row)
	panel.visible = false
	return panel

## Troca a moldura dos painéis e dos botões de texto (os de Configurações/Coop vêm com o estilo antigo).
func _restyle(n: Node) -> void:
	if n is PanelContainer and (n == _main_panel or n == _new_panel or n == _settings_panel or n == _coop_panel):
		TitleStyle.style_panel(n as PanelContainer)
	elif n is Button and not n.has_meta(&"title_fx") and (n as Button).text.length() > 1 and (n as Button).get_child_count() == 0:
		var b := n as Button
		var fs := b.get_theme_font_size("font_size")
		TitleStyle.style_button(b, clampi(fs + 2, 16, 24))
	for c in n.get_children():
		_restyle(c)

# --------------------------------------------------------------------------- animação

## Entrada: tela preta clareando, raio, logotipo caindo com impacto e botões entrando um a um.
func _intro() -> void:
	_logo.modulate.a = 0.0
	_logo_tex.scale = Vector2.ONE * 1.35
	_subtitle.modulate.a = 0.0
	_current.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 1.6).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_callback(func() -> void: _backdrop.strike()).set_delay(0.7)
	tw.parallel().tween_property(_logo, "modulate:a", 1.0, 0.35).set_delay(0.9)
	tw.parallel().tween_property(_logo_tex, "scale", Vector2.ONE, 0.55).set_delay(0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_callback(func() -> void: AudioManager.play(&"gong", -6.0)).set_delay(1.2)
	tw.parallel().tween_property(_subtitle, "modulate:a", 1.0, 0.6).set_delay(1.5)
	tw.tween_callback(func() -> void: _reveal(_current))

## Mostra um painel: desliza da direita e os botões entram em sequência.
func _reveal(p: Control) -> void:
	p.visible = true
	p.modulate.a = 0.0
	await get_tree().process_frame
	if not is_instance_valid(p):
		return
	var base_x := p.position.x
	p.position.x = base_x + 90.0
	var tw := create_tween().set_parallel()
	tw.tween_property(p, "modulate:a", 1.0, 0.3)
	tw.tween_property(p, "position:x", base_x, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var i := 0
	for b in p.find_children("*", "Button", true, false):
		if not (b as Control).is_visible_in_tree() or i > 10:
			continue
		var c := b as Control
		c.modulate.a = 0.0
		tw.tween_property(c, "modulate:a", 1.0, 0.25).set_delay(0.12 + i * 0.06)
		i += 1

func _go(name: String) -> void:
	var target: Control = {"main": _main_panel, "new": _new_panel, "coop": _coop_panel, "settings": _settings_panel}[name]
	if _busy or target == _current and target.visible:
		return
	_busy = true
	_backdrop.focus(name)
	var old := _current
	var tw := create_tween().set_parallel()
	if old and old.visible:
		tw.tween_property(old, "modulate:a", 0.0, 0.18)
		tw.tween_property(old, "position:x", old.position.x + 60.0, 0.18)
	# Logotipo encolhe no canto quando um submenu abre (os painéis são largos).
	var small := name != "main"
	tw.tween_property(_logo, "scale", Vector2.ONE * (0.62 if small else 1.0), 0.45).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_subtitle, "modulate:a", 0.0 if small else 1.0, 0.3)
	await tw.finished
	if old:
		old.visible = false
		old.modulate.a = 1.0
	_current = target
	_busy = false
	_reveal(target)

## Antes de entrar no jogo: escurece a tela.
func _leave(then: Callable) -> void:
	if _busy:
		return
	_busy = true
	AudioManager.play(&"gong", -4.0)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.6)
	tw.tween_callback(then)

# --------------------------------------------------------------------------- escolhas

## Retratos clicáveis das aparências do herói (lembra a última escolha).
func _hero_picker() -> Control:
	var cfg := ConfigFile.new()
	cfg.load(AudioManager.SETTINGS)
	GameManager.hero_skin = str(cfg.get_value("game", "hero_skin", GameManager.hero_skin))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for sk: Dictionary in HeroSkins.playable():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = sk["id"] == GameManager.hero_skin
		b.custom_minimum_size = Vector2(92, 106)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = sk["name"]
		var st := UIStyle.hud_panel_style(Color(0.06, 0.05, 0.05, 0.95), 6)
		st.border_color = Color(0.36, 0.27, 0.15)
		st.set_border_width_all(2)
		var on := st.duplicate() as StyleBoxFlat
		on.border_color = Color(1.0, 0.72, 0.3)
		on.set_border_width_all(3)
		on.bg_color = Color(0.24, 0.1, 0.03, 0.98)
		on.shadow_color = Color(1.0, 0.35, 0.05, 0.55)
		on.shadow_size = 10
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
		tr.custom_minimum_size = Vector2(82, 70)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(tr)
		var l := UIStyle.label(sk["name"], 13, Color.WHITE)
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
	row.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for k: String in options:
		var b := TitleStyle.button(options[k], 20)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = k == default_key
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: on_pick.call(k))
		row.add_child(b)
	return row
