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

var builder: WorldBuilder
var hero: Hero
var _nav_dirty: bool = false
var _baking: bool = false

func _ready() -> void:
	loading.visible = true
	hud.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	builder = WorldBuilder.new()
	builder.name = "Builder"
	add_child(builder)
	builder.build(self, GameManager.world_seed)

	hero = HERO_SCENE.instantiate() as Hero
	add_child(hero)
	hero.global_position = HERO_SPAWN
	hero.set_home(HERO_SPAWN)
	hero.set_camera(camera_rig.camera)
	camera_rig.set_target(hero)

	horde.spawn_points = builder.spawn_points
	spawner.regions = builder.regions
	hud.bind(hero, services, builder.regions, builder.lootables)

	_baking = true
	builder.nav_region.bake_finished.connect(_on_bake_finished)
	builder.nav_region.bake_navigation_mesh(true)
	await builder.nav_region.bake_finished
	spawner.populate_initial()
	TimeManager.phase_changed.connect(_on_phase_changed)
	GameManager.world_ready(self)
	loading.visible = false
	hud.visible = true
	if TimeManager.day == 1 and TimeManager.phase == TimeManager.Phase.DAY and TimeManager.phase_time < 1.0:
		EventBus.banner.emit("DIA 1", "Explore, colete recursos e volte antes do anoitecer.", Color(1.0, 0.85, 0.4))
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
	camera_rig.set_target(hero)
