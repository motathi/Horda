extends Node
## Mede "piscar" de sombras: câmera e herói parados, o tempo do jogo correndo
## (sol se movendo). Salva quadros consecutivos para comparação.
##   xvfb-run godot --rendering-method gl_compatibility res://tests/flicker_test.tscn -- <pasta> [--touch --lowend]

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	GameManager.difficulty = "normal"
	ResourceManager.reset()
	TimeManager.setup("normal")
	var world := (load("res://scenes/world/main.tscn") as PackedScene).instantiate() as World
	add_child(world)
	while not GameManager.is_playing():
		await get_tree().process_frame
	world.hud.visible = false
	for e in Enemy.all:
		e.queue_free()
	var hero := world.hero
	hero.health.invulnerable = true
	hero.global_position = Vector3(-6, 0, 22)
	world.camera_rig.global_position = hero.global_position
	TimeManager.set_state(TimeManager.Phase.DAY, 1, 300.0)
	TimeManager.time_scale = 20.0  # sol andando rápido (como horas passando)
	for i in 30:
		await get_tree().process_frame
	for i in 24:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/f%02d.png" % [out, i])
	get_tree().quit()
