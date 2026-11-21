extends Node
## Sincronização da partida cooperativa (autoload "Coop"). O anfitrião (peer 1) simula
## o mundo (zumbis, hordas, torres, tempo, armazém, pesquisas); os clientes recebem o
## estado e enviam ações. Cada jogador controla o próprio herói; os dos outros são
## "fantoches" (Hero.is_puppet) movidos pelo estado recebido.

const HERO_RATE := 1.0 / 15.0
const ENEMY_RATE := 1.0 / 10.0
const STRUCT_RATE := 0.5
const TIME_RATE := 1.0
const STORAGE_DEBOUNCE := 0.15

var world: Node = null
var remote_heroes: Dictionary = {}   # peer_id -> Hero (fantoche)
var enemies: Dictionary = {}         # net_id -> Enemy
var pickups: Dictionary = {}         # net_id -> Node3D (ResourcePickup / GearPickup)
var soldiers: Dictionary = {}        # net_id -> Soldier
var _next_soldier: int = 1
var _next_enemy: int = 1
var _next_pickup: int = 1
var _t_hero: float = 0.0
var _t_enemy: float = 0.0
var _t_struct: float = 0.0
var _t_time: float = 0.0
var _storage_dirty: float = -1.0
var _struct_hp: Dictionary = {}      # nome -> último hp enviado
var _pending: Dictionary = {}        # ação -> Callable (respostas do anfitrião)

func active() -> bool:
	return Net.is_online() and Net.in_game

func is_client() -> bool:
	return active() and Net.is_client()

func is_host() -> bool:
	return active() and Net.is_host()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Chamado pelo World depois de gerar o mapa e o herói local.
func attach(w: Node) -> void:
	world = w
	remote_heroes.clear()
	enemies.clear()
	pickups.clear()
	soldiers.clear()
	_struct_hp.clear()
	_next_enemy = 1
	_next_pickup = 1
	if not active():
		return
	var i := 1
	for pid: int in Net.players:
		if pid != Net.my_id():
			_spawn_puppet(pid, i)
		i += 1
	if is_host():
		var er: Node = w.get(&"enemies_root")
		er.child_entered_tree.connect(_on_enemy_added)
		ResourceManager.storage.changed.connect(func() -> void: _storage_dirty = STORAGE_DEBOUNCE)
		Tech.changed.connect(_send_tech)
		(w.get(&"army") as Army).changed.connect(func() -> void: army_state(int((w.get(&"army") as Army).order)))
		EventBus.horde_started.connect(func(n: int, total: int) -> void: _event.rpc("horde_started", [n, total]))
		EventBus.horde_ended.connect(func(n: int) -> void: _event.rpc("horde_ended", [n]))
		EventBus.horde_progress.connect(func(r: int, t: int) -> void: _event.rpc("horde_progress", [r, t]))
		EventBus.victory.connect(func() -> void: _event.rpc("victory", []))
		EventBus.base_core_destroyed.connect(func() -> void: _event.rpc("core_destroyed", []))
		TimeManager.phase_changed.connect(func(_p: int, _d: int) -> void: _send_time())
		Tech.researched.connect(func(d: TechDef) -> void: _event.rpc("tech_done", [String(d.id)]))
		TimeManager.night_warning.connect(func(sec: float) -> void: _event.rpc("night_warning", [sec]))
		_storage_dirty = 0.01
	else:
		TimeManager.running = false

func detach() -> void:
	world = null
	remote_heroes.clear()
	enemies.clear()
	pickups.clear()
	soldiers.clear()

func remove_player(pid: int) -> void:
	var h := remote_heroes.get(pid) as Node
	if h and is_instance_valid(h):
		h.queue_free()
	remote_heroes.erase(pid)

func local_hero() -> Hero:
	return GameManager.hero as Hero

