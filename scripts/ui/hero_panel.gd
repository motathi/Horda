class_name HeroPanel
extends Control
## Painel do herói (canto superior esquerdo): retrato com selo de nível, nome,
## vida, energia e mochila. Tocar/clicar no retrato abre o painel do personagem.

signal portrait_pressed

const W := 330.0
const H := 140.0
const PORTRAIT := 96.0

var hero: Hero
var _hp_bar: ProgressBar
var _hp_label: Label
var _bag_bar: ProgressBar
var _en_bar: ProgressBar
var _en_label: Label
var _bag_label: Label
var _portrait_tex: Texture2D
var _heart: Texture2D
var _bag: Texture2D

func _ready() -> void:
	custom_minimum_size = Vector2(W, H)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_portrait_tex = HeroSkins.portrait(GameManager.hero_skin)
	_heart = UIStyle.hud_icon("heart")
	_bag = UIStyle.hud_icon("backpack")
	var name_l := UIStyle.label(HeroSkins.get_skin(GameManager.hero_skin)["name"] if GameManager.hero_skin != HeroSkins.DEFAULT else "Sobrevivente", 21, Color.WHITE)
	name_l.position = Vector2(PORTRAIT + 26, 6)
	add_child(name_l)
	_hp_bar = UIStyle.hud_bar(Color(0.22, 0.78, 0.18), 26)
	_hp_bar.position = Vector2(PORTRAIT + 58, 40)
	_hp_bar.size = Vector2(W - PORTRAIT - 72, 26)
	add_child(_hp_bar)
	_hp_label = _bar_label(_hp_bar)
	_en_bar = UIStyle.hud_bar(Color(0.2, 0.45, 1.0), 20)
	_en_bar.position = Vector2(PORTRAIT + 58, 72)
	_en_bar.size = Vector2(W - PORTRAIT - 72, 20)
	add_child(_en_bar)
	_en_label = _bar_label(_en_bar)
	_en_label.add_theme_font_size_override("font_size", 14)
	_bag_bar = UIStyle.hud_bar(Color(0.72, 0.5, 0.2), 22)
	_bag_bar.position = Vector2(PORTRAIT + 58, 102)
	_bag_bar.size = Vector2(W - PORTRAIT - 72, 22)
	add_child(_bag_bar)
	_bag_label = _bar_label(_bag_bar)
	tooltip_text = "Clique no retrato para abrir o personagem (P)"

func _bar_label(bar: ProgressBar) -> Label:
	var l := UIStyle.label("", 16, Color.WHITE)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(l)
	return l

func _gui_input(event: InputEvent) -> void:
	var pressed := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if pressed and event.position.x < PORTRAIT + 16:
		portrait_pressed.emit()
		accept_event()

func _process(_delta: float) -> void:
	if hero == null:
		return
	var h := hero.health
	_hp_bar.max_value = h.max_health
	_hp_bar.value = h.current
	_hp_label.text = "%d / %d" % [int(h.current), int(h.max_health)]
	_en_bar.max_value = hero.max_energy
	_en_bar.value = hero.energy
	_en_label.text = "%d / %d" % [int(hero.energy), int(hero.max_energy)]
	var inv := ResourceManager.hero_inventory
	_bag_bar.max_value = inv.capacity
	_bag_bar.value = inv.used_weight()
	_bag_label.text = "%d / %d" % [inv.used_weight(), inv.capacity]
	tooltip_text = "Nível %d — XP %d / %d\nDano %d • Armadura %d • Crítico %d%%\nClique no retrato para abrir o personagem (P)" % [
		hero.level, hero.xp, hero.xp_to_next(), int(hero.damage()), int(h.armor), roundi(hero.crit() * 100)]
	queue_redraw()

func _draw() -> void:
	# Fundo do painel (atrás do retrato, começando na metade dele)
	var panel := Rect2(Vector2(PORTRAIT * 0.55, 4), Vector2(W - PORTRAIT * 0.55, H - 8))
	draw_style_box(UIStyle.hud_panel_style(UIStyle.PANEL_BG, 12), panel)
	# Ícones das barras
	if _heart:
		draw_texture_rect(_heart, Rect2(Vector2(PORTRAIT + 20, 34), Vector2(36, 36)), false)
	if _bag:
		draw_texture_rect(_bag, Rect2(Vector2(PORTRAIT + 20, 96), Vector2(34, 34)), false)
	# Ícone de energia (gota azul)
	draw_circle(Vector2(PORTRAIT + 38, 82), 11.0, Color(0.15, 0.4, 1.0))
	draw_circle(Vector2(PORTRAIT + 35, 79), 4.0, Color(0.7, 0.85, 1.0, 0.8))
	# Retrato com moldura dourada
	var pr := Rect2(Vector2(4, 4), Vector2(PORTRAIT, PORTRAIT + 4))
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color.BLACK
	frame.border_color = UIStyle.GOLD_EDGE
	frame.set_border_width_all(4)
	frame.set_corner_radius_all(14)
	frame.shadow_color = Color(0, 0, 0, 0.6)
	frame.shadow_size = 6
	draw_style_box(frame, pr.grow(2))
	if _portrait_tex:
		draw_texture_rect(_portrait_tex, pr.grow(-4), false)
	# Barra fina de XP na base do retrato
	if hero:
		var xr := Rect2(pr.position + Vector2(8, pr.size.y - 10), Vector2(pr.size.x - 16, 5))
		draw_rect(xr, Color(0, 0, 0, 0.8))
		draw_rect(Rect2(xr.position, Vector2(xr.size.x * float(hero.xp) / hero.xp_to_next(), xr.size.y)), UIStyle.GOLD)
	# Selo de nível (hexágono) no canto inferior esquerdo do retrato
	var bc := Vector2(14, PORTRAIT - 2)
	draw_colored_polygon(UIStyle.hex_points(bc, 19), UIStyle.GOLD_DARK)
	draw_colored_polygon(UIStyle.hex_points(bc, 16), UIStyle.GOLD_EDGE)
	draw_colored_polygon(UIStyle.hex_points(bc, 12), Color(0.06, 0.06, 0.08))
	var f := UIStyle.theme().default_font
	var t := str(hero.level if hero else 1)
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string_outline(f, bc + Vector2(-tw * 0.5, 7), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color.BLACK)
	draw_string(f, bc + Vector2(-tw * 0.5, 7), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	# Pontos de atributo livres: selo "+" pulsante no canto superior direito do retrato.
	if hero and hero.attr_points > 0:
		var pc := Vector2(PORTRAIT - 4, 14)
		var pulse := 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.008)
		draw_circle(pc, 15.0 * pulse, UIStyle.GOLD_DARK)
		draw_circle(pc, 12.5 * pulse, UIStyle.GOLD)
		draw_rect(Rect2(pc - Vector2(7, 2), Vector2(14, 4)), Color(0.1, 0.06, 0.02))
		draw_rect(Rect2(pc - Vector2(2, 7), Vector2(4, 14)), Color(0.1, 0.06, 0.02))
