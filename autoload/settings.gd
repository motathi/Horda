extends Node
## Configurações do jogador (autoload "Settings"), salvas em user://settings.cfg:
## qualidade gráfica, limite de FPS, contador de FPS, números de dano e tutorial.
## O volume fica no AudioManager (mesmo arquivo).

signal changed

const FILE := "user://settings.cfg"
const QUALITY_NAMES: Array[String] = ["Baixa", "Média", "Alta"]
const FPS_OPTIONS: Array[int] = [30, 60, 0]  # 0 = sem limite

## 0 baixa, 1 média, 2 alta.
var quality: int = 2
var fps_limit: int = 60
var show_fps: bool = false
var damage_numbers: bool = true
var tutorial_done: bool = false

var _fps_layer: CanvasLayer
var _fps_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	quality = 1 if Platform.low_end else 2
	fps_limit = 60
	var cfg := ConfigFile.new()
	if cfg.load(FILE) == OK:
		quality = int(cfg.get_value("video", "quality", quality))
		fps_limit = int(cfg.get_value("video", "fps_limit", fps_limit))
		show_fps = bool(cfg.get_value("video", "show_fps", show_fps))
		damage_numbers = bool(cfg.get_value("game", "damage_numbers", damage_numbers))
		tutorial_done = bool(cfg.get_value("game", "tutorial_done", tutorial_done))
	_build_fps_label()
	apply()

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(FILE)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "fps_limit", fps_limit)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("game", "damage_numbers", damage_numbers)
	cfg.set_value("game", "tutorial_done", tutorial_done)
	cfg.save(FILE)

func set_value(key: String, value: Variant) -> void:
	set(key, value)
	save()
	apply()
	changed.emit()

# --- Valores derivados da qualidade ------------------------------------------------

func shadows_enabled() -> bool:
	return quality >= 1

func grass_density() -> float:
	return [0.22, 0.38, 0.55][quality]

func decor_density() -> float:
	return [0.35, 0.6, 1.0][quality]

func render_scale() -> float:
	# Baixa renderiza o 3D em resolução menor (a interface continua nítida).
	if quality == 0:
		return 0.7
	if quality == 1 and Platform.touch:
		return 0.85
	return 1.0

## Aplica o que pode mudar na hora (o resto vale ao carregar o mundo).
func apply() -> void:
	Engine.max_fps = fps_limit
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X if not Platform.low_end else Viewport.MSAA_2X][quality]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = render_scale()
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096 if not Platform.low_end else 2048][quality], false)
	get_tree().call_group(&"quality_sun", &"apply_quality")
	if _fps_layer:
		_fps_layer.visible = show_fps

func _build_fps_label() -> void:
	_fps_layer = CanvasLayer.new()
	_fps_layer.layer = 90
	add_child(_fps_layer)
	_fps_label = Label.new()
	_fps_label.position = Vector2(8, 4)
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_layer.add_child(_fps_label)
	_fps_layer.visible = show_fps

func _process(_delta: float) -> void:
	if show_fps and Engine.get_process_frames() % 20 == 0:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