# --- Laço ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not active() or world == null or not is_instance_valid(world) or not GameManager.is_playing():
		return
	_t_hero -= delta
	if _t_hero <= 0.0:
		_t_hero = HERO_RATE
		_send_hero()
	if is_host():
		_t_enemy -= delta
		if _t_enemy <= 0.0:
			_t_enemy = ENEMY_RATE
			_send_enemies()
			_send_soldiers()
		_t_struct -= delta
		if _t_struct <= 0.0:
			_t_struct = STRUCT_RATE
			_send_structures()
		_t_time -= delta
		if _t_time <= 0.0:
			_t_time = TIME_RATE
			_send_time()
		if _storage_dirty > 0.0:
			_storage_dirty -= delta
			if _storage_dirty <= 0.0:
				_storage.rpc(ResourceManager.storage.to_dict())
	else:
		# Relógio do cliente avança entre as atualizações do anfitrião (contagem suave).
		TimeManager.phase_time += delta

# --- Heróis ---------------------------------------------------------------------------

func _spawn_puppet(pid: int, index: int) -> void:
	var scene := load("res://scenes/player/hero.tscn") as PackedScene
	var h := scene.instantiate() as Hero
	h.is_puppet = true
	h.net_peer = pid
	h.skin_override = Net.player_skin(pid)
	h.name = "Hero_%d" % pid
	world.add_child(h)
	h.global_position = Vector3(index * 1.5, 0, 5)
	remote_heroes[pid] = h
	print("[coop] jogador %d (%s) na partida" % [pid, Net.player_name(pid)])

func _send_hero() -> void:
	var h := local_hero()
	if h == null:
		return
	_hero_state.rpc(h.global_position, h.model.rotation.y, Vector2(h.velocity.x, h.velocity.z).length() / maxf(0.1, h.current_move_speed()),
		h.health.current, h.health.max_health, h.health.dead, h.net_attack_count, h.level)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _hero_state(pos: Vector3, yaw: float, speed: float, hp: float, max_hp: float, dead: bool, atk: int, lvl: int) -> void:
	var h := remote_heroes.get(multiplayer.get_remote_sender_id()) as Hero
	if h and is_instance_valid(h):
		h.apply_net_state(pos, yaw, speed, hp, max_hp, dead, atk, lvl)

## Anfitrião: um zumbi acertou o fantoche de outro jogador → o dono aplica o dano.
func forward_hero_hit(pid: int, info: DamageInfo) -> void:
	if pid == Net.my_id():
		return
	_hero_hit.rpc_id(pid, info.amount, info.type == DamageInfo.Type.TRUE, info.from_melee)

@rpc("authority", "call_remote", "reliable")
func _hero_hit(amount: float, true_damage: bool, melee: bool) -> void:
	var h := local_hero()
	if h == null:
		return
	var info := DamageInfo.make(amount, null)
	info.from_melee = melee
	if true_damage:
		info.type = DamageInfo.Type.TRUE
	h.take_damage(info)

## Um jogador terminou de reviver o herói caído de `pid`: o dono do herói o levanta no lugar.
func request_revive(pid: int) -> void:
	if pid == Net.my_id():
		return
	_revive_me.rpc_id(pid, Net.my_name)

@rpc("any_peer", "call_remote", "reliable")
func _revive_me(by: String) -> void:
	var h := local_hero()
	if h:
		h.revive_here(by)

# --- Inimigos ---------------------------------------------------------------------------

func _on_enemy_added(n: Node) -> void:
	if n is Enemy and not (n as Enemy).puppet:
		# configure() é chamado logo depois de add_child: anuncia no quadro seguinte.
		_announce_enemy.call_deferred(n)

func _announce_enemy(e: Enemy) -> void:
	if not is_instance_valid(e) or e.is_dead() or e.def == null:
		return
	if not e.has_meta(&"net_id"):
		e.set_meta(&"net_id", _next_enemy)
		_next_enemy += 1
	var id := int(e.get_meta(&"net_id"))
	enemies[id] = e
	var flags := (1 if e.is_elite else 0) | (2 if e.is_boss else 0) | (4 if e.is_horde else 0) | (8 if e.is_guardian else 0)
	_enemy_spawn.rpc(id, e.def.resource_path, e.global_position, e.health.max_health, flags, e.boss_title)

