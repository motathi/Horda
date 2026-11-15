class_name TimePanel
extends PanelContainer
## Painel do ciclo (canto superior direito): ícone de sol/lua, "DIA N"/"NOITE N"
## e contagem regressiva. Tocar/clicar pausa o jogo.

signal pressed

var _icon: TextureRect
var _title: Label
var _caption: Label
var _timer: Label
var _sub: Label
var _sun: Texture2D
var _moon: Texture2D
var _remaining: int = 0

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
	head.add_theme_constant_override("separation", 14)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon = UIStyle.icon(_sun, 46)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = UIStyle.label("DIA 1", 30, Color.WHITE)
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
	_sub = UIStyle.label("", 14, UIStyle.TEXT_DIM)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_sub)
	EventBus.horde_started.connect(func(_n: int, total: int) -> void: _remaining = total)
	EventBus.horde_progress.connect(func(rem: int, _t: int) -> void: _remaining = rem)

func set_compact() -> void:
	pass

func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
		pressed.emit()
		accept_event()

func _process(_delta: float) -> void:
	var night := TimeManager.is_night()
	_icon.texture = _moon if night else _sun
	_title.text = ("NOITE %d" if night else "DIA %d") % TimeManager.day
	if night:
		_caption.text = "AMANHECER EM:"
		_timer.text = _fmt(TimeManager.phase_duration(TimeManager.phase) - TimeManager.phase_time)
		_timer.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		_sub.text = "%d zumbis restantes" % _remaining
		_sub.visible = true
	else:
		_caption.text = "HORDA CHEGANDO EM:"
		var left := TimeManager.seconds_until_night()
		_timer.text = _fmt(left)
		_timer.add_theme_color_override("font_color", Color(1.0, 0.27, 0.25))
		_sub.visible = false

static func _fmt(s: float) -> String:
	var t := maxi(0, int(s))
	return "%02d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]
