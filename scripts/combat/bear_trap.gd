class_name BearTrap
extends Node3D
## Armadilha de urso do Caçador (modelo feito no Blender: assets/models/blender/bear_trap.glb).
## Fica armada no chão; o primeiro inimigo que pisar leva dano e fica preso (atordoado).
## No coop, os outros jogadores veem uma cópia só visual (visual_only).

const SCENE := "res://assets/models/blender/bear_trap.glb"
const ARMED_TIME := 90.0
const MAX_PER_HERO := 3

static var active: Array[BearTrap] = []

var owner_hero: Node3D
var damage: float = 60.0
var root_time: float = 3.0
var radius: float = 1.2
var visual_only: bool = false
var _armed: bool = true
var _life: float = ARMED_TIME
var _check: float = 0.0
var _jaws: Array[Node3D] = []

func _ready() -> void:
	add_to_group(&"bear_traps")
	active.append(self)
	if ResourceLoader.exists(SCENE):
		var m := (load(SCENE) as PackedScene).instantiate() as Node3D
		m.scale = Vector3.ONE * 1.7
		add_child(m)
		for n in ["JawA", "JawB"]:
			var j := m.find_child(n, true, false) as Node3D
			if j:
				_jaws.append(j)
	# Marca no chão para o jogador achar a armadilha.
	(func() -> void: SkillFx.trap_armed(global_position, radius)).call_deferred()
	# Limite por herói: a mais antiga some.
	var mine := active.filter(func(t: BearTrap) -> bool: return is_instance_valid(t) and t.owner_hero == owner_hero and t._armed)
	while mine.size() > MAX_PER_HERO:
		(mine.pop_front() as BearTrap).queue_free()

func _exit_tree() -> void:
	active.erase(self)

func is_armed() -> bool:
	return _armed

func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if not _armed:
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.1
	for e in Enemy.all:
		if not is_instance_valid(e) or e.is_dead() or e.is_leaping():
			continue
		var d := e.global_position - global_position
		d.y = 0.0
		if d.length() <= radius + e.get_radius():
			_snap(e)
			return

func _snap(e: Enemy) -> void:
	_armed = false
	_life = 2.5
	for j in _jaws:
		var closed := signf(j.rotation.z if absf(j.rotation.z) > 0.01 else 1.0) * deg_to_rad(86.0)
		create_tween().tween_property(j, "rotation:z", closed, 0.08)
	AudioManager.play_3d(&"upgrade", global_position, 3.0, 1.5)
	AudioManager.play_3d(&"hit", global_position, 0.0, 0.8)
	EffectsHub.spawn_debris(global_position + Vector3.UP * 0.3, true)
	SkillFx.trap_snap(global_position)
	if visual_only:
		return
	EffectsHub.spawn_blood(e.global_position + Vector3.UP * 0.5, true)
	e.take_damage(DamageInfo.make(damage, owner_hero if is_instance_valid(owner_hero) else null, true))
	e.stun(root_time)
	EventBus.notify("%s caiu na armadilha!" % e.display_name(), Color(1.0, 0.8, 0.4))
