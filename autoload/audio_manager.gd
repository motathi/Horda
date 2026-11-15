extends Node
## Áudio do jogo: efeitos 2D/3D com variações (pool de players), música dinâmica com
## crossfade (menu / preparação / horda / chefe / derrota), camadas de ambiente
## (dia, noite, área sombria) e canais de volume salvos em user://settings.cfg.
## Sons: assets/sounds/<id>_<n>.ogg (créditos em assets/sounds/CREDITS.md).

const SOUND_DIR := "res://assets/sounds/"
const MUSIC_DIR := "res://assets/music/"
const AMBIENT_DIR := "res://assets/ambient/"
const SETTINGS := "user://settings.cfg"
const POOL_2D := 10
const POOL_3D := 28
const BUSES: Array[String] = ["Music", "SFX", "Ambient", "UI"]
const MUSIC_FADE := 2.5
const DARK_CENTER := Vector3(88, 0, -88)
const DARK_RADIUS := 34.0

var _variants: Dictionary = {}  # id -> Array[AudioStream]
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _i2: int = 0
var _i3: int = 0
var _last_played: Dictionary = {}
var _last_variant: Dictionary = {}
var master_volume_db: float = 0.0
var volumes: Dictionary = {"Master": 1.0, "Music": 0.7, "SFX": 1.0, "Ambient": 0.8, "UI": 0.8}

var _music: Array[AudioStreamPlayer] = []
var _music_i: int = 0
var _music_id: String = ""
var _music_mode: String = ""
var _amb: Dictionary = {}  # "day"/"night"/"dark" -> AudioStreamPlayer
var _amb_target: Dictionary = {"day": 0.0, "night": 0.0, "dark": 0.0, "horror": 0.0, "storm": 0.0}
## Tempestade em andamento (DayNightVisuals): liga a chuva no ambiente.
var storm: bool = false
var _dark: float = 0.0
var _boss_wave: bool = false
var _horde_on: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_load_settings()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players_2d.append(p)
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.max_distance = 70.0
		p3.unit_size = 4.5
		p3.bus = "SFX"
		add_child(p3)
		_players_3d.append(p3)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	for k: String in _amb_target:
		var a := AudioStreamPlayer.new()
		a.bus = "Ambient"
		a.volume_db = -80.0
		var st := _load_loop(AMBIENT_DIR + k + ".ogg")
		if st:
			a.stream = st
		add_child(a)
		_amb[k] = a
	EventBus.horde_started.connect(_on_horde_started)
	EventBus.horde_ended.connect(func(_n: int) -> void: _horde_on = false)
	# Clique em qualquer botão da interface.
	get_tree().node_added.connect(_on_node_added)

func _setup_buses() -> void:
	# Limitador no canal principal: muitos golpes/explosões juntos não distorcem.
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			has_limiter = true
	if not has_limiter:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		lim.pre_gain_db = 0.0
		AudioServer.add_bus_effect(0, lim)
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")

# --- Volumes ---------------------------------------------------------------------

func set_volume(bus: String, linear: float) -> void:
	volumes[bus] = clampf(linear, 0.0, 1.0)
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volumes[bus], 0.0001)))
		AudioServer.set_bus_mute(idx, volumes[bus] <= 0.001)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	for b: String in volumes:
		cfg.set_value("audio", b, volumes[b])
	cfg.save(SETTINGS)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		for b: String in volumes:
			volumes[b] = float(cfg.get_value("audio", b, volumes[b]))
	for b: String in volumes:
		set_volume(b, volumes[b])

# --- Efeitos ---------------------------------------------------------------------

## Todas as variações de um som (id_1.ogg, id_2.ogg... ou id.ogg / id.wav).
func _streams(id: StringName) -> Array:
	if _variants.has(id):
		return _variants[id]
	var list: Array = []
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(SOUND_DIR + String(id) + ext):
			list.append(load(SOUND_DIR + String(id) + ext))
	var n := 1
	while ResourceLoader.exists(SOUND_DIR + "%s_%d.ogg" % [id, n]):
		list.append(load(SOUND_DIR + "%s_%d.ogg" % [id, n]))
		n += 1
	_variants[id] = list
	return list

## Sorteia uma variação diferente da última.
func _pick(id: StringName) -> AudioStream:
	var list := _streams(id)
	if list.is_empty():
		return null
	var i := randi() % list.size()
	if list.size() > 1 and i == int(_last_variant.get(id, -1)):
		i = (i + 1) % list.size()
	_last_variant[id] = i
	return list[i]

func has_sound(id: StringName) -> bool:
	return not _streams(id).is_empty()

## Evita o mesmo som dezenas de vezes no mesmo instante (hordas grandes).
func _throttled(id: StringName, gap_ms: int = 45) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(id, -100000)) < gap_ms:
		return true
	_last_played[id] = now
	return false

