class_name TimePanel
extends PanelContainer
## Painel do ciclo (canto superior direito): "DIA/NOITE N" e contagem regressiva.

var _title: Label
var _icon: Label
var _caption: Label
var _timer: Label
var _sub: Label
var _remaining: int = 0

func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.06, 0.04, 0.05, 0.88), Color(0.45, 0.12, 0.1), 2, 6))
	custom_minimum_size = Vector2(250, 0)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 10)
	_icon = UIStyle.label("☀", 34, UIStyle.GOLD)
	_title = UIStyle.label("DIA 1", 30, UIStyle.TEXT)
	head.add_child(_icon)
	head.add_child(_title)
	col.add_child(head)
	_caption = UIStyle.label("", 15, Color(1, 0.85, 0.75))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_caption)
	_timer = UIStyle.label("", 30, UIStyle.RED)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_timer)
	_sub = UIStyle.label("", 13, UIStyle.TEXT_DIM)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_sub)
	EventBus.horde_started.connect(func(_n: int, total: int) -> void: _remaining = total)
	EventBus.horde_progress.connect(func(rem: int, _t: int) -> void: _remaining = rem)

func _process(_delta: float) -> void:
	var night := TimeManager.is_night()
	_icon.text = "☾" if night else ("☀" if TimeManager.phase != TimeManager.Phase.DUSK else "◐")
	_icon.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0) if night else UIStyle.GOLD)
	_title.text = ("NOITE %d" if night else "DIA %d") % TimeManager.day
	if night:
		_caption.text = "AMANHECER EM:"
		_timer.text = _fmt(TimeManager.phase_duration(TimeManager.phase) - TimeManager.phase_time)
		_timer.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		_sub.text = "☠ %d zumbis restantes" % _remaining
	else:
		_caption.text = "HORDA CHEGANDO EM:"
		var left := TimeManager.seconds_until_night()
		_timer.text = _fmt(left)
		_timer.add_theme_color_override("font_color", UIStyle.RED if left < 120.0 else Color(1.0, 0.45, 0.35))
		_sub.text = "%s  •  %s" % [TimeManager.phase_name(), TimeManager.clock_string()]

static func _fmt(s: float) -> String:
	var t := maxi(0, int(s))
	return "%02d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]
