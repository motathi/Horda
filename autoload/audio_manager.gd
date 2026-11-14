extends Node
## Sons 2D/3D com pool de players (evita criar nós a cada efeito).

const SOUND_DIR := "res://assets/sounds/"
const POOL_2D := 8
const POOL_3D := 24

var _streams: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _i2: int = 0
var _i3: int = 0
var _last_played: Dictionary = {}
var master_volume_db: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players_2d.append(p)
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.max_distance = 60.0
		p3.unit_size = 8.0
		add_child(p3)
		_players_3d.append(p3)

func _stream(id: StringName) -> AudioStream:
	if not _streams.has(id):
		var path := SOUND_DIR + String(id) + ".wav"
		_streams[id] = load(path) if ResourceLoader.exists(path) else null
	return _streams[id]

## Evita o mesmo som dezenas de vezes no mesmo instante (hordas grandes).
func _throttled(id: StringName) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(id, -1000)) < 40:
		return true
	_last_played[id] = now
	return false

func play(id: StringName, volume_db: float = 0.0) -> void:
	var s := _stream(id)
	if s == null or _throttled(id):
		return
	var p := _players_2d[_i2]
	_i2 = (_i2 + 1) % POOL_2D
	p.stream = s
	p.volume_db = volume_db + master_volume_db
	p.pitch_scale = 1.0
	p.play()

func play_3d(id: StringName, pos: Vector3, volume_db: float = 0.0) -> void:
	var s := _stream(id)
	if s == null or _throttled(id):
		return
	var p := _players_3d[_i3]
	_i3 = (_i3 + 1) % POOL_3D
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db + master_volume_db
	p.pitch_scale = randf_range(0.9, 1.1)
	p.play()
