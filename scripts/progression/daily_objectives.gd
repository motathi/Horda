class_name DailyObjectives
extends Node
## Objetivos do dia: metas curtas que incentivam explorar e se preparar para a
## noite. Renovados a cada amanhecer; recompensas vão para o armazém da base.

var objectives: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	EventBus.enemy_killed.connect(_on_kill)
	EventBus.item_picked_up.connect(_on_pickup)
	EventBus.container_looted.connect(func(_c: Node3D) -> void: _progress("loot", "", 1))
	EventBus.building_placed.connect(func(_b: Node3D) -> void: _progress("build", "", 1))
	TimeManager.phase_changed.connect(_on_phase)
	generate(TimeManager.day)

func generate(day: int) -> void:
	_rng.seed = hash(day * 7919 + GameManager.world_seed)
	# Metas curtas: cabem em uma rodada (2 min de preparação + a horda).
	var r := 1.0 + minf(day, 60) * 0.05  # recompensas crescem com as hordas
	var pool: Array[Dictionary] = [
		_make("kill", "", "Elimine %d zumbis", mini(5 + day, 40), _rw({&"herbs": 3, &"cloth": 3}, r)),
		_make("collect", "wood", "Colete %d de Madeira", mini(10 + day * 2, 60), _rw({&"scrap": 4, &"stone": 3}, r)),
		_make("collect", "stone", "Colete %d de Pedra", mini(6 + day, 40), _rw({&"scrap": 3, &"wood": 6}, r)),
		_make("loot", "", "Saqueie %d locais", mini(2 + day / 4, 6), _rw({&"herbs": 2, &"cloth": 4}, r)),
		_make("collect", "scrap", "Colete %d de Sucata", mini(4 + day, 40), _rw({&"stone": 4, &"wood": 6}, r)),
		_make("build", "", "Construa %d defesas", mini(1 + day / 5, 4), _rw({&"scrap": 4, &"stone": 4}, r)),
	]
	objectives.clear()
	for i in 2:
		objectives.append(pool.pop_at(_rng.randi() % pool.size()))
	objectives.append(_make("return", "", "Esteja na base quando a horda chegar", 1, _rw({&"wood": 8, &"stone": 4}, r)))
	EventBus.objectives_changed.emit()

func _rw(base: Dictionary, mult: float) -> Dictionary:
	var out := {}
	for id in base:
		out[id] = int(round(int(base[id]) * mult))
	return out

func _make(kind: String, item: String, fmt: String, target: int, reward: Dictionary) -> Dictionary:
	return {"kind": kind, "item": item, "text": fmt % target if fmt.contains("%d") else fmt, "target": target, "progress": 0, "done": false, "reward": reward}

func _on_kill(_e: Node3D, _d: EnemyDef, killer: Node) -> void:
	if killer is Hero:
		_progress("kill", "", 1)

func _on_pickup(id: StringName, amount: int) -> void:
	_progress("collect", String(id), amount)

func _on_phase(phase: int, day: int) -> void:
	if phase == TimeManager.Phase.NIGHT and BaseZone.hero_inside:
		_progress("return", "", 1)
	elif phase == TimeManager.Phase.DAWN:
		generate(day)

func _progress(kind: String, item: String, amount: int) -> void:
	var changed := false
	for o in objectives:
		if o.done or o.kind != kind or (item != "" and o.item != item) or (item == "" and o.item != ""):
			continue
		o.progress = mini(int(o.progress) + amount, int(o.target))
		changed = true
		if o.progress >= o.target:
			o.done = true
			_reward(o)
	if changed:
		EventBus.objectives_changed.emit()

func _reward(o: Dictionary) -> void:
	var r: Dictionary = o.reward
	for id in r:
		ResourceManager.storage.add(StringName(id), int(r[id]))
	EventBus.notify("Objetivo concluído: %s! Recompensa no armazém: %s" % [o.text, ResourceManager.cost_to_string(r)], UIStyle.GOLD)
	AudioManager.play(&"objective")

func to_save() -> Array:
	var out := []
	for o in objectives:
		var r := {}
		for id in o.reward:
			r[String(id)] = o.reward[id]
		var c: Dictionary = o.duplicate()
		c.reward = r
		out.append(c)
	return out

func from_save(arr: Array) -> void:
	if arr.is_empty():
		return
	objectives.clear()
	for o: Dictionary in arr:
		var r := {}
		for id: String in o.get("reward", {}):
			r[StringName(id)] = int(o.reward[id])
		objectives.append({"kind": str(o.kind), "item": str(o.item), "text": str(o.text), "target": int(o.target), "progress": int(o.progress), "done": bool(o.done), "reward": r})
	EventBus.objectives_changed.emit()
