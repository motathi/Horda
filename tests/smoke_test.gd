extends Node
## Teste automatizado da Fase 1 (rodar em modo headless):
##   godot --headless res://tests/smoke_test.tscn
## Gera o mundo, simula combate/coleta/saque, avança até a noite, verifica a
## horda atacando a base e o amanhecer queimando os zumbis.

var world: World
var failures: int = 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS: ", msg)
	else:
		failures += 1
		print("  FAIL: ", msg)

func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout

func _ready() -> void:
	print("== Smoke test Fase 1 ==")
	GameManager.difficulty = "normal"
	ResourceManager.reset()
	TimeManager.setup("normal")
	world = (load("res://scenes/world/main.tscn") as PackedScene).instantiate() as World
	add_child(world)
	var t0 := Time.get_ticks_msec()
	while not GameManager.is_playing():
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > 60000:
			check(false, "mundo carregou em < 60s")
			_finish()
			return
	print("Mundo pronto em %d ms" % (Time.get_ticks_msec() - t0))
	await _test_world()
	await _test_audio()
	await _test_combat()
	await _test_abilities()
	await _test_attributes()
	await _test_special_enemies()
	await _test_harvest_and_loot()
	await _test_base_services()
	await _test_building()
	await _test_defenses()
	await _test_night()
	await _test_save()
	await _test_wave_flow()
	_finish()

func _test_world() -> void:
	print("[mundo]")
	var b := world.builder
	check(b.harvestables.size() > 200, "árvores/rochas geradas (%d)" % b.harvestables.size())
	check(b.lootables.size() > 30, "saqueáveis gerados (%d)" % b.lootables.size())
	check(b.structures.size() == 21, "base com núcleo + 20 segmentos (%d)" % b.structures.size())
	check(b.spawn_points.size() == 8, "8 pontos de surgimento")
	check(Enemy.all.size() > 20, "zumbis diurnos povoando o mapa (%d)" % Enemy.all.size())
	check(GameManager.base_core != null, "núcleo registrado")
	var nm := b.nav_region.navigation_mesh
	check(nm.get_polygon_count() > 100, "malha de navegação assada (%d polígonos)" % nm.get_polygon_count())
	check(BaseZone.hero_inside, "herói começa dentro da base")
	# Cenário de terceiros (CC0): vegetação em MultiMesh, cemitério e árvores variadas.
	var decor := 0
	for n in world.get_children():
		if n is DecorScatter:
			decor += (n as DecorScatter).count()
	check(decor > 600, "vegetação decorativa espalhada (%d peças)" % decor)
	var crypt := false
	var tp_trees := 0
	for n in b.nav_region.get_children():
		if n is StaticBody3D and n.get_child_count() > 0 and String(n.get_child(0).scene_file_path).ends_with("crypt.gltf"):
			crypt = true
		if n is Harvestable:
			for x: Node in n.find_children("*", "Node3D", true, false):
				if x.scene_file_path.contains("third_party"):
					tp_trees += 1
					break
	check(crypt, "cemitério com cripta na Área Contaminada")
	check(tp_trees > 40, "árvores variadas do pacote de natureza (%d)" % tp_trees)
	# Esqueletos (KayKit) com animações.
	for id in ["skeleton_minion", "skeleton_rogue", "skeleton_warrior", "skeleton_mage"]:
		var sk := _spawn_def(id, Vector3(30, 0, 30))
		await get_tree().process_frame
		check(sk.model._rigged and sk.model._anim_names.has("slash") and sk.model._anim_names.has("hurt"), "%s animado (%s)" % [id, ", ".join(sk.model._anim_names.keys())])
		sk.queue_free()
	var c := TimeManager.config
	check(TimeManager.day == 1 and absf(c.dawn_duration + c.day_duration + c.dusk_duration - 120.0) < 0.01, "começa na horda 1 com 2 minutos de preparação")
	check(world.objectives.objectives.size() == 3, "3 objetivos do dia gerados")
	# Objetivo "estar na base ao anoitecer" é verificado no início da noite.
	var ret: Dictionary = world.objectives.objectives[2]
	check(ret.kind == "return" and not ret.done, "objetivo de retorno pendente")

