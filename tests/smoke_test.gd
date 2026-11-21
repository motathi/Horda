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
	Settings.tutorial_done = true  # o tutorial tem teste próprio
	# Os testes de combate/habilidades usam o Cavaleiro (corpo a corpo); o Caçador tem teste próprio.
	GameManager.hero_skin = "knight"
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
	await _test_map_threats()
	await _test_audio()
	await _test_atmosphere()
	await _test_settings_tutorial()
	await _test_combat()
	await _test_combat_challenge()
	await _test_app_switch()
	await _test_abilities()
	await _test_attributes()
	await _test_equipment()
	await _test_tech()
	await _test_special_enemies()
	await _test_horror_gameplay()
	await _test_hunter()
	await _test_fixes()
	await _test_army()
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
	# Cenário: vegetação em MultiMesh, cemitério e árvores do Blender (casulos, poças e árvores doentes da
	# Área Contaminada são colocados um a um, fora do DecorScatter).
	var decor := 0
	for n in world.get_children():
		if n is DecorScatter:
			decor += (n as DecorScatter).count()
	check(decor > 500, "vegetação decorativa espalhada (%d peças)" % decor)
	var blight := 0
	for n in world.builder.nav_region.get_children():
		if n.get_child_count() > 0 and String(n.get_child(0).scene_file_path).contains("models/blender/blight_"):
			blight += 1
		elif String(n.scene_file_path).contains("models/blender/blight_"):
			blight += 1
	check(blight >= 10, "contaminação na Área Contaminada: casulos, poças e árvores doentes (%d)" % blight)
	var crypt := false
	var tp_trees := 0
	for n in b.nav_region.get_children():
		if n is StaticBody3D and n.get_child_count() > 0 and String(n.get_child(0).scene_file_path).ends_with("crypt_ruin.glb"):
			crypt = true
		if n is Harvestable:
			for x: Node in n.find_children("*", "Node3D", true, false):
				if x.scene_file_path.contains("models/blender/tree_") or x.scene_file_path.contains("models/blender/pine_"):
					tp_trees += 1
					break
	check(crypt, "cemitério com cripta na Área Contaminada")
	check(tp_trees > 300, "árvores feitas no Blender (%d)" % tp_trees)
	# Ruínas (Blender), acampamento (KayKit Dungeon), casas (Blender) e sobreviventes (Quaternius).
	var ruins := 0
	var camp := 0
	var houses := 0
	for n in b.nav_region.get_children():
		if n is StaticBody3D and n.get_child_count() > 0:
			var path := String(n.get_child(0).scene_file_path)
			if path.contains("models/blender/ruin_") or path.contains("models/blender/rubble_pile"):
				ruins += 1
			elif path.contains("kaykit_dungeon"):
				camp += 1
			elif path.contains("models/blender/house_ruin") or path.contains("models/blender/shack_"):
				houses += 1
	check(ruins > 20, "ruínas feitas no Blender (%d peças)" % ruins)
	check(camp >= 5, "acampamento do Dungeon Pack na base (%d peças)" % camp)
	check(houses >= 6, "casas e barracos feitos no Blender (%d)" % houses)
	var survivors: Array[Survivor] = []
	for n in b.structures_root.get_children():
		if n is Survivor:
			survivors.append(n)
	check(survivors.size() >= 4, "sobreviventes na base (%d)" % survivors.size())
	await get_tree().process_frame
	check(survivors.all(func(sv: Survivor) -> bool: return sv._ap != null and sv._ap.is_playing()), "sobreviventes animados")
	EventBus.horde_started.emit(1, 1)
	await wait(4.5)
	check(survivors.all(func(sv: Survivor) -> bool: return sv.is_hidden()), "sobreviventes se escondem na fortaleza durante a horda")
	EventBus.horde_ended.emit(1)
	await get_tree().process_frame
	check(survivors.all(func(sv: Survivor) -> bool: return sv.visible), "sobreviventes voltam depois da horda")
	# Escolha de herói (só heróis no estilo do jogo) e visuais dos soldados.
	check(HeroSkins.playable().map(func(sk: Dictionary) -> String: return sk["id"]) == ["hunter", "knight"], "escolha de herói: Caçador e Cavaleiro")
	for skin in ["knight", "ranger", "barbarian", "mage"]:
		GameManager.hero_skin = skin
		var cm := CharacterModel.new()
		add_child(cm)
		cm.build_hero()
		check(cm._rigged and cm._anim_names.has("slash") and cm._anim_names.has("run"), "herói %s com modelo e animações" % skin)
		cm.queue_free()
	GameManager.hero_skin = HeroSkins.DEFAULT
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

func _test_atmosphere() -> void:
	print("[atmosfera]")
	var missing: Array[String] = []
	for id in ["thunder", "heartbeat", "heartbeat_fast", "crow", "scream", "ghost", "howl"]:
		if not AudioManager.has_sound(StringName(id)):
			missing.append(id)
	check(missing.is_empty(), "sons de terror presentes (faltando: %s)" % ", ".join(missing))
	check(ResourceLoader.exists("res://assets/ambient/horror.ogg") and ResourceLoader.exists("res://assets/ambient/storm.ogg"), "ambientes de terror e chuva")
	var dnv := DayNightVisuals.current
	check(dnv != null, "controle de atmosfera ativo")
	if dnv == null:
		return
	var horde := world.get(&"horde") as HordeDirector
	var boss_w := horde.config.boss_every if horde.config.boss_every > 0 else 10
	var saved_day := TimeManager.day
	var saved_phase := TimeManager.phase
	var saved_time := TimeManager.phase_time
	TimeManager.day = boss_w
	dnv._roll_night()
	check(dnv.blood_moon and not dnv.storm, "lua de sangue na rodada do chefe (%d)" % boss_w)
	TimeManager.day = 1
	dnv._roll_night()
	check(dnv.storm and not dnv.blood_moon, "primeira noite tem tempestade")
	TimeManager.phase = TimeManager.Phase.NIGHT  # sem sinal: não dispara a horda
	for i in 3:
		await get_tree().process_frame
	var lan := get_tree().get_nodes_in_group(&"hero_lantern")
	check(lan.size() >= 1 and (lan[0] as OmniLight3D).visible and (lan[0] as OmniLight3D).light_energy > 1.0, "lanterna do herói acesa à noite")
	check(AudioManager.storm, "chuva no ambiente durante a tempestade")
	var env := (world.get_node("WorldEnvironment") as WorldEnvironment).environment
	check(env.fog_density > 0.007 and env.adjustment_saturation < 0.7, "noite com neblina e cores apagadas")
	var hub := EffectsHub.instance()
	var before := hub._pools.filter(func(m: MeshInstance3D) -> bool: return m.visible).size()
	EventBus.enemy_killed.emit(world.hero, null, null)
	var after := hub._pools.filter(func(m: MeshInstance3D) -> bool: return m.visible).size()
	check(after == before + 1, "zumbi morto deixa poça de sangue")
	TimeManager.set_state(saved_phase, saved_day, saved_time)
	dnv._roll_night()
	for i in 3:
		await get_tree().process_frame
	check(not AudioManager.storm, "chuva para quando amanhece")