func play(id: StringName, volume_db: float = 0.0, pitch: float = 1.0, bus: String = "SFX") -> void:
	if _throttled(id):
		return
	var s := _pick(id)
	if s == null:
		return
	var p := _players_2d[_i2]
	_i2 = (_i2 + 1) % POOL_2D
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db + master_volume_db
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.play()

func play_ui(id: StringName, volume_db: float = 0.0) -> void:
	play(id, volume_db, 1.0, "UI")

func play_3d(id: StringName, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0, gap_ms: int = 45) -> void:
	if _throttled(id, gap_ms):
		return
	var s := _pick(id)
	if s == null:
		return
	var p := _players_3d[_i3]
	_i3 = (_i3 + 1) % POOL_3D
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db + master_volume_db
	p.pitch_scale = pitch * randf_range(0.9, 1.1)
	p.play()

func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta(&"no_click_sound"):
		(n as BaseButton).pressed.connect(func() -> void: play_ui(&"ui_click", -4.0))
		(n as BaseButton).mouse_entered.connect(func() -> void:
			if not (n as BaseButton).disabled:
				play_ui(&"ui_hover", -14.0))

# --- Música ----------------------------------------------------------------------

func _load_loop(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var s: Variant = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s as AudioStream

## Troca a música com crossfade. "" silencia.
func play_music(id: String, fade: float = MUSIC_FADE) -> void:
	if id == _music_id:
		return
	_music_id = id
	var old := _music[_music_i]
	_music_i = 1 - _music_i
	var nw := _music[_music_i]
	var tw := create_tween().set_parallel(true)
	tw.tween_property(old, "volume_db", -80.0, fade)
	if id != "":
		var st := _load_loop(MUSIC_DIR + id + ".ogg")
		if st:
			if id == "defeat" and st is AudioStreamOggVorbis:
				(st as AudioStreamOggVorbis).loop = false
			nw.stream = st
			nw.volume_db = -40.0
			nw.play()
			tw.tween_property(nw, "volume_db", 0.0, fade)
	tw.chain().tween_callback(func() -> void:
		if old.volume_db <= -79.0:
			old.stop())

func _on_horde_started(night: int, _total: int) -> void:
	_horde_on = true
	var w := GameManager.world
	_boss_wave = w != null and w.get(&"horde") != null and (w.get(&"horde") as HordeDirector).config.is_boss_wave(night)

## Escolhe a música/ambiente conforme o estado do jogo (chamado todo quadro, barato).
func _process(_delta: float) -> void:
	var mode := "menu"
	match GameManager.state:
		GameManager.State.PLAYING, GameManager.State.LOADING:
			mode = ("boss" if _boss_wave else "battle") if _horde_on else "prep"
		GameManager.State.GAME_OVER:
			mode = "defeat"
		GameManager.State.VICTORY:
			mode = "menu"
	if mode != _music_mode:
		_music_mode = mode
		match mode:
			"prep": play_music("prep_%d" % (1 + TimeManager.wave() % 2))
			"battle": play_music("battle_%d" % (1 + TimeManager.wave() % 2))
			_: play_music(mode)
	_update_ambient()

## 0..1: quanto o herói está dentro da área contaminada.
func dark_amount() -> float:
	return _dark

func _update_ambient() -> void:
	var playing := GameManager.state == GameManager.State.PLAYING
	var night := _horde_on or (playing and TimeManager.phase == TimeManager.Phase.NIGHT)
	var dark := 0.0
	var hero := GameManager.hero
	if playing and hero:
		var d := Vector2(hero.global_position.x - DARK_CENTER.x, hero.global_position.z - DARK_CENTER.z).length()
		dark = clampf(1.0 - (d - DARK_RADIUS * 0.6) / (DARK_RADIUS * 0.6), 0.0, 1.0)
	_dark = dark
	_amb_target["day"] = 0.0 if not playing or night else 0.8 - 0.8 * dark
	_amb_target["night"] = 0.55 if playing and night else 0.0
	_amb_target["dark"] = dark if playing else 0.0
	# Zumbido de terror por baixo de tudo à noite (e um pouco na área contaminada).
	_amb_target["horror"] = (0.9 if night else 0.45 * dark) if playing else 0.0
	_amb_target["storm"] = 0.75 if playing and storm else 0.0
	for k: String in _amb:
		var a: AudioStreamPlayer = _amb[k]
		if a.stream == null:
			continue
		var target_db := linear_to_db(maxf(float(_amb_target[k]), 0.0001))
		a.volume_db = lerpf(a.volume_db, target_db, 0.03)
		if float(_amb_target[k]) > 0.01 and not a.playing:
			a.play()
		elif float(_amb_target[k]) <= 0.01 and a.playing and a.volume_db < -60.0:
			a.stop()