func _test_audio() -> void:
	print("[áudio]")
	var missing: Array[String] = []
	for id in ["swing", "hit", "zombie_hit", "zombie_death", "groan", "chop", "mine", "step_grass", "step_stone", "ab_whirl", "ab_dash", "ab_warcry", "ab_nova", "explosion", "cannon", "bolt", "arrow", "zap", "spit", "acid", "leap", "build", "upgrade", "levelup", "gong", "ui_click", "skeleton", "fuse"]:
		if not AudioManager.has_sound(StringName(id)):
			missing.append(id)
	check(missing.is_empty(), "todos os efeitos têm arquivos (faltando: %s)" % ", ".join(missing))
	check(AudioManager._streams(&"groan").size() >= 8, "gemidos com várias variações (%d)" % AudioManager._streams(&"groan").size())
	var buses_ok := true
	for b in AudioManager.BUSES:
		buses_ok = buses_ok and AudioServer.get_bus_index(b) >= 0
	check(buses_ok, "canais de volume Música/Efeitos/Ambiente/Interface")
	await get_tree().process_frame
	check(AudioManager._music_id.begins_with("prep_"), "música de preparação tocando (%s)" % AudioManager._music_id)
	EventBus.horde_started.emit(10, 5)
	await get_tree().process_frame
	check(AudioManager._music_id == "boss", "horda de chefe troca para a música do chefe (%s)" % AudioManager._music_id)
	EventBus.horde_ended.emit(10)
	AudioManager._boss_wave = false
	await get_tree().process_frame
	check(AudioManager._music_id.begins_with("prep_"), "fim da horda volta à preparação")
	AudioManager.set_volume("Music", 0.5)
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.5)) < 0.01, "volume da música ajustável")
	AudioManager.set_volume("Music", 0.7)

func _test_combat() -> void:
	print("[combate]")
	var hero := world.hero
	# Sem root motion: o quadril do modelo acompanha o personagem enquanto anda.
	var skel := hero.model.find_children("*", "Skeleton3D", true, false)
	if not skel.is_empty():
		var sk := skel[0] as Skeleton3D
		var hip := sk.find_bone("Hip")
		hero.global_position = Vector3(30, 0, 30)
		var max_off := 0.0
		var ap := hero.model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		hero.model.animate(0.05, 0.4)  # entra no estado "walk"
		for i in 40:
			ap.advance(0.05)
			var hp := (sk.global_transform * sk.get_bone_global_pose(hip)).origin
			var off := Vector2(hp.x - hero.global_position.x, hp.z - hero.global_position.z).length()
			max_off = maxf(max_off, off)
		check(max_off < 0.7, "modelo não se afasta do personagem ao andar (desvio máx. %.2f m)" % max_off)
	var e := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
	world.enemies_root.add_child(e)
	e.global_position = Vector3(40, 0, 40)
	e.configure(load("res://data/enemies/zombie.tres"))
	hero.global_position = Vector3(40, 0, 37.5)
	await wait(0.2)
	# Aponta o herói para o zumbi e ataca até morrer.
	var kills_before: int = GameManager.stats.kills
	var swings := 0
	while not e.is_dead() and swings < 12:
		hero.model.rotation.y = atan2(-(e.global_position.x - hero.global_position.x), -(e.global_position.z - hero.global_position.z))
		hero._attack_timer = 0.0
		hero._start_attack()
		await wait(0.5)
		swings += 1
	check(e.is_dead(), "herói mata zumbi em %d golpes" % swings)
	check(GameManager.stats.kills == kills_before + 1, "abate contabilizado")
	check(hero.xp > 0 or hero.level > 1, "herói ganhou experiência (%d XP, nível %d)" % [hero.xp, hero.level])
	var lvl := hero.level
	hero.add_xp(hero.xp_to_next())
	check(hero.level == lvl + 1 and hero.health.max_health > hero.max_health, "subiu de nível: vida máx. %d" % int(hero.health.max_health))
	# Zumbi persegue e ataca o herói
	var e2 := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
	world.enemies_root.add_child(e2)
	e2.global_position = Vector3(46, 0, 40)
	e2.configure(load("res://data/enemies/zombie_fast.tres"))
	hero.global_position = Vector3(40, 0, 40)
	var hp0 := hero.health.current
	await wait(4.0)
	check(e2.state == Enemy.State.ATTACK or e2.state == Enemy.State.CHASE, "zumbi persegue o herói (estado %d)" % e2.state)
	check(hero.health.current < hp0, "zumbi causa dano ao herói (%.0f -> %.0f)" % [hp0, hero.health.current])
	e2.take_damage(DamageInfo.make(9999, hero))
	hero.health.heal(9999)

func _spawn_zombie(pos: Vector3) -> Enemy:
	var e := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
	world.enemies_root.add_child(e)
	e.global_position = pos
	e.configure(load("res://data/enemies/zombie_brute.tres"))
	return e

