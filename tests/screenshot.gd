extends Node
## Captura telas do jogo para revisão visual (precisa de display, ex.: xvfb-run).
##   xvfb-run godot res://tests/screenshot.tscn -- <pasta_saida>

var out_dir := "user://shots"
var world: World

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1600, 900)
	# Menu principal
	var menu := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _frames(20)
	await _shot("01_menu")
	menu.queue_free()
	GameManager.difficulty = "normal"
	ResourceManager.reset()
	TimeManager.setup("normal")
	world = (load("res://scenes/world/main.tscn") as PackedScene).instantiate() as World
	add_child(world)
	while not GameManager.is_playing():
		await get_tree().process_frame
	TimeManager.running = false
	var hero := world.hero
	hero.health.invulnerable = true
	await _frames(30)
	TimeManager.phase_time = 200.0
	world.camera_rig.global_position = hero.global_position
	await _frames(60)
	await _shot("02_base_day")
	# Floresta com zumbis
	hero.global_position = Vector3(-20, 0, -45)
	world.camera_rig.global_position = hero.global_position
	for i in 4:
		var e := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
		world.enemies_root.add_child(e)
		e.global_position = hero.global_position + Vector3(-4 + i * 2.5, 0, -6 - (i % 2) * 2)
		e.configure(load("res://data/enemies/%s.tres" % ["zombie", "zombie_fast", "zombie_brute", "zombie"][i]))
	await _frames(40)
	hero._start_attack()
	await _frames(8)
	await _shot("03_forest_combat")
	# Cidade
	hero.global_position = Vector3(70, 0, 8)
	world.camera_rig.global_position = hero.global_position
	await _frames(60)
	await _shot("04_city")
	# Área contaminada (entardecer)
	TimeManager.set_state(TimeManager.Phase.DUSK, 1, 60.0)
	hero.global_position = Vector3(80, 0, -80)
	world.camera_rig.global_position = hero.global_position
	await _frames(60)
	await _shot("05_contaminated_dusk")
	# Noite: horda atacando a base
	hero.global_position = Vector3(2, 0, -8)
	world.camera_rig.global_position = hero.global_position
	TimeManager.set_state(TimeManager.Phase.NIGHT, 1, 10.0)
	TimeManager.running = true
	for i in 14:
		var e2 := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
		world.enemies_root.add_child(e2)
		e2.global_position = Vector3(-8 + i * 1.3, 0, -26 - (i % 3) * 2)
		e2.configure(load("res://data/enemies/%s.tres" % ["zombie", "zombie", "zombie_fast", "zombie_brute"][i % 4]))
		e2.start_siege()
	await get_tree().create_timer(9.0).timeout
	hero._start_attack()
	await _frames(6)
	await _shot("06_night_horde")
	world.hud.inventory.visible = true
	ResourceManager.storage.add(&"wood", 42)
	ResourceManager.storage.add(&"stone", 18)
	ResourceManager.hero_inventory.add(&"meat", 3)
	await _frames(10)
	await _shot("07_inventory")
	world.hud.inventory.visible = false
	hero.global_position = Vector3(0, 0, 4)
	await get_tree().create_timer(0.5).timeout
	world.hud.base_panel.visible = true
	await _frames(10)
	await _shot("08_base_panel")
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)