func _test_settings_tutorial() -> void:
	print("[configurações e tutorial]")
	var q0 := Settings.quality
	var fps0 := Settings.fps_limit
	var sun := world.get_node(^"Sun") as DirectionalLight3D
	Settings.set_value("quality", 0)
	check(not sun.shadow_enabled and is_equal_approx(get_viewport().scaling_3d_scale, 0.7), "qualidade Baixa: sem sombras e resolução 3D 70%")
	Settings.set_value("quality", 2)
	check(sun.shadow_enabled and is_equal_approx(get_viewport().scaling_3d_scale, 1.0), "qualidade Alta: sombras e resolução cheia")
	Settings.set_value("fps_limit", 30)
	check(Engine.max_fps == 30, "limite de 30 FPS aplicado")
	Settings.set_value("fps_limit", fps0)
	Settings.set_value("quality", q0)
	# Tutorial (primeira partida solo).
	Settings.tutorial_done = false
	world.hud.start_tutorial()
	var tut := world.hud.tutorial
	check(tut != null and tut.visible and not world.hud.objectives_panel.visible, "tutorial aparece no lugar dos objetivos")
	check(not TimeManager.running, "relógio da preparação parado durante o tutorial")
	var hero := world.hero
	hero.global_position += Vector3(7, 0, 0)
	await wait(0.1)
	ResourceManager.give_hero(&"wood", 1)
	EventBus.enemy_killed.emit(null, load("res://data/enemies/zombie.tres"), hero)
	hero.global_position = Vector3(0, 0, 5)
	await wait(0.3)
	check(tut.step == 4, "tutorial avança: mover, coletar, derrotar zumbi, voltar à base (passo %d)" % tut.step)
	EventBus.building_placed.emit(null)
	hero.ability_cast.emit(0)
	check(tut.step == 6 and TimeManager.running, "construir e usar habilidade liberam o relógio")
	var wood0 := ResourceManager.storage.count(&"wood")
	EventBus.horde_started.emit(1, 1)
	EventBus.horde_ended.emit(1)
	check(not tut.visible and Settings.tutorial_done and ResourceManager.storage.count(&"wood") == wood0 + 25 and world.hud.objectives_panel.visible, "chamar a horda conclui o tutorial com bônus")
	TimeManager.running = true

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

## Celular: trocar de app/girar a tela não pode deixar o jogo pausado nem toques presos.
func _test_app_switch() -> void:
	print("[celular: trocar de app e voltar]")
	var hud := world.hud
	get_tree().paused = false
	Platform.set_portrait(true)
	check(get_tree().paused, "na vertical o jogo pausa")
	Platform.set_portrait(false)
	check(not get_tree().paused, "de volta na horizontal o jogo despausa")
	hud.call("_toggle_pause")
	check(get_tree().paused, "menu de pausa aberto")
	Platform.set_portrait(true)
	Platform.set_portrait(false)
	check(get_tree().paused, "com o menu de pausa aberto, continua pausado depois de girar")
	hud.call("_toggle_pause")
	check(not get_tree().paused, "fechar o menu de pausa despausa")
	# Toque preso (o "soltou" se perdeu): botão de ataque e joystick ficam livres depois do reset.
	var acts := hud.find_children("*", "HudActions", true, false)
	if not acts.is_empty():
		var ha := acts[0] as HudActions
		ha._buttons[0].touch = 0
		ha._stick_touch = 1
		world.hero.touch_attack_held = true
		Input.action_press("move_left", 1.0)
		Platform.reset_input()
		check(ha._buttons[0].touch == -99 and ha._stick_touch == -1 and not world.hero.touch_attack_held and not Input.is_action_pressed("move_left"),
			"ao voltar ao jogo, toques e joystick presos são liberados")
	else:
		check(false, "botões de ação do HUD encontrados")

## Guardiões, baús, golpe em arco limitado e passo do herói casado com a velocidade.
func _test_map_threats() -> void:
	print("[mapa: guardiões, baús e golpe em arco]")
	var hero := world.hero
	var b := world.builder
	var guardians := Enemy.all.filter(func(e: Enemy) -> bool: return is_instance_valid(e) and e.is_guardian and not e.is_dead())
	check(b.guardians.size() == 5 and guardians.size() == 5, "5 guardiões pelo mapa (%d covis, %d vivos)" % [b.guardians.size(), guardians.size()])
	var chests := b.lootables.values().filter(func(l: Lootable) -> bool: return l.lid != null)
	check(chests.size() >= 15, "baús espalhados pelo mapa (%d)" % chests.size())
	var locked := chests.filter(func(l: Lootable) -> bool: return l.guard_radius > 0.0)
	check(locked.size() == 5 and (locked[0] as Lootable).is_guarded() and not (locked[0] as Lootable).can_interact(), "Baú do Guardião trancado enquanto o chefe vive")
	var day_enemies := Enemy.all.filter(func(e: Enemy) -> bool: return is_instance_valid(e) and not e.is_horde and not e.is_guardian).size()
	check(day_enemies >= 60, "mapa mais povoado (%d inimigos espalhados)" % day_enemies)
	# Golpe corpo a corpo: no máximo 4 inimigos, só o principal com dano cheio.
	await _clear_enemies()
	world.spawner.set_process(false)
	var was_ranged := hero.ranged
	hero.ranged = false
	hero.global_position = _clear_spot(Vector3(-40, 0, 40), 6.0)
	var fwd := hero.facing()
	var side := Vector3(-fwd.z, 0, fwd.x)
	var pack: Array[Enemy] = []
	for k in 6:
		pack.append(_spawn_zombie(hero.global_position + fwd * 1.6 + side * (k - 2.5) * 0.45))
	await wait(0.05)
	hero._aim_point = hero.global_position + fwd * 3.0
	hero._apply_hit()
	var hit := pack.filter(func(e: Enemy) -> bool: return e.health.current < e.health.max_health)
	var losses := hit.map(func(e: Enemy) -> float: return e.health.max_health - e.health.current)
	losses.sort()
	check(hit.size() == Hero.CLEAVE_MAX, "golpe em arco acerta no máximo %d de 6 zumbis (%d)" % [Hero.CLEAVE_MAX, hit.size()])
	check(losses.size() >= 2 and losses[-1] > losses[0] * 1.5, "só o alvo principal leva o dano cheio")
	hero.ranged = was_ranged
	await _clear_enemies()
	world.spawner.set_process(true)
	# Passo do herói: cadência da corrida acompanha a velocidade real (sem patinar).
	var m := hero.model
	if m._stride.has("run"):
		m.ground_speed = hero.current_move_speed()
		m.animate(0.016, 1.0)
		var expect: float = hero.current_move_speed() / float(m._stride["run"])
		check(m._current == "run" and absf(m._anim.speed_scale - clampf(expect, 0.6, 2.0)) < 0.05, "corrida no ritmo do passo (x%.2f)" % m._anim.speed_scale)
	else:
		check(false, "passo medido nas animações do herói")

