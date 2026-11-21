extends Node
## Detecção de plataforma e ajustes para celular/navegador: interface de toque,
## escala da interface, qualidade gráfica reduzida e aviso de orientação.

## true quando a interface de toque deve ser usada (celular/tablet).
var touch: bool = false
## true em navegador/celular: reduz custos gráficos (grama, sombras, luzes).
var low_end: bool = false

var _portrait_layer: CanvasLayer
## Pausa que existia antes do aviso de "gire o celular" (para voltar exatamente ao estado anterior).
var _paused_before: bool = false
var _js_visibility_cb: JavaScriptObject

## Toques/joystick/ataque presos foram zerados (o app saiu e voltou, a aba ficou escondida...).
signal input_reset

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	touch = _detect_touch()
	low_end = OS.has_feature("web") or OS.has_feature("mobile") or "--lowend" in OS.get_cmdline_user_args()
	if touch:
		# Mesma base virtual do layout de referência (1280x720).
		get_window().content_scale_size = Vector2i(1280, 720)
	if low_end:
		# MSAA 2x é barato em GPUs de celular (renderização em blocos) e tira o serrilhado.
		get_viewport().msaa_3d = Viewport.MSAA_2X
		# Profundidade de 24 bits: 16 bits causava "acne" (sombras piscando).
		RenderingServer.directional_shadow_atlas_set_size(2048, false)
	_build_portrait_warning()
	# No navegador do celular, trocar de app/aba nem sempre entrega o "soltou" dos dedos: zera tudo ao
	# esconder e ao voltar (além dos avisos de foco do próprio Godot, em _notification).
	if OS.has_feature("web"):
		_js_visibility_cb = JavaScriptBridge.create_callback(func(_args: Array) -> void: reset_input())
		var doc: JavaScriptObject = JavaScriptBridge.get_interface("document")
		if doc:
			doc.addEventListener("visibilitychange", _js_visibility_cb)
		var win: JavaScriptObject = JavaScriptBridge.get_interface("window")
		if win:
			win.addEventListener("pagehide", _js_visibility_cb)
			win.addEventListener("blur", _js_visibility_cb)
	if OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search", true)).contains("dbg=1"):
		var t := Timer.new()
		t.wait_time = 0.5
		t.autostart = true
		t.timeout.connect(func() -> void:
			var vp := get_viewport()
			if GameManager.hero:
				var hp := GameManager.hero.global_position
				print("[dbg] hero=%.2f,%.2f" % [hp.x, hp.z])
			print("[dbg] fps=%d 3D objs=%d draws=%d prims=%d" % [Engine.get_frames_per_second(),
				vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
				vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
				vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)]))
		add_child(t)

func _detect_touch() -> bool:
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("window.location.search", true))
		if q.contains("touch=1"):
			return true
		if q.contains("touch=0"):
			return false
		return OS.has_feature("web_android") or OS.has_feature("web_ios") or DisplayServer.is_touchscreen_available()
	return OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_OUT,
			NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED]:
		reset_input()

## Solta tudo o que pode ter ficado "apertado": movimento, ataque, joystick, botões e toques da câmera.
func reset_input() -> void:
	for a: String in ["move_left", "move_right", "move_up", "move_down", "attack"]:
		if InputMap.has_action(a):
			Input.action_release(a)
	input_reset.emit()

func toggle_fullscreen() -> void:
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _build_portrait_warning() -> void:
	_portrait_layer = CanvasLayer.new()
	_portrait_layer.layer = 100
	add_child(_portrait_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.04, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_layer.add_child(bg)
	var l := Label.new()
	l.text = "Gire o celular\npara jogar na horizontal"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(l)
	_portrait_layer.visible = false

func _process(_delta: float) -> void:
	if not touch:
		return
	var s := get_window().size
	set_portrait(s.y > s.x)

## Celular na vertical: mostra o aviso e pausa; de volta na horizontal, volta ao estado de antes.
func set_portrait(portrait: bool) -> void:
	if portrait == _portrait_layer.visible:
		return
	_portrait_layer.visible = portrait
	if portrait:
		_paused_before = get_tree().paused
		get_tree().paused = true
	else:
		# Só continua pausado se o jogador tinha aberto o menu de pausa (no menu e no carregamento, despausa;
		# antes só despausava durante a partida e a tela inicial ficava congelada depois de trocar de app).
		get_tree().paused = _paused_before and _user_paused()
		reset_input()

func _user_paused() -> bool:
	var hud := get_tree().get_first_node_in_group("hud")
	return hud != null and hud.call(&"is_menu_paused")
