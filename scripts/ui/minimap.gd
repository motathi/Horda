class_name Minimap
extends Control
## Mapa (minimapa do HUD e mapa grande): o terreno de verdade pintado por shader a partir das camadas
## do WorldBuilder (capim seco, terra e estradas, calçamento, área contaminada, copas das árvores,
## pedras e construções com sombra e contorno, relevo de papel e grade tática), e por cima os ícones:
## fortaleza, baús, inimigos, aliados e a seta do herói apontando para onde ele olha.

signal pressed

const MAP_HALF := 120.0
var regions: Array[Dictionary] = []
var lootables: Dictionary = {}
## Mapa grande: ícones e nomes maiores, grade numerada.
var large: bool = false
var _t: float = 0.0
var _stragglers: Array[Enemy] = []
var _warned_count: int = -1
var _terrain: TextureRect
var _mat: ShaderMaterial

const REGION_COLORS := {"Floresta": Color(0.62, 0.8, 0.45), "Pedreira": Color(0.8, 0.8, 0.78), "Cidade Abandonada": Color(0.85, 0.8, 0.7),
	"Fazenda": Color(0.95, 0.78, 0.45), "Área Contaminada": Color(0.8, 0.55, 1.0)}

func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(220, 220)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_terrain = TextureRect.new()
	_terrain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_terrain.show_behind_parent = true
	_terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_terrain.texture = _white()
	_mat = ShaderMaterial.new()
	_mat.shader = _shader()
	_terrain.material = _mat
	add_child(_terrain)

## Camadas do mapa geradas pelo WorldBuilder.
func set_layers(splat: Texture2D, objects: Texture2D, noise: Texture2D) -> void:
	_mat.set_shader_parameter("splat", splat)
	_mat.set_shader_parameter("objects", objects)
	_mat.set_shader_parameter("noise", noise)
	_mat.set_shader_parameter("grid", 8.0)

func copy_layers_from(other: Minimap) -> void:
	for p: String in ["splat", "objects", "noise", "grid"]:
		_mat.set_shader_parameter(p, other._mat.get_shader_parameter(p))

func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		pressed.emit()
		accept_event()

func _process(delta: float) -> void:
	_t += delta
	if _t > 0.1:
		_t = 0.0
		_update_stragglers()
		queue_redraw()