## Golpe lento e anunciado, mais dano no herói, esquiva com invulnerabilidade e contra-ataque.
func _test_combat_challenge() -> void:
	print("[combate desafiador: golpe lento, esquiva e contra-ataque]")
	var hero := world.hero
	var start := hero.global_position
	var start_yaw := hero.model.rotation.y
	var zdef := load("res://data/enemies/zombie.tres") as EnemyDef
	var bdef := load("res://data/enemies/zombie_brute.tres") as EnemyDef
	# O mapa tem matilhas por toda parte: sem outros zumbis por perto durante o teste.
	await _clear_enemies()
	world.spawner.set_process(false)
	check(Enemy.melee_windup(zdef) >= 0.8, "golpe do zumbi é lento (%.2f s de preparação)" % Enemy.melee_windup(zdef))
	check(Enemy.melee_windup(bdef) > Enemy.melee_windup(zdef), "brutamontes demora ainda mais (%.2f s)" % Enemy.melee_windup(bdef))
	hero.health.heal(9999)
	# Zumbi parado de frente para o herói: o golpe acerta com dano aumentado.
	var e := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
	world.enemies_root.add_child(e)
	e.global_position = Vector3(60, 0, 60)
	e.configure(zdef)
	hero.global_position = Vector3(60, 0, 61.2)
	await wait(0.3)
	var hp0 := hero.health.current
	var t := 0.0
	while hero.health.current >= hp0 and t < 4.0:
		await wait(0.1)
		t += 0.1
	var lost := hp0 - hero.health.current
	check(lost >= e.damage_value * 1.5, "golpe do zumbi dói mais no herói (%.0f de dano, base %.0f)" % [lost, e.damage_value])
	check(e._tele != null, "aviso vermelho no chão durante a preparação do golpe")
	# Sair da frente durante a preparação faz o golpe errar.
	hero.health.heal(9999)
	e._attack_cd = 0.0
	e._windup = -1.0
	await wait(0.05)
	var hp1 := hero.health.current
	t = 0.0
	while e._windup < 0.0 and t < 3.0:
		await wait(0.05)
		t += 0.05
	check(e._windup >= 0.0, "zumbi começa a preparar outro golpe")
	await wait(e._melee_total * 0.6)  # mira já travada
	var fwd := Vector3(-sin(e.model.rotation.y), 0, -cos(e.model.rotation.y))
	hero.global_position = e.global_position - fwd * 1.6  # pelas costas
	await wait(e._melee_total * 0.6)
	check(hero.health.current >= hp1, "sair da frente no fim da preparação faz o golpe errar")
	world.spawner.set_process(true)
	# Esquiva: invulnerável por um instante; desviar de um golpe arma um contra-ataque crítico.
	e.take_damage(DamageInfo.make(9999, hero))
	await wait(0.3)
	check(hero.dodge(), "esquiva funciona (Shift / botão)")
	check(not hero.dodge(), "esquiva tem recarga")
	var hp2 := hero.health.current
	hero.take_damage(DamageInfo.make(50, null))
	check(hero.health.current == hp2, "esquiva evita o dano")
	check(hero._riposte > 0.0, "esquiva no momento certo arma o contra-ataque")
	await wait(0.6)
	hero.take_damage(DamageInfo.make(30, null))
	check(hero.health.current < hp2, "fora da esquiva o herói volta a tomar dano")
	var e3 := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
	world.enemies_root.add_child(e3)
	e3.global_position = Vector3(64, 0, 64)
	e3.configure(bdef)
	hero.global_position = Vector3(64, 0, 65.6)
	hero._riposte = 1.0
	var e3hp := e3.health.current
	hero.model.rotation.y = atan2(-(e3.global_position.x - hero.global_position.x), -(e3.global_position.z - hero.global_position.z))
	hero._attack_timer = 0.0
	hero._start_attack()
	await wait(0.5)
	check(e3.health.current < e3hp and hero._riposte == 0.0, "contra-ataque acerta e é consumido (%.0f de dano)" % (e3hp - e3.health.current))
	e3.take_damage(DamageInfo.make(99999, hero))
	hero.health.heal(9999)
	# Zumbi esquiva do golpe do herói com um passo rápido (chance forçada a 100% no teste)...
	var ev := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
	world.enemies_root.add_child(ev)
	ev.global_position = Vector3(70, 0, 70)
	ev.configure(zdef)
	hero.global_position = Vector3(70, 0, 71.4)
	await wait(0.2)
	ev._attack_cd = 99.0  # parado, sem atacar
	ev._windup = -1.0
	Enemy.evade_override = 1.0
	var ev_hp := ev.health.current
	var ev_p := ev.global_position
	hero.model.rotation.y = atan2(-(ev.global_position.x - hero.global_position.x), -(ev.global_position.z - hero.global_position.z))
	hero._attack_timer = 0.0
	hero._start_attack()
	await wait(0.6)
	check(ev.health.current == ev_hp and _flat(ev.global_position, ev_p) > 1.2, "zumbi desvia do golpe com um passo rápido (%.1f m)" % _flat(ev.global_position, ev_p))
	# ...mas não durante a preparação do próprio golpe (janela para o contra-ataque).
	ev._evade_cd = 0.0
	ev._windup = 0.8
	ev._melee_total = 0.8
	ev.threatened(hero, 0.25)
	check(ev._evade_delay < 0.0 and ev._evade_t <= 0.0, "zumbi não desvia enquanto prepara o próprio golpe")
	ev._windup = -1.0
	ev._melee_total = 0.0
	Enemy.evade_override = 0.0
	var zbrute := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
	world.enemies_root.add_child(zbrute)
	zbrute.configure(bdef)
	Enemy.evade_override = -1.0
	check(zbrute.evade_chance() == 0.0 and ev.evade_chance() > 0.15, "brutamontes não desvia; zumbi comum desvia às vezes (%.0f%%)" % (ev.evade_chance() * 100.0))
	ev.take_damage(DamageInfo.make(99999, hero))
	zbrute.take_damage(DamageInfo.make(99999, hero))
	hero.global_position = start
	hero.model.rotation.y = start_yaw
	await wait(0.2)

