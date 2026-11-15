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
	await _test_combat()
	await _test_abilities()
	await _test_harvest_and_loot()
	await _test_base_services()
	await _test_building()
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
	var c := TimeManager.config
	check(TimeManager.day == 1 and absf(c.dawn_duration + c.day_duration + c.dusk_duration - 120.0) < 0.01, "começa na horda 1 com 2 minutos de preparação")
	check(world.objectives.objectives.size() == 3, "3 objetivos do dia gerados")
	# Objetivo "estar na base ao anoitecer" é verificado no início da noite.
	var ret: Dictionary = world.objectives.objectives[2]
	check(ret.kind == "return" and not ret.done, "objetivo de retorno pendente")

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
	# Itens no chão são atraídos e coletados
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
