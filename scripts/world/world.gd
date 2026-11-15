class_name World
extends Node3D
## Cena principal da partida: gera o mapa, assa a navegação, posiciona o herói
## e conecta os sistemas (hordas, spawner, HUD, salvamento).

const HERO_SCENE := preload("res://scenes/player/hero.tscn")
const HERO_SPAWN := Vector3(0, 0, 5)

@onready var enemies_root: Node3D = $Enemies
@onready var camera_rig: CameraRig = $CameraRig
@onready var horde: HordeDirector = $HordeDirector
@onready var spawner: WorldSpawner = $WorldSpawner
@onready var services: BaseServices = $BaseServices
@onready var hud: HUD = $HUD
@onready var loading: CanvasLayer = $Loading
var objectives: DailyObjectives
var build_manager: BuildManager

var builder: WorldBuilder
var army: Army
var hero: Hero
var _nav_dirty: bool = false
var _ally_dirty: float = -1.0
var _ally_baking: bool = false

## Refaz a malha dos soldados (em segundo plano) quando construções mudam.
func bake_ally_nav() -> void:
	if _ally_baking:
		_ally_dirty = 1.0
		return
	_ally_baking = true
	if not builder.ally_nav_region.bake_finished.is_connected(_on_ally_baked):
		builder.ally_nav_region.bake_finished.connect(_on_ally_baked)
	builder.ally_nav_region.bake_navigation_mesh(true)

func _on_ally_baked() -> void:
	_ally_baking = false

func _process(delta: float) -> void:
	if _ally_dirty > 0.0:
		_ally_dirty -= delta
		if _ally_dirty <= 0.0:
			bake_ally_nav()
var _baking: bool = false

const TIPS: Array[String] = [
	"Dica: a mochila é guardada no armazém automaticamente ao entrar na base.",
	"Dica: torres de canhão e elétricas seguram grupos grandes de zumbis.",
	"Dica: o Zumbi Explosivo arrasa muros — mate-o de longe.",
	"Dica: pontos de Engenharia aumentam a vida das construções e a sorte na Forja.",
	"Dica: soldados no modo Defender protegem a fortaleza enquanto você explora.",
	"Dica: chefes aparecem a cada 10 hordas e sempre deixam equipamento Raro ou melhor.",
	"Dica: pesquise Coletores para que os sobreviventes produzam recursos.",
	"Dica: jogue com amigos em Jogar em grupo (coop) — basta compartilhar o código da sala.",
	"Dica: o Saltador pula por cima dos muros; tenha defesas também dentro da base.",
]

func _ready() -> void:
	loading.visible = true
	var tip := loading.get_node_or_null(^"Label") as Label
	if tip:
		tip.text = "Gerando o mundo...\n" + TIPS[randi() % TIPS.size()]
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.offset_top -= 50.0
	hud.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	builder = WorldBuilder.new()
	builder.name = "Builder"
	add_child(builder)
	builder.build(self, GameManager.world_seed)

	hero = HERO_SCENE.instantiate() as Hero
	add_child(hero)
	var spawn := HERO_SPAWN
	if Net.in_game:
		# Coop: cada jogador nasce um pouco ao lado do outro.
		var ids := Net.players.keys()
		ids.sort()
		spawn += Vector3((ids.find(Net.my_id()) - (ids.size() - 1) * 0.5) * 1.6, 0, 0)
	hero.global_position = spawn
	hero.set_home(spawn)
	hero.set_camera(camera_rig.camera)
	camera_rig.set_target(hero)

	horde.spawn_points = builder.spawn_points
	spawner.regions = builder.regions
	objectives = DailyObjectives.new()
	objectives.name = "DailyObjectives"
	add_child(objectives)
	hud.bind(hero, services, builder.regions, builder.lootables, objectives)
	build_manager = BuildManager.new()
	build_manager.name = "BuildManager"
	add_child(build_manager)
	build_manager.setup(builder.structures_root, camera_rig.camera)
	army = Army.new()
	army.name = "Army"
	army.parent_root = self
	add_child(army)
	hud.bind_army(army)
	hud.bind_build(build_manager)

	_baking = true
	builder.nav_region.bake_finished.connect(_on_bake_finished)
	builder.nav_region.bake_navigation_mesh(true)
	await builder.nav_region.bake_finished
	bake_ally_nav()
	EventBus.building_placed.connect(func(_b: Node3D) -> void: _ally_dirty = 1.5)
	EventBus.building_changed.connect(func(_b: Node3D) -> void: _ally_dirty = 1.5)
	EventBus.structure_destroyed.connect(func(_s: Node3D) -> void: _ally_dirty = 1.5)
	spawner.populate_initial()
	Coop.attach(self)
	TimeManager.phase_changed.connect(_on_phase_changed)
	GameManager.world_ready(self)
	hud.start_tutorial()
	loading.visible = false
	hud.visible = true
	if Net.in_game:
		EventBus.banner.emit("COOP — %d JOGADORES" % Net.players.size(), "Base, recursos e pesquisas são compartilhados. Defendam a fortaleza juntos!", Color(0.55, 0.85, 1.0))
	elif TimeManager.day == 1 and TimeManager.phase == TimeManager.Phase.DAWN and TimeManager.phase_time < 1.0:
		EventBus.banner.emit("100 HORDAS", "Você tem 2 minutos antes de cada horda. Colete, construa e defenda a fortaleza!", Color(1.0, 0.85, 0.4))
		EventBus.notify("Dica: pressione F1 para ver os controles.", UIStyle.TEXT_DIM)