func _test_abilities() -> void:
	print("[habilidades]")
	var hero := world.hero
	hero.global_position = Vector3(50, 0, 50)
	hero.health.invulnerable = true
	hero.energy = hero.max_energy
	check(hero.level < 5 and hero.ability_block_reason(3).contains("nível"), "Explosão Arcana bloqueada antes do nível 5 (herói nv. %d)" % hero.level)
	# Golpe Giratório
	var ring: Array[Enemy] = []
	for k in 3:
		var a := k * TAU / 3.0
		ring.append(_spawn_zombie(hero.global_position + Vector3(cos(a), 0, sin(a)) * 2.5))
	await wait(0.1)
	var hp0 := ring.map(func(e: Enemy) -> float: return e.health.current)
	var why := hero.cast_ability(0)
	await wait(0.1)
	var all_hit := true
	for k in 3:
		all_hit = all_hit and ring[k].health.current < hp0[k]
	check(why == "" and all_hit, "Golpe Giratório acerta todos em volta")
	check(hero.energy < hero.max_energy - 20.0 and hero.cooldown_left(0) > 0.0, "gasta energia e entra em recarga")
	check(hero.cast_ability(0).contains("recarga"), "não usa de novo durante a recarga")
	for e in ring:
		e.take_damage(DamageInfo.make(99999, null))
	# Sobe para o nível 5 (libera todas)
	while hero.level < 5:
		hero.add_xp(hero.xp_to_next())
	hero.energy = hero.max_energy
	# Investida
	var victim := _spawn_zombie(hero.global_position + hero.facing() * 4.0)
	await wait(0.1)
	var p0 := hero.global_position
	why = hero.cast_ability(1)
	await wait(0.6)
	var moved := hero.global_position.distance_to(p0)
	check(why == "" and moved > 5.0, "Investida avança %.1f m" % moved)
	check(victim.is_stunned() or victim.health.current < victim.health.max_health, "Investida fere/atordoa quem está no caminho")
	victim.take_damage(DamageInfo.make(99999, null))
	# Grito de Guerra
	hero.health.invulnerable = false
	hero.health.take_damage(DamageInfo.make(150, null))
	hero.health.invulnerable = true
	var armor0 := hero.health.armor
	var hp_before := hero.health.current
	hero.energy = hero.max_energy
	why = hero.cast_ability(2)
	await wait(1.5)
	check(why == "" and hero.health.armor > armor0 and hero.health.current > hp_before, "Grito de Guerra cura e dá armadura")
	# Explosão Arcana no grupo
	hero.energy = hero.max_energy
	var group: Array[Enemy] = []
	for k in 4:
		group.append(_spawn_zombie(hero.global_position + Vector3(7 + k * 0.8, 0, 1)))
	await wait(0.1)
	why = hero.cast_ability(3)
	await wait(0.9)
	var hit := group.filter(func(e: Enemy) -> bool: return e.is_dead() or (e.health.current < e.health.max_health and e.is_stunned())).size()
	check(why == "" and hit >= 3, "Explosão Arcana atinge o grupo (%d de 4)" % hit)
	for e in group:
		if not e.is_dead():
			e.take_damage(DamageInfo.make(99999, null))
	hero.energy = 0.0
	hero._cd = [0.0, 0.0, 0.0, 0.0]
	check(hero.cast_ability(0).contains("Energia"), "sem energia não usa habilidade")
	hero.energy = hero.max_energy
	hero.health.invulnerable = false
	hero.health.heal(9999)