func _spawn_zombie(pos: Vector3) -> Enemy:
	var e := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
	world.enemies_root.add_child(e)
	e.global_position = pos
	e.configure(load("res://data/enemies/zombie_brute.tres"))
	return e

## Ponto perto de `near` sem nada sólido (casas, carros, árvores, pedras) num raio `r` — o mapa muda com o sorteio.
func _clear_spot(near: Vector3, r: float) -> Vector3:
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = r
	q.shape = sph
	q.collision_mask = Layers.WORLD | Layers.STRUCTURES
	var space := world.get_world_3d().direct_space_state
	for k in 64:
		var p := near + Vector3(float(k % 8) * 7.0 - 24.0, 0, float(k / 8) * 7.0 - 24.0)
		if p.length() < 35.0:
			continue
		q.transform = Transform3D(Basis(), p + Vector3.UP * (r + 0.3))
		if space.intersect_shape(q, 1).is_empty():
			return p
	return near

func _test_abilities() -> void:
	print("[habilidades]")
	var hero := world.hero
	hero.global_position = _clear_spot(Vector3(50, 0, 50), 9.0)
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
	check(why == "" and moved > 5.0, "Investida avança %.1f m (%s)" % [moved, why])
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

func _test_equipment() -> void:
	print("[equipamento]")
	var hero := world.hero
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	check(Gear.defs().size() == 11, "11 itens base de equipamento (%d)" % Gear.defs().size())
	check(hero.equipped(EquipmentDef.Slot.WEAPON) != null and hero.equipped(EquipmentDef.Slot.WEAPON).def.id == &"axe", "herói começa com machado")
	var sword := Gear.get_def(&"sword")
	var c1 := Gear.make_item(sword, 0, 1, rng)
	var l1 := Gear.make_item(sword, 4, 1, rng)
	var c20 := Gear.make_item(sword, 0, 20, rng)
	check(l1.stat("damage") > c1.stat("damage") * 2.0 and l1.affixes.size() == 4, "Lendário: dano %.1f vs comum %.1f, 4 bônus" % [l1.stat("damage"), c1.stat("damage")])
	check(c20.stat("damage") > c1.stat("damage") * 1.5, "nível do item escala atributos (nv 20: %.1f)" % c20.stat("damage"))
	# Equipar troca e devolve o antigo para a bolsa.
	hero.gear_bag.clear()
	var dmg0 := hero.damage()
	var rare_sword := Gear.make_item(sword, 2, 5, rng)
	hero.add_gear(rare_sword)
	hero.equip(rare_sword)
	check(hero.damage() > dmg0 and hero.gear_bag.size() == 1 and hero.gear_bag[0].def.id == &"axe", "equipar espada aumenta dano (%.0f -> %.0f) e o machado volta à bolsa" % [dmg0, hero.damage()])
	var arm0 := hero.health.armor
	var ms0 := hero.current_move_speed()
	var plate := Gear.make_item(Gear.get_def(&"plate"), 0, 1, rng)
	hero.add_gear(plate)
	hero.equip(plate)
	check(hero.health.armor > arm0 + 10.0 and hero.current_move_speed() < ms0, "placas: armadura %.0f -> %.0f e movimento menor" % [arm0, hero.health.armor])
	hero.unequip(EquipmentDef.Slot.ARMOR)
	check(is_equal_approx(hero.health.armor, arm0), "remover armadura restaura a armadura")
	# Desmontar
	var scrap0 := ResourceManager.storage.count(&"scrap")
	var msg := hero.salvage(plate)
	check(ResourceManager.storage.count(&"scrap") > scrap0 and not hero.gear_bag.has(plate), "desmontar devolve recursos (%s)" % msg)
	# Forja: Engenharia melhora as chances.
	var svc := world.services
	var odds0 := svc.forge_odds(hero)
	hero.attributes[&"engineering"] = 10
	var odds1 := svc.forge_odds(hero)
	hero.attributes[&"engineering"] = 0
	check(odds1[4] > odds0[4] * 3.0 and odds1[0] < odds0[0], "Engenharia aumenta chance de Lendário (%.1f%% -> %.1f%%)" % [odds0[4] * 100, odds1[4] * 100])
	var axe_def := Gear.get_def(&"axe")
	for id: StringName in axe_def.craft_cost:
		ResourceManager.storage.add(id, int(axe_def.craft_cost[id]))
	hero.global_position = Vector3(3, 0, 3)
	await wait(0.2)
	var bag0 := hero.gear_bag.size()
	msg = svc.forge(axe_def, hero)
	check(hero.gear_bag.size() == bag0 + 1, "Forja cria item na bolsa (%s)" % msg)
	# Saque de chefe sempre Raro ou melhor.
	var all_rare := true
	for i in 25:
		var bd := Gear.enemy_drop(rng, true, false, false)
		all_rare = all_rare and bd != null and bd.rarity >= 2
	check(all_rare, "chefes sempre largam Raro ou melhor")
	# Item no chão é coletado para a bolsa.
	hero.gear_bag.clear()
	EffectsHub.drop_gear(hero.global_position + Vector3(1.2, 0, 0), Gear.make_item(Gear.get_def(&"amulet_life"), 3, 4, rng))
	await wait(2.0)
	check(hero.gear_bag.size() == 1 and hero.gear_bag[0].def.id == &"amulet_life", "equipamento no chão vai para a bolsa")
	# Salvar/carregar
	var saved := hero.to_save()
	var eq_id := hero.equipped(EquipmentDef.Slot.WEAPON).def.id
	hero.equipment.clear()
	hero.gear_bag.clear()
	hero.from_save(saved)
	check(hero.equipped(EquipmentDef.Slot.WEAPON) != null and hero.equipped(EquipmentDef.Slot.WEAPON).def.id == eq_id and hero.gear_bag.size() == 1 and hero.gear_bag[0].rarity == 3, "equipamento e bolsa persistem no save")
	hero.gear_bag.clear()

