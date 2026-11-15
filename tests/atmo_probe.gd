extends Node
## Captura rápida da atmosfera em vários horários (revisão visual).
##   xvfb-run godot res://tests/atmo_probe.tscn -- <pasta>
var out_dir := "user://atmo"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	Settings.tutorial_done = true
	GameManager.difficulty = "normal"
	ResourceManager.reset()
	TimeManager.setup("normal")
	var world := (load("res://scenes/world/main.tscn") as PackedScene).instantiate() as World
	add_child(world)
	while not GameManager.is_playing():
		await get_tree().process_frame
	TimeManager.running = false
	var hero := world.hero
	hero.health.invulnerable = true
	var spots := {"base": Vector3(2, 0, 6), "corrupt": Vector3(80, 0, -80), "forest": Vector3(-70, 0, -60)}
	var times := {"day": [TimeManager.Phase.DAY, 25.0], "dusk": [TimeManager.Phase.DUSK, 20.0], "night": [TimeManager.Phase.NIGHT, 10.0]}
	var only := OS.get_environment("ATMO_ONLY")
	for sname: String in spots:
		hero.global_position = spots[sname]
		world.camera_rig.global_position = hero.global_position
		for tname: String in times:
			if only != "" and not (sname + "_" + tname).contains(only):
				continue
			TimeManager.set_state(times[tname][0], 1, times[tname][1])
			for i in 50:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var cnt := 0
			for l in get_tree().root.find_children("*", "OmniLight3D", true, false):
				if (l as OmniLight3D).is_visible_in_tree() and (l as Node3D).global_position.distance_to(hero.global_position) < 30.0:
					cnt += 1
			var lan := get_tree().get_nodes_in_group(&"hero_lantern")
			print("%s_%s luzes=%d lanterna=%s" % [sname, tname, cnt, [(lan[0] as OmniLight3D).visible, (lan[0] as OmniLight3D).light_energy] if lan.size() > 0 else "nenhuma"])
			get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [sname, tname]))
	# Casos especiais na base: lua de sangue, relâmpago e vida baixa.
	hero.global_position = spots["base"]
	world.camera_rig.global_position = hero.global_position
	var dnv := DayNightVisuals.current
	TimeManager.set_state(TimeManager.Phase.NIGHT, 1, 10.0)
	dnv.storm = false
	dnv.blood_moon = true
	await _wait_frames(240)
	await _save("special_bloodmoon")
	dnv.blood_moon = false
	dnv.storm = true
	await _wait_frames(60)
	dnv.set(&"_flash", 1.0)
	await _wait_frames(2)
	await _save("special_lightning")
	dnv.storm = false
	hero.health.invulnerable = false
	hero.health.current = hero.health.max_health * 0.12
	await _wait_frames(40)
	await _save("special_lowhp")
	# Poças de sangue
	for i in 5:
		EffectsHub.spawn_blood_pool(hero.global_position + Vector3(randf_range(-4, 4), 0, randf_range(-3, 3)))
	TimeManager.set_state(TimeManager.Phase.DAY, 1, 25.0)
	hero.health.current = hero.health.max_health
	await _wait_frames(60)
	await _save("special_blood_day")
	get_tree().quit()

func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _save(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
