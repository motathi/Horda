extends Node
## Estado global da partida: configurações, registro de entidades-chave,
## pausa, fim de jogo e troca de cenas.

enum State { MENU, LOADING, PLAYING, GAME_OVER }

const WORLD_SCENE := "res://scenes/world/main.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

## Multiplicadores de dificuldade (vida/dano dos inimigos, quantidade nas hordas).
const DIFFICULTIES := {
	"facil": {"name": "Fácil", "enemy_hp": 0.75, "enemy_damage": 0.7, "horde_count": 0.75},
	"normal": {"name": "Normal", "enemy_hp": 1.0, "enemy_damage": 1.0, "horde_count": 1.0},
	"dificil": {"name": "Difícil", "enemy_hp": 1.3, "enemy_damage": 1.35, "horde_count": 1.35},
}

const STARTER_KIT := {&"wood": 30, &"stone": 15, &"scrap": 8}

var state: State = State.MENU
var difficulty: String = "normal"
var cycle_preset: String = "normal"
var world_seed: int = 1337
var load_from_save: bool = false

var hero: Node3D = null
var base_core: Node3D = null
var world: Node3D = null

var stats := {"kills": 0, "nights_survived": 0, "items_collected": 0}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.base_core_destroyed.connect(_on_base_core_destroyed)
	EventBus.enemy_killed.connect(func(_e: Node3D, _d: EnemyDef, _k: Node) -> void: stats.kills += 1)
	EventBus.night_survived.connect(func(n: int) -> void: stats.nights_survived = maxi(stats.nights_survived, n))
	EventBus.item_picked_up.connect(func(_id: StringName, amt: int) -> void: stats.items_collected += amt)

func diff_value(key: String) -> float:
	return float(DIFFICULTIES.get(difficulty, DIFFICULTIES.normal)[key])

func start_new_game(diff: String, cycle: String) -> void:
	difficulty = diff
	cycle_preset = cycle
	world_seed = 1337
	load_from_save = false
	stats = {"kills": 0, "nights_survived": 0, "items_collected": 0}
	ResourceManager.reset()
	# Kit inicial: dá para erguer a primeira defesa já no Dia 1.
	for id: StringName in STARTER_KIT:
		ResourceManager.storage.add(id, STARTER_KIT[id])
	TimeManager.setup(cycle)
	_change_to_world()

func continue_game() -> void:
	if not SaveManager.has_save():
		return
	load_from_save = true
	var meta := SaveManager.peek_meta()
	difficulty = str(meta.get("difficulty", "normal"))
	cycle_preset = str(meta.get("cycle", "normal"))
	world_seed = int(meta.get("seed", 1337))
	stats = meta.get("stats", stats)
	ResourceManager.reset()
	TimeManager.setup(cycle_preset)
	_change_to_world()

func _change_to_world() -> void:
	state = State.LOADING
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)

## Chamado pelo mundo quando terminou de gerar/carregar.
func world_ready(w: Node3D) -> void:
	world = w
	if load_from_save:
		SaveManager.apply_loaded_state()
		load_from_save = false
	state = State.PLAYING
	TimeManager.running = true

func return_to_menu() -> void:
	state = State.MENU
	TimeManager.running = false
	hero = null
	base_core = null
	world = null
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)

func is_playing() -> bool:
	return state == State.PLAYING

func set_paused(p: bool) -> void:
	if state != State.PLAYING and p:
		return
	get_tree().paused = p

func _on_base_core_destroyed() -> void:
	if state != State.PLAYING:
		return
	state = State.GAME_OVER
	TimeManager.running = false
	SaveManager.delete_save()
	EventBus.banner.emit("A BASE CAIU", "Você sobreviveu %d noite(s)." % stats.nights_survived, Color(0.9, 0.2, 0.15))
