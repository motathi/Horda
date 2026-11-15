class_name Army
extends Node
## Exército da base: recrutamento nos Quartéis (fila de treino), capacidade,
## ordens (defender / seguir / caçar) e posições de cada soldado.

signal changed

enum Order { DEFEND, FOLLOW, HUNT }

const DEFS_DIR := "res://data/soldiers/"
const SOLDIER_SCENE := preload("res://scenes/army/soldier.tscn")
const PER_BARRACKS := 4
const PER_LEVEL := 2
const MAX_TOTAL := 12
const MAX_TOTAL_MOBILE := 8
const POST_RADIUS := 9.5
const ORDER_NAMES: Array[String] = ["Defender a base", "Seguir o herói", "Caçar zumbis"]

var defs: Array[SoldierDef] = []
var soldiers: Array[Soldier] = []
## Fila de treino: [{def, t}] (um de cada vez).
var queue: Array[Dictionary] = []
var order: Order = Order.DEFEND
## Herói que os soldados seguem (quem deu a ordem "Seguir").
var leader: Node3D = null
var parent_root: Node3D

func _ready() -> void:
	var dir := DirAccess.open(DEFS_DIR)
	if dir:
		for f in dir.get_files():
			var file := f.trim_suffix(".remap")
			if file.ends_with(".tres"):
				var d := load(DEFS_DIR + file) as SoldierDef
				if d:
					defs.append(d)
	defs.sort_custom(func(a: SoldierDef, b: SoldierDef) -> bool: return a.unlock_wave < b.unlock_wave)

func get_def(id: StringName) -> SoldierDef:
	for d in defs:
		if d.id == id:
			return d
	return null

func barracks() -> Array[Building]:
	var out: Array[Building] = []
	for n in get_tree().get_nodes_in_group("buildings"):
		var b := n as Building
		if b and not b.is_queued_for_deletion() and not b.health.dead and b.def.category == BuildingDef.Category.BARRACKS:
			out.append(b)
	return out

func capacity() -> int:
	var c := 0
	for b in barracks():
		c += PER_BARRACKS + PER_LEVEL * (b.level - 1)
	return mini(c, MAX_TOTAL_MOBILE if Platform.low_end else MAX_TOTAL)

func alive_count() -> int:
	soldiers = soldiers.filter(func(s: Soldier) -> bool: return is_instance_valid(s) and not s.is_dead())
	return soldiers.size()

## Nível médio dos quartéis (soldados ficam 15% mais fortes por nível).
func level_mult() -> float:
	var bs := barracks()
	if bs.is_empty():
		return 1.0
	var lv := 0
	for b in bs:
		lv = maxi(lv, b.level)
	return 1.0 + 0.15 * (lv - 1)

## "" se pode recrutar; senão o motivo.
func block_reason(d: SoldierDef) -> String:
	if barracks().is_empty():
		return "Construa um Quartel (menu Construir)."
	if TimeManager.wave() < d.unlock_wave:
		return "Libera na horda %d." % d.unlock_wave
	if alive_count() + queue.size() >= capacity():
		return "Exército no limite (%d). Construa ou melhore Quartéis." % capacity()
	if not ResourceManager.can_afford(d.cost):
		return "Faltam recursos: " + ResourceManager.cost_to_string(d.cost)
	return ""

func recruit(d: SoldierDef) -> String:
	if Coop.is_client():
		var why0 := block_reason(d)
		if why0 != "":
			return why0
		Coop.request("recruit", [String(d.id)])
		return "Pedido de recrutamento enviado ao anfitrião."
	var why := block_reason(d)
	if why != "":
		return why
	ResourceManager.spend(d.cost)
	queue.append({"def": d, "t": d.train_time})
	AudioManager.play(&"build", -4.0)
	changed.emit()
	return "%s em treinamento (%ds)." % [d.display_name, int(d.train_time)]

func set_order(o: int, who: Node3D = null) -> String:
	if Coop.is_client():
		Coop.request("army_order", [o])
		order = o as Order
		changed.emit()
		return "Ordem enviada: " + ORDER_NAMES[o]
	order = o as Order
	leader = who if who else GameManager.hero
	AudioManager.play(&"gong", -10.0, 1.6)
	changed.emit()
	Coop.army_state(order)
	return "Exército: " + ORDER_NAMES[o]

