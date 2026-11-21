extends Node
## Resistência: joga várias hordas seguidas (herói invulnerável matando a horda) e mede, a cada amanhecer,
## memória, objetos, nós, inimigos e itens no chão — para achar o que acumula e derruba o navegador.
##   godot --headless res://tests/endurance_test.tscn -- [hordas] [--lowend]
var world: World
var _last_us: int = 0
var max_gap_ms: float = 0.0

func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		max_gap_ms = maxf(max_gap_ms, (now - _last_us) / 1000.0)
	_last_us = now

func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var nights := int(args[0]) if args.size() > 0 and args[0].is_valid_int() else 7
	Settings.tutorial_done = true
	GameManager.hero_skin = "knight"
	GameManager.difficulty = "normal"
	ResourceManager.reset()
	TimeManager.setup("normal")
	world = (load("res://scenes/world/main.tscn") as PackedScene).instantiate() as World
	add_child(world)
	while not GameManager.is_playing():
		await get_tree().process_frame
	var hero := world.hero
	hero.health.invulnerable = true
	print("low_end=", Platform.low_end)
	_report("início")
	for n in range(1, nights + 1):
		TimeManager.set_state(TimeManager.Phase.DAY, n, 0.0)
		await wait(1.0)
		var t0 := Time.get_ticks_msec()
		TimeManager.start_horde_now()
		Engine.time_scale = 4.0
		var t := 0.0
		var kills := 0
		max_gap_ms = 0.0
		while TimeManager.is_night() and t < 400.0:
			await wait(0.25)
			t += 0.25
			# O herói "mata" os zumbis da horda que chegam perto da base (como num jogo real, com saque).
			for e in Enemy.all.duplicate():
				if is_instance_valid(e) and e.is_horde and not e.is_dead() and e.global_position.length() < 60.0:
					e.take_damage(DamageInfo.make(999999, hero))
					kills += 1
		var gap_night := max_gap_ms
		max_gap_ms = 0.0
		Engine.time_scale = 1.0
		await wait(4.0)
		var t_save := Time.get_ticks_msec()
		var ok := SaveManager.save_game()
		var save_ms := Time.get_ticks_msec() - t_save
		var save_len := JSON.stringify(world.collect_save()).length()
		print("  pior quadro: noite %.0f ms, amanhecer %.0f ms; salvar %d ms (%s), save %d KB" % [gap_night, max_gap_ms, save_ms, ok, save_len / 1024])
		print("horda %d: %d mortos em %.0f s de jogo (%d ms reais), fase=%s" % [n, kills, t * 4.0, Time.get_ticks_msec() - t0, TimeManager.phase_name()])
		_report("após horda %d" % n)
		# Um pedaço do dia: o mapa repõe inimigos e guardiões.
		Engine.time_scale = 4.0
		await wait(15.0)
		Engine.time_scale = 1.0
		_report("dia %d" % (n + 1))
	get_tree().quit()

func _report(tag: String) -> void:
	var pickups := get_tree().get_nodes_in_group("pickups").size()
	var enemies := Enemy.all.size()
	var horde := Enemy.all.filter(func(e: Enemy) -> bool: return is_instance_valid(e) and e.is_horde).size()
	print("[%s] mem=%.1f MB objs=%d nós=%d órfãos=%d recursos=%d inimigos=%d (horda %d) itens_no_chão=%d fps_proc=%.1f ms" % [tag,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		enemies, horde, pickups,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
