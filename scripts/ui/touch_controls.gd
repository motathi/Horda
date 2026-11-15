class_name TouchControls
extends Control
## Controles de toque (multitoque): joystick virtual à esquerda e botões de ação
## à direita. Usa InputEventScreenTouch diretamente para permitir mover e atacar
## ao mesmo tempo (a emulação de mouse do Godot só cobre o primeiro dedo).

signal toggle_inventory
signal toggle_base
signal toggle_pause

const STICK_RADIUS := 78.0

var hero: Hero
var _stick_touch: int = -1
var _stick_center: Vector2
var _stick_vec: Vector2 = Vector2.ZERO
var _buttons: Array[Dictionary] = []   # {id, center, radius, label, icon, touch}
var _icons: Dictionary = {}
var _last_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icons = {
		"attack": load("res://assets/ui/icons/ability_attack.jpg"),
		"loot": load("res://assets/ui/icons/res_scrap.jpg"),
		"meat": load("res://assets/ui/icons/res_meat.jpg"),
		"bandage": load("res://assets/ui/icons/ability_heal.jpg"),
		"inv": load("res://assets/ui/icons/res_cloth.jpg"),
		"base": load("res://assets/ui/icons/base_core.jpg"),
	}
	_layout()

func _layout() -> void:
	var s := get_viewport_rect().size
	_stick_center = Vector2(130, s.y - 130)
	var br := Vector2(s.x - 100, s.y - 110)
	_buttons = [
		{"id": "attack", "center": br, "radius": 62.0, "label": "", "touch": -1},
		{"id": "loot", "center": br + Vector2(-128, 28), "radius": 36.0, "label": "E", "touch": -1},
		{"id": "meat", "center": br + Vector2(-118, -72), "radius": 32.0, "label": "1", "touch": -1},
		{"id": "bandage", "center": br + Vector2(-30, -122), "radius": 32.0, "label": "2", "touch": -1},
		{"id": "inv", "center": Vector2(102, 33), "radius": 26.0, "label": "I", "touch": -1},
		{"id": "base", "center": Vector2(160, 33), "radius": 26.0, "label": "B", "touch": -1},
		{"id": "pause", "center": Vector2(s.x / 2.0, 22), "radius": 0.0, "label": "", "touch": -1},
	]
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _stick_touch == -1 and t.position.distance_to(_stick_center) < STICK_RADIUS * 1.8:
				_stick_touch = t.index
				_update_stick(t.position)
				get_viewport().set_input_as_handled()
				return
			for b in _buttons:
				if b.radius > 0.0 and t.position.distance_to(b.center) <= b.radius * 1.25:
					b.touch = t.index
					_press(b.id)
					queue_redraw()
					get_viewport().set_input_as_handled()
					return
		else:
			if t.index == _stick_touch:
				_stick_touch = -1
				_update_stick(_stick_center)
			for b in _buttons:
				if b.touch == t.index:
					b.touch = -1
					_release(b.id)
					queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_touch:
			_update_stick(d.position)
			get_viewport().set_input_as_handled()

func _update_stick(pos: Vector2) -> void:
	var v := (pos - _stick_center) / STICK_RADIUS
	if v.length() > 1.0:
		v = v.normalized()
	_stick_vec = v if v.length() > 0.15 else Vector2.ZERO
	_set_action("move_left", maxf(0.0, -_stick_vec.x))
	_set_action("move_right", maxf(0.0, _stick_vec.x))
	_set_action("move_up", maxf(0.0, -_stick_vec.y))
	_set_action("move_down", maxf(0.0, _stick_vec.y))
	queue_redraw()

func _set_action(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)

func _press(id: String) -> void:
	if hero == null:
		return
	match id:
		"attack": hero.touch_attack_held = true
		"loot": hero.try_interact()
		"meat": hero.use_consumable(&"meat")
		"bandage": hero.use_consumable(&"bandage")
		"inv": toggle_inventory.emit()
		"base": toggle_base.emit()

func _release(id: String) -> void:
	if id == "attack" and hero:
		hero.touch_attack_held = false

func _draw() -> void:
	# Joystick
	draw_circle(_stick_center, STICK_RADIUS, Color(0, 0, 0, 0.35))
	draw_arc(_stick_center, STICK_RADIUS, 0, TAU, 40, Color(UIStyle.BRONZE, 0.8), 3.0)
	draw_circle(_stick_center + _stick_vec * STICK_RADIUS, 34.0, Color(UIStyle.GOLD, 0.55 if _stick_touch >= 0 else 0.35))
	var font := ThemeDB.fallback_font
	for b in _buttons:
		if b.radius <= 0.0:
			continue
		var c: Vector2 = b.center
		var r: float = b.radius
		var pressed: bool = b.touch >= 0
		draw_circle(c, r + 3.0, Color(0, 0, 0, 0.55))
		var tex: Texture2D = _icons.get(b.id)
		if tex:
			draw_texture_rect(tex, Rect2(c - Vector2(r, r) * 0.78, Vector2(r, r) * 1.56), false, Color(1, 1, 1, 1.0 if pressed else 0.85))
		draw_arc(c, r, 0, TAU, 40, UIStyle.GOLD if pressed else UIStyle.BRONZE, 3.0)
		if b.label != "":
			draw_string_outline(font, c + Vector2(r * 0.35, r * 0.95), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color.BLACK)
			draw_string(font, c + Vector2(r * 0.35, r * 0.95), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		if b.id in ["meat", "bandage"] and hero:
			var id := StringName(b.id)
			var n := ResourceManager.hero_inventory.count(id) + (ResourceManager.storage.count(id) if BaseZone.hero_inside else 0)
			draw_string_outline(font, c + Vector2(-r * 0.9, -r * 0.55), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color.BLACK)
			draw_string(font, c + Vector2(-r * 0.9, -r * 0.55), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

func _process(_delta: float) -> void:
	var vs := get_viewport_rect().size
	if vs != _last_size:
		_last_size = vs
		var touches := []
		for b in _buttons:
			touches.append(b.touch)
		_layout()
		for i in mini(touches.size(), _buttons.size()):
			_buttons[i].touch = touches[i]
	queue_redraw()
