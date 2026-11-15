class_name HudActions
extends Control
## Botões de ação hexagonais (canto inferior direito) e, no celular, joystick
## virtual (canto inferior esquerdo). Multitoque via InputEventScreenTouch; no PC
## os botões também funcionam com o mouse (e com os atalhos Espaço/E/1/2).

const STICK_RADIUS := 82.0

signal build_pressed

var hero: Hero
var touch_enabled: bool = false
var _stick_touch: int = -1
var _stick_center: Vector2
var _stick_vec: Vector2 = Vector2.ZERO
var _buttons: Array[Dictionary] = []
var _last_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons = [
		{"id": "attack", "off": Vector2(-96, -118), "r": 70.0, "key": "", "icon": UIStyle.hud_icon("swords"), "touch": -99, "glow": 1.0},
		{"id": "loot", "off": Vector2(-258, -112), "r": 50.0, "key": "E", "icon": UIStyle.hud_icon("loot"), "touch": -99, "glow": 0.0},
		{"id": "meat", "off": Vector2(-212, -258), "r": 46.0, "key": "1", "icon": UIStyle.hud_icon("meat"), "touch": -99, "glow": 0.0},
		{"id": "bandage", "off": Vector2(-90, -284), "r": 46.0, "key": "2", "icon": UIStyle.hud_icon("potion"), "touch": -99, "glow": 0.0},
		{"id": "build", "off": Vector2(-376, -104), "r": 44.0, "key": "G", "icon": UIStyle.hud_icon("build"), "touch": -99, "glow": 0.0},
	]

func _center(b: Dictionary) -> Vector2:
	return get_viewport_rect().size + (b.off as Vector2)

## Retângulo ocupado pelos botões (para outros painéis evitarem a área).
func is_over_button(p: Vector2) -> bool:
	for b in _buttons:
		if p.distance_to(_center(b)) <= b.r:
			return true
	return false

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var vs := get_viewport_rect().size
	_stick_center = Vector2(150, vs.y - 150)
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if touch_enabled and _stick_touch == -1 and t.position.distance_to(_stick_center) < STICK_RADIUS * 1.8:
				_stick_touch = t.index
				_update_stick(t.position)
				get_viewport().set_input_as_handled()
				return
			if _try_press(t.position, t.index):
				get_viewport().set_input_as_handled()
		else:
			if t.index == _stick_touch:
				_stick_touch = -1
				_update_stick(_stick_center)
			_release_index(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_touch:
			_update_stick(d.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not Platform.touch:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if _try_press(mb.position, -1):
				get_viewport().set_input_as_handled()
		else:
			_release_index(-1)

func _try_press(p: Vector2, index: int) -> bool:
	for b in _buttons:
		if p.distance_to(_center(b)) <= b.r * 1.15:
			b.touch = index
			_press(b.id)
			return true
	return false

func _release_index(index: int) -> void:
	for b in _buttons:
		if b.touch == index:
			b.touch = -99
			if b.id == "attack" and hero:
				hero.touch_attack_held = false

func _press(id: String) -> void:
	if hero == null:
		return
	match id:
		"attack": hero.touch_attack_held = true
		"loot": hero.try_interact()
		"meat": hero.use_consumable(&"meat")
		"bandage": hero.use_consumable(&"bandage")
		"build": build_pressed.emit()

func _update_stick(pos: Vector2) -> void:
	var v := (pos - _stick_center) / STICK_RADIUS
	if v.length() > 1.0:
		v = v.normalized()
	_stick_vec = v if v.length() > 0.15 else Vector2.ZERO
	_set_action("move_left", maxf(0.0, -_stick_vec.x))
	_set_action("move_right", maxf(0.0, _stick_vec.x))
	_set_action("move_up", maxf(0.0, -_stick_vec.y))
	_set_action("move_down", maxf(0.0, _stick_vec.y))

func _set_action(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var vs := get_viewport_rect().size
	if touch_enabled:
		_stick_center = Vector2(150, vs.y - 150)
		draw_circle(_stick_center, STICK_RADIUS + 4, Color(0, 0, 0, 0.25))
		draw_arc(_stick_center, STICK_RADIUS, 0, TAU, 48, Color(UIStyle.GOLD_EDGE, 0.85), 4.0, true)
		draw_circle(_stick_center + _stick_vec * STICK_RADIUS, 36.0, Color(UIStyle.GOLD_EDGE, 0.55 if _stick_touch >= 0 else 0.35))
		draw_arc(_stick_center + _stick_vec * STICK_RADIUS, 36.0, 0, TAU, 32, Color(0, 0, 0, 0.5), 2.0, true)
	var f := UIStyle.theme().default_font
	for b in _buttons:
		var c := _center(b)
		var r: float = b.r
		var pressed: bool = b.touch != -99
		var count := -1
		if b.id in ["meat", "bandage"] and hero:
			var cid := StringName(b.id)
			count = ResourceManager.hero_inventory.count(cid) + (ResourceManager.storage.count(cid) if BaseZone.hero_inside else 0)
		UIStyle.draw_hex_button(self, c, r, b.icon, pressed, b.glow, count == 0)
		if b.key != "" and not (Platform.touch and b.id == "attack"):
			UIStyle.draw_badge(self, c + Vector2(r * 0.6, r * 0.62), 15.0, b.key, 19)
		if count > 0:
			var t := str(count)
			var pos := c + Vector2(-r * 0.5, -r * 0.28)
			draw_string_outline(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color.BLACK)
			draw_string(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
