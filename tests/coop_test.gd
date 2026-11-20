extends Node
## Teste do coop com dois processos (ENet local):
##   tools/run_coop_test.sh   (inicia anfitrião e cliente e junta os resultados)
## Cada processo roda este script com "-- --role=host" ou "-- --role=client".

var role := "host"
var failures := 0
var _step_done: Dictionary = {}

func check(cond: bool, msg: String) -> void:
	print("  %s: [%s] %s" % ["PASS" if cond else "FAIL", role, msg])
	if not cond:
		failures += 1

func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
	# Sobrevive à troca de cena (menu -> mundo).
	name = "CoopTestDriver"
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	await get_tree().create_timer(0.5).timeout
	print("== Coop test (%s) ==" % role)
	if role == "host":
		await _run_host()
	else:
		await _run_client()
	print("== %s %s (%d falhas) ==" % [role, "OK" if failures == 0 else "FALHOU", failures])
	await wait(1.0)
	get_tree().quit(1 if failures > 0 else 0)

# --- Sincronização entre os dois processos (RPC no próprio driver) ---

@rpc("any_peer", "call_remote", "reliable")
func step(n: String) -> void:
	_step_done[n] = true

func wait_step(n: String, timeout: float = 30.0) -> bool:
	var t := 0.0
	while not _step_done.has(n) and t < timeout:
		await wait(0.1)
		t += 0.1
	return _step_done.has(n)

func wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await wait(0.1)
		t += 0.1
	return cond.call()

func _world_ready() -> bool:
	return await wait_until(func() -> bool: return GameManager.is_playing() and Coop.world != null, 60.0)

# --- Anfitrião ---

func _run_host() -> void:
	GameManager.hero_skin = "knight"
	Net.host_room("Anfitrião")
	check(Net.is_host(), "sala aberta")
	check(await wait_until(func() -> bool: return Net.players.size() == 2, 30.0), "cliente entrou na sala (%d jogadores)" % Net.players.size())
	Net.start_game("normal")
	check(await _world_ready(), "mundo carregado no anfitrião")
	var world := Coop.world
	world.get(&"hero").get(&"health").set(&"invulnerable", true)
	check(await wait_until(func() -> bool: return Coop.remote_heroes.size() == 1, 20.0), "herói do cliente aparece como fantoche")
	step.rpc("host_ready")
	await wait_step("client_ready")
	# Posição do herói do cliente replicada.
	var puppet := Coop.remote_heroes.values()[0] as Hero
	check(await wait_until(func() -> bool: return puppet.global_position.distance_to(Vector3(8, 0, 8)) < 1.0, 10.0), "fantoche segue o herói do cliente (%s)" % puppet.global_position)
	check(puppet.skin_override == "hunter", "fantoche usa a aparência escolhida pelo cliente")
	# Inimigo do anfitrião aparece no cliente; o cliente golpeia.
	var e := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
	e.def = load("res://data/enemies/zombie_brute.tres") as EnemyDef
	(world.get(&"enemies_root") as Node).add_child(e)
	e.global_position = Vector3(10, 0, 8)
	e.set_physics_process(false)
	await wait(0.5)
	var hp0 := e.health.current
	step.rpc("enemy_spawned")
	await wait_step("client_hit")
	await wait(0.5)
	check(e.health.current < hp0, "golpe do cliente tira vida do inimigo no anfitrião (%d -> %d)" % [int(hp0), int(e.health.current)])
	# Zumbi ataca o fantoche: o dano vai para o dono.
	puppet.take_damage(DamageInfo.make(30.0, e))
	step.rpc("hero_hit_sent")
	# Cliente mata o inimigo e recebe XP.
	e.health.current = 5.0
	step.rpc("enemy_low")
	check(await wait_until(func() -> bool: return not is_instance_valid(e) or e.is_dead(), 10.0), "inimigo morre pelo golpe final do cliente")
	# Saque compartilhado perto do cliente.
	await wait_step("ready_drop")
	Coop.host_drop(Vector3(8.5, 0, 8.5), &"cloth", 3)
	step.rpc("drop_sent")
	check(await wait_until(func() -> bool: return Coop.pickups.is_empty(), 10.0), "saque compartilhado coletado pelo cliente some no anfitrião")
	# Armazém e construção pedida pelo cliente.
	ResourceManager.storage.add(&"wood", 100)
	ResourceManager.storage.add(&"stone", 100)
	step.rpc("storage_sent")
	check(await wait_until(func() -> bool: return get_tree().get_nodes_in_group("buildings").size() > 0, 15.0), "construção pedida pelo cliente foi feita pelo anfitrião")
	var army := world.get(&"army") as Army
	army.spawn(army.get_def(&"guard"), Vector3(4, 0, 9))
	step.rpc("soldier_sent")
	# Reviver: o cliente cai e o anfitrião o levanta (segurando E perto dele).
	check(await wait_step("client_down", 30.0), "cliente avisou que caiu")
	check(await wait_until(func() -> bool: return puppet.health.dead, 8.0), "herói caído do cliente aparece caído no anfitrião")
	check(puppet._down_ring != null and puppet._down_ring.visible, "círculo de resgate sob o aliado caído")
	var me: Hero = world.hero
	me.global_position = puppet.global_position + Vector3(1.0, 0, 0)
	await wait(0.3)
	me.try_interact()
	check(me.is_reviving(), "anfitrião começa a reviver o aliado (E)")
	check(await wait_until(func() -> bool: return not puppet.health.dead, Hero.REVIVE_TIME + 5.0), "aliado revivido pelo anfitrião")
	await wait_step("client_done", 40.0)