func _test_tech() -> void:
	print("[tecnologias]")
	var hero := world.hero
	Tech.reset()
	check(Tech.defs.size() == 16, "16 tecnologias (%d)" % Tech.defs.size())
	var day0 := TimeManager.day
	TimeManager.day = 1
	check(Tech.block_reason(Tech.get_def(&"veteran")).contains("horda"), "Veterano bloqueado por horda")
	TimeManager.day = 5
	check(Tech.block_reason(Tech.get_def(&"gears")).begins_with("Requer"), "Mecanismos exige Pontas de Aço")
	hero.global_position = Vector3(3, 0, 3)
	await wait(0.2)
	var tools := Tech.get_def(&"tools")
	for id: StringName in tools.cost:
		ResourceManager.storage.add(id, int(tools.cost[id]) * 2)
	var wood0 := ResourceManager.storage.count(&"wood")
	var msg := Tech.start(tools)
	check(Tech.active == &"tools" and ResourceManager.storage.count(&"wood") < wood0, "pesquisa inicia e cobra recursos (%s)" % msg)
	check(Tech.block_reason(Tech.get_def(&"packs")).contains("andamento"), "só uma pesquisa por vez")
	Tech.progress = tools.research_time - 0.05
	await wait(0.3)
	check(Tech.has(&"tools") and Tech.active == &"", "pesquisa conclui com o tempo")
	check(int(Tech.bonus("harvest_bonus")) == 1, "Ferramentas: +1 recurso por golpe")
	# Efeitos aplicados na hora.
	var wall := world.builder.structures["wall1"] as Structure
	var whp0 := wall.health.max_health
	Tech.complete(Tech.get_def(&"walls1"))
	check(is_equal_approx(wall.health.max_health, whp0 * 1.25), "Muros Reforçados: paliçada %d -> %d" % [int(whp0), int(wall.health.max_health)])
	var tower := world.build_manager.place(Building.load_def(&"archer_tower"), Vector3(70, 0, 70), 0.0, false)
	await wait(0.05)
	var td0 := tower.tower_damage()
	var tr0 := tower.tower_range()
	Tech.complete(Tech.get_def(&"arrows1"))
	Tech.complete(Tech.get_def(&"optics"))
	check(tower.tower_damage() > td0 * 1.19 and tower.tower_range() > tr0 * 1.14, "torres: dano %.0f -> %.0f, alcance %.1f -> %.1f" % [td0, tower.tower_damage(), tr0, tower.tower_range()])
	tower.queue_free()
	var cap0 := ResourceManager.hero_inventory.capacity
	var dmg0 := hero.damage()
	Tech.complete(Tech.get_def(&"packs"))
	Tech.complete(Tech.get_def(&"training"))
	check(ResourceManager.hero_inventory.capacity == cap0 + 20 and hero.damage() > dmg0 * 1.09, "Mochilas +20 de carga e Treinamento +10% de dano")
	# Coletores produzem recursos fora da horda.
	Tech.complete(Tech.get_def(&"gatherers"))
	var w1 := ResourceManager.storage.count(&"wood")
	Tech._income_t = 0.05
	await wait(0.2)
	check(ResourceManager.storage.count(&"wood") == w1 + 3, "Coletores entregam madeira ao armazém")
	# Cancelar devolve metade.
	var med := Tech.get_def(&"medicine")
	for id: StringName in med.cost:
		ResourceManager.storage.add(id, int(med.cost[id]))
	var herbs0 := ResourceManager.storage.count(&"herbs")
	Tech.start(med)
	Tech.cancel()
	check(ResourceManager.storage.count(&"herbs") == herbs0 - int(med.cost[&"herbs"]) + int(med.cost[&"herbs"]) / 2 and Tech.active == &"", "cancelar devolve metade dos recursos")
	# Salvar/carregar
	var saved := Tech.to_save()
	Tech.reset()
	check(not Tech.has(&"walls1") and is_equal_approx(wall.health.max_health, whp0), "reset remove os bônus")
	Tech.from_save(saved)
	check(Tech.has(&"walls1") and Tech.has(&"gatherers") and is_equal_approx(wall.health.max_health, whp0 * 1.25), "tecnologias persistem no save")
	Tech.reset()
	hero.refresh_tech()
	TimeManager.day = day0

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