func _test_attributes() -> void:
	print("[atributos]")
	var hero := world.hero
	var lvl0 := hero.level
	var pts0 := hero.attr_points
	hero.add_xp(hero.xp_to_next())
	check(hero.level == lvl0 + 1 and hero.attr_points == pts0 + hero.attr_cfg.points_per_level, "subir de nível dá %d pontos de atributo" % hero.attr_cfg.points_per_level)
	hero.attr_points = 5
	var dmg0 := hero.damage()
	var cap0 := ResourceManager.hero_inventory.capacity
	check(hero.add_attribute(&"strength") == "", "gasta ponto em Força")
	check(hero.damage() > dmg0 and ResourceManager.hero_inventory.capacity == cap0 + hero.attr_cfg.str_carry, "Força aumenta dano (%.1f -> %.1f) e carga" % [dmg0, hero.damage()])
	var hp0 := hero.health.max_health
	hero.add_attribute(&"vitality")
	check(is_equal_approx(hero.health.max_health, hp0 + hero.attr_cfg.vit_hp), "Vitalidade aumenta vida máxima")
	var as0 := hero.attack_speed()
	var ms0 := hero.current_move_speed()
	hero.add_attribute(&"agility")
	check(hero.attack_speed() > as0 and hero.current_move_speed() > ms0, "Agilidade aumenta velocidade de ataque e movimento")
	var en0 := hero.max_energy
	hero.add_attribute(&"intelligence")
	check(hero.max_energy > en0 and hero.ability_power() > 1.0 and hero.cooldown_mult() < 1.0, "Inteligência aumenta energia, poder e reduz recarga")
	# Engenharia afeta construções já existentes.
	var def := load("res://data/buildings/stone_wall.tres") as BuildingDef
	var b := Building.new()
	b.setup(def, 1)
	world.add_child(b)
	b.global_position = world.hero.global_position + Vector3(6, 0, 0)
	await wait(0.05)
	var bhp0 := b.health.max_health
	hero.add_attribute(&"engineering")
	check(b.health.max_health > bhp0, "Engenharia aumenta vida das construções existentes (%d -> %d)" % [int(bhp0), int(b.health.max_health)])
	check(hero.attr_points == 0 and hero.add_attribute(&"strength") != "", "sem pontos, não é possível gastar mais")
	# Redistribuir
	ResourceManager.storage.add(&"scrap", 50)
	var spent := hero.spent_points()
	check(hero.respec() == "" and hero.attr_points == spent and hero.attr(&"strength") == 0, "redistribuir devolve %d pontos" % spent)
	check(ResourceManager.hero_inventory.capacity == ResourceManager.HERO_CAPACITY, "carga volta ao normal após redistribuir")
	# Salvar/carregar atributos
	hero.add_attribute(&"vitality")
	var saved := hero.to_save()
	hero.attributes[&"vitality"] = 0
	hero.attr_points = 0
	hero.from_save(saved)
	check(hero.attr(&"vitality") == 1 and hero.attr_points == spent - 1, "atributos persistem no save")
	hero.respec()
	hero.attr_points = 0
	b.queue_free()

func _spawn_def(id: String, pos: Vector3) -> Enemy:
	var e := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
	e.def = load("res://data/enemies/%s.tres" % id) as EnemyDef
	world.enemies_root.add_child(e)
	e.global_position = pos
	return e

func _clear_enemies() -> void:
	for e in Enemy.all.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	await wait(0.05)

