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
	if OS.get_environment("ATMO_COMBAT") != "":
		# Zumbis preparando o golpe (aviso no chão) e os botões de esquiva/poção.
		TimeManager.set_state(TimeManager.Phase.DAY, 1, 25.0)
		hero.global_position = Vector3(36, 0, 30)
		world.camera_rig.set(&"distance", 11.0)
		world.camera_rig.set(&"_zoom_target", 11.0)
		ResourceManager.hero_inventory.add(&"potion", 3)
		for k in 3:
			var z := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
			world.enemies_root.add_child(z)
			var a := k * 2.1
			z.global_position = hero.global_position + Vector3(sin(a), 0, cos(a)) * 1.7
			z.configure(load("res://data/enemies/zombie_brute.tres" if k == 0 else "res://data/enemies/zombie.tres"))
		var best := 0.0
		for i in 120:
			await get_tree().process_frame
			for z in Enemy.all:
				if is_instance_valid(z) and z._melee_total > 0.0 and z._windup >= 0.0:
					best = maxf(best, 1.0 - z._windup / z._melee_total)
			if best > 0.6:
				break
		await _save("combate_aviso")
		get_tree().quit()
		return
	if OS.get_environment("ATMO_MAP") != "":
		# Minimapa no HUD e o mapa grande aberto.
		TimeManager.set_state(TimeManager.Phase.DAY, 1, 25.0)
		hero.global_position = Vector3(30, 0, 20)
		await _wait_frames(40)
		await _save("mapa_hud")
		world.hud.call("_toggle_map")
		await _wait_frames(30)
		await _save("mapa_grande")
		get_tree().quit()
		return
	if OS.get_environment("ATMO_DECOR") != "":
		await _decor_shots(world, hero, OS.get_environment("ATMO_DECOR"))
		get_tree().quit()
		return
	if OS.get_environment("ATMO_FIND") != "":
		await _find_shots(world, hero, OS.get_environment("ATMO_FIND"))
		get_tree().quit()
		return
	if OS.get_environment("ATMO_SKILLS") != "":
		await _skill_shots(world, hero)
		get_tree().quit()
		return
	if OS.get_environment("ATMO_BUILD") != "":
		# Vista de construção (city builder) com uma torre em prévia.
		TimeManager.set_state(TimeManager.Phase.DAY, 1, 25.0)
		hero.global_position = Vector3(6, 0, 10)
		await _wait_frames(30)
		await _save("build_antes")
		world.build_manager.start(Building.load_def(&"archer_tower"))
		await _wait_frames(90)
		await _save("build_vista")
		world.build_manager.cancel()
		await _wait_frames(90)
		await _save("build_depois")
		get_tree().quit()
		return
	if OS.get_environment("ATMO_LAIR") != "":
		await _lair_shots(world, hero)
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
	var zoom := float(OS.get_environment("ATMO_ZOOM")) if OS.get_environment("ATMO_ZOOM") != "" else 12.0
	world.camera_rig.set(&"distance", zoom)
	world.camera_rig.set(&"_zoom_target", zoom)
	world.camera_rig.global_position = t.global_position
	await _wait_frames(5)
	var cb := get_viewport().get_camera_3d().global_transform.basis
	# A câmera segue o herói: ele fica um pouco atrás do objeto, que fica no centro da tela.
	hero.global_position = t.global_position + Vector3(cb.z.x, 0, cb.z.z).normalized() * (3.5 if zoom < 14.0 else -0.5)
	TimeManager.running = false
	TimeManager.set_state(TimeManager.Phase.DAY, 3, 20.0)
	await _wait_frames(40)
	await _save("%s_dia" % prefix)
	TimeManager.set_state(TimeManager.Phase.NIGHT, 3, 10.0)
	await _wait_frames(60)
	await _save("%s_noite" % prefix)

