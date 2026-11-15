extends Node
## Pesquisa de tecnologias (autoload "Tech"): uma pesquisa por vez, com custo e tempo;
## ao concluir, os efeitos somam em torres, muros, coleta, saque, herói e Forja.
## Também cuida dos efeitos contínuos: reparo automático e produção dos coletores.

signal researched(def: TechDef)
signal changed

const DIR := "res://data/tech/"
const INCOME_INTERVAL := 20.0
const INCOME := {&"wood": 3, &"stone": 2, &"scrap": 1}

var defs: Array[TechDef] = []
var done: Dictionary = {}  # id -> true
var active: StringName = &""
var progress: float = 0.0
var _income_t: float = INCOME_INTERVAL

func _ready() -> void:
	var dir := DirAccess.open(DIR)
	if dir:
		for f in dir.get_files():
			var file := f.trim_suffix(".remap")
			if file.ends_with(".tres"):
				var d := load(DIR + file) as TechDef
				if d:
					defs.append(d)
	defs.sort_custom(func(a: TechDef, b: TechDef) -> bool: return a.branch < b.branch or (a.branch == b.branch and a.min_wave < b.min_wave))

func reset() -> void:
	done.clear()
	active = &""
	progress = 0.0
	_income_t = INCOME_INTERVAL
	_apply_now()
	changed.emit()

func get_def(id: StringName) -> TechDef:
	for d in defs:
		if d.id == id:
			return d
	return null

func has(id: StringName) -> bool:
	return done.has(id)

## Soma de um efeito em todas as tecnologias concluídas.
func bonus(key: String) -> float:
	var t := 0.0
	for id: StringName in done:
		var d := get_def(id)
		if d:
			t += float(d.effects.get(key, 0.0))
	return t

func active_def() -> TechDef:
	return get_def(active) if active != &"" else null

func ratio() -> float:
	var d := active_def()
	return progress / maxf(0.01, d.research_time) if d else 0.0

## "" se pode pesquisar; senão o motivo.
func block_reason(d: TechDef) -> String:
	if has(d.id):
		return "Concluída."
	if active == d.id:
		return "Pesquisando..."
	if active != &"":
		return "Já há uma pesquisa em andamento."
	if TimeManager.wave() < d.min_wave:
		return "Libera na horda %d." % d.min_wave
	for r in d.requires:
		if not has(r):
			var rd := get_def(r)
			return "Requer: %s." % (rd.display_name if rd else String(r))
	if not ResourceManager.can_afford(d.cost):
		return "Faltam recursos: " + ResourceManager.cost_to_string(d.cost)
	return ""

func start(d: TechDef, remote: bool = false) -> String:
	if Coop.is_client():
		var why0 := block_reason(d)
		if why0 != "":
			return why0
		Coop.request("research", [String(d.id)])
		return "Pedido de pesquisa enviado ao anfitrião."
	if not remote and not BaseZone.hero_inside:
		return "Volte para a base para pesquisar."
	var why := block_reason(d)
	if why != "":
		return why
	ResourceManager.spend(d.cost)
	active = d.id
	progress = 0.0
	AudioManager.play(&"build", -2.0)
	changed.emit()
	return "Pesquisa iniciada: %s (%ds)." % [d.display_name, int(d.research_time)]

## Cancela e devolve metade do custo.
func cancel() -> String:
	if Coop.is_client():
		Coop.request("cancel_research")
		return "Pedido de cancelamento enviado."
	var d := active_def()
	if d == null:
		return ""
	for id: StringName in d.cost:
		ResourceManager.storage.add(id, int(d.cost[id]) / 2)
	active = &""
	progress = 0.0
	changed.emit()
	return "Pesquisa cancelada (metade dos recursos devolvida)."

func complete(d: TechDef) -> void:
	done[d.id] = true
	if active == d.id:
		active = &""
		progress = 0.0
	_apply_now()
	researched.emit(d)
	changed.emit()
	EventBus.banner.emit("PESQUISA CONCLUÍDA", d.display_name + " — " + d.description, Color(0.45, 0.85, 1.0))
	AudioManager.play(&"levelup")

## Reaplica efeitos que mudam atributos já calculados (vida das estruturas, herói).
func _apply_now() -> void:
	if not is_inside_tree():
		return
	get_tree().call_group("structures", "refresh_stats")
	var h := GameManager.hero
	if h and h.has_method(&"refresh_tech"):
		h.call(&"refresh_tech")

func _process(delta: float) -> void:
	if not GameManager.is_playing():
		return
	var d := active_def()
	if Coop.is_client():
		# Cliente: só mostra o progresso; quem conclui é o anfitrião.
		if d:
			progress = minf(progress + delta, d.research_time - 0.05)
		return
	if d:
		progress += delta
		if progress >= d.research_time:
			complete(d)
	var horde := TimeManager.phase == TimeManager.Phase.NIGHT
	# Pedreiros: estruturas se consertam fora da horda.
	var regen := bonus("struct_regen")
	if regen > 0.0 and not horde:
		for n in get_tree().get_nodes_in_group("structures"):
			var s := n as Structure
			if s and not s.is_dead() and s.health.current < s.health.max_health:
				s.health.heal(s.health.max_health * regen * delta)
	# Coletores: os sobreviventes produzem recursos durante a preparação.
	if bonus("passive_income") > 0.0 and not horde:
		_income_t -= delta
		if _income_t <= 0.0:
			_income_t = INCOME_INTERVAL
			var mult := int(bonus("passive_income"))
			var parts: Array[String] = []
			for id: StringName in INCOME:
				ResourceManager.storage.add(id, int(INCOME[id]) * mult)
				parts.append("+%d %s" % [int(INCOME[id]) * mult, ResourceManager.item_name(id)])
			var core := GameManager.base_core as Node3D
			if core:
				EffectsHub.float_text(core.global_position + Vector3.UP * 6.0, "Coletores: " + ", ".join(parts), Color(0.6, 1.0, 0.6), 34)

func to_save() -> Dictionary:
	return {"done": done.keys().map(func(k: StringName) -> String: return String(k)), "active": String(active), "progress": progress}

func from_save(d: Dictionary) -> void:
	reset()
	for k: String in d.get("done", []):
		done[StringName(k)] = true
	active = StringName(str(d.get("active", "")))
	progress = float(d.get("progress", 0.0))
	_apply_now()
	changed.emit()
