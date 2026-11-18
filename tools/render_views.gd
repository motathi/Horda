extends Node3D
## Renderiza um GLB de frente, esquerda, costas e direita (fundo neutro) — entrada
## para a geração por múltiplas vistas do Tripo.
##   xvfb-run godot res://tools/render_views.tscn -- modelo.glb /saida/prefixo
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	get_window().size = Vector2i(1024, 1024)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(1, 1, 1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 25, 0)
	key.light_energy = 0.7
	add_child(key)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(args[0], st) != OK:
		get_tree().quit(1)
		return
	var model := doc.generate_scene(st) as Node3D
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.add_child(model)
	var aabb := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		aabb = mi.get_aabb() if first else aabb.merge(mi.get_aabb())
		first = false
	model.position = -aabb.get_center()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = aabb.size.y * 1.12
	cam.position = Vector3(0, 0, 10)
	add_child(cam)
	cam.current = true
	# O modelo olha para +Z: frente, esquerda (do personagem), costas, direita.
	var names := ["front", "left", "back", "right"]
	var yaws := [0.0, 90.0, 180.0, -90.0]
	for i in 4:
		pivot.rotation_degrees.y = yaws[i]
		for f in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg("%s_%s.jpg" % [args[1], names[i]], 0.95)
	get_tree().quit()
