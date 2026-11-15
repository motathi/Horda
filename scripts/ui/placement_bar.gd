class_name PlacementBar
extends PanelContainer
## Barra exibida durante o posicionamento: nome, custo, validade e botões
## (Girar / Construir aqui / Cancelar).

var manager: BuildManager
var _title: Label
var _status: Label
var _confirm: Button

func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.hud_panel_style(Color(0.06, 0.06, 0.08, 0.92), 10))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	_title = UIStyle.label("", 16, Color.WHITE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_status = UIStyle.label("", 14, UIStyle.TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var rot := UIStyle.button("Girar (T)", 15)
	rot.pressed.connect(func() -> void: manager.rotate_preview())
	row.add_child(rot)
	_confirm = UIStyle.button("Construir aqui", 15)
	_confirm.pressed.connect(func() -> void: manager.confirm())
	row.add_child(_confirm)
	var cancel := UIStyle.button("Cancelar", 15)
	cancel.pressed.connect(func() -> void: manager.cancel())
	row.add_child(cancel)
	col.add_child(row)
	visible = false

func bind(m: BuildManager) -> void:
	manager = m
	m.mode_changed.connect(func(a: bool) -> void: visible = a)
	m.preview_changed.connect(_refresh)

func _refresh() -> void:
	if manager.active_def == null:
		return
	var d := manager.active_def
	_title.text = "%s — %s" % [d.display_name, ResourceManager.cost_to_string(d.cost)]
	if manager.valid:
		_status.text = ("Toque no chão para mover a prévia" if Platform.touch else "Clique para construir • botão direito cancela")
		_status.add_theme_color_override("font_color", UIStyle.GREEN)
	else:
		_status.text = manager.reason
		_status.add_theme_color_override("font_color", UIStyle.RED)
	_confirm.disabled = not manager.valid
