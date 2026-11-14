class_name HealthComponent
extends Node
## Componente reutilizável de vida/armadura para heróis, inimigos e estruturas.

signal damaged(info: DamageInfo, final_amount: float)
signal healed(amount: float)
signal died(info: DamageInfo)
signal changed(current: float, maximum: float)

@export var max_health: float = 100.0
@export var armor: float = 0.0
## Regeneração por segundo (aplicada somente fora de combate se `regen_out_of_combat`).
@export var regen_per_second: float = 0.0
@export var regen_out_of_combat: bool = true
@export var is_structure: bool = false

var current: float = 100.0
var dead: bool = false
var invulnerable: bool = false
var _since_damage: float = 999.0
var _hot_left: float = 0.0
var _hot_rate: float = 0.0

func _ready() -> void:
	current = max_health

func setup(max_hp: float, arm: float = 0.0) -> void:
	max_health = max_hp
	armor = arm
	current = max_hp
	dead = false
	changed.emit(current, max_health)

func ratio() -> float:
	return current / max_health if max_health > 0.0 else 0.0

## Redução estilo Warcraft III: cada ponto de armadura reduz ~6%.
func armor_reduction() -> float:
	return (armor * 0.06) / (1.0 + armor * 0.06) if armor >= 0.0 else -(1.0 - pow(0.94, -armor))

func take_damage(info: DamageInfo) -> float:
	if dead or invulnerable:
		return 0.0
	var amt := info.amount
	if is_structure:
		amt *= info.structure_multiplier
	if info.type != DamageInfo.Type.TRUE:
		amt *= 1.0 - armor_reduction()
	amt = maxf(1.0, amt)
	current = maxf(0.0, current - amt)
	_since_damage = 0.0
	damaged.emit(info, amt)
	changed.emit(current, max_health)
	var owner_node := get_parent() as Node3D
	if owner_node:
		EventBus.damage_dealt.emit(owner_node, info, amt)
	if current <= 0.0:
		dead = true
		died.emit(info)
	return amt

func heal(amount: float) -> float:
	if dead or amount <= 0.0:
		return 0.0
	var before := current
	current = minf(max_health, current + amount)
	var done := current - before
	if done > 0.0:
		healed.emit(done)
		changed.emit(current, max_health)
	return done

func heal_over_time(total: float, duration: float) -> void:
	_hot_rate = total / maxf(0.1, duration)
	_hot_left = duration

func revive(ratio_hp: float = 1.0) -> void:
	dead = false
	current = max_health * ratio_hp
	_hot_left = 0.0
	changed.emit(current, max_health)

func in_combat() -> bool:
	return _since_damage < 5.0

func _process(delta: float) -> void:
	if dead:
		return
	_since_damage += delta
	if _hot_left > 0.0:
		_hot_left -= delta
		heal(_hot_rate * delta)
	if regen_per_second > 0.0 and current < max_health and (not regen_out_of_combat or not in_combat()):
		heal(regen_per_second * delta)