## Vegetação rasteira (DecorScatter): enquadra a cópia ATMO_INDEX do modelo pedido, de dia e à noite.
## Escolhe a cópia com mais vizinhos (de qualquer tipo) por perto, para mostrar o chão bem coberto.
func _decor_shots(world: World, hero: Hero, model: String) -> void:
	var pts: Array[Vector3] = []
	var all_pts: Array[Vector3] = []
	for mmi in world.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (mmi as MultiMeshInstance3D).multimesh
		if mmi.get_parent() is DecorScatter or mmi.get_parent() is Foliage:
			var nm := String(mmi.get_meta(&"kind", mmi.name))
			if nm.contains("MultiMeshInstance3D"):
				continue  # capim e flores
			for i in mm.instance_count:
				var p := (mmi as Node3D).global_transform * mm.get_instance_transform(i).origin
				all_pts.append(p)
				if nm.begins_with(model):
					pts.append(p)
	if pts.is_empty():
		print("nenhum ", model)
		return
	var scored: Array = []
	for p in pts:
		var n := 0
		for q in all_pts:
			if p.distance_squared_to(q) < 36.0:
				n += 1
		scored.append([n, p])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var idx := int(OS.get_environment("ATMO_INDEX")) if OS.get_environment("ATMO_INDEX") != "" else 0
	var t: Vector3 = scored[idx % scored.size()][1]
	print("%d %s; enquadrando %s (%d vizinhos)" % [pts.size(), model, t, scored[idx % scored.size()][0]])
	world.hud.visible = false
	var zoom := float(OS.get_environment("ATMO_ZOOM")) if OS.get_environment("ATMO_ZOOM") != "" else 9.0
	world.camera_rig.set(&"distance", zoom)
	world.camera_rig.set(&"_zoom_target", zoom)
	world.camera_rig.global_position = t
	await _wait_frames(5)
	var cb := get_viewport().get_camera_3d().global_transform.basis
	hero.global_position = t + Vector3(cb.z.x, 0, cb.z.z).normalized() * 2.5
	TimeManager.running = false
	TimeManager.set_state(TimeManager.Phase.DAY, 3, 20.0)
	await _wait_frames(40)
	await _save("%s_dia" % model)
	TimeManager.set_state(TimeManager.Phase.NIGHT, 3, 10.0)
	await _wait_frames(60)
	await _save("%s_noite" % model)

## Objetos de cenário do Blender (3 exemplos lado a lado), de dia e ao entardecer.
## Cada habilidade da classe (HORDA_SKIN) em três momentos depois de lançar, numa clareira com zumbis parados.
func _skill_shots(world: World, hero: Hero) -> void:
	world.hud.visible = OS.get_environment("ATMO_HUD") != ""
	hero.health.invulnerable = true
	TimeManager.running = false
	TimeManager.set_state(TimeManager.Phase.DUSK, 3, 24.0)
	while hero.level < 5:
		hero.add_xp(hero.xp_to_next())
	var cp := Vector3(-26, 0, 22)
	for h in get_tree().get_nodes_in_group("harvestable"):
		if (h as Node3D).global_position.distance_to(cp) < 16.0:
			h.queue_free()
	for e in Enemy.all.duplicate():
		if is_instance_valid(e) and e.global_position.distance_to(cp) < 40.0:
			e.queue_free()
	world.spawner.set_process(false)
	world.camera_rig.set(&"distance", 13.0)
	world.camera_rig.set(&"_zoom_target", 13.0)
	hero.global_position = cp
	world.camera_rig.global_position = cp
	var only := OS.get_environment("ATMO_SKILLS")
	var skin := GameManager.hero_skin
	for i in 4:
		if only != "1" and not only.contains(str(i)):
			continue
		# Zumbis em volta (parados) para as habilidades terem alvo.
		var ring: Array[Enemy] = []
		for k in 7:
			var a := k * TAU / 7.0
			var z := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
			world.enemies_root.add_child(z)
			z.global_position = cp + Vector3(cos(a), 0, sin(a)) * (3.0 if k % 2 == 0 else 6.5) + Vector3(0, 0, -3.0)
			z.configure(load("res://data/enemies/zombie.tres"))
			z.health.setup(99999.0)
			ring.append(z)
		await _wait_frames(10)
		for z in ring:
			z.stun(60.0)
		hero.global_position = cp
		hero.model.rotation.y = 0.0
		hero._aim_point = cp + Vector3(0, 0, -6)
		hero.energy = hero.max_energy
		hero._cd = [0.0, 0.0, 0.0, 0.0]
		var why := hero.cast_ability(i)
		print("habilidade %d: %s" % [i, why if why != "" else "ok"])
		var t := 0.0
		var shots: Array = [0.12, 0.32, 0.7] if not (skin == "hunter" and i == 3) else [0.8, 2.0, 4.0]
		if skin == "hunter" and i == 2:
			shots = [0.3, 1.2, 2.5]
		for k in shots.size():
			await get_tree().create_timer(float(shots[k]) - t).timeout
			t = float(shots[k])
			await RenderingServer.frame_post_draw
			await _save("skill_%s_%d_%d" % [skin, i, k])
		await get_tree().create_timer(1.0).timeout
		for z in ring:
			if is_instance_valid(z):
				z.queue_free()
		await _wait_frames(5)