@rpc("authority", "call_remote", "reliable")
func _enemy_spawn(id: int, def_path: String, pos: Vector3, max_hp: float, flags: int, title: String) -> void:
	if world == null or enemies.has(id):
		return
	var e := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
	e.puppet = true
	e.def = load(def_path) as EnemyDef
	e.set_meta(&"net_id", id)
	(world.get(&"enemies_root") as Node).add_child(e)
	e.global_position = pos
	if flags & 8:
		e.make_guardian(title)
	elif flags & 2:
		e.make_boss(title)
	elif flags & 1:
		e.make_elite()
	e.is_horde = (flags & 4) != 0
	e.health.max_health = max_hp
	e.health.current = max_hp
	e.puppet_target = pos
	enemies[id] = e

func _send_enemies() -> void:
	var data := PackedFloat32Array()
	for id: int in enemies.keys():
		var e := enemies[id] as Enemy
		if not is_instance_valid(e) or e.is_dead():
			enemies.erase(id)
			continue
		data.append_array([float(id), e.global_position.x, e.global_position.y, e.global_position.z, e.model.rotation.y,
			e.health.current, Vector2(e.velocity.x, e.velocity.z).length() / maxf(0.1, e.def.move_speed), float(e.net_attack_count)])
	if not data.is_empty():
		_enemy_snap.rpc(data)

@rpc("authority", "call_remote", "unreliable_ordered")
func _enemy_snap(data: PackedFloat32Array) -> void:
	for i in range(0, data.size(), 8):
		var e := enemies.get(int(data[i])) as Enemy
		if e and is_instance_valid(e) and not e.is_dead():
			e.apply_net_state(Vector3(data[i + 1], data[i + 2], data[i + 3]), data[i + 4], data[i + 5], data[i + 6], int(data[i + 7]))

## Anfitrião: inimigo morreu (killer_peer = jogador que matou, 0 = ninguém/torre).
func enemy_died(e: Enemy, killer: Node) -> void:
	if not is_host() or not e.has_meta(&"net_id"):
		return
	var kp := 0
	if killer is Hero:
		kp = (killer as Hero).net_peer
	elif killer is Soldier:
		kp = -1
	_enemy_died.rpc(int(e.get_meta(&"net_id")), kp)
	enemies.erase(int(e.get_meta(&"net_id")))

@rpc("authority", "call_remote", "reliable")
func _enemy_died(id: int, killer_peer: int) -> void:
	var e := enemies.get(id) as Enemy
	enemies.erase(id)
	if e and is_instance_valid(e):
		if killer_peer == -1:
			e.set_meta(&"soldier_kill", true)
		e.puppet_die(local_hero() if killer_peer == Net.my_id() else null)

## Anfitrião: inimigo retirado do mapa sem morrer (economia de memória no celular): some também nos clientes.
func enemy_removed(e: Enemy) -> void:
	if not is_host() or not e.has_meta(&"net_id"):
		return
	enemies.erase(int(e.get_meta(&"net_id")))
	_enemy_removed.rpc(int(e.get_meta(&"net_id")))

@rpc("authority", "call_remote", "reliable")
func _enemy_removed(id: int) -> void:
	var e := enemies.get(id) as Enemy
	enemies.erase(id)
	if e and is_instance_valid(e):
		e.queue_free()

## Golpe de um jogador num inimigo. No anfitrião aplica; no cliente envia ao anfitrião.
func hit_enemy(e: Enemy, amount: float, crit: bool, stun: float = 0.0) -> void:
	if not e.has_meta(&"net_id"):
		return
	_hit_enemy.rpc_id(1, int(e.get_meta(&"net_id")), amount, crit, stun)

@rpc("any_peer", "call_remote", "reliable")
func _hit_enemy(id: int, amount: float, crit: bool, stun: float) -> void:
	if not is_host():
		return
	var e := enemies.get(id) as Enemy
	if e == null or not is_instance_valid(e) or e.is_dead():
		return
	var src := remote_heroes.get(multiplayer.get_remote_sender_id()) as Node
	if stun > 0.0:
		e.stun(stun)
	if amount > 0.0:
		e.take_damage(DamageInfo.make(amount, src, crit))

