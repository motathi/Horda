class_name EquipmentDef
extends Resource
## Item base de equipamento (dados em data/equipment/*.tres). Os valores são do item
## Comum no nível 1; raridade e nível multiplicam (ver GearItem).

enum Slot { WEAPON, ARMOR, TRINKET }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon_name: String = ""
@export var slot: Slot = Slot.WEAPON
## Atributos: damage, attack_speed_pct, crit, reach, armor, max_hp, move_speed_pct,
## health_regen, energy, ability_power_pct, cdr_pct, lifesteal_pct.
@export var stats: Dictionary = {}
## Custo na Forja (vazio = não fabricável).
@export var craft_cost: Dictionary = {}
## Disponível na Forja a partir desta horda.
@export var min_wave: int = 1

func icon() -> Texture2D:
	return UIStyle.hud_icon(icon_name)

static func slot_name(s: int) -> String:
	return ["Arma", "Armadura", "Amuleto"][s]
