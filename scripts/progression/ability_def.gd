class_name AbilityDef
extends Resource
## Dados de uma habilidade do herói.

enum Kind { WHIRLWIND, DASH, WARCRY, NOVA }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon_name: String = ""
@export var kind: Kind = Kind.WHIRLWIND
@export var unlock_level: int = 1
@export var energy_cost: float = 25.0
@export var cooldown: float = 6.0
## Multiplicador sobre o dano do herói.
@export var power: float = 2.0
@export var radius: float = 4.0
## Distância (investida) ou duração (buffs, atordoamento).
@export var distance: float = 8.0
@export var duration: float = 1.0

func icon() -> Texture2D:
	return UIStyle.hud_icon(icon_name)