func _test_special_enemies() -> void:
	print("[inimigos especiais]")
	var hero := world.hero
	await _clear_enemies()
	hero.global_position = Vector3(60, 0, 60)
	var was_invulnerable := hero.health.invulnerable
	hero.health.invulnerable = false
	hero.health.max_health = 5000.0
	hero.health.current = 5000.0
	# Explosivo chega ao herói, incha e explode.
	var ex := _spawn_def("zombie_exploder", hero.global_position + Vector3(2.2, 0, 0))
	var hp0 := hero.health.current
	await wait(2.2)
	check(ex.is_dead() or not is_instance_valid(ex), "Explosivo explode sozinho ao alcançar o herói")
	check(hero.health.current < hp0, "explosão fere o herói (%d de dano)" % int(hp0 - hero.health.current))
	# Explosivo abatido fere zumbis ao redor e dá XP ao herói.
	await _clear_enemies()
	var ex2 := _spawn_def("zombie_exploder", hero.global_position + Vector3(8, 0, 0))
	var near := _spawn_def("zombie", hero.global_position + Vector3(9.2, 0, 0))
	near.health.invulnerable = false
	await wait(0.05)
	var nhp := near.health.current
	ex2.take_damage(DamageInfo.make(9999.0, hero))
	await wait(0.1)
	check(not is_instance_valid(near) or near.is_dead() or near.health.current < nhp, "Explosivo abatido fere zumbis próximos")
	# Cuspidor ataca de longe e deixa poça de ácido.
	await _clear_enemies()
	hero.health.current = 5000.0
	var sp := _spawn_def("zombie_spitter", hero.global_position + Vector3(8, 0, 0))
	var hp1 := hero.health.current
	var saw_puddle := false
	for i in 40:
		await wait(0.1)
		if not AcidPuddle.active.is_empty():
			saw_puddle = true
	check(saw_puddle, "Cuspidor cospe ácido e cria poça")
	check(is_instance_valid(sp) and _flat(sp.global_position, hero.global_position) > 3.5, "Cuspidor mantém distância do herói (%.1f m)" % _flat(sp.global_position, hero.global_position))
	check(hero.health.current < hp1, "ácido fere o herói")
	# Saltador salta sobre o herói.
	await _clear_enemies()
	var lp := _spawn_def("zombie_leaper", hero.global_position + Vector3(8, 0, 0))
	var leapt := false
	var max_y := 0.0
	for i in 20:
		await wait(0.1)
		max_y = maxf(max_y, lp.global_position.y)
		if lp._leap_t >= 0.0 or lp._leap_wind >= 0.0:
			leapt = true
	check(leapt and max_y > 1.0, "Saltador salta em arco (altura %.1f m)" % max_y)
	check(_flat(lp.global_position, hero.global_position) < 3.0, "Saltador aterrissa junto ao herói")
	check(lp.collision_mask & Layers.STRUCTURES != 0, "colisão com estruturas restaurada após o salto")
	# Durante o cerco, salta por cima de muros em direção ao núcleo.
	await _clear_enemies()
	var core := GameManager.base_core as Node3D
	var start := core.global_position + Vector3(0, 0, 22)
	var lp2 := _spawn_def("zombie_leaper", start)
	lp2.start_siege()
	var d0 := _flat(lp2.global_position, core.global_position)
	check(lp2._leap_over_wall(), "Saltador inicia salto sobre o muro")
	await wait(1.2)
	check(_flat(lp2.global_position, core.global_position) < d0 - 3.0, "salto sobre o muro aproxima do núcleo (%.1f -> %.1f m)" % [d0, _flat(lp2.global_position, core.global_position)])
	await _clear_enemies()
	hero.health.max_health = hero.total_max_health()
	hero.health.current = hero.health.max_health
	hero.health.invulnerable = was_invulnerable

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _test_harvest_and_loot() -> void:
	print("[coleta e saque]")
	var hero := world.hero
	var tree: Harvestable = null
	for h: Harvestable in world.builder.harvestables.values():
		if h.kind == Harvestable.Kind.TREE and h.global_position.length() > 30:
			tree = h
			break
	var wood0 := ResourceManager.hero_inventory.count(&"wood")
	hero.global_position = tree.global_position + Vector3(1.6, 0, 0)
	await wait(0.2)
	for i in tree.hits:
		hero.model.rotation.y = atan2(-(tree.global_position.x - hero.global_position.x), -(tree.global_position.z - hero.global_position.z))
		hero._start_attack()
		await wait(0.45)
	check(ResourceManager.hero_inventory.count(&"wood") > wood0, "árvore rende madeira (%d)" % ResourceManager.hero_inventory.count(&"wood"))
	check(tree.is_depleted(), "árvore esgota após %d golpes" % tree.hits)
	var car: Lootable = null
	for l: Lootable in world.builder.lootables.values():
		if l.display_label == "Carro Destruído":
			car = l
			break
	hero.global_position = car.global_position + Vector3(2.4, 0, 0)
	await wait(0.2)
	var scrap0 := ResourceManager.hero_inventory.count(&"scrap")
	hero._try_interact()
	await wait(car.duration + 0.5)
	check(car.looted, "carro saqueado com E")
	check(ResourceManager.hero_inventory.count(&"scrap") > scrap0, "saque rende sucata")
	# Itens no chão são atraídos e coletados (mochila esvaziada antes: os testes anteriores a enchem)
	print("    mochila: %d / %d" % [ResourceManager.hero_inventory.used_weight(), ResourceManager.hero_inventory.capacity])
	ResourceManager.deposit_all()
	var cloth0 := ResourceManager.hero_inventory.count(&"cloth")
	EffectsHub.drop_item(hero.global_position + Vector3(1, 0, 0), &"cloth", 3)
	await wait(1.5)
	check(ResourceManager.hero_inventory.count(&"cloth") == cloth0 + 3, "item no chão coletado automaticamente")
	# Volta à base: depósito automático
	hero.global_position = Vector3(0, 0, 5)
	await wait(0.5)
	check(ResourceManager.storage.count(&"wood") > 0 and ResourceManager.hero_inventory.count(&"wood") == 0, "recursos depositados no armazém ao entrar na base")

func _test_base_services() -> void:
	print("[serviços da base]")
	var hero := world.hero
	var wall := world.builder.structures["wall3"] as Structure
	wall.take_damage(DamageInfo.make(200, null))
	ResourceManager.storage.add(&"wood", 30)
	ResourceManager.storage.add(&"scrap", 20)
	ResourceManager.storage.add(&"stone", 20)
	ResourceManager.storage.add(&"herbs", 4)
	ResourceManager.storage.add(&"cloth", 4)
	var msg := world.services.repair_walls()
	check(wall.missing_health() == 0.0, "muro reparado: " + msg)
	var dmg0 := hero.damage()
	msg = world.services.sharpen(hero)
	check(hero.damage() > dmg0, "arma afiada: " + msg)
	var r: Recipe = world.services.recipes[0]
	msg = world.services.craft(r)
	check(ResourceManager.hero_inventory.count(&"bandage") >= 1, "curativo fabricado: " + msg)
	hero.health.take_damage(DamageInfo.make(80, null))
	var hp := hero.health.current
	hero.use_consumable(&"bandage")
	await wait(2.0)
	check(hero.health.current > hp, "curativo cura ao longo do tempo")

