class_name TopBar
extends PanelContainer
## HUD superior: dia, período, relógio, tempo até a horda, recursos e perigo.

const SHOWN_RESOURCES: Array[StringName] = [&"wood", &"stone", &"scrap", &"cloth", &"herbs", &"meat"]

var _day: Label
var _phase: Label
var _clock: Label
var _countdown: Label
var _danger: Label
var _phase_bar: ProgressBar
var _res_labels: Dictionary = {}
var _remaining: int = 0
var _total: int = 0

func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	var time_box := VBoxContainer.new()
	time_box.add_theme_constant_override("separation", 0)
	row.add_child(time_box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	time_box.add_child(line)
	_day = UIStyle.label("Dia 1", 22, UIStyle.GOLD)
	_phase = UIStyle.label("Dia", 18)
	_clock = UIStyle.label("07:00", 18, UIStyle.TEXT_DIM)
	line.add_child(_day)
	line.add_child(_phase)
	line.add_child(_clock)
	_phase_bar = UIStyle.bar(UIStyle.GOLD, 6)
	_phase_bar.custom_minimum_size = Vector2(240, 6)
	time_box.add_child(_phase_bar)
	_countdown = UIStyle.label("", 15, UIStyle.TEXT_DIM)
	time_box.add_child(_countdown)
	row.add_child(VSeparator.new())
	for id in SHOWN_RESOURCES:
		var def := ResourceManager.get_def(id)
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		box.tooltip_text = "%s (armazém + mochila)\n%s" % [def.display_name, def.description] if def else ""
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(UIStyle.icon(def.icon if def else null, 34))
		var l := UIStyle.label("0", 18)
		box.add_child(l)
		_res_labels[id] = l
		row.add_child(box)
	row.add_child(VSeparator.new())
	_danger = UIStyle.label("", 18)
	_danger.custom_minimum_size = Vector2(200, 0)
	row.add_child(_danger)
	EventBus.horde_started.connect(func(_n: int, total: int) -> void:
		_total = total
		_remaining = total)
	EventBus.horde_progress.connect(func(rem: int, total: int) -> void:
		_remaining = rem
		_total = total)

func _process(_delta: float) -> void:
	_day.text = "Dia %d" % TimeManager.day
	_phase.text = TimeManager.phase_name()
	_phase.add_theme_color_override("font_color", UIStyle.RED if TimeManager.is_night() else UIStyle.TEXT)
	_clock.text = TimeManager.clock_string()
	_phase_bar.value = TimeManager.phase_ratio() * 100.0
	if TimeManager.is_night():
		var left := TimeManager.phase_duration(TimeManager.phase) - TimeManager.phase_time
		_countdown.text = "Amanhecer em %s" % _fmt(left)
	else:
		_countdown.text = "Horda em %s" % _fmt(TimeManager.seconds_until_night())
	for id: StringName in _res_labels:
		(_res_labels[id] as Label).text = str(ResourceManager.available(id))
	if TimeManager.is_night():
		_danger.text = "☠ HORDA: %d restantes" % _remaining
		_danger.add_theme_color_override("font_color", UIStyle.RED)
	elif TimeManager.phase == TimeManager.Phase.DUSK:
		_danger.text = "⚠ PERIGO: volte à base!"
		_danger.add_theme_color_override("font_color", Color(1.0, 0.55, 0.2))
	else:
		_danger.text = "Explorar (seguro na base)"
		_danger.add_theme_color_override("font_color", UIStyle.GREEN)

static func _fmt(s: float) -> String:
	var t := maxi(0, int(s))
	return "%d:%02d" % [t / 60, t % 60]
