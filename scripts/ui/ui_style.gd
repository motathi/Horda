class_name UIStyle
## Paleta e fábricas de componentes da interface (painéis de pedra escura com
## bordas de bronze, inspirados em Dota 2 / Warcraft III).

const BG := Color(0.07, 0.065, 0.06, 0.92)
const BG_LIGHT := Color(0.13, 0.12, 0.1, 0.95)
const BRONZE := Color(0.62, 0.47, 0.25)
const BRONZE_DARK := Color(0.32, 0.24, 0.13)
const GOLD := Color(1.0, 0.82, 0.4)
const TEXT := Color(0.93, 0.89, 0.8)
const TEXT_DIM := Color(0.65, 0.6, 0.52)
const RED := Color(0.85, 0.2, 0.15)
const GREEN := Color(0.3, 0.85, 0.3)
const BLUE := Color(0.3, 0.6, 1.0)

static func panel_style(bg: Color = BG, border: Color = BRONZE, width: int = 2, radius: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 6
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

static func panel(bg: Color = BG) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg))
	return p

static func label(text: String, size: int = 16, color: Color = TEXT, outline: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 4)
	return l

static func button(text: String, size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.42, 0.38))
	var normal := panel_style(Color(0.16, 0.13, 0.1, 0.95), BRONZE_DARK, 2, 3)
	var hover := panel_style(Color(0.24, 0.19, 0.12, 0.98), BRONZE, 2, 3)
	var pressed := panel_style(Color(0.1, 0.08, 0.06, 1.0), GOLD, 2, 3)
	var disabled := panel_style(Color(0.1, 0.1, 0.1, 0.8), Color(0.22, 0.2, 0.18), 2, 3)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", hover)
	b.pressed.connect(func() -> void: AudioManager.play(&"ui_click", -4.0))
	return b

static func bar(fill: Color, height: float = 18.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.04, 0.03, 0.95)
	bg.border_color = Color(0, 0, 0)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(2)
	fg.border_color = fill.lightened(0.3)
	fg.border_width_top = 2
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb

static func icon(tex: Texture2D, size: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return t

## Ícone de item com contador no canto (estilo slot de inventário).
static func item_slot(id: StringName, count: int, size: float = 48.0) -> Control:
	var def := ResourceManager.get_def(id)
	var holder := PanelContainer.new()
	var st := panel_style(Color(0.04, 0.035, 0.03, 0.95), BRONZE_DARK, 1, 2)
	st.set_content_margin_all(2)
	holder.add_theme_stylebox_override("panel", st)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(size, size)
	holder.add_child(stack)
	var ic := icon(def.icon if def else null, size)
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(ic)
	var l := label(str(count), 14, Color.WHITE)
	l.position = Vector2(size - 30, size - 20)
	l.size = Vector2(28, 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(l)
	if def:
		holder.tooltip_text = "%s\n%s" % [def.display_name, def.description]
	return holder

# --- HUD estilo "mobile strategy" (layout da referência) ----------------------

const HUD_ICONS := "res://assets/ui/hud/"
const GOLD_EDGE := Color(0.86, 0.66, 0.3)
const GOLD_DARK := Color(0.42, 0.29, 0.12)
const PANEL_BG := Color(0.07, 0.07, 0.09, 0.86)

static var _theme: Theme

## Tema com fonte em negrito e contorno (textos legíveis sobre o cenário).
static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		f.variation_embolden = 0.55
		_theme.default_font = f
		_theme.default_font_size = 16
	return _theme

static func hud_icon(icon_name: String) -> Texture2D:
	var path := HUD_ICONS + icon_name + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

## Painel escuro com borda dourada dupla e cantos levemente arredondados.
static func hud_panel_style(bg: Color = PANEL_BG, radius: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = GOLD_EDGE
	s.set_border_width_all(3)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	s.set_content_margin_all(10)
	s.anti_aliasing = true
	return s

## Barra com cantos arredondados (vida, mochila).
static func hud_bar(fill: Color, height: float = 26.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.03, 0.04, 0.95)
	bg.border_color = Color(0.0, 0.0, 0.0, 1.0)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(int(height * 0.3))
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(int(height * 0.3))
	fg.border_color = fill.lightened(0.35)
	fg.border_width_top = 3
	fg.border_width_bottom = 2
	fg.border_color = fill.lightened(0.35)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb

## Vértices de um hexágono "em pé" (ponta para cima).
static func hex_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 90.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts

## Botão hexagonal: aura (opcional), borda dourada em degraus, fundo escuro e ícone.
static func draw_hex_button(ci: CanvasItem, c: Vector2, r: float, tex: Texture2D, pressed: bool, glow: float = 0.0, dim: bool = false) -> void:
	if glow > 0.0:
		for k in 3:
			ci.draw_colored_polygon(hex_points(c, r + 8.0 + k * 5.0), Color(1.0, 0.75, 0.25, glow * (0.22 - k * 0.06)))
	ci.draw_colored_polygon(hex_points(c + Vector2(0, 4), r + 4.0), Color(0, 0, 0, 0.55))
	ci.draw_colored_polygon(hex_points(c, r + 3.0), GOLD_DARK)
	ci.draw_colored_polygon(hex_points(c, r), GOLD_EDGE.lightened(0.25) if pressed else GOLD_EDGE)
	ci.draw_colored_polygon(hex_points(c, r - 5.0), Color(0.16, 0.12, 0.08))
	var inner := hex_points(c, r - 8.0)
	var cols := PackedColorArray()
	for i in 6:
		cols.append(Color(0.2, 0.17, 0.16) if i in [0, 1, 5] else Color(0.05, 0.05, 0.07))
	ci.draw_polygon(inner, cols)
	if tex:
		var s := r * (1.25 if pressed else 1.18)
		ci.draw_texture_rect(tex, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(0.45, 0.45, 0.45, 0.8) if dim else Color.WHITE)
	ci.draw_polyline(hex_points(c, r - 8.0) + PackedVector2Array([hex_points(c, r - 8.0)[0]]), Color(0, 0, 0, 0.6), 2.0, true)

## Selo circular com número (atalho de teclado / contagem).
static func draw_badge(ci: CanvasItem, c: Vector2, r: float, text: String, size: int = 18) -> void:
	ci.draw_circle(c, r + 2.0, GOLD_EDGE)
	ci.draw_circle(c, r, Color(0.05, 0.05, 0.06))
	var f := theme().default_font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string_outline(f, c + Vector2(-w * 0.5, size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color.BLACK)
	ci.draw_string(f, c + Vector2(-w * 0.5, size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
