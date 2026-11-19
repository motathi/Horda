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
	if OS.get_environment("HORDA_SKIN") != "":
		GameManager.hero_skin = OS.get_environment("HORDA_SKIN")
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
	if OS.get_environment("ATMO_CLOSE") != "":
		world.camera_rig.set(&"distance", 8.0)
		world.camera_rig.set(&"_zoom_target", 8.0)
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
	if OS.get_environment("ATMO_FIND") != "":
		await _find_shots(world, hero, OS.get_environment("ATMO_FIND"))
		get_tree().quit()
		return
	if OS.get_environment("ATMO_PROP") != "":
		await _prop_shots(world, hero, OS.get_environment("ATMO_PROP"))
		get_tree().quit()
		return
	if OS.get_environment("ATMO_DEFENSE") != "":
		await _defense_shots(world, hero, OS.get_environment("ATMO_DEFENSE"))
		get_tree().quit()
		return
	if OS.get_environment("ATMO_HUNTER") != "":
		await _hunter_shots(world, hero)
		get_tree().quit()
		return
	if OS.get_environment("ATMO_HORROR") != "":
		await _horror_shots(world, hero)
		get_tree().quit()
		return
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

## Inimigos do terror: olhos, Espreitador, Gritador, Braseiro e névoa.
func _horror_shots(world: World, hero: Hero) -> void:
	var p := Vector3(30, 0, 40)
	hero.global_position = p
	world.camera_rig.global_position = p
	var dnv := DayNightVisuals.current
	dnv.storm = false
	dnv.fog = false
	TimeManager.day = 6
	TimeManager.set_state(TimeManager.Phase.NIGHT, 6, 5.0)
	TimeManager.running = false
	var mk := func(id: String, at: Vector3) -> Enemy:
		var e := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
		e.def = load("res://data/enemies/%s.tres" % id) as EnemyDef
		world.enemies_root.add_child(e)
		e.global_position = at
		e.set_physics_process(false)
		return e
	for i in 5:
		mk.call("zombie", p + Vector3(-4 + i * 2.0, 0, -5.5 + (i % 2) * 1.2))
	var sc: Enemy = mk.call("zombie_screamer", p + Vector3(-3.5, 0, -2))
	var st_lit: Enemy = mk.call("zombie_stalker", p + Vector3(7.5, 0, 3.5))
	var st_dark: Enemy = mk.call("zombie_stalker", p + Vector3(-7, 0, 3))
	for e: Enemy in [sc, st_lit, st_dark]:
		e.set_physics_process(true)
		e.speed_value = 0.0
	world.build_manager.place(Building.load_def(&"brazier"), p + Vector3(5, 0, 2), 0.0, false)
	await _wait_frames(90)
	var cam := get_viewport().get_camera_3d()
	for e: Enemy in [sc, st_lit, st_dark]:
		print(e.def.id, " tela=", cam.unproject_position(e.global_position + Vector3.UP), " hidden=", e.hidden, " olhos=", e.model.find_children("Eyes", "", true, false).size())
		var ey := e.model.find_children("Eyes", "", true, false)
		if ey.size() > 0:
			var en := ey[0] as Node3D
			print("   olhos em ", en.global_position - e.global_position, " vis=", en.is_visible_in_tree(), " parent=", en.get_parent().get_class(), " bone=", (en.get_parent() as BoneAttachment3D).bone_name, " int=", CharacterModel.eye_intensity)
	for b in get_tree().get_nodes_in_group("buildings"):
		print("construção ", b.name, " tela=", cam.unproject_position((b as Node3D).global_position))
	print("heroi tela=", cam.unproject_position(hero.global_position))
	await _save("horror_night")
	dnv.fog = true
	await _wait_frames(240)
	await _save("horror_fog")
	dnv.fog = false
	TimeManager.set_state(TimeManager.Phase.DAY, 6, 20.0)
	await _wait_frames(60)
	await _save("horror_day")

## Caçador: pose de tiro com arco, armadilha, chuva de flechas e águia.
func _hunter_shots(world: World, hero: Hero) -> void:
	var p := Vector3(-30, 0, 30)
	hero.global_position = p
	world.camera_rig.global_position = p
	world.camera_rig.set(&"distance", 11.0)
	world.camera_rig.set(&"_zoom_target", 11.0)
	TimeManager.set_state(TimeManager.Phase.DAY, 3, 20.0)
	TimeManager.running = false
	hero.level = 6
	hero.health.invulnerable = true
	var mk := func(at: Vector3) -> Enemy:
		var e := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
		e.def = load("res://data/enemies/zombie_brute.tres") as EnemyDef
		world.enemies_root.add_child(e)
		e.global_position = at
		e.speed_value = 0.4
		return e
	for h in get_tree().get_nodes_in_group("harvestable"):
		if (h as Node3D).global_position.distance_to(p) < 8.0:
			h.queue_free()
	for i in 4:
		mk.call(p + Vector3(7.5, 0, -3 + i * 2))
	await _wait_frames(30)
	hero._aim_point = p + Vector3(8, 0, 0)
	hero._face(p + Vector3(8, 0, 0), 1.0, 100.0)
	hero._attack_timer = 0.0
	hero._start_attack()
	await _wait_frames(3)
	await _save("hunter_draw")
	await _wait_frames(30)
	hero.energy = 100.0
	hero.cast_ability(2)
	hero._aim_point = p + Vector3(-1, 0, 4)
	hero.cast_ability(1)
	hero.energy = 100.0
	hero.cast_ability(3)
	await _wait_frames(5)
	await _save("hunter_rain")
	await _wait_frames(14)
	await _save("hunter_eagle")

