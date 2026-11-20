class_name TitleStyle
## Estilo da tela inicial: botões e painéis com a arte de metal e ouro renderizada no Blender
## (tools/blender_ui.py → assets/ui/title/), fonte serifada e efeitos de hover/clique.

const DIR := "res://assets/ui/title/"
const FONT := "res://assets/ui/fonts/CrimsonPro-Bold.ttf"
const CREAM := Color(0.96, 0.88, 0.68)
const HOT := Color(1.0, 0.95, 0.82)

static var _font: Font
static var _shine: Shader

static func font() -> Font:
	if _font == null:
		_font = load(FONT) as Font if ResourceLoader.exists(FONT) else ThemeDB.fallback_font
	return _font

static func _tex_box(name: String, margin_h: float, margin_v: float, content_h: float, content_v: float) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(DIR + name + ".png") as Texture2D
	sb.texture_margin_left = margin_h
	sb.texture_margin_right = margin_h
	sb.texture_margin_top = margin_v
	sb.texture_margin_bottom = margin_v
	sb.content_margin_left = content_h
	sb.content_margin_right = content_h
	sb.content_margin_top = content_v
	sb.content_margin_bottom = content_v
	return sb

## Aplica a arte de botão a um Button já existente (mantém texto, sinais e toggle).
static func style_button(b: Button, font_size: int = 24) -> void:
	for st: String in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, _tex_box("ui_button_" + st, 28, 23, 26, 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover_pressed", _tex_box("ui_button_pressed", 28, 23, 26, 10))
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", HOT)
	b.add_theme_color_override("font_pressed_color", HOT)
	b.add_theme_color_override("font_hover_pressed_color", HOT)
	b.add_theme_color_override("font_focus_color", CREAM)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.47, 0.42))
	b.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0))
	b.add_theme_constant_override("outline_size", 6)
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, maxf(48.0, font_size * 2.4))
	b.material = shine_material()
	_hook_fx(b)

static func button(text: String, font_size: int = 24) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	style_button(b, font_size)
	return b

## Moldura de painel (9-slice) para PanelContainer.
static func panel_box() -> StyleBoxTexture:
	return _tex_box("ui_panel", 70, 70, 58, 54)

static func style_panel(p: PanelContainer) -> void:
	p.add_theme_stylebox_override("panel", panel_box())

static func divider(width: float = 320.0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(DIR + "ui_divider.png") as Texture2D
	t.custom_minimum_size = Vector2(width, width * 48.0 / 640.0)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

static func title_label(text: String, size: int = 34) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1.0, 0.8, 0.42))
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.02, 0.0))
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_shadow_color", Color(1.0, 0.3, 0.05, 0.45))
	l.add_theme_constant_override("shadow_outline_size", 14)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	return l

## Brilho que passa pelo botão quando o cursor está em cima (uniform "hover" 0..1).
static func shine_material() -> ShaderMaterial:
	if _shine == null:
		_shine = Shader.new()
		_shine.code = """
shader_type canvas_item;
uniform float hover = 0.0;
uniform float width = 380.0;
varying vec2 local;
void vertex() { local = VERTEX; }
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float sweep = fract(TIME * 0.7) * 1.8 - 0.4;
	float x = local.x / width - local.y / width * 0.35;
	float band = smoothstep(0.08, 0.0, abs(x - sweep));
	c.rgb += vec3(1.0, 0.78, 0.45) * band * 0.35 * hover * c.a;
	COLOR = c;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _shine
	return m

## Hover: cresce um pouco, acende o brilho e toca o som; clique: lampejo e som.
static func _hook_fx(b: Button) -> void:
	if b.has_meta(&"title_fx"):
		return
	b.set_meta(&"title_fx", true)
	b.resized.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		if b.material:
			(b.material as ShaderMaterial).set_shader_parameter("width", maxf(1.0, b.size.x)))
	b.mouse_entered.connect(func() -> void:
		if b.disabled:
			return
		var tw := b.create_tween().set_parallel()
		tw.tween_property(b, "scale", Vector2.ONE * 1.04, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if b.material:
			tw.tween_property(b.material, "shader_parameter/hover", 1.0, 0.15))
	b.mouse_exited.connect(func() -> void:
		var tw := b.create_tween().set_parallel()
		tw.tween_property(b, "scale", Vector2.ONE, 0.15)
		if b.material:
			tw.tween_property(b.material, "shader_parameter/hover", 0.0, 0.25))
	b.button_down.connect(func() -> void:
		var tw := b.create_tween()
		tw.tween_property(b, "modulate", Color(1.8, 1.45, 1.1), 0.05)
		tw.tween_property(b, "modulate", Color.WHITE, 0.25))