# --- Cliente ---

func _run_client() -> void:
	GameManager.hero_skin = "hunter"
	await wait(1.0)
	Net.join_room("127.0.0.1", "Convidado")
	check(await wait_until(func() -> bool: return Net.players.size() == 2, 20.0), "entrou na sala do anfitrião")
	check(await _world_ready(), "mundo carregado no cliente")
	var world := Coop.world
	var hero := world.get(&"hero") as Hero
	check(TimeManager.running == false, "relógio do cliente é comandado pelo anfitrião")
	await wait_step("host_ready")
	check(Coop.remote_heroes.size() == 1 and (Coop.remote_heroes.values()[0] as Hero).skin_override == "knight", "herói do anfitrião aparece com a aparência dele")
	hero.global_position = Vector3(8, 0, 8)
	step.rpc_id(1, "client_ready")
	await wait_step("enemy_spawned")
	var find := func() -> Enemy:
		for en in Enemy.all:
			if en.puppet and en.def and en.def.id == &"zombie_brute" and not en.is_dead() and en.global_position.distance_to(Vector3(10, 0, 8)) < 3.0:
				return en
		return null
	await wait_until(func() -> bool: return find.call() != null, 5.0)
	var puppet_enemy: Enemy = find.call()
	check(puppet_enemy != null, "inimigo do anfitrião aparece no cliente como fantoche")
	if puppet_enemy:
		check(puppet_enemy.global_position.distance_to(Vector3(10, 0, 8)) < 1.5, "posição do inimigo replicada")
		puppet_enemy.take_damage(DamageInfo.make(40.0, hero))
	hero.health.invulnerable = false
	var hp0 := hero.health.current
	step.rpc_id(1, "client_hit")
	await wait_step("hero_hit_sent")
	check(await wait_until(func() -> bool: return hero.health.current < hp0, 5.0), "dano do zumbi no fantoche chega ao herói do cliente (%d -> %d)" % [int(hp0), int(hero.health.current)])
	await wait_step("enemy_low")
	var xp0 := hero.xp
	var lvl0 := hero.level
	if puppet_enemy:
		puppet_enemy.take_damage(DamageInfo.make(50.0, hero))
	check(await wait_until(func() -> bool: return hero.xp > xp0 or hero.level > lvl0, 8.0), "cliente ganha XP pela morte do inimigo")
	var cloth0 := ResourceManager.available(&"cloth")
	step.rpc_id(1, "ready_drop")
	await wait_step("drop_sent")
	await wait(1.0)
	print("    [client] saques compartilhados: %d, herói em %s, mochila %d/%d" % [Coop.pickups.size(), hero.global_position, ResourceManager.hero_inventory.used_weight(), ResourceManager.hero_inventory.capacity])
	# Dentro da base a mochila é guardada no armazém (compartilhado) automaticamente.
	check(await wait_until(func() -> bool: return ResourceManager.available(&"cloth") >= cloth0 + 3, 10.0), "cliente coleta o saque compartilhado (vai para mochila/armazém)")
	await wait_step("storage_sent")
	check(await wait_until(func() -> bool: return ResourceManager.storage.count(&"wood") >= 100, 5.0), "armazém do anfitrião replicado no cliente")
	check(TimeManager.day == 1 and TimeManager.phase == TimeManager.Phase.DAWN or TimeManager.phase == TimeManager.Phase.DAY, "tempo sincronizado (dia %d, fase %d)" % [TimeManager.day, TimeManager.phase])
	var bm := world.get(&"build_manager") as BuildManager
	bm.start(Building.load_def(&"barricade"))
	await wait(0.3)
	bm.set(&"_target", Vector3(6, 0, 16))
	bm.confirm()
	check(await wait_until(func() -> bool: return get_tree().get_nodes_in_group("buildings").size() > 0, 10.0), "construção replicada de volta ao cliente")
	bm.cancel()
	await wait_step("soldier_sent")
	check(await wait_until(func() -> bool: return Soldier.all.any(func(so: Soldier) -> bool: return so.puppet), 8.0), "soldado do anfitrião aparece no cliente")
	var where := hero.global_position
	hero.health.invulnerable = false
	var kill := DamageInfo.make(999999, null)
	kill.type = DamageInfo.Type.TRUE
	hero.take_damage(kill)
	check(hero.health.dead, "herói do cliente caiu")
	step.rpc_id(1, "client_down")
	check(await wait_until(func() -> bool: return not hero.health.dead, 20.0), "cliente foi revivido pelo anfitrião")
	check(hero.global_position.distance_to(where) < 2.5 and hero.health.current <= hero.health.max_health * 0.5, "levanta no lugar com parte da vida (%.0f/%.0f)" % [hero.health.current, hero.health.max_health])
	step.rpc_id(1, "client_done")