func _test_hunter() -> void:
	print("[caçador: arco, armadilhas e águia]")
	var hero := world.hero
	await _clear_enemies()
	var was_inv := hero.health.invulnerable
	hero.health.invulnerable = true
	hero.apply_class("hunter")
	await wait(0.1)
	check(hero.ranged and hero.model.has_bow(), "Caçador ataca com arco (arco na mão)")
	check(hero.abilities.map(func(a: AbilityDef) -> StringName: return a.id) == [&"multishot", &"bear_trap", &"arrow_rain", &"eagle"], "habilidades do Caçador")
	var spot := Vector3(-60, 0, 40)
	hero.global_position = spot
	# Flecha acerta zumbi a 9 m.
	var z := _spawn_def("zombie", spot + Vector3(9, 0, 0))
	await wait(0.05)
	z.set_physics_process(false)
	var hp0 := z.health.current
	hero._aim_point = z.global_position
	hero._start_attack()
	check(not hero._melee_swing and hero._shot_target == z, "mira o zumbi a 9 m")
	await wait(1.0)
	check(z.health.current < hp0, "flecha fere o zumbi à distância (%d -> %d)" % [int(hp0), int(z.health.current)])
	check(hero.reach() >= 13.0, "alcance do arco %.0f m" % hero.reach())
	# Sem inimigo e perto de uma árvore: usa o machado para coletar.
	await _clear_enemies()
	var tree_node: Node3D = null
	for h in get_tree().get_nodes_in_group("harvestable"):
		tree_node = h as Node3D
		break
	if tree_node:
		hero.global_position = tree_node.global_position + Vector3(1.6, 0, 0)
		hero._aim_point = tree_node.global_position
		hero._attack_timer = 0.0
		hero._start_attack()
		check(hero._melee_swing, "perto de árvore/pedra o Caçador coleta com o machado")
	hero.global_position = spot
	hero.level = 6
	# Tiro Múltiplo: um inimigo por flecha.
	var pack: Array[Enemy] = []
	for i in 4:
		var m := _spawn_def("zombie", spot + Vector3(8, 0, -3 + i * 2))
		pack.append(m)
	await wait(0.05)
	for m in pack:
		m.set_physics_process(false)
	var hps := pack.map(func(m: Enemy) -> float: return m.health.current)
	hero.energy = hero.max_energy
	hero._aim_point = spot + Vector3(8, 0, 0)
	check(hero.cast_ability(0) == "", "Tiro Múltiplo lançado")
	await wait(1.0)
	var hit := 0
	for i in pack.size():
		if pack[i].health.current < hps[i]:
			hit += 1
	check(hit == 4, "Tiro Múltiplo acerta vários (%d de 4)" % hit)
	# Chuva de Flechas no grupo: dano contínuo e lentidão.
	var hps2 := pack.map(func(m: Enemy) -> float: return m.health.current)
	hero.energy = hero.max_energy
	check(hero.cast_ability(2) == "", "Chuva de Flechas lançada")
	await wait(1.3)
	var rained := 0
	for i in pack.size():
		if is_instance_valid(pack[i]) and (pack[i].is_dead() or pack[i].health.current < hps2[i]) and (pack[i].is_dead() or pack[i]._fear > 0.0):
			rained += 1
	check(rained >= 3, "chuva fere e deixa lentos (%d de 4)" % rained)
	await _clear_enemies()
	await wait(3.0)
	# Armadilha de urso: prende quem pisa.
	hero.energy = hero.max_energy
	hero._aim_point = spot + Vector3(5, 0, 0)
	var n0 := BearTrap.active.size()
	check(hero.cast_ability(1) == "", "Armadilha armada")
	await wait(0.05)
	check(BearTrap.active.size() == n0 + 1, "armadilha no chão")
	var trap := BearTrap.active.back() as BearTrap
	var victim := _spawn_def("zombie_brute", trap.global_position + Vector3(0.3, 0, 0))
	var vhp := victim.health.current
	await wait(0.4)
	check(not trap.is_armed() and victim.is_stunned() and victim.health.current < vhp, "armadilha fecha, fere e prende")
	await _clear_enemies()
	# Águia: voa com o herói e mergulha nos inimigos; revela Espreitadores.
	hero.energy = hero.max_energy
	check(hero.cast_ability(3) == "", "Chamado da Águia")
	await wait(0.1)
	var eagles := get_tree().get_nodes_in_group(&"eagles")
	check(eagles.size() == 1 and (eagles[0] as Node).is_in_group(&"reveal_lights"), "águia invocada (e revela Espreitadores)")
	var prey := _spawn_def("zombie_brute", spot + Vector3(6, 0, 3))
	await wait(0.05)
	prey.set_physics_process(false)
	var php := prey.health.current
	await wait(4.0)
	check(prey.health.current < php, "águia mergulha e fere (%d -> %d)" % [int(php), int(prey.health.current)])
	for e in get_tree().get_nodes_in_group(&"eagles"):
		e.queue_free()
	for t in get_tree().get_nodes_in_group(&"bear_traps"):
		t.queue_free()
	await _clear_enemies()
	hero.apply_class("knight")
	hero.level = 1
	hero.health.invulnerable = was_inv
	check(not hero.ranged and hero.abilities[0].id == &"whirlwind", "Cavaleiro continua corpo a corpo")