# --- Efeitos visuais (anfitrião → clientes) -------------------------------------------------

func fx(kind: String, a: Vector3, b: Vector3 = Vector3.ZERO, f: float = 0.0, c: Color = Color.WHITE) -> void:
	if is_host():
		_fx.rpc(kind, a, b, f, c)

## Efeito visual de qualquer jogador para os outros (flechas, armadilhas, águia do Caçador).
func fx_all(kind: String, a: Vector3, b: Vector3 = Vector3.ZERO, f: float = 0.0, c: Color = Color.WHITE) -> void:
	if active():
		_fx_any.rpc(kind, a, b, f, c)

@rpc("any_peer", "call_remote", "unreliable")
func _fx_any(kind: String, a: Vector3, b: Vector3, f: float, c: Color) -> void:
	_fx(kind, a, b, f, c)

@rpc("authority", "call_remote", "unreliable")
func _fx(kind: String, a: Vector3, b: Vector3, f: float, c: Color) -> void:
	match kind:
		"explosion": EffectsHub.spawn_explosion(a, f, c)
		"ring": EffectsHub.spawn_ring(a, f, c, 0.4)
		"scream":
			EffectsHub.spawn_ring(a + Vector3.UP * 0.2, f * 0.6, Color(c, 0.45), 0.7)
			AudioManager.play_3d(&"scream", a, 6.0, 1.1)
		"bolt": EffectsHub.spawn_bolt(a, b, f)
		"lightning": EffectsHub.spawn_lightning(PackedVector3Array([a, b]))
		"lob": EffectsHub.spawn_lob(a, b, f, 4.0, func() -> void: EffectsHub.spawn_explosion(b, 3.0, Color(1.0, 0.55, 0.15)))
		"acid":
			var p := AcidProjectile.new()
			p.visual_only = true
			p.color = c
			p.puddle_radius = f
			world.add_child(p)
			p.setup(a, b)
		"arrow": EffectsHub.spawn_bolt(a, b, 40.0, f > 0.5)
		"whirlwind": SkillFx.whirlwind(a, f, b.x)
		"warcry": SkillFx.warcry(a)
		"nova_t": SkillFx.nova_telegraph(a, f, b.x)
		"nova": SkillFx.nova_burst(a, f)
		"tpulse": SkillFx.tower_pulse(a, f, b.x)
		"trap":
			var trap := BearTrap.new()
			trap.visual_only = true
			trap.owner_hero = _hero_near(a)
			EffectsHub.instance().add_child(trap)
			trap.global_position = a
		"arrow_rain":
			var rain := ArrowRain.new()
			rain.visual_only = true
			rain.radius = b.x
			rain.duration = b.y
			EffectsHub.instance().add_child(rain)
			rain.global_position = a
		"eagle":
			var eg := Eagle.new()
			eg.visual_only = true
			eg.owner_hero = _hero_near(a)
			eg.lifetime = b.x
			eg.hunt_radius = b.y
			eg.reveal_radius = b.z
			EffectsHub.instance().add_child(eg)
	if kind in ["explosion", "lob"]:
		AudioManager.play_3d(&"explosion", b if kind == "lob" else a, 0.0)
	elif kind == "lightning":
		AudioManager.play_3d(&"zap", a, -4.0)