func cycle_order() -> String:
	return set_order((order + 1) % 3)

func _process(delta: float) -> void:
	if Coop.is_client() or not GameManager.is_playing() or queue.is_empty():
		return
	if barracks().is_empty():
		return
	var q: Dictionary = queue[0]
	q["t"] = float(q["t"]) - delta
	if float(q["t"]) <= 0.0:
		queue.pop_front()
		spawn(q["def"])
		changed.emit()

## Coloca um soldado treinado na porta de um quartel.
func spawn(d: SoldierDef, at: Variant = null, hp: float = -1.0) -> Soldier:
	var bs := barracks()
	var pos: Vector3 = Vector3(0, 0, 6)
	if at != null:
		pos = at
	elif not bs.is_empty():
		# Sai pelo lado do quartel voltado para a base.
		var b := bs[soldiers.size() % bs.size()]
		var to_core := -b.global_position
		to_core.y = 0.0
		to_core = to_core.normalized() if to_core.length() > 0.1 else Vector3(0, 0, -1)
		pos = b.global_position + to_core * (maxf(b.def.footprint.x, b.def.footprint.y) * 0.5 + 1.4) + to_core.rotated(Vector3.UP, PI * 0.5) * (soldiers.size() % 3 - 1) * 1.0
	var s := SOLDIER_SCENE.instantiate() as Soldier
	s.def = d
	s.army = self
	s.level_mult = level_mult()
	parent_root.add_child(s)
	s.global_position = pos
	if hp > 0.0:
		s.health.current = minf(hp, s.health.max_health)
	soldiers.append(s)
	_assign_posts()
	if at == null:
		EventBus.notify("%s pronto para lutar!" % d.display_name, Color(0.55, 0.85, 1.0))
		AudioManager.play_3d(&"ab_dash", pos, -6.0)
	Coop.soldier_spawned(s)
	return s

func on_soldier_died(s: Soldier) -> void:
	soldiers.erase(s)
	_assign_posts()
	Coop.soldier_died(s)
	EventBus.notify("%s caiu em combate." % s.def.display_name, Color(1, 0.55, 0.4))
	changed.emit()

## Postos de defesa espalhados num anel dentro da paliçada.
func _assign_posts() -> void:
	var list := soldiers.filter(func(s: Soldier) -> bool: return is_instance_valid(s) and not s.is_dead())
	for i in list.size():
		var a := i * TAU / maxi(1, list.size()) + 0.35
		(list[i] as Soldier).post = Vector3(sin(a) * POST_RADIUS, 0, -cos(a) * POST_RADIUS)

## Para onde cada soldado vai quando não está lutando.
func anchor_for(s: Soldier) -> Vector3:
	match order:
		Order.FOLLOW:
			var l := leader if is_instance_valid(leader) else GameManager.hero
			if l == null:
				return s.post
			var i := soldiers.find(s)
			var row := i / 3
			var col := i % 3 - 1
			var back := Vector3(col * 1.6, 0, 2.2 + row * 1.6)
			return l.global_position + back.rotated(Vector3.UP, (l as Node3D).rotation.y if l is Hero else 0.0)
		_:
			return s.post

func to_save() -> Dictionary:
	return {"order": order, "soldiers": soldiers.filter(func(s: Soldier) -> bool: return is_instance_valid(s) and not s.is_dead()).map(func(s: Soldier) -> Dictionary: return s.to_save()),
		"queue": queue.map(func(q: Dictionary) -> Dictionary: return {"id": String((q["def"] as SoldierDef).id), "t": q["t"]})}

func from_save(d: Dictionary) -> void:
	order = int(d.get("order", 0)) as Order
	for sd: Dictionary in d.get("soldiers", []):
		var def := get_def(StringName(sd.get("id", "")))
		var p: Array = sd.get("pos", [0, 6])
		if def:
			spawn(def, Vector3(p[0], 0, p[1]), float(sd.get("hp", -1.0)))
	queue.clear()
	for qd: Dictionary in d.get("queue", []):
		var def2 := get_def(StringName(qd.get("id", "")))
		if def2:
			queue.append({"def": def2, "t": float(qd.get("t", def2.train_time))})
	changed.emit()