func _on_bake_finished() -> void:
	_baking = false

func _on_phase_changed(phase: int, day: int) -> void:
	if phase != TimeManager.Phase.DAWN:
		return
	for h: Harvestable in builder.harvestables.values():
		if h.respawn_day >= 0:
			_nav_dirty = true
		h.try_respawn(day)
	for l: Lootable in builder.lootables.values():
		l.try_restock(day)
	# Árvores derrubadas abrem caminho: atualiza a malha de navegação em segundo plano.
	if _nav_dirty and not _baking:
		_nav_dirty = false
		_baking = true
		builder.nav_region.bake_navigation_mesh(true)
	# Salvamento automático a cada amanhecer.
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if SaveManager.save_game():
			EventBus.notify("Progresso salvo automaticamente.", UIStyle.TEXT_DIM))

# --- Salvamento ----------------------------------------------------------------

func collect_save() -> Dictionary:
	var structs := {}
	for id: String in builder.structures:
		structs[id] = (builder.structures[id] as Structure).to_save()
	var depleted := {}
	for id: String in builder.harvestables:
		var h := builder.harvestables[id] as Harvestable
		if h.respawn_day >= 0:
			depleted[id] = h.respawn_day
	var looted := {}
	for id: String in builder.lootables:
		var l := builder.lootables[id] as Lootable
		if l.looted:
			looted[id] = l.restock_day
	var hub := EffectsHub.instance()
	return {
		"hero": hero.to_save(),
		"structures": structs,
		"depleted": depleted,
		"looted": looted,
		"pickups": hub.pickups_to_save() if hub else [],
		"objectives": objectives.to_save(),
		"army": army.to_save(),
		"buildings": get_tree().get_nodes_in_group("buildings").filter(func(b: Node) -> bool: return not b.is_queued_for_deletion()).map(func(b: Node) -> Dictionary: return (b as Building).to_save()),
	}

func apply_save(d: Dictionary) -> void:
	if d.is_empty():
		return
	hero.from_save(d.get("hero", {}))
	var structs: Dictionary = d.get("structures", {})
	for id: String in structs:
		if builder.structures.has(id):
			(builder.structures[id] as Structure).from_save(structs[id])
	var depleted: Dictionary = d.get("depleted", {})
	for id: String in depleted:
		if builder.harvestables.has(id):
			(builder.harvestables[id] as Harvestable).restore_depleted(int(depleted[id]))
	var looted: Dictionary = d.get("looted", {})
	for id: String in looted:
		if builder.lootables.has(id):
			(builder.lootables[id] as Lootable).restore_looted(int(looted[id]))
	for p: Dictionary in d.get("pickups", []):
		var pos: Array = p.get("pos", [0, 0])
		EffectsHub.drop_item(Vector3(pos[0], 0, pos[1]), StringName(p.get("id", "wood")), int(p.get("n", 1)))
	objectives.from_save(d.get("objectives", []))
	for bd: Dictionary in d.get("buildings", []):
		var def := Building.load_def(StringName(bd.get("id", "barricade")))
		var p: Array = bd.get("pos", [0, 0])
		var b := build_manager.place(def, Vector3(p[0], 0, p[1]), float(bd.get("rot", 0.0)), false, int(bd.get("level", 1)))
		b.from_save(bd)
	army.from_save(d.get("army", {}))
	camera_rig.set_target(hero)