## Herói (de qualquer jogador) mais perto de um ponto — dono dos efeitos recebidos.
func _hero_near(p: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for h: Node in get_tree().get_nodes_in_group(&"hero"):
		var d := (h as Node3D).global_position.distance_squared_to(p)
		if d < bd:
			bd = d
			best = h as Node3D
	return best

# --- Saques no chão ------------------------------------------------------------------------

## Anfitrião: cria um saque compartilhado (todos veem; o primeiro a pegar leva).
func host_drop(pos: Vector3, item_id: StringName, amount: int) -> void:
	var id := _next_pickup
	_next_pickup += 1
	_drop.rpc(id, pos, String(item_id), amount, {})
	_drop(id, pos, String(item_id), amount, {})

func host_drop_gear(pos: Vector3, item: GearItem) -> void:
	var id := _next_pickup
	_next_pickup += 1
	_drop.rpc(id, pos, "", 0, item.to_dict())
	_drop(id, pos, "", 0, item.to_dict())

@rpc("authority", "call_remote", "reliable")
func _drop(id: int, pos: Vector3, item_id: String, amount: int, gear: Dictionary) -> void:
	var node: Node3D = null
	if gear.is_empty():
		node = EffectsHub.spawn_pickup_local(pos, StringName(item_id), amount)
	else:
		var g := GearItem.from_dict(gear)
		if g:
			node = EffectsHub.spawn_gear_local(pos, g)
	if node:
		node.set_meta(&"net_id", id)
		pickups[id] = node

## Qualquer jogador tocou num saque compartilhado.
func claim_pickup(node: Node3D) -> void:
	var id := int(node.get_meta(&"net_id"))
	if is_host():
		_resolve_claim(id, 1)
	else:
		_claim.rpc_id(1, id)

@rpc("any_peer", "call_remote", "reliable")
func _claim(id: int) -> void:
	if is_host():
		_resolve_claim(id, multiplayer.get_remote_sender_id())

func _resolve_claim(id: int, who: int) -> void:
	var node := pickups.get(id) as Node3D
	if node == null or not is_instance_valid(node):
		return
	pickups.erase(id)
	var item_id := ""
	var amount := 0
	var gear := {}
	if node is ResourcePickup:
		item_id = String((node as ResourcePickup).item_id)
		amount = (node as ResourcePickup).amount
	elif node is GearPickup:
		gear = (node as GearPickup).item.to_dict()
	_remove_pickup.rpc(id)
	_remove_pickup(id)
	if who == 1:
		_grant(item_id, amount, gear)
	else:
		_grant.rpc_id(who, item_id, amount, gear)

@rpc("authority", "call_remote", "reliable")
func _remove_pickup(id: int) -> void:
	var node := pickups.get(id) as Node3D
	pickups.erase(id)
	if node and is_instance_valid(node):
		if node is ResourcePickup:
			(node as ResourcePickup).release_net()
		else:
			node.queue_free()

@rpc("authority", "call_remote", "reliable")
func _grant(item_id: String, amount: int, gear: Dictionary) -> void:
	var h := local_hero()
	if h == null:
		return
	if not gear.is_empty():
		var g := GearItem.from_dict(gear)
		if g and h.add_gear(g):
			EffectsHub.float_text(h.global_position + Vector3.UP * 2.6, "%s %s" % [g.display_name(), g.rarity_name()], g.color(), 40)
			AudioManager.play(&"objective", -2.0)
		return
	var got := ResourceManager.give_hero(StringName(item_id), amount)
	if got > 0:
		EffectsHub.float_text(h.global_position + Vector3.UP * 2.4, "+%d %s" % [got, ResourceManager.item_name(StringName(item_id))], ResourceManager.get_def(StringName(item_id)).color)
		AudioManager.play_3d(&"pickup", h.global_position, -6.0)
	if got < amount:
		EffectsHub.drop_item(h.global_position, StringName(item_id), amount - got)

# --- Árvores, rochas e contêineres ----------------------------------------------------------

func harvest(node_id: String) -> void:
	if is_host():
		_harvest_state.rpc(node_id, _harvest_hits(node_id))
	else:
		_harvest.rpc_id(1, node_id)

@rpc("any_peer", "call_remote", "reliable")
func _harvest(node_id: String) -> void:
	if not is_host():
		return
	var h := (world.get(&"builder") as WorldBuilder).harvestables.get(node_id) as Harvestable
	if h:
		h.remote_hit()
		_harvest_state.rpc(node_id, h.hits_left())

func _harvest_hits(node_id: String) -> int:
	var h := (world.get(&"builder") as WorldBuilder).harvestables.get(node_id) as Harvestable
	return h.hits_left() if h else 0

@rpc("authority", "call_remote", "reliable")
func _harvest_state(node_id: String, hits_left: int) -> void:
	var h := (world.get(&"builder") as WorldBuilder).harvestables.get(node_id) as Harvestable
	if h:
		h.set_hits_left(hits_left)

func looted(node_id: String, restock_day: int) -> void:
	if is_host():
		_looted.rpc(node_id, restock_day)
	else:
		_looted_req.rpc_id(1, node_id, restock_day)

@rpc("any_peer", "call_remote", "reliable")
func _looted_req(node_id: String, restock_day: int) -> void:
	if is_host():
		_looted(node_id, restock_day)
		_looted.rpc(node_id, restock_day)

@rpc("authority", "call_remote", "reliable")
func _looted(node_id: String, restock_day: int) -> void:
	var l := (world.get(&"builder") as WorldBuilder).lootables.get(node_id) as Lootable
	if l and not l.looted:
		l.restore_looted(restock_day)

# --- Construções e estruturas ---------------------------------------------------------------

func building_placed(b: Building) -> void:
	if is_host():
		_building_placed.rpc(String(b.def.id), b.global_position, b.rotation.y, b.level, b.name)

@rpc("authority", "call_remote", "reliable")
func _building_placed(def_id: String, pos: Vector3, rot: float, lvl: int, node_name: String) -> void:
	var bm := world.get(&"build_manager") as BuildManager
	var b := bm.place(Building.load_def(StringName(def_id)), pos, rot, false, lvl)
	if b:
		b.name = node_name
		AudioManager.play_3d(&"build", b.global_position)

func building_changed(b: Building, removed: bool) -> void:
	if is_host():
		_building_changed.rpc(b.name, b.level, b.branch, removed)

@rpc("authority", "call_remote", "reliable")
func _building_changed(node_name: String, lvl: int, br: String, removed: bool) -> void:
	var b := _find_building(node_name)
	if b == null:
		return
	if removed:
		b.queue_free()
	else:
		b.apply_level(lvl, br)

func _find_building(node_name: String) -> Building:
	for n in get_tree().get_nodes_in_group("buildings"):
		if n.name == node_name:
			return n as Building
	return null

func _structures() -> Array[Structure]:
	var out: Array[Structure] = []
	for n in get_tree().get_nodes_in_group("structures"):
		if n is Structure and not n.is_queued_for_deletion():
			out.append(n)
	return out

func _send_structures() -> void:
	var names := PackedStringArray()
	var hps := PackedFloat32Array()
	for s in _structures():
		var hp := 0.0 if s.health.dead else s.health.current
		if absf(float(_struct_hp.get(s.name, -1.0)) - hp) > 0.5:
			_struct_hp[s.name] = hp
			names.append(s.name)
			hps.append(hp)
	if not names.is_empty():
		_struct_snap.rpc(names, hps)

@rpc("authority", "call_remote", "reliable")
func _struct_snap(names: PackedStringArray, hps: PackedFloat32Array) -> void:
	var by_name := {}
	for s in _structures():
		by_name[String(s.name)] = s
	for i in names.size():
		var s := by_name.get(names[i]) as Structure
		if s:
			s.apply_net_hp(hps[i])

# --- Armazém, tempo, pesquisas e eventos ----------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _storage(d: Dictionary) -> void:
	ResourceManager.storage.from_dict(d)

## Cliente: recursos entraram no armazém (depósito, desmontar, objetivos...).
func sync_store(id: StringName, n: int) -> void:
	if is_client() and n > 0:
		_store.rpc_id(1, String(id), n)

@rpc("any_peer", "call_remote", "reliable")
func _store(id: String, n: int) -> void:
	if is_host():
		ResourceManager.storage.add(StringName(id), n)

## Cliente: gastou do armazém (o anfitrião desconta também).
func sync_spend(cost: Dictionary) -> void:
	if is_client() and not cost.is_empty():
		var d := {}
		for k: StringName in cost:
			d[String(k)] = int(cost[k])
		_spend.rpc_id(1, d)

@rpc("any_peer", "call_remote", "reliable")
func _spend(d: Dictionary) -> void:
	if not is_host():
		return
	for k: String in d:
		ResourceManager.storage.remove(StringName(k), int(d[k]))

func _send_time() -> void:
	_time.rpc(TimeManager.phase, TimeManager.day, TimeManager.phase_time)

@rpc("authority", "call_remote", "reliable")
func _time(phase: int, day: int, t: float) -> void:
	if phase != TimeManager.phase or day != TimeManager.day:
		TimeManager.set_state(phase, day, t)
	else:
		TimeManager.phase_time = t

func _send_tech() -> void:
	_tech.rpc(Tech.to_save())

@rpc("authority", "call_remote", "reliable")
func _tech(d: Dictionary) -> void:
	var before := Tech.done.size()
	Tech.from_save(d)
	if Tech.done.size() != before:
		var h := local_hero()
		if h:
			h.refresh_tech()

func banner_all(title: String, sub: String, color: Color) -> void:
	EventBus.banner.emit(title, sub, color)
	if is_host():
		_event.rpc("banner", [title, sub, color])

@rpc("authority", "call_remote", "reliable")
func _event(kind: String, args: Array) -> void:
	match kind:
		"horde_started": EventBus.horde_started.emit(int(args[0]), int(args[1]))
		"horde_ended": EventBus.horde_ended.emit(int(args[0]))
		"horde_progress": EventBus.horde_progress.emit(int(args[0]), int(args[1]))
		"banner": EventBus.banner.emit(str(args[0]), str(args[1]), args[2] as Color)
		"victory": GameManager.victory()
		"night_warning": TimeManager.night_warning.emit(float(args[0]))
		"core_destroyed": EventBus.base_core_destroyed.emit()
		"tech_done":
			var d := Tech.get_def(StringName(str(args[0])))
			if d:
				EventBus.banner.emit("PESQUISA CONCLUÍDA", d.display_name + " — " + d.description, Color(0.45, 0.85, 1.0))
				AudioManager.play(&"levelup")

# --- Pedidos ao anfitrião (ações compartilhadas) ---------------------------------------------

## Cliente pede uma ação ao anfitrião; on_reply(mensagem) é chamado com a resposta.
func request(action: String, args: Array = [], on_reply: Callable = Callable()) -> void:
	if on_reply.is_valid():
		_pending[action] = on_reply
	_request.rpc_id(1, action, args)

@rpc("any_peer", "call_remote", "reliable")
func _request(action: String, args: Array) -> void:
	if not is_host():
		return
	var who := multiplayer.get_remote_sender_id()
	var msg := ""
	var w := world
	match action:
		"build":
			var bm := w.get(&"build_manager") as BuildManager
			var d := Building.load_def(StringName(str(args[0])))
			var why := bm.check(d, args[1], float(args[2]), true)
			if why != "":
				msg = why
			else:
				var b := bm.place(d, args[1], float(args[2]), true)
				msg = "%s construída." % d.display_name if b else "Recursos insuficientes."
		"upgrade":
			var b2 := _find_building(str(args[0]))
			msg = b2.upgrade() if b2 else "Construção não encontrada."
		"tower_branch":
			var b4 := _find_building(str(args[0]))
			msg = b4.choose_branch(str(args[1])) if b4 else "Construção não encontrada."
		"repair_one":
			var st: Structure = null
			for n in get_tree().get_nodes_in_group("structures"):
				if n.name == str(args[0]):
					st = n as Structure
			msg = st.repair_with_materials() if st else "Estrutura não encontrada."
		"demolish":
			var b3 := _find_building(str(args[0]))
			if b3:
				b3.demolish()
				msg = "Demolida."
		"repair_walls":
			msg = (w.get(&"services") as BaseServices).repair_walls(true)
		"repair_core":
			msg = (w.get(&"services") as BaseServices).repair_core(true)
		"research":
			msg = Tech.start(Tech.get_def(StringName(str(args[0]))), true)
		"cancel_research":
			msg = Tech.cancel()
		"call_horde":
			TimeManager.start_horde_now()
			msg = "Horda chamada!"
		"recruit":
			var army := w.get(&"army") as Army
			var sd := army.get_def(StringName(str(args[0])))
			msg = army.recruit(sd) if sd else "Tipo de soldado desconhecido."
		"army_order":
			msg = (w.get(&"army") as Army).set_order(int(args[0]), remote_heroes.get(who) as Node3D)
	_reply.rpc_id(who, action, msg)

@rpc("authority", "call_remote", "reliable")
func _reply(action: String, msg: String) -> void:
	var cb := _pending.get(action) as Callable
	_pending.erase(action)
	if cb and cb.is_valid():
		cb.call(msg)
	elif msg != "":
		EventBus.notify(msg, UIStyle.GOLD)

# --- Exército ----------------------------------------------------------------------------

func soldier_spawned(so: Soldier) -> void:
	if not is_host():
		return
	var id := _next_soldier
	_next_soldier += 1
	so.set_meta(&"net_id", id)
	soldiers[id] = so
	_soldier_spawn.rpc(id, String(so.def.id), so.global_position, so.health.max_health)

@rpc("authority", "call_remote", "reliable")
func _soldier_spawn(id: int, def_id: String, pos: Vector3, max_hp: float) -> void:
	if world == null or soldiers.has(id):
		return
	var army := world.get(&"army") as Army
	var d := army.get_def(StringName(def_id))
	if d == null:
		return
	var so := Army.SOLDIER_SCENE.instantiate() as Soldier
	so.def = d
	so.puppet = true
	so.army = army
	world.add_child(so)
	so.global_position = pos
	so.health.max_health = max_hp
	so.health.current = max_hp
	so.set_meta(&"net_id", id)
	soldiers[id] = so
	army.soldiers.append(so)
	army.changed.emit()

func soldier_died(so: Soldier) -> void:
	if is_host() and so.has_meta(&"net_id"):
		soldiers.erase(int(so.get_meta(&"net_id")))
		_soldier_died.rpc(int(so.get_meta(&"net_id")))

@rpc("authority", "call_remote", "reliable")
func _soldier_died(id: int) -> void:
	var so := soldiers.get(id) as Soldier
	soldiers.erase(id)
	if so and is_instance_valid(so):
		so.puppet_die()

func _send_soldiers() -> void:
	var data := PackedFloat32Array()
	for id: int in soldiers.keys():
		var so := soldiers[id] as Soldier
		if not is_instance_valid(so) or so.is_dead():
			soldiers.erase(id)
			continue
		data.append_array([float(id), so.global_position.x, so.global_position.y, so.global_position.z, so.model.rotation.y,
			so.health.current, Vector2(so.velocity.x, so.velocity.z).length() / maxf(0.1, so.def.move_speed), float(so.net_attack_count)])
	if not data.is_empty():
		_soldier_snap.rpc(data)

@rpc("authority", "call_remote", "unreliable_ordered")
func _soldier_snap(data: PackedFloat32Array) -> void:
	for i in range(0, data.size(), 8):
		var so := soldiers.get(int(data[i])) as Soldier
		if so and is_instance_valid(so) and not so.is_dead():
			so.apply_net_state(Vector3(data[i + 1], data[i + 2], data[i + 3]), data[i + 4], data[i + 5], data[i + 6], int(data[i + 7]))

## Anfitrião: ordem atual e fila de treino (para a interface dos clientes).
func army_state(o: int) -> void:
	if not is_host() or world == null:
		return
	var army := world.get(&"army") as Army
	_army_state.rpc(o, army.queue.map(func(q: Dictionary) -> Array: return [String((q["def"] as SoldierDef).id), float(q["t"])]))

@rpc("authority", "call_remote", "reliable")
func _army_state(o: int, q: Array) -> void:
	if world == null:
		return
	var army := world.get(&"army") as Army
	army.order = o as Army.Order
	army.queue.clear()
	for e: Array in q:
		var d := army.get_def(StringName(str(e[0])))
		if d:
			army.queue.append({"def": d, "t": float(e[1])})
	army.changed.emit()
