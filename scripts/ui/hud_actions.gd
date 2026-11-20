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
var _stick_home: Vector2
var _stick_vec: Vector2 = Vector2.ZERO
var _buttons: Array[Dictionary] = []
var _last_size: Vector2 = Vector2.ZERO
var _lock_icon: Texture2D

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons = [
		{"id": "attack", "off": Vector2(-100, -120), "r": 66.0, "key": "", "icon": UIStyle.hud_icon("swords"), "touch": -99, "glow": 1.0},
		# Habilidades em arco em volta do ataque
		{"id": "ab0", "off": Vector2(-238, -64), "r": 42.0, "key": "Q", "icon": UIStyle.hud_icon("ab_whirl"), "touch": -99, "glow": 0.0},
		{"id": "ab1", "off": Vector2(-258, -172), "r": 42.0, "key": "F", "icon": UIStyle.hud_icon("ab_dash"), "touch": -99, "glow": 0.0},
		{"id": "ab2", "off": Vector2(-198, -268), "r": 42.0, "key": "R", "icon": UIStyle.hud_icon("ab_warcry"), "touch": -99, "glow": 0.0},
		{"id": "ab3", "off": Vector2(-88, -294), "r": 46.0, "key": "T", "icon": UIStyle.hud_icon("ab_nova"), "touch": -99, "glow": 0.0},
		# Fileira de utilidades
		# Esquiva (Shift): ao lado do ataque, fácil de alcançar com o polegar.
		{"id": "dodge", "off": Vector2(-350, -128), "r": 38.0, "key": "⇧", "icon": UIStyle.hud_icon("dodge"), "touch": -99, "glow": 0.0},
		{"id": "loot", "off": Vector2(-378, -50), "r": 34.0, "key": "E", "icon": UIStyle.hud_icon("loot"), "touch": -99, "glow": 0.0},
		{"id": "potion", "off": Vector2(-460, -50), "r": 34.0, "key": "3", "icon": UIStyle.hud_icon("potion_red"), "touch": -99, "glow": 0.0},
		{"id": "meat", "off": Vector2(-542, -50), "r": 34.0, "key": "1", "icon": UIStyle.hud_icon("meat"), "touch": -99, "glow": 0.0},
		{"id": "bandage", "off": Vector2(-624, -50), "r": 34.0, "key": "2", "icon": UIStyle.hud_icon("potion"), "touch": -99, "glow": 0.0},
		{"id": "build", "off": Vector2(-706, -50), "r": 34.0, "key": "G", "icon": UIStyle.hud_icon("build"), "touch": -99, "glow": 0.0},
	]
	_lock_icon = UIStyle.hud_icon("lock")

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
	_stick_home = Vector2(150, vs.y - 150)
	if _stick_touch == -1:
		_stick_center = _stick_home
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _try_press(t.position, t.index):
				get_viewport().set_input_as_handled()
				return
			# Joystick flutuante: nasce onde o dedo tocar no terço inferior esquerdo.
			if touch_enabled and _stick_touch == -1 and _in_stick_zone(t.position, vs):
				_stick_touch = t.index
				_stick_center = t.position
				_update_stick(t.position)
				get_viewport().set_input_as_handled()
				return
		else:
			if t.index == _stick_touch:
				_stick_touch = -1
				_stick_center = _stick_home
				_update_stick(_stick_center)
				get_viewport().set_input_as_handled()
			_release_index(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_touch:
			_update_stick(d.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouse and Platform.touch:
		# O navegador também gera "mouse" a partir do 1º dedo: se esse dedo está no
		# joystick ou num botão, o evento não pode virar um toque no mundo.
		if _stick_touch == 0 or _any_button_touch(0) or (event is InputEventMouseButton and (_in_stick_zone(event.position, vs) or is_over_button(event.position))):
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

func _in_stick_zone(p: Vector2, vs: Vector2) -> bool:
	return p.x < vs.x * 0.38 and p.y > vs.y * 0.45

func _any_button_touch(index: int) -> bool:
	for b in _buttons:
		if b.touch == index:
			return true
	return false

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
		"potion": hero.use_consumable(&"potion")
		"dodge": hero.dodge()
		"bandage": hero.use_consumable(&"bandage")
		"build": build_pressed.emit()
		"ab0", "ab1", "ab2", "ab3":
			var why := hero.cast_ability(int(id.substr(2)))
			if why != "":
				EventBus.notify(why, Color(1, 0.6, 0.45))

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

## Ícones das habilidades da classe do herói, carregados fora do _draw (carregar uma
## textura pela primeira vez durante o desenho a deixa branca no renderizador web).
var _ab_icons: Array[Texture2D] = []
var _ab_icons_for: Array = []

func _process(_delta: float) -> void:
	if hero and _ab_icons_for != hero.abilities:
		_ab_icons_for = hero.abilities.duplicate()
		_ab_icons.clear()
		for a: AbilityDef in hero.abilities:
			_ab_icons.append(a.icon())
	queue_redraw()

func _draw() -> void:
	var vs := get_viewport_rect().size
	if touch_enabled:
		if _stick_touch == -1:
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
		if String(b.id).begins_with("ab"):
			_draw_ability(b, c, r, pressed, f)
			continue
		var count := -1
		if b.id in ["meat", "bandage", "potion"] and hero:
			var cid := StringName(b.id)
			count = ResourceManager.hero_inventory.count(cid) + (ResourceManager.storage.count(cid) if BaseZone.hero_inside else 0)
		var dim := count == 0
		if b.id == "dodge" and hero:
			dim = hero.dodge_ratio() > 0.0
		UIStyle.draw_hex_button(self, c, r, b.icon, pressed, b.glow, dim)
		if b.id == "dodge" and hero and hero.dodge_ratio() > 0.0:
			draw_arc(c, r * 0.82, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - hero.dodge_ratio()), 32, Color(0.6, 0.9, 1.0, 0.9), 4.0, true)
		if b.key != "" and not (Platform.touch and b.id == "attack"):
			UIStyle.draw_badge(self, c + Vector2(r * 0.6, r * 0.62), 15.0, b.key, 19)
		if count > 0:
			var t := str(count)
			var pos := c + Vector2(-r * 0.5, -r * 0.28)
			draw_string_outline(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color.BLACK)
			draw_string(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)

func _draw_ability(b: Dictionary, c: Vector2, r: float, pressed: bool, f: Font) -> void:
	if hero == null:
		return
	var i := int(String(b.id).substr(2))
	var a := hero.abilities[i]
	var locked := not hero.is_unlocked(i)
	var cd := hero.cooldown_left(i)
	var no_energy := hero.energy < a.energy_cost
	# Ícone da habilidade da classe do herói (Caçador e Cavaleiro têm habilidades diferentes).
	var tex: Texture2D = _ab_icons[i] if i < _ab_icons.size() and _ab_icons[i] else b.icon
	UIStyle.draw_hex_button(self, c, r, tex, pressed, 0.6 if (not locked and cd <= 0.0 and not no_energy and i == 3) else 0.0, locked or no_energy)
	if locked:
		draw_colored_polygon(UIStyle.hex_points(c, r - 8.0), Color(0, 0, 0, 0.55))
		if _lock_icon:
			draw_texture_rect(_lock_icon, Rect2(c - Vector2(r, r) * 0.38, Vector2(r, r) * 0.76), false)
		var t := "Nv %d" % a.unlock_level
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string_outline(f, c + Vector2(-w * 0.5, r * 0.62), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color.BLACK)
		draw_string(f, c + Vector2(-w * 0.5, r * 0.62), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIStyle.GOLD)
	elif cd > 0.0:
		# Escurece a fração ainda em recarga (de cima para baixo) e mostra os segundos.
		var ratio := hero.cooldown_ratio(i)
		var pts := UIStyle.hex_points(c, r - 8.0)
		var top := c.y - (r - 8.0)
		var cut := top + (r - 8.0) * 2.0 * ratio
		var clipped := Geometry2D.intersect_polygons(pts, PackedVector2Array([Vector2(c.x - r, top - 2), Vector2(c.x + r, top - 2), Vector2(c.x + r, cut), Vector2(c.x - r, cut)]))
		for poly in clipped:
			draw_colored_polygon(poly, Color(0, 0, 0, 0.62))
		var t2 := str(ceili(cd))
		var w2 := f.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string_outline(f, c + Vector2(-w2 * 0.5, 9), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 5, Color.BLACK)
		draw_string(f, c + Vector2(-w2 * 0.5, 9), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	UIStyle.draw_badge(self, c + Vector2(r * 0.62, r * 0.62), 13.0, b.key, 16)
	# Custo de energia (gota azul)
	var cost := str(int(a.energy_cost))
	var pos := c + Vector2(-r * 0.78, r * 0.72)
	draw_circle(pos + Vector2(8, -6), 11.0, Color(0.1, 0.25, 0.7, 0.95))
	var cw := f.get_string_size(cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(f, pos + Vector2(8 - cw * 0.5, -1), cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
