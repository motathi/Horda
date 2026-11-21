class_name TimePanel
extends PanelContainer
## Painel da rodada (canto superior direito): "HORDA N/100", contagem da
## preparação (com botão "Chamar agora") ou zumbis restantes durante a horda.
## Tocar/clicar no painel pausa o jogo.

signal pressed

var _icon: TextureRect
var _title: Label
var _caption: Label
var _timer: Label
var _call_btn: Button
var _sun: Texture2D
var _moon: Texture2D
var _remaining: int = 0
var _total: int = 0

func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.hud_panel_style(Color(0.06, 0.05, 0.06, 0.9), 12))
	custom_minimum_size = Vector2(250, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Clique para pausar (Esc)"
	_sun = UIStyle.hud_icon("sun")
	_moon = UIStyle.hud_icon("moon")
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon = UIStyle.icon(_sun, 44)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = UIStyle.label("HORDA 1/100", 26, Color.WHITE)
	head.add_child(_icon)
	head.add_child(_title)
	col.add_child(head)
	_caption = UIStyle.label("", 15, Color.WHITE)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_caption)
	_timer = UIStyle.label("", 32, Color(1.0, 0.27, 0.25))
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.add_theme_constant_override("outline_size", 6)
	col.add_child(_timer)
	_call_btn = UIStyle.button("Chamar agora", 13)
	_call_btn.tooltip_text = "Pula o resto da preparação e chama a horda"
	_call_btn.pressed.connect(func() -> void:
		if Coop.is_client():
			Coop.request("call_horde")
		else:
			TimeManager.start_horde_now())
	col.add_child(_call_btn)
	EventBus.horde_started.connect(func(_n: int, total: int) -> void:
		_total = total
		_remaining = total)
	EventBus.horde_progress.connect(func(rem: int, total: int) -> void:
		_remaining = rem
		_total = total)

func set_compact() -> void:
	pass

func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
		accept_event()
		if Platform.accept_tap("time_panel"):
			pressed.emit()

func _process(_delta: float) -> void:
	var night := TimeManager.is_night()
	_icon.texture = _moon if night else _sun
	_title.text = "HORDA %d/%d" % [TimeManager.wave(), TimeManager.TOTAL_WAVES]
	_call_btn.visible = not night
	if night:
		_caption.text = "ZUMBIS RESTANTES:"
		_timer.text = str(_remaining)
		_timer.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	else:
		_caption.text = "PRÓXIMA HORDA EM:"
		var left := TimeManager.prep_seconds_left()
		_timer.text = _fmt(left)
		_timer.add_theme_color_override("font_color", Color(1.0, 0.27, 0.25) if left < 30.0 else Color(1.0, 0.55, 0.4))

static func _fmt(s: float) -> String:
	var t := maxi(0, int(ceil(s)))
	return "%02d:%02d" % [t / 60, t % 60]
