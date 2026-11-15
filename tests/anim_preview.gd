extends Node3D
## Renderiza poses de animação de um personagem rigado (revisão visual).
##   xvfb-run godot res://tests/anim_preview.tscn -- res://assets/models/rigged/hero.glb /saida/prefixo

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	get_window().size = Vector2i(1500, 420)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.35, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var scene := load(args[0]) as PackedScene
	var anims: Array[String] = ["idle", "walk", "run", "slash", "hurt"]
	var times: Array[float] = [0.3, 0.25, 0.2, 0.45, 0.3]
	for i in anims.size():
		var inst := scene.instantiate() as Node3D
		add_child(inst)
		inst.position = Vector3((i - 2) * 1.6, 0, 0)
		inst.rotation_degrees.y = 25
		var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var name: String = anims[i]
		for n in ap.get_animation_list():
			if n.to_lower().ends_with(name):
				name = n
		ap.play(name)
		ap.seek(ap.get_animation(name).length * times[i], true)
		ap.pause()
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.4, 6.0)
	cam.look_at(Vector3(0, 0.9, 0))
	cam.fov = 40
	for f in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[1] + ".png")
	get_tree().quit()