func _test_horror_gameplay() -> void:
	print("[terror na jogabilidade]")
	var hero := world.hero
	var dnv := DayNightVisuals.current
	await _clear_enemies()
	var saved := [TimeManager.day, TimeManager.phase, TimeManager.phase_time]
	TimeManager.phase = TimeManager.Phase.NIGHT  # sem sinal: não dispara a horda
	TimeManager.phase_time = 30.0
	dnv.storm = false
	dnv.fog = false
	dnv.blood_moon = false
	var was_inv := hero.health.invulnerable
	hero.health.invulnerable = true
	var spot := Vector3(-40, 0, 70)
	hero.global_position = spot
	# Olhos que brilham à noite.
	var z := _spawn_def("zombie", spot + Vector3(30, 0, 0))
	await wait(0.2)
	check(z.model.find_children("Eyes", "MeshInstance3D", true, false).size() == 1, "zumbi tem olhos brilhantes presos à cabeça")
	check(CharacterModel.eye_intensity > 0.7, "olhos acesos à noite (%.2f)" % CharacterModel.eye_intensity)
	# Espreitador: invisível longe da luz, revelado pela lanterna.
	await _clear_enemies()
	var st := _spawn_def("zombie_stalker", spot + Vector3(25, 0, 0))
	st.set_physics_process(true)
	await wait(0.6)
	check(st.hidden and not st.is_targetable(), "Espreitador some na escuridão")
	var tower := world.build_manager.place(Building.load_def(&"archer_tower"), spot + Vector3(18, 0, 6), 0.0, false)
	check(tower._find_target(30.0) == null, "torre não mira Espreitador escondido")
	st.global_position = spot + Vector3(4, 0, 0)
	await wait(0.5)
	check(not st.hidden and st.is_targetable(), "lanterna do herói revela o Espreitador")
	check(st._ambush, "Espreitador revelado prepara emboscada")
	tower.queue_free()
	# Braseiro revela e assusta.
	await _clear_enemies()
	TimeManager.day = 5
	var bz_def := Building.load_def(&"brazier")
	check(bz_def.is_unlocked(), "Braseiro liberado na horda %d" % bz_def.unlock_wave)
	var bz := world.build_manager.place(bz_def, spot + Vector3(30, 0, 0), 0.0, false)
	await wait(0.1)
	check(DayNightVisuals.is_lit(spot + Vector3(36, 0, 0)), "Braseiro ilumina ao redor (revela)")
	var zz := _spawn_def("zombie", spot + Vector3(33, 0, 0))
	await wait(0.8)
	check(zz._fear > 0.0, "zumbi perto do fogo fica com medo (mais lento)")
	bz.queue_free()
	# Gritador atrai os zumbis próximos.
	await _clear_enemies()
	var sc := _spawn_def("zombie_screamer", spot + Vector3(12, 0, 0))
	var pack: Array[Enemy] = []
	for i in 3:
		var m := _spawn_def("zombie", spot + Vector3(26, 0, -4 + i * 4))
		pack.append(m)
	var screamed := false
	for i in 40:
		await wait(0.1)
		if sc._scream_wind >= 0.0 or sc._special_cd > 0.0:
			screamed = true
		if screamed and pack[0]._frenzy > 0.0:
			break
	check(screamed, "Gritador grita ao ver o herói")
	check(pack.all(func(m: Enemy) -> bool: return m._frenzy > 0.0 and m._target == hero), "grito atrai e enfurece os zumbis próximos")
	check(_flat(sc.global_position, hero.global_position) > 4.0, "Gritador mantém distância (%.1f m)" % _flat(sc.global_position, hero.global_position))
	# Névoa densa reduz o alcance das torres e o minimapa.
	await _clear_enemies()
	dnv.fog = true
	var t2 := world.build_manager.place(Building.load_def(&"archer_tower"), spot + Vector3(0, 0, 8), 0.0, false)
	check(absf(t2.tower_range() - t2.base_tower_range() * DayNightVisuals.FOG_RANGE_MULT) < 0.01, "névoa reduz o alcance das torres (%.1f m)" % t2.tower_range())
	check(DayNightVisuals.map_reveal_radius() < 100.0, "névoa limita o minimapa")
	t2.queue_free()
	dnv.fog = false
	TimeManager.day = 3
	dnv._roll_night()
	TimeManager.day = 4
	var fog_seen := false
	for w in range(3, 40):
		TimeManager.day = w
		dnv._roll_night()
		fog_seen = fog_seen or dnv.fog
		if dnv.fog and (dnv.storm or dnv.blood_moon):
			fog_seen = false
			break
	check(fog_seen, "algumas noites têm névoa densa (e nunca junto com tempestade/lua de sangue)")
	# Chefes da lua de sangue variam.
	var hd := world.horde
	check(hd.boss_variant(10)["title"] == "Abominação" and hd.boss_variant(20)["title"] == "Rainha dos Gritos", "chefes diferentes a cada lua de sangue")
	check(hd.boss_def(20).id == &"zombie_screamer" and hd.boss_def(30).id == &"zombie_stalker" and hd.boss_def(40).id == &"zombie_leaper", "chefes: Gritadora, Sombra e Saltador")
	var boss := _spawn_def("zombie_screamer", spot + Vector3(10, 0, 0))
	await wait(0.05)
	boss.make_boss("Rainha dos Gritos")
	check(boss.display_name() == "Chefe: Rainha dos Gritos", "chefe com título próprio")
	var before := Enemy.all.size()
	boss._summon_minions(3)
	await wait(0.05)
	check(Enemy.all.size() == before + 3, "Rainha dos Gritos ergue zumbis")
	await _clear_enemies()
	TimeManager.set_state(saved[1], saved[0], saved[2])
	dnv._roll_night()
	hero.health.invulnerable = was_inv

func _test_fixes() -> void:
	print("[correções: horda e herói preso]")
	var hd := world.horde
	await _clear_enemies()
	# Surgimento sempre na malha de navegação.
	var crypt_pos := Vector3.ZERO
	for n in world.builder.nav_region.get_children():
		if n is StaticBody3D and n.get_child_count() > 0 and String(n.get_child(0).scene_file_path).ends_with("crypt_ruin.glb"):
			crypt_pos = (n as Node3D).global_position
	var np := hd._nav_point(crypt_pos)
	check(crypt_pos != Vector3.ZERO and np.distance_to(crypt_pos) > 1.0, "ponto de surgimento dentro de obstáculo (cripta) é movido para a malha de navegação (%.1f m)" % np.distance_to(crypt_pos))
	# Zumbi fora do mapa é resgatado.
	var lost := _spawn_def("zombie", Vector3(60, 0, 60))
	await wait(0.05)
	lost.start_siege()
	lost.global_position = Vector3(130, -8, 0)
	hd._alive.append(lost)
	hd._watch_t = 0.0
	hd._watchdog(0.016)
	check(absf(lost.global_position.x) < 40.0 and lost.global_position.y > -1.0, "zumbi fora do mapa trazido para perto da base (%s)" % lost.global_position)
	# Zumbi parado por 20 s é resgatado.
	var stuck := _spawn_def("zombie", Vector3(80, 0, -20))
	await wait(0.05)
	stuck.start_siege()
	stuck.set_physics_process(false)
	hd._alive.append(stuck)
	for i in 11:
		hd._watch_t = 0.0
		hd._watchdog(0.016)
	check(stuck.global_position.distance_to(Vector3(80, 0, -20)) > 20.0, "zumbi preso por 20 s é reposicionado (%s)" % stuck.global_position)
	# Últimos zumbis: marcados no minimapa/feixe e, por fim, eliminados.
	var phase0 := TimeManager.phase
	TimeManager.phase = TimeManager.Phase.NIGHT  # sem sinal: não dispara uma horda real
	world.hud.minimap._update_stragglers()
	check(lost.get_node_or_null(^"Beacon") != null, "últimos zumbis da horda ganham feixe vermelho")
	hd._straggler_t = hd.STRAGGLER_KILL + 1.0
	hd._straggler_stage = 1
	hd._watchdog(0.016)
	await wait(0.1)
	check(lost.is_dead() and stuck.is_dead(), "retardatários eliminados no último recurso")
	hd._alive.clear()
	hd._straggler_t = 0.0
	hd._straggler_stage = 0
	TimeManager.phase = phase0
	await _clear_enemies()
	# Não constrói em cima de herói.
	var hero := world.hero
	hero.global_position = Vector3(6, 0, 18)
	await wait(0.1)
	var bm := world.build_manager
	ResourceManager.storage.add(&"wood", 50)
	check(bm.check(Building.load_def(&"barricade"), Vector3(6, 0, 18), 0.0) == "Um herói está no caminho", "não deixa construir em cima de um herói")
	# Herói dentro de uma construção é destravado.
	var trap := bm.place(Building.load_def(&"stone_wall"), Vector3(6, 0, 18), 0.0, false)
	await wait(1.2)
	check(not hero._overlaps_at(hero.global_position) and hero.global_position.distance_to(Vector3(6, 0, 18)) > 0.5, "herói preso dentro de uma construção é destravado (%s)" % hero.global_position)
	trap.queue_free()
	await wait(0.05)

