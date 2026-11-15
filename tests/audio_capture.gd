extends Node
## Mede o áudio de uma luta: grava o canal Master (sem música/ambiente) e salva um WAV.
##   godot --headless --audio-driver Dummy res://tests/audio_capture.tscn -- saida.wav

var world: World

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://luta.wav"
	GameManager.difficulty = "normal"
	ResourceManager.reset()
	TimeManager.setup("normal")
	world = (load("res://scenes/world/main.tscn") as PackedScene).instantiate() as World
	add_child(world)
	while not GameManager.is_playing():
		await get_tree().process_frame
	TimeManager.running = false
	AudioManager.set_volume("Music", 0.0)
	AudioManager.set_volume("Ambient", 0.0)
	var hero := world.hero
	hero.health.invulnerable = true
	hero.global_position = Vector3(40, 0, 40)
	world.camera_rig.set_target(hero)
	await get_tree().create_timer(0.5).timeout
	for i in 3:
		var a := i * TAU / 3.0
		var e := (load("res://scenes/enemies/zombie.tscn") as PackedScene).instantiate() as Enemy
		e.def = load("res://data/enemies/zombie_brute.tres") as EnemyDef
		world.enemies_root.add_child(e)
		e.global_position = hero.global_position + Vector3(cos(a), 0, sin(a)) * 2.2
		e.health.invulnerable = true
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	rec.set_recording_active(true)
	var t := 0.0
	while t < 6.0:
		hero._aim_point = hero.global_position + Vector3(1, 0, 0)
		hero._start_attack()
		await get_tree().create_timer(0.9).timeout
		t += 0.9
	rec.set_recording_active(false)
	var wav := rec.get_recording()
	if wav:
		wav.save_to_wav(out)
		print("gravado: ", out, " (", wav.data.size(), " bytes)")
	else:
		print("sem gravação")
	get_tree().quit()
