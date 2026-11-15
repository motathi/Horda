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
	TimeManager.setup("rapido")
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
	await _test_harvest_and_loot()
	await _test_base_services()
	await _test_night()
	await _test_save()
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
	check(TimeManager.phase == TimeManager.Phase.DAY and TimeManager.day == 1, "começa no Dia 1")
	check(world.objectives.objectives.size() == 3, "3 objetivos do dia gerados")
	# Objetivo "estar na base ao anoitecer" é verificado no início da noite.
	var ret: Dictionary = world.objectives.objectives[2]
	check(ret.kind == "return" and not ret.done, "objetivo de retorno pendente")

func _test_combat() -> void:
	print("[combate]")
	var hero := world.hero
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

func _test_night() -> void:
	print("[noite e horda]")
	var hero := world.hero
	hero.health.invulnerable = true
	hero.global_position = Vector3(0, 0, 0)
	while TimeManager.phase != TimeManager.Phase.NIGHT:
		TimeManager.advance_phase()
	await wait(0.5)
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
	var n5 := cfg.compose(5, rng)
	var has_brute := n5.any(func(d: EnemyDef) -> bool: return d.id == &"zombie_brute")
	var has_fast := n5.any(func(d: EnemyDef) -> bool: return d.id == &"zombie_fast")
	check(n5.size() > n1.size(), "noite 5 maior que noite 1 (%d > %d)" % [n5.size(), n1.size()])
	check(has_brute and has_fast, "noite 5 contém zumbis rápidos e resistentes")
	check(n1.all(func(d: EnemyDef) -> bool: return d.id == &"zombie"), "noite 1 só tem zumbis comuns")
	check(cfg.is_blood_moon(7) and cfg.elite_count(7) > 0, "noite 7: lua de sangue com elite")

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
