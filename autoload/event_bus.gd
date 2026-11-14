extends Node
## Barramento global de eventos. Sistemas se comunicam por sinais daqui para
## evitar referências diretas (e dependências circulares) entre módulos.

# --- Combate ---
signal damage_dealt(target: Node3D, info: DamageInfo, final_amount: float)
signal enemy_killed(enemy: Node3D, def: EnemyDef, killer: Node)
signal hero_damaged(amount: float)
signal hero_died
signal hero_respawned

# --- Economia / inventário ---
signal item_picked_up(item_id: StringName, amount: int)
signal inventory_full(item_id: StringName)
signal resources_deposited(summary: Dictionary)

# --- Mundo ---
signal structure_damaged(structure: Node3D)
signal structure_destroyed(structure: Node3D)
signal base_core_destroyed
signal object_selected(obj: Node)
signal object_deselected

# --- Tempo / hordas ---
signal horde_started(night: int, total_enemies: int)
signal horde_progress(remaining: int, total: int)
signal horde_ended(night: int)
signal night_survived(night: int)

# --- Interface ---
signal message(text: String, color: Color)
signal banner(title: String, subtitle: String, color: Color)
signal interaction_progress(label: String, ratio: float)
signal interaction_hint(text: String)

func notify(text: String, color: Color = Color(0.95, 0.9, 0.75)) -> void:
	message.emit(text, color)
