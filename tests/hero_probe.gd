extends Node3D
## Captura os heróis (parado, andando, correndo; frente/lado/costas) para revisar modelo e animação.
## xvfb-run ... res://tests/hero_probe.tscn -- <pasta> [skin]
var out := "user://"
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var skin: String = args[1] if args.size() > 1 else "knight"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.37, 0.4)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	var m := CharacterModel.new()
	add_child(m)
	m.build_hero(skin)
	if bool(HeroSkins.get_skin(skin).get("ranged", false)):
		m.attach_bow()
	else:
		m.attach_sword()
	for state: Array in [["parado", 0.0], ["andando", 0.55], ["correndo", 1.0]]:
		for k in 30:
			m.animate(1.0 / 30.0, state[1])
			await get_tree().process_frame
		for view: Array in [["frente", Vector3(0, 1.3, -3.6)], ["lado", Vector3(3.6, 1.3, 0)], ["costas", Vector3(0, 1.3, 3.6)]]:
			cam.global_position = view[1]
			cam.look_at(Vector3(0, 1.1, 0), Vector3.UP)
			for k in 4:
				m.animate(1.0 / 30.0, state[1])
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("%s_%s_%s.png" % [skin, state[0], view[0]]))
	# Golpe: 4 quadros ao longo da animação de ataque, vistos de lado e de frente.
	for view: Array in [["frente", Vector3(-1.5, 1.3, -3.3)], ["lado", Vector3(3.6, 1.3, 0)]]:
		cam.global_position = view[1]
		cam.look_at(Vector3(0, 1.1, 0), Vector3.UP)
		m.play_attack(0.6)
		for f in 4:
			for k in 4:
				m.animate(1.0 / 30.0, 0.0)
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("%s_golpe%d_%s.png" % [skin, f, view[0]]))
		for k in 20:
			m.animate(1.0 / 30.0, 0.0)
			await get_tree().process_frame
	get_tree().quit()