func _test_building() -> void:
	print("[construção]")
	var bm := world.build_manager
	for id: StringName in [&"wood", &"stone", &"scrap"]:
		ResourceManager.storage.add(id, 300)
	var barricade := Building.load_def(&"barricade")
	var tower := Building.load_def(&"archer_tower")
	var spikes := Building.load_def(&"spikes")
	check(bm.check(barricade, Vector3(70, 0, 0), 0.0) != "", "fora da área da base é inválido")
	check(bm.check(barricade, Vector3(0, 0, 0), 0.0) != "", "em cima da fortaleza é inválido")
	var wood0 := ResourceManager.available(&"wood")
	var reason := bm.check(barricade, Vector3(4, 0, 21), 0.0)
	check(reason == "", "posição livre fora da muralha é válida (%s)" % reason)
	var b := bm.place(barricade, Vector3(4, 0, 21), 0.0)
	await wait(0.2)
	check(b != null and ResourceManager.available(&"wood") == wood0 - int(barricade.cost[&"wood"]), "barricada construída e paga")
	check(bm.check(barricade, Vector3(4, 0, 21), 0.0) == "Espaço ocupado", "não sobrepõe construções")
	# Modo de construção com prévia
	bm.start(tower)
	check(bm.is_active() and world.hero.build_mode, "modo de construção ativo (herói não ataca)")
	bm.cancel()
	check(not bm.is_active() and not world.hero.build_mode, "modo de construção cancelado")
	# Torre mata zumbi ao alcance
	var t := bm.place(tower, Vector3(-8, 0, -4), 0.0)
	var e := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
	world.enemies_root.add_child(e)
	e.global_position = Vector3(-8, 0, -16)
	e.configure(load("res://data/enemies/zombie.tres"))
	var hp0 := e.health.current
	await wait(5.0)
	check(e.is_dead() or e.health.current < hp0, "torre de arqueiros atira no zumbi (vida %d -> %d)" % [int(hp0), int(e.health.current) if is_instance_valid(e) else 0])
	var dmg1 := t.tower_damage()
	var msg := t.upgrade()
	check(t.level == 2 and t.tower_damage() > dmg1, "torre melhorada: " + msg)
	# Armadilha fere quem passa por cima
	var sp := bm.place(spikes, Vector3(-16, 0, 20), 0.0)
	var e2 := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
	world.enemies_root.add_child(e2)
	e2.global_position = Vector3(-16, 0, 20)
	e2.configure(load("res://data/enemies/zombie.tres"))
	var hp2 := e2.health.current
	var trap_hp := sp.health.current
	await wait(2.0)
	check(e2.is_dead() or e2.health.current < hp2, "espinhos ferem o zumbi")
	check(sp.health.current < trap_hp, "armadilha desgasta ao ferir")
	if is_instance_valid(e2) and not e2.is_dead():
		e2.take_damage(DamageInfo.make(9999, null))
	# Zumbis atacam construções que bloqueiam o caminho
	var wall_hp := b.health.current
	b.take_damage(DamageInfo.make(50, null))
	check(b.health.current < wall_hp, "construção recebe dano")
	var save := world.collect_save()
	check((save.buildings as Array).size() == 3, "construções entram no salvamento (%d)" % (save.buildings as Array).size())
	var wood1 := ResourceManager.storage.count(&"wood")
	var back := b.demolish()
	await wait(0.1)
	check(not back.is_empty() and ResourceManager.storage.count(&"wood") > wood1, "demolir devolve recursos: " + ResourceManager.cost_to_string(back))
	# Limpa as construções para o teste da noite não depender delas (a torre mataria a horda).
	for n in get_tree().get_nodes_in_group("buildings"):
		n.queue_free()
	await wait(0.1)

