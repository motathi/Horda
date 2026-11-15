extends Node3D
## Renderiza um modelo GLB em dois ângulos para revisão.
##   xvfb-run godot res://tests/model_preview.tscn -- res://assets/models/x.glb /saida/prefixo

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0]
	var out := args[1]
	get_window().size = Vector2i(900, 700)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.36, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_file(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path, state)
	if err != OK:
		push_error("falha ao carregar %s" % path)
		get_tree().quit(1)
		return
	var model := gltf.generate_scene(state) as Node3D
	add_child(model)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 35
	var aabb := AABB()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		aabb = aabb.merge((mi as MeshInstance3D).get_aabb())
	var center := aabb.get_center()
	var radius := aabb.size.length() * 0.5
	for i in 2:
		model.rotation.y = deg_to_rad(-30 + i * 160)
		cam.position = center + Vector3(0, radius * 1.2, radius * 2.2)
		cam.look_at(center)
		for f in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [out, i])
	get_tree().quit()