## Enquadra um objeto já colocado no mapa (o primeiro nó cujo nome começa com `prefix`
## e que tenha um vizinho do mesmo tipo por perto, se houver), de dia e à noite.
func _find_shots(world: World, hero: Hero, prefix: String) -> void:
	var found: Array[Node3D] = []
	for n in world.find_children(prefix + "*", "Node3D", true, false):
		found.append(n as Node3D)
	if found.is_empty():
		print("nenhum ", prefix)
		return
	var idx := int(OS.get_environment("ATMO_INDEX")) if OS.get_environment("ATMO_INDEX") != "" else 0
	var t := found[idx % found.size()]
	print("%d %s; enquadrando %s" % [found.size(), prefix, t.global_position])
	world.hud.visible = false
	world.camera_rig.set(&"distance", 12.0)
	world.camera_rig.set(&"_zoom_target", 12.0)
	world.camera_rig.global_position = t.global_position
	await _wait_frames(5)
	var cb := get_viewport().get_camera_3d().global_transform.basis
	hero.global_position = t.global_position + Vector3(cb.z.x, 0, cb.z.z).normalized() * 3.5
	TimeManager.running = false
	TimeManager.set_state(TimeManager.Phase.DAY, 3, 20.0)
	await _wait_frames(40)
	await _save("%s_dia" % prefix)
	TimeManager.set_state(TimeManager.Phase.NIGHT, 3, 10.0)
	await _wait_frames(60)
	await _save("%s_noite" % prefix)

## Objetos de cenário do Blender (3 exemplos lado a lado), de dia e ao entardecer.
func _prop_shots(world: World, hero: Hero, kind: String) -> void:
	var p := Vector3(-26, 0, 22)
	for h in get_tree().get_nodes_in_group("harvestable"):
		if (h as Node3D).global_position.distance_to(p) < 14.0:
			h.queue_free()
	world.camera_rig.global_position = p
	world.camera_rig.set(&"distance", 13.0)
	world.camera_rig.set(&"_zoom_target", 13.0)
	world.hud.visible = false
	await _wait_frames(5)
	var cb := get_viewport().get_camera_3d().global_transform.basis
	var right := Vector3(cb.x.x, 0, cb.x.z).normalized()
	var toward := Vector3(cb.z.x, 0, cb.z.z).normalized()
	hero.global_position = p + toward * 3.8
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 3:
		var n: Node3D = WorldProps.make(kind, rng, i)
		world.add_child(n)
		if n is Lootable and kind == "car" and i == 1:
			n.queue_free()
			n = Lootable.new()
			var v := (load("res://assets/models/blender/car_wreck_a.glb") as PackedScene).instantiate() as Node3D
			n.add_child(v)
			world.add_child(n)
		n.global_position = p + right * ((i - 1) * 4.6)
		n.rotation.y = [0.4, -0.9, 2.2][i]
	TimeManager.running = false
	TimeManager.set_state(TimeManager.Phase.DAY, 3, 20.0)
	await _wait_frames(40)
	await _save("%s_dia" % kind)
	TimeManager.set_state(TimeManager.Phase.DUSK, 3, 30.0)
	await _wait_frames(40)
	await _save("%s_entardecer" % kind)

## Uma defesa nos 3 níveis lado a lado (revisão dos modelos do Blender).
func _defense_shots(world: World, hero: Hero, id: String) -> void:
	var p := Vector3(-26, 0, 22)
	for h in get_tree().get_nodes_in_group("harvestable"):
		if (h as Node3D).global_position.distance_to(p) < 12.0:
			h.queue_free()
	world.camera_rig.global_position = p
	var zoom := 12.0 if Building.load_def(StringName(id)).height < 4.0 else 15.0
	world.camera_rig.set(&"distance", zoom)
	world.camera_rig.set(&"_zoom_target", zoom)
	await _wait_frames(5)
	# Alinha com a tela: comprimento na direita da câmera, frente virada para ela.
	var cb := get_viewport().get_camera_3d().global_transform.basis
	var right := Vector3(cb.x.x, 0, cb.x.z).normalized()
	var toward := Vector3(cb.z.x, 0, cb.z.z).normalized()
	hero.global_position = p - toward * 1.2
	world.hud.visible = false
	var yaw := atan2(-right.z, right.x)
	var d := Building.load_def(StringName(id))
	var gap := d.footprint.x + 1.6
	for lv in [1, 2, 3]:
		world.build_manager.place(d, p + right * ((lv - 2) * gap), yaw, false, lv)
	if d.category == BuildingDef.Category.TOWER:
		# Zumbi parado ao lado para as armas giratórias mirarem.
		var z := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
		z.def = load("res://data/enemies/zombie.tres") as EnemyDef
		world.enemies_root.add_child(z)
		z.global_position = p + right * (gap * 2.2) - toward * 3.0
		z.set_physics_process(false)
		z.health.invulnerable = true
	TimeManager.running = false
	TimeManager.set_state(TimeManager.Phase.DAY, 3, 20.0)
	await _wait_frames(40)
	await _save("%s_dia" % id)
	TimeManager.set_state(TimeManager.Phase.DUSK, 3, 30.0)
	await _wait_frames(40)
	await _save("%s_entardecer" % id)

func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _save(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