func _test_defenses() -> void:
	print("[defesas]")
	var bm := world.build_manager
	var tesla := Building.load_def(&"tesla")
	var day0 := TimeManager.day
	check(Building.all_defs().size() == 8, "8 construções no menu")
	if day0 < tesla.unlock_wave:
		check(bm.check(tesla, Vector3(6, 0, 6), 0.0).contains("horda"), "Torre Elétrica bloqueada antes da horda %d" % tesla.unlock_wave)
	TimeManager.day = 10
	check(Building.load_def(&"iron_wall").is_unlocked() and tesla.is_unlocked(), "defesas liberadas na horda 10")
	await _clear_enemies()
	var origin := Vector3(60, 0, -40)
	# Balista atravessa a fila.
	var bal := bm.place(Building.load_def(&"ballista"), origin, 0.0, false)
	var line: Array[Enemy] = []
	for k in 3:
		var z := _spawn_def("zombie_brute", origin + Vector3(6 + k * 3, 0, 0))
		z.health.invulnerable = false
		line.append(z)
	await wait(0.05)
	for z in line:
		z.set_physics_process(false)
	var hp_before := line.map(func(z: Enemy) -> float: return z.health.current)
	bal._fire_bolt(bal.global_position + Vector3.UP * 2.5, line[0])
	await wait(0.3)
	var pierced := 0
	for i in line.size():
		if line[i].health.current < hp_before[i]:
			pierced += 1
	check(pierced == 3, "Balista atravessa a fila (%d de 3)" % pierced)
	bal.queue_free()
	await _clear_enemies()
	# Canhão explode em área e atordoa.
	var can := bm.place(Building.load_def(&"cannon"), origin, 0.0, false)
	var group: Array[Enemy] = []
	for k in 3:
		var z := _spawn_def("zombie_brute", origin + Vector3(10, 0, -1.2 + k * 1.2))
		group.append(z)
	await wait(0.05)
	for z in group:
		z.set_physics_process(false)
	var hp2 := group.map(func(z: Enemy) -> float: return z.health.current)
	can._fire_cannon(can.global_position + Vector3.UP * 3.0, group[1])
	await wait(1.6)
	var hit2 := 0
	for i in group.size():
		if group[i].health.current < hp2[i]:
			hit2 += 1
	check(hit2 == 3 and group[0].is_stunned(), "Canhão atinge o grupo inteiro (%d de 3) e atordoa" % hit2)
	can.queue_free()
	await _clear_enemies()
	# Torre elétrica: raio em cadeia.
	var tes := bm.place(tesla, origin, 0.0, false)
	var chain: Array[Enemy] = []
	for k in 4:
		var z := _spawn_def("zombie_brute", origin + Vector3(6 + k * 2.5, 0, 0))
		chain.append(z)
	await wait(0.05)
	for z in chain:
		z.set_physics_process(false)
	var hp3 := chain.map(func(z: Enemy) -> float: return z.health.current)
	tes._fire_chain(tes.global_position + Vector3.UP * 5.0, chain[0])
	var hit3 := 0
	for i in chain.size():
		if chain[i].health.current < hp3[i]:
			hit3 += 1
	check(hit3 == 4 and chain[3].is_stunned(), "raio salta por 4 zumbis e paralisa (%d)" % hit3)
	tes.queue_free()
	await _clear_enemies()
	# Muro de ferro é o mais resistente.
	var iw := bm.place(Building.load_def(&"iron_wall"), origin, 0.0, false)
	var sw := bm.place(Building.load_def(&"stone_wall"), origin + Vector3(0, 0, 6), 0.0, false)
	await wait(0.05)
	check(iw.health.max_health > sw.health.max_health * 2.0 and iw.health.armor > sw.health.armor, "Muro de Ferro: %d de vida (pedra: %d)" % [int(iw.health.max_health), int(sw.health.max_health)])
	iw.queue_free()
	sw.queue_free()
	TimeManager.day = day0
	await wait(0.05)

