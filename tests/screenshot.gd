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
	menu.set("_main_panel", menu.get("_main_panel"))
	(menu.get("_main_panel") as Control).visible = false
	(menu.get("_new_panel") as Control).visible = true
	await _frames(6)
	await _shot("01b_novo_jogo")
	menu.queue_free()
	# Herói escolhido pela variável de ambiente HORDA_SKIN (padrão: caçador).
	GameManager.hero_skin = OS.get_environment("HORDA_SKIN") if OS.get_environment("HORDA_SKIN") != "" else HeroSkins.DEFAULT
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
	TimeManager.set_state(TimeManager.Phase.DAY, 1, 25.0)
	world.camera_rig.global_position = hero.global_position
	await _frames(60)
	await _shot("02_base_day")
	# Construções do jogador
	for id: StringName in [&"wood", &"stone", &"scrap"]:
		ResourceManager.storage.add(id, 400)
	var bm := world.build_manager
	bm.place(Building.load_def(&"archer_tower"), Vector3(-7, 0, 7), 0.0)
	bm.place(Building.load_def(&"stone_wall"), Vector3(5, 0, 20), 0.0)
	bm.place(Building.load_def(&"stone_wall"), Vector3(-0.5, 0, 21), 0.3)
	bm.place(Building.load_def(&"barricade"), Vector3(10, 0, 19), -0.5)
	bm.place(Building.load_def(&"spikes"), Vector3(2, 0, 17), 0.0)
	var t2 := bm.place(Building.load_def(&"archer_tower"), Vector3(8, 0, 9), 0.0)
	t2.upgrade()
	t2.upgrade()
	hero.global_position = Vector3(2, 0, 12)
	world.camera_rig.global_position = hero.global_position
	await _frames(40)
	world.hud.build_panel.visible = true
	await _frames(10)
	await _shot("09_build_menu")
	world.hud.build_panel.visible = false
	bm.start(Building.load_def(&"archer_tower"))
	bm._target = Vector3(-12, 0, 17)
	await _frames(20)
	await _shot("10_placement")
	bm.cancel()
	EventBus.object_selected.emit(t2)
	await _frames(10)
	await _shot("11_selected_tower")
	world.hud.selection.visible = false
	# Floresta com zumbis
	hero.global_position = Vector3(-20, 0, -45)
	world.camera_rig.global_position = hero.global_position
	for i in 4:
		var e := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
		world.enemies_root.add_child(e)
		e.global_position = hero.global_position + Vector3(-4 + i * 2.5, 0, -6 - (i % 2) * 2)
		e.configure(load("res://data/enemies/%s.tres" % ["zombie", "zombie_fast", "zombie_brute", "zombie"][i]))
	await _frames(40)
	while hero.level < 3:
		hero.add_xp(hero.xp_to_next())
	hero.cast_ability(0)
	await _frames(6)
	await _shot("03_forest_combat")
	hero.energy = hero.max_energy
	while hero.level < 5:
		hero.add_xp(hero.xp_to_next())
	hero.cast_ability(3)
	await get_tree().create_timer(0.62).timeout
	await _shot("12_nova")
	hero.add_attribute(&"strength")
	hero.add_attribute(&"strength")
	hero.add_attribute(&"vitality")
	world.hud.character.visible = true
	await _frames(4)
	await _shot("13_character")
	world.hud.character.visible = false
	var grng := RandomNumberGenerator.new()
	grng.seed = 3
	for gid: StringName in [&"sword", &"plate", &"amulet_arcane", &"daggers", &"ring_hunter", &"chain", &"hammer"]:
		hero.add_gear(Gear.make_item(Gear.get_def(gid), grng.randi_range(0, 4), 6, grng))
	hero.equip(hero.gear_bag[0])
	world.hud.character.show_gear_tab()
	world.hud.character._select(hero.gear_bag[1], false)
	await _frames(6)
	await _shot("20_equipamento")
	world.hud.character.visible = false
	world.hud.base_panel.visible = true
	world.hud.base_panel._tab = 1
	world.hud.base_panel._rebuild()
	await _frames(6)
	await _shot("21_forja")
	Tech.complete(Tech.get_def(&"walls1"))
	Tech.complete(Tech.get_def(&"tools"))
	Tech.complete(Tech.get_def(&"training"))
	Tech.active = &"arrows1"
	Tech.progress = 22.0
	world.hud.base_panel._tab = 2
	world.hud.base_panel._rebuild()
	await _frames(6)
	await _shot("23_pesquisa")
	world.hud.base_panel.visible = false
	world.hud.base_panel._tab = 0
	for i in 3:
		EffectsHub.drop_gear(hero.global_position + Vector3(3.5 + i * 1.6, 0, -2.0), Gear.make_item(Gear.defs()[i * 3], 2 + i % 3, 6, grng))
	await get_tree().create_timer(1.2).timeout
	await _shot("22_saque_equip")
	hero.health.invulnerable = true
	var offs := {"zombie_exploder": Vector3(-3.5, 0, 2.5), "zombie_spitter": Vector3(0, 0, 7.5), "zombie_leaper": Vector3(4.5, 0, 3.0),
		"skeleton_minion": Vector3(-5.5, 0, -1.0), "skeleton_warrior": Vector3(5.5, 0, -1.5), "skeleton_rogue": Vector3(-2.0, 0, 5.0), "skeleton_mage": Vector3(3.0, 0, 6.0)}
	for id: String in offs:
		var z := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
		z.def = load("res://data/enemies/%s.tres" % id) as EnemyDef
		world.enemies_root.add_child(z)
		z.global_position = hero.global_position + offs[id]
	await get_tree().create_timer(1.1).timeout
	await _shot("14_especiais")
	for z in Enemy.all.duplicate():
		z.queue_free()
	TimeManager.day = 10
	var bm2 := world.build_manager
	var base := GameManager.base_core.global_position
	var placed: Array[Building] = []
	placed.append(bm2.place(Building.load_def(&"ballista"), base + Vector3(-9, 0, 9), 0.0, false))
	placed.append(bm2.place(Building.load_def(&"cannon"), base + Vector3(-3, 0, 10), 0.0, false))
	placed.append(bm2.place(Building.load_def(&"tesla"), base + Vector3(3, 0, 10), 0.0, false))
	placed.append(bm2.place(Building.load_def(&"iron_wall"), base + Vector3(9, 0, 10), 0.0, false))
	hero.global_position = base + Vector3(0, 0, 13)
	await _frames(30)
	await _shot("15_defesas")
	world.hud.build_panel.visible = true
	await _frames(6)
	await _shot("16_menu_construir")
	world.hud.build_panel.visible = false
	hero.global_position = Vector3(82, 0, -82)
	await _frames(40)
	await _shot("17_cemiterio")
	hero.global_position = Vector3(-30, 0, -66)
	await _frames(40)
	await _shot("18_floresta")
	world.hud._toggle_pause()
	await _frames(4)
	await _shot("19_pausa_som")
	world.hud._toggle_pause()
	for b in placed:
		b.queue_free()
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