## Últimos zumbis da horda (3 ou menos): feixe vermelho e marcador pulsante.
func _update_stragglers() -> void:
	if large:
		return  # o minimapa do HUD já cuida disso
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
	var k := size.x / 172.0  # escala dos ícones (minimapa = 1)
	var font := TitleStyle.font()
	# Nomes das regiões (fonte serifada com contorno, cor da região).
	var fs := int(clampf(10.0 * k, 10.0, 22.0))
	for r in regions:
		if r.get("hidden", false):
			continue
		var c: Color = REGION_COLORS.get(r.name, Color(0.9, 0.9, 0.9))
		var name: String = r.name if large or r.name != "Cidade Abandonada" else "Cidade"
		var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := _to_map(r.center) + Vector2(-w * 0.5, fs * 0.35)
		pos.x = clampf(pos.x, 4.0, size.x - w - 4.0)
		pos.y = clampf(pos.y, fs + 2.0, size.y - 4.0)
		draw_string_outline(font, pos, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, int(4 * k)), Color(0.02, 0.02, 0.02, 0.9))
		draw_string(font, pos, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
	# Baús/saqueáveis ainda fechados: losangos dourados.
	var ls := 1.8 * maxf(1.0, k * 0.8)
	for id: String in lootables:
		var l := lootables[id] as Lootable
		if is_instance_valid(l) and not l.looted:
			var p := _to_map(l.global_position)
			# Baús maiores, na cor do brilho (mantimentos dourado, equipamentos azul, guardião roxo).
			var chest := l.lid != null
			var q := ls * (1.6 if chest else 1.0)
			var col := l.glow_color if chest else Color(1.0, 0.82, 0.3)
			if chest:
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -q - 1), p + Vector2(q + 1, 0), p + Vector2(0, q + 1), p + Vector2(-q - 1, 0)]), Color(0, 0, 0, 0.8))
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -q), p + Vector2(q, 0), p + Vector2(0, q), p + Vector2(-q, 0)]), col)
	_draw_keep(_to_map(Vector3.ZERO), 6.5 * maxf(1.0, k * 0.75))
	# Inimigos (Espreitadores escondidos não aparecem; na névoa densa só os próximos do herói).
	var reveal_r := DayNightVisuals.map_reveal_radius()
	var me := GameManager.hero
	var er := 2.0 * maxf(1.0, k * 0.75)
	for e in Enemy.all:
		if is_instance_valid(e) and e.is_targetable():
			if reveal_r < INF and me and e.global_position.distance_to(me.global_position) > reveal_r and not _stragglers.has(e):
				continue
			var p := _to_map(e.global_position)
			if e.is_guardian:
				# Guardião (chefe do mapa): marcador roxo grande com anel.
				var gr := er * 2.0
				draw_circle(p, gr + 1.5, Color(0, 0, 0, 0.85))
				draw_circle(p, gr, Color(0.72, 0.3, 1.0))
				draw_arc(p, gr + 2.5, 0, TAU, 20, Color(0.85, 0.55, 1.0, 0.9), 1.5)
				continue
			var rr := er * (1.3 if e.is_horde else 1.0) * (1.4 if e.def and e.def.model_scale > 1.4 else 1.0)
			draw_circle(p, rr + 1.0, Color(0, 0, 0, 0.8))
			draw_circle(p, rr, Color(1, 0.18, 0.12) if e.is_horde else Color(0.9, 0.38, 0.3))
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	for e in _stragglers:
		if is_instance_valid(e) and not e.is_dead():
			var mp := _to_map(e.global_position)
			draw_arc(mp, (6.0 + pulse * 4.0) * maxf(1.0, k * 0.7), 0, TAU, 16, Color(1, 0.2, 0.1, 1.0 - pulse * 0.6), 2.0)
			draw_circle(mp, 3.4, Color(1, 0.25, 0.1))
	# Coop: aliados em azul-claro (setas).
	for ally: Node in Coop.remote_heroes.values():
		if is_instance_valid(ally):
			var a3 := ally as Node3D
			_draw_arrow(_to_map(a3.global_position), Vector2(0, -1).rotated(-a3.global_rotation.y), 5.0 * maxf(1.0, k * 0.8), Color(0.45, 0.85, 1.0))
	var hero := GameManager.hero
	if hero:
		var f: Vector3 = hero.call(&"facing")
		_draw_arrow(_to_map(hero.global_position), Vector2(f.x, f.z), 6.0 * maxf(1.0, k * 0.8), Color(0.45, 1.0, 0.4))
	if large:
		_draw_grid_labels(font)

## Seta (triângulo com recorte atrás) apontando na direção dada.
func _draw_arrow(p: Vector2, dir: Vector2, s: float, col: Color) -> void:
	if dir.length_squared() < 0.0001:
		dir = Vector2(0, -1)
	dir = dir.normalized()
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([p + dir * s * 1.2, p - dir * s * 0.8 + side * s * 0.85, p - dir * s * 0.35, p - dir * s * 0.8 - side * s * 0.85])
	var outline := PackedVector2Array()
	for q in pts:
		outline.append(p + (q - p) * 1.28)
	draw_colored_polygon(outline, Color(0, 0, 0, 0.85))
	draw_colored_polygon(pts, col)

## Ícone da fortaleza: torre com ameias, escura com contorno dourado.
func _draw_keep(c: Vector2, s: float) -> void:
	var poly := PackedVector2Array()
	var w := s
	var h := s * 0.9
	poly.append(c + Vector2(-w, h))
	poly.append(c + Vector2(-w, -h * 0.5))
	for i in 5:
		var x0 := -w + i * (w * 2.0 / 5.0)
		var x1 := x0 + w * 2.0 / 5.0
		var top := -h if i % 2 == 0 else -h * 0.5
		poly.append(c + Vector2(x0, top))
		poly.append(c + Vector2(x1, top))
	poly.append(c + Vector2(w, -h * 0.5))
	poly.append(c + Vector2(w, h))
	var outline := PackedVector2Array()
	for q in poly:
		outline.append(c + (q - c) * 1.3)
	draw_colored_polygon(outline, Color(0.9, 0.7, 0.3))
	draw_colored_polygon(poly, Color(0.12, 0.1, 0.09))
	draw_rect(Rect2(c + Vector2(-s * 0.22, h * 0.15), Vector2(s * 0.44, h * 0.85)), Color(1.0, 0.6, 0.2, 0.9))