func _test_night() -> void:
	print("[noite e horda]")
	var hero := world.hero
	hero.health.invulnerable = true
	hero.global_position = Vector3(0, 0, 0)
	check(TimeManager.prep_seconds_left() > 0.0 and TimeManager.prep_seconds_left() <= 120.0, "contagem da preparação ativa (%.0fs restantes)" % TimeManager.prep_seconds_left())
	TimeManager.start_horde_now()
	await wait(0.5)
	check(TimeManager.is_night(), "'Chamar agora' inicia a horda")
	check(world.horde.is_active(), "horda iniciou na noite 1 (%d inimigos)" % world.horde.remaining())
	check(bool(world.objectives.objectives[2].done), "objetivo 'na base ao anoitecer' concluído")
	TimeManager.time_scale = 1.0
	Engine.time_scale = 4.0
	var hit_structures := false
	var structures_hp0 := 0.0
	for s: Structure in world.builder.structures.values():
		structures_hp0 += s.health.current
	var t := 0.0
	while t < 120.0:
		await wait(1.0)  # 1 s de jogo (o timer respeita Engine.time_scale)
		t += 1.0
		var hp := 0.0
		for s: Structure in world.builder.structures.values():
			hp += s.health.current
		if hp < structures_hp0:
			hit_structures = true
			break
	var horde_count := 0
	for e in Enemy.all:
		if e.is_horde:
			horde_count += 1
	check(horde_count > 0, "zumbis da horda em campo (%d)" % horde_count)
	check(hit_structures, "horda alcança e ataca a base (%.0fs de jogo)" % t)
	# Avança para o amanhecer: zumbis restantes queimam.
	Engine.time_scale = 1.0
	TimeManager.advance_phase()
	await wait(0.3)
	check(TimeManager.phase == TimeManager.Phase.DAWN and TimeManager.day == 2, "amanhecer do dia 2")
	check(not world.horde.is_active(), "horda encerrada")
	check(GameManager.stats.nights_survived == 1, "noite 1 contabilizada como sobrevivida")
	await wait(6.0)
	var alive_horde := 0
	for e in Enemy.all:
		if e.is_horde and not e.is_dead():
			alive_horde += 1
	check(alive_horde == 0, "zumbis da horda queimaram ao amanhecer (%d restantes)" % alive_horde)
	hero.health.invulnerable = false
	# Composição progressiva
	var cfg := world.horde.config
	var rng := RandomNumberGenerator.new()
	var n1 := cfg.compose(1, rng)
	var n6 := cfg.compose(6, rng)
	var has_brute := n6.any(func(d: EnemyDef) -> bool: return d.id == &"zombie_brute")
	var has_fast := n6.any(func(d: EnemyDef) -> bool: return d.id == &"zombie_fast")
	check(n6.size() > n1.size(), "horda 6 maior que horda 1 (%d > %d)" % [n6.size(), n1.size()])
	check(has_brute and has_fast, "horda 6 contém zumbis rápidos e resistentes")
	check(n1.all(func(d: EnemyDef) -> bool: return d.id == &"zombie"), "horda 1 só tem zumbis comuns")
	check(cfg.elite_count(5) == 1 and cfg.boss_count(10) == 1 and cfg.boss_count(9) == 0, "elite na horda 5, chefe na horda 10")
	var c100 := cfg.total_count(100)
	check(c100 > 300 and c100 < 450 and cfg.hp_multiplier(100) > 8.0 and cfg.hp_multiplier(100) < 12.0, "horda 100: %d zumbis, vida x%.1f" % [c100, cfg.hp_multiplier(100)])

func _test_wave_flow() -> void:
	print("[fluxo das hordas]")
	# Horda termina sozinha quando todos os zumbis morrem.
	TimeManager.start_horde_now()
	await wait(0.3)
	var w := TimeManager.wave()
	check(world.horde.is_active(), "horda %d começou" % w)
	world.hero.health.invulnerable = true
	var t := 0.0
	while world.horde.is_active() and t < 60.0:
		for e in Enemy.all.duplicate():
			if is_instance_valid(e) and e.is_horde and not e.is_dead():
				e.take_damage(DamageInfo.make(99999, null))
		await wait(0.5)
		t += 0.5
	check(not world.horde.is_active() and TimeManager.phase == TimeManager.Phase.DAWN and TimeManager.wave() == w + 1, "horda vencida inicia a próxima preparação (%.0fs)" % t)
	# Vitória ao vencer a horda 100.
	TimeManager.set_state(TimeManager.Phase.DUSK, TimeManager.TOTAL_WAVES, 0.0)
	TimeManager.start_horde_now()
	await wait(0.3)
	world.horde.end_night()
	await wait(0.2)
	check(GameManager.state == GameManager.State.VICTORY, "vitória ao vencer a horda %d" % TimeManager.TOTAL_WAVES)
	world.hero.health.invulnerable = false

func _test_save() -> void:
	print("[salvamento]")
	TimeManager.advance_phase()  # DAWN -> DAY
	var ok := SaveManager.save_game()
	check(ok, "jogo salvo de dia")
	check(SaveManager.has_save(), "arquivo de save existe")
	var meta := SaveManager.peek_meta()
	check(int(meta.get("day", 0)) == 2, "save registra o dia 2")
	SaveManager.delete_save()

func _finish() -> void:
	print("== %s (%d falhas) ==" % ["OK" if failures == 0 else "FALHOU", failures])
	get_tree().quit(1 if failures > 0 else 0)