func _test_army() -> void:
	print("[exército]")
	var army := world.army
	var hero := world.hero
	await _clear_enemies()
	var day0 := TimeManager.day
	TimeManager.day = 6
	check(army.defs.size() == 4, "4 tipos de soldado (%d)" % army.defs.size())
	var guard := army.get_def(&"guard")
	check(army.block_reason(guard).contains("Quartel"), "sem Quartel não recruta")
	var bar := world.build_manager.place(Building.load_def(&"barracks"), Vector3(-20, 0, 20), 0.0, false)
	await wait(0.1)
	check(army.capacity() == 4, "Quartel dá 4 vagas (%d)" % army.capacity())
	for id: StringName in [&"wood", &"stone", &"scrap", &"cloth", &"herbs"]:
		ResourceManager.storage.add(id, 300)
	var msg := army.recruit(guard)
	check(army.queue.size() == 1, "recrutar coloca na fila de treino (%s)" % msg)
	army.queue[0]["t"] = 0.05
	await wait(0.3)
	check(army.alive_count() == 1 and army.queue.is_empty(), "soldado treinado sai do Quartel")
	var s := army.soldiers[0]
	s.health.invulnerable = true
	s.global_position = s.post
	# Defender: ataca zumbi que chega perto do posto.
	hero.global_position = Vector3(60, 0, 60)
	var z := _spawn_def("zombie_brute", s.post + Vector3(4, 0, 0))
	z.set_physics_process(false)
	await wait(0.2)
	var hp0 := z.health.current
	await wait(4.0)
	check(z.health.current < hp0, "Guarda defende o posto e ataca o zumbi (%d -> %d)" % [int(hp0), int(z.health.current)])
	# Zumbi ataca soldado quando o herói está longe.
	z.set_physics_process(true)
	s.health.invulnerable = false
	var shp := s.health.current
	await wait(3.0)
	check(s.health.current < shp, "zumbi revida e ataca o soldado")
	s.health.invulnerable = true
	# XP para o herói quando o exército mata.
	var xp0 := hero.xp
	var lvl0 := hero.level
	z.health.current = 1.0
	await wait(3.0)
	check(z.is_dead() and (hero.xp > xp0 or hero.level > lvl0), "morte pelo exército dá XP ao herói")
	await _clear_enemies()
	# Caçar: vai atrás de zumbi longe do posto.
	army.set_order(Army.Order.HUNT)
	var far := _spawn_def("zombie_brute", Vector3(30, 0, -30))
	far.set_physics_process(false)
	await wait(0.2)
	var fhp := far.health.current
	await wait(14.0)
	check(far.health.current < fhp, "ordem Caçar: soldado vai até o zumbi distante")
	await _clear_enemies()
	# Seguir o herói.
	hero.global_position = Vector3(-30, 0, -10)
	army.set_order(Army.Order.FOLLOW, hero)
	await wait(14.0)
	check(s.global_position.distance_to(hero.global_position) < 6.0, "ordem Seguir: soldado acompanha o herói (%.1f m)" % s.global_position.distance_to(hero.global_position))
	army.set_order(Army.Order.DEFEND)
	# Limite de vagas.
	for i in 3:
		army.recruit(guard)
	check(army.block_reason(guard).contains("limite"), "limite de soldados respeitado")
	# Salvar/carregar.
	var saved := army.to_save()
	check((saved["soldiers"] as Array).size() == 1 and (saved["queue"] as Array).size() == 3, "exército e fila salvos")
	for so in army.soldiers.duplicate():
		so.queue_free()
	army.soldiers.clear()
	army.queue.clear()
	await wait(0.1)
	army.from_save(saved)
	check(army.alive_count() == 1 and army.queue.size() == 3, "exército restaurado do save")
	for so in army.soldiers.duplicate():
		so.queue_free()
	army.soldiers.clear()
	army.queue.clear()
	bar.queue_free()
	TimeManager.day = day0
	await wait(0.1)

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
	print("    mochila antes do saque: %d / %d" % [ResourceManager.hero_inventory.used_weight(), ResourceManager.hero_inventory.capacity])
	ResourceManager.deposit_all()
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
	var r: Recipe = null
	var potion_r: Recipe = null
	for rr: Recipe in world.services.recipes:
		if rr.id == &"bandage":
			r = rr
		elif rr.id == &"potion":
			potion_r = rr
	msg = world.services.craft(r)
	check(ResourceManager.hero_inventory.count(&"bandage") >= 1, "curativo fabricado: " + msg)
	# Poção de cura comprada na base: cura 160 na hora (tecla 3).
	check(potion_r != null and potion_r.buy, "poção de cura à venda no menu da base")
	msg = world.services.craft(potion_r)
	check(ResourceManager.hero_inventory.count(&"potion") >= 1 and msg.begins_with("Comprado"), "poção comprada: " + msg)
	hero.health.take_damage(DamageInfo.make(200, null))
	var hp_p := hero.health.current
	hero.use_consumable(&"potion")
	check(hero.health.current >= minf(hero.health.max_health, hp_p + 150.0), "poção cura na hora (%.0f -> %.0f)" % [hp_p, hero.health.current])
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
	check(Building.all_defs().size() == 10, "10 construções no menu")
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
	check(n1.size() >= 15 and n1.filter(func(d: EnemyDef) -> bool: return d.id == &"zombie_fast").size() >= 2, "horda 1 mais forte: %d zumbis, com rápidos" % n1.size())
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
