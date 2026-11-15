class_name Survivor
extends Node3D
## Sobrevivente da base (NPC ambiente, CC0 Quaternius): trabalha, vigia, conversa ou
## circula entre pontos. Quando a horda chega, corre para a fortaleza e se esconde;
## volta quando a horda termina.

enum Role { WORK, GUARD, TALK, WANDER }

const SPEED := 1.6
const RUN_SPEED := 4.2

var model_id: String = "npc_peasant_m"
var role: Role = Role.WANDER
var spot: Vector3
var face_to: Vector3 = Vector3.ZERO
var wander_points: Array[Vector3] = []

var _pivot: Node3D
var _ap: AnimationPlayer
var _target: Vector3
var _wait: float = 0.0
var _hiding: bool = false
var _anim: String = ""
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_pivot = Node3D.new()
	add_child(_pivot)
	var path := CharacterModel.rigged_path(model_id)
	if path == "":
		return
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	_pivot.add_child(inst)
	var aabb := AABB()
	var first := true
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		var b := mi.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var s := 1.75 / maxf(0.01, aabb.size.y)
	inst.scale = Vector3.ONE * s
	inst.position.y = -aabb.position.y * s
	inst.rotation.y = PI * 0.5
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	_ap = aps[0] as AnimationPlayer if not aps.is_empty() else null
	global_position = spot
	_target = spot
	_resume()
	EventBus.horde_started.connect(func(_n: int, _t: int) -> void: _hide())
	EventBus.horde_ended.connect(func(_n: int) -> void: _return())
	# Pausa a animação fora da tela.
	var vis := VisibleOnScreenNotifier3D.new()
	vis.aabb = AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
	add_child(vis)
	vis.screen_entered.connect(func() -> void: if _ap: _ap.process_mode = Node.PROCESS_MODE_INHERIT)
	vis.screen_exited.connect(func() -> void: if _ap: _ap.process_mode = Node.PROCESS_MODE_DISABLED)

func _play(n: String) -> void:
	if _ap == null or n == _anim or not _ap.has_animation(n):
		return
	_anim = n
	_ap.play(n, 0.25)

func _resume() -> void:
	match role:
		Role.WORK: _play("work")
		Role.GUARD: _play("torch" if _rng.randf() < 0.5 else "idle")
		Role.TALK: _play("talk")
		Role.WANDER: _play("idle")
	if face_to != Vector3.ZERO:
		_look(face_to)

func _look(p: Vector3) -> void:
	var to := p - global_position
	to.y = 0.0
	if to.length() > 0.05:
		_pivot.rotation.y = atan2(-to.x, -to.z)

func _hide() -> void:
	_hiding = true
	var core := GameManager.base_core as Node3D
	_target = core.global_position if core else Vector3.ZERO

func _return() -> void:
	_hiding = false
	visible = true
	global_position = spot
	_target = spot
	_anim = ""
	_resume()

func is_hidden() -> bool:
	return _hiding and not visible

func _process(delta: float) -> void:
	if not visible:
		return
	if _hiding:
		if _move_to(_target, RUN_SPEED, delta, "run", 3.2):
			visible = false
		return
	if role != Role.WANDER:
		return
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0 and not wander_points.is_empty():
			_target = wander_points[_rng.randi() % wander_points.size()]
		return
	if _move_to(_target, SPEED, delta, "walk", 0.4):
		_wait = _rng.randf_range(3.0, 7.0)
		_play("idle" if _rng.randf() < 0.6 else "interact")

## Anda até o ponto; true ao chegar.
func _move_to(p: Vector3, speed: float, delta: float, anim: String, reach: float) -> bool:
	var to := p - global_position
	to.y = 0.0
	if to.length() <= reach:
		return true
	_play(anim)
	global_position += to.normalized() * minf(speed * delta, to.length())
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, atan2(-to.x, -to.z), clampf(delta * 8.0, 0.0, 1.0))
	return false