## Mapa grande: letras e números da grade nas bordas (como um mapa tático).
func _draw_grid_labels(font: Font) -> void:
	var n := 8
	var fs := 14
	for i in n:
		var x := (i + 0.5) * size.x / n
		var y := (i + 0.5) * size.y / n
		draw_string_outline(font, Vector2(x - 5, 16), "ABCDEFGH"[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(x - 5, 16), "ABCDEFGH"[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.85, 0.6))
		draw_string_outline(font, Vector2(6, y + 5), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(6, y + 5), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.85, 0.6))

static var _white_tex: Texture2D
static func _white() -> Texture2D:
	if _white_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex

static var _sh: Shader
static func _shader() -> Shader:
	if _sh == null:
		_sh = Shader.new()
		_sh.code = """
shader_type canvas_item;
uniform sampler2D splat : filter_linear;
uniform sampler2D objects : filter_linear;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform float grid = 8.0;
float obj_a(vec2 uv) { return texture(objects, uv).a; }
void fragment() {
	vec2 uv = UV;
	vec4 s = texture(splat, uv);
	float n = texture(noise, uv * 3.0).r;
	float n2 = texture(noise, uv * 11.0 + vec2(0.3, 0.7)).r;
	float n3 = texture(noise, uv * 37.0).r;
	// Terreno: capim seco com manchas, terra/estradas, calçamento, área contaminada com rachaduras verdes.
	vec3 col = mix(vec3(0.27, 0.27, 0.15), vec3(0.4, 0.37, 0.21), smoothstep(0.3, 0.75, n));
	col = mix(col, vec3(0.22, 0.2, 0.14), smoothstep(0.62, 0.78, n2) * 0.6);
	col = mix(col, vec3(0.44, 0.32, 0.2) * (0.9 + 0.2 * n3), smoothstep(0.35, 0.6, s.r));
	col = mix(col, vec3(0.3, 0.29, 0.28) * (0.85 + 0.3 * n3), smoothstep(0.35, 0.6, s.g));
	vec3 cor = mix(vec3(0.2, 0.08, 0.24), vec3(0.32, 0.14, 0.36), n2);
	cor = mix(cor, vec3(0.3, 0.95, 0.4), smoothstep(0.82, 0.9, n3) * 0.7);
	col = mix(col, cor, smoothstep(0.35, 0.6, s.b));
	// Sombra projetada dos objetos (luz de cima à esquerda) e os objetos por cima.
	vec2 px = vec2(1.0) / vec2(textureSize(objects, 0));
	float sh = obj_a(uv - px * vec2(1.6, 1.6));
	vec4 o = texture(objects, uv);
	col *= 1.0 - sh * 0.45 * (1.0 - o.a);
	vec3 canopy = mix(vec3(0.08, 0.11, 0.05), vec3(0.2, 0.21, 0.08), n3);
	col = mix(col, canopy, o.r * 0.95);
	col = mix(col, vec3(0.52, 0.5, 0.47), o.g * 0.85);
	// Construções: telhado escuro com borda clara (contorno = diferença para os vizinhos).
	float bmin = min(min(texture(objects, uv + vec2(px.x, 0)).b, texture(objects, uv - vec2(px.x, 0)).b),
		min(texture(objects, uv + vec2(0, px.y)).b, texture(objects, uv - vec2(0, px.y)).b));
	col = mix(col, vec3(0.13, 0.11, 0.1), o.b);
	col = mix(col, vec3(0.78, 0.68, 0.5), clamp(o.b - bmin, 0.0, 1.0) * 0.9);
	// Papel envelhecido, grade tática e vinheta.
	col *= 0.88 + 0.2 * n3;
	vec2 g = abs(fract(uv * grid) - 0.5);
	float line = 1.0 - smoothstep(0.0, 0.025, min(0.5 - g.x, 0.5 - g.y));
	col = mix(col, col * 0.72, line * 0.5);
	vec2 q = uv - 0.5;
	col *= 1.0 - dot(q, q) * 1.1;
	COLOR = vec4(col, 1.0);
}
"""
	return _sh
