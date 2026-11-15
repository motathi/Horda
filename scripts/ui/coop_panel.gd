class_name CoopPanel
extends PanelContainer
## Menu do modo cooperativo: criar sala (código + link), entrar com código,
## lista de jogadores e início da partida pelo anfitrião.

signal back_pressed

const SITE := "https://horda-five.vercel.app/"

var _name_edit: LineEdit
var _code_edit: LineEdit
var _setup_box: VBoxContainer
var _lobby_box: VBoxContainer
var _status: Label
var _code_label: Label
var _players_box: VBoxContainer
var _start_btn: Button
var _link_btn: Button
var _diff: String = "normal"
var _diff_row: Control

func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style(UIStyle.BG, UIStyle.GOLD))
	custom_minimum_size = Vector2(640, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	col.add_child(UIStyle.label("Jogar em grupo (coop online)", 24, UIStyle.GOLD))
	# --- Antes de entrar na sala ---
	_setup_box = VBoxContainer.new()
	_setup_box.add_theme_constant_override("separation", 6)
	col.add_child(_setup_box)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	nrow.add_child(UIStyle.label("Seu nome:", 17))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(260, 40)
	_name_edit.text = _saved_name()
	nrow.add_child(_name_edit)
	_setup_box.add_child(nrow)
	var host_btn := UIStyle.button("Criar sala", 20)
	host_btn.custom_minimum_size = Vector2(0, 48)
	host_btn.pressed.connect(_on_host)
	_setup_box.add_child(host_btn)
	var jrow := HBoxContainer.new()
	jrow.add_theme_constant_override("separation", 8)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Código da sala" if Net.use_webrtc() else "IP do anfitrião (ex.: 192.168.0.10)"
	_code_edit.custom_minimum_size = Vector2(300, 46)
	_code_edit.max_length = 40
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.text = _url_room()
	jrow.add_child(_code_edit)
	var join_btn := UIStyle.button("Entrar", 20)
	join_btn.custom_minimum_size = Vector2(140, 46)
	join_btn.pressed.connect(_on_join)
	jrow.add_child(join_btn)
	_setup_box.add_child(jrow)
	var hint := UIStyle.label("Até %d jogadores. Base, recursos e pesquisas são compartilhados; cada um tem seu herói, nível e equipamento. Partidas coop não são salvas." % Net.MAX_PLAYERS, 13, UIStyle.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(600, 0)
	_setup_box.add_child(hint)
	# --- Dentro da sala ---
	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 8)
	_lobby_box.visible = false
	col.add_child(_lobby_box)
	_code_label = UIStyle.label("", 40, UIStyle.GOLD)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_box.add_child(_code_label)
	_link_btn = UIStyle.button("Copiar link de convite", 16)
	_link_btn.pressed.connect(_copy_link)
	_lobby_box.add_child(_link_btn)
	_lobby_box.add_child(UIStyle.label("Jogadores", 17))
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 4)
	_lobby_box.add_child(_players_box)
	_diff_row = _difficulty_row()
	_lobby_box.add_child(_diff_row)
	_start_btn = UIStyle.button("Começar partida", 20)
	_start_btn.custom_minimum_size = Vector2(0, 48)
	_start_btn.pressed.connect(func() -> void: Net.start_game(_diff))
	_lobby_box.add_child(_start_btn)
	# --- Comum ---
	_status = UIStyle.label("", 15, UIStyle.TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(600, 0)
	col.add_child(_status)
	var back := UIStyle.button("Voltar", 18)
	back.pressed.connect(func() -> void:
		Net.leave()
		_show_lobby(false)
		back_pressed.emit())
	col.add_child(back)
	Net.status_changed.connect(func(t: String) -> void: _status.text = t)
	Net.lobby_changed.connect(_refresh)
	Net.failed.connect(func(reason: String) -> void:
		_status.text = reason
		_status.add_theme_color_override("font_color", UIStyle.RED)
		_show_lobby(false))
	Net.joined.connect(func() -> void: _show_lobby(true))
	visible = false

## O menu principal entrega o seletor de herói (mesmo do "Novo jogo").
func add_hero_picker(picker: Control) -> void:
	_setup_box.add_child(UIStyle.label("Herói", 17))
	_setup_box.move_child(_setup_box.get_child(_setup_box.get_child_count() - 1), 1)
	_setup_box.add_child(picker)
	_setup_box.move_child(picker, 2)

func _difficulty_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UIStyle.label("Dificuldade:", 16))
	var group := ButtonGroup.new()
	for k: String in ["facil", "normal", "dificil"]:
		var b := UIStyle.button({"facil": "Fácil", "normal": "Normal", "dificil": "Difícil"}[k], 16)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = k == _diff
		b.pressed.connect(func() -> void: _diff = k)
		row.add_child(b)
	return row

func _player_name() -> String:
	var n := _name_edit.text.strip_edges()
	if n == "":
		n = "Sobrevivente %d" % (randi() % 90 + 10)
	var cfg := ConfigFile.new()
	cfg.load(AudioManager.SETTINGS)
	cfg.set_value("game", "player_name", n)
	cfg.save(AudioManager.SETTINGS)
	return n

func _saved_name() -> String:
	var cfg := ConfigFile.new()
	cfg.load(AudioManager.SETTINGS)
	return str(cfg.get_value("game", "player_name", ""))

func _url_room() -> String:
	if not OS.has_feature("web"):
		return ""
	var q := str(JavaScriptBridge.eval("window.location.search", true))
	var i := q.find("sala=")
	return q.substr(i + 5, 5).to_upper() if i >= 0 else ""

func open_with_code() -> bool:
	return _url_room() != ""

func _on_host() -> void:
	_status.remove_theme_color_override("font_color")
	Net.host_room(_player_name())
	_show_lobby(true)

func _on_join() -> void:
	if _code_edit.text.strip_edges() == "" and Net.use_webrtc():
		_status.text = "Digite o código da sala."
		return
	_status.remove_theme_color_override("font_color")
	Net.join_room(_code_edit.text, _player_name())

func _show_lobby(on: bool) -> void:
	_setup_box.visible = not on
	_lobby_box.visible = on
	_refresh()

func _refresh() -> void:
	var host := Net.is_host()
	_code_label.text = ("Código: %s" % Net.room_code) if Net.room_code != "" else ""
	_link_btn.visible = host and Net.use_webrtc()
	_diff_row.visible = host
	_start_btn.visible = host
	_start_btn.text = "Começar partida (%d jogador%s)" % [Net.players.size(), "es" if Net.players.size() != 1 else ""]
	for c in _players_box.get_children():
		c.queue_free()
	var ids := Net.players.keys()
	ids.sort()
	for pid: int in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var tr := TextureRect.new()
		tr.texture = HeroSkins.portrait(Net.player_skin(pid))
		tr.custom_minimum_size = Vector2(40, 40)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		row.add_child(tr)
		var tag := " (anfitrião)" if pid == 1 else ""
		tag += " — você" if pid == Net.my_id() else ""
		row.add_child(UIStyle.label("%s%s — %s" % [Net.player_name(pid), tag, HeroSkins.get_skin(Net.player_skin(pid))["name"]], 16))
		_players_box.add_child(row)
	if not host and Net.is_client() and not Net.players.is_empty():
		_status.text = "Na sala com %d jogador(es). Aguardando o anfitrião começar..." % Net.players.size()

func _copy_link() -> void:
	var link := SITE + "?sala=" + Net.room_code
	DisplayServer.clipboard_set(link)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("navigator.clipboard && navigator.clipboard.writeText('%s')" % link, true)
	_status.text = "Link copiado: " + link
