class_name Minimap
extends Control
## Minimapa: regiões, base, herói, inimigos e saqueáveis disponíveis.

const MAP_HALF := 120.0
var regions: Array[Dictionary] = []
var lootables: Dictionary = {}
var _t: float = 0.0
var _stragglers: Array[Enemy] = []
var _warned_count: int = -1

func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(220, 220)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t += delta
	if _t > 0.2:
		_t = 0.0
		_update_stragglers()
		queue_redraw()

## Últimos zumbis da horda (3 ou menos): feixe vermelho e marcador pulsante.
func _update_stragglers() -> void:
	var horde: Array[Enemy] = []
	if TimeManager.is_night():
		for e in Enemy.all:
			if is_instance_valid(e) and e.is_horde and not e.is_dead():
				horde.append(e)
	var mark := horde.size() > 0 and horde.size() <= 3
	for e in _stragglers:
		if is_instance_valid(e) and (not mark or not horde.has(e)):
			e.set_beacon(false)
	_stragglers = horde if mark else ([] as Array[Enemy])
	for e in _stragglers:
		e.set_beacon(true)
	if mark and horde.size() != _warned_count:
		_warned_count = horde.size()
		EventBus.notify("Resta%s %d zumbi%s — marcado%s com feixe vermelho e no mapa." % ["m" if horde.size() > 1 else "", horde.size(), "s" if horde.size() > 1 else "", "s" if horde.size() > 1 else ""], Color(1, 0.5, 0.35))
	elif not mark:
		_warned_count = -1

func _to_map(p: Vector3) -> Vector2:
	return Vector2((p.x / (MAP_HALF * 2) + 0.5) * size.x, (p.z / (MAP_HALF * 2) + 0.5) * size.y)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.16, 0.08, 0.92))
	var font := ThemeDB.fallback_font
	var region_colors := {"Floresta": Color(0.12, 0.3, 0.1), "Pedreira": Color(0.35, 0.35, 0.35), "Cidade Abandonada": Color(0.32, 0.3, 0.34), "Fazenda": Color(0.4, 0.3, 0.12), "Área Contaminada": Color(0.3, 0.1, 0.35)}
	for r in regions:
		var c: Color = region_colors.get(r.name, Color(0.2, 0.2, 0.2))
		draw_circle(_to_map(r.center), float(r.radius) / (MAP_HALF * 2) * size.x, Color(c, 0.75))
	for r in regions:
		draw_string(font, _to_map(r.center) + Vector2(-30, 4), r.name, HORIZONTAL_ALIGNMENT_CENTER, 60, 9, Color(1, 1, 1, 0.7))
	for id: String in lootables:
		var l := lootables[id] as Lootable
		if is_instance_valid(l) and not l.looted:
			draw_circle(_to_map(l.global_position), 1.6, Color(1.0, 0.85, 0.3))
	draw_circle(_to_map(Vector3.ZERO), 7.0, Color(0.3, 0.6, 1.0, 0.9))
	draw_arc(_to_map(Vector3.ZERO), 7.0, 0, TAU, 20, Color.WHITE, 1.0)
	for e in Enemy.all:
		if is_instance_valid(e) and not e.is_dead():
			draw_circle(_to_map(e.global_position), 2.2 if not e.is_horde else 2.6, Color(1, 0.2, 0.15) if e.is_horde else Color(0.85, 0.35, 0.3))
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	for e in _stragglers:
		if is_instance_valid(e) and not e.is_dead():
			var mp := _to_map(e.global_position)
			draw_arc(mp, 6.0 + pulse * 4.0, 0, TAU, 16, Color(1, 0.2, 0.1, 1.0 - pulse * 0.6), 2.0)
			draw_circle(mp, 3.4, Color(1, 0.25, 0.1))
	# Coop: aliados em azul-claro.
	for ally: Node in Coop.remote_heroes.values():
		if is_instance_valid(ally):
			draw_circle(_to_map((ally as Node3D).global_position), 3.6, Color(0.45, 0.85, 1.0))
	var hero := GameManager.hero
	if hero:
		var hp := _to_map(hero.global_position)
		draw_circle(hp, 4.0, Color(0.3, 1.0, 0.3))
		draw_arc(hp, 4.5, 0, TAU, 12, Color.BLACK, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), UIStyle.BRONZE, false, 2.0)