## Covil de guardião (chefe + Baú do Guardião), um baú comum, e o baú aberto depois do chefe cair.
func _lair_shots(world: World, hero: Hero) -> void:
	world.hud.visible = false
	hero.health.invulnerable = true
	TimeManager.running = false
	var idx := int(OS.get_environment("ATMO_INDEX")) if OS.get_environment("ATMO_INDEX") != "" else 0
	var g: Dictionary = world.builder.guardians[idx % world.builder.guardians.size()]
	var boss: Enemy = null
	for e in Enemy.all:
		if e.is_guardian and e.global_position.distance_to(g.pos) < 12.0:
			boss = e
	print("guardiões: ", world.builder.guardians.size(), " baús: ", world.builder.lootables.values().filter(func(l: Lootable) -> bool: return l.lid != null).size())
	for zoom: float in [11.0]:
		world.camera_rig.set(&"distance", zoom)
		world.camera_rig.set(&"_zoom_target", zoom)
	var chest: Lootable = null
	for l: Lootable in world.builder.lootables.values():
		if l.guard_radius > 0.0 and l.global_position.distance_to(g.pos) < 8.0:
			chest = l
	world.camera_rig.global_position = g.pos
	hero.global_position = g.pos + Vector3(0, 0, 7)
	TimeManager.set_state(TimeManager.Phase.DAY, 3, 20.0)
	await _wait_frames(60)
	print("baú trancado: ", chest.is_guarded() if chest else "sem baú", " chefe: ", boss.display_name() if boss else "nenhum")
	await _save("lair_%d_dia" % idx)
	if boss:
		boss.take_damage(DamageInfo.make(999999, hero))
	await _wait_frames(40)
	if chest:
		print("depois do chefe: trancado=", chest.is_guarded())
		chest.interact(hero)
	world.camera_rig.set(&"distance", 6.0)
	world.camera_rig.set(&"_zoom_target", 6.0)
	world.camera_rig.global_position = chest.global_position if chest else g.pos
	await _wait_frames(5)
	var cb := get_viewport().get_camera_3d().global_transform.basis
	hero.global_position = world.camera_rig.global_position + Vector3(cb.z.x, 0, cb.z.z).normalized() * 2.2
	await _wait_frames(60)
	await _save("lair_%d_aberto" % idx)
	# Os três baús lado a lado numa clareira; depois o do meio aberto.
	var cp := Vector3(-26, 0, 22)
	for h in get_tree().get_nodes_in_group("harvestable"):
		if (h as Node3D).global_position.distance_to(cp) < 14.0:
			h.queue_free()
	world.camera_rig.set(&"distance", 9.0)
	world.camera_rig.set(&"_zoom_target", 9.0)
	world.camera_rig.global_position = cp
	await _wait_frames(5)
	var cb3 := get_viewport().get_camera_3d().global_transform.basis
	var right := Vector3(cb3.x.x, 0, cb3.x.z).normalized()
	hero.global_position = cp + Vector3(cb3.z.x, 0, cb3.z.z).normalized() * 3.0
	var rng := RandomNumberGenerator.new()
	var made: Array[Lootable] = []
	for k in 3:
		var l := PropFactory.make_lootable(["chest_supplies", "chest_gear", "chest_guardian"][k], rng)
		world.add_child(l)
		l.global_position = cp + right * ((k - 1) * 2.4)
		l.rotation.y = atan2(cb3.z.x, cb3.z.z) + [0.5, 0.0, -0.5][k]
		made.append(l)
	TimeManager.set_state(TimeManager.Phase.DAY, 3, 20.0)
	await _wait_frames(40)
	await _save("baus_dia")
	made[1].interact(hero)
	TimeManager.set_state(TimeManager.Phase.DUSK, 3, 21.0)
	await _wait_frames(60)
	await _save("baus_entardecer_aberto")

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
