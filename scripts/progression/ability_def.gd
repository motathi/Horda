class_name AbilityDef
extends Resource
## Dados de uma habilidade do herói.

## Cavaleiro: WHIRLWIND, DASH, WARCRY, NOVA. Caçador: MULTISHOT (leque de flechas: radius = abertura
## em graus, distance = alcance, duration = nº de flechas), TRAP (armadilha de urso: radius = gatilho,
## distance = à frente, duration = tempo preso), ARROW_RAIN (radius = área, distance = alcance,
## duration = segundos; power por golpe a cada 0,4 s), EAGLE (radius = caça, distance = revela
## Espreitadores, duration = segundos; power por mergulho).
enum Kind { WHIRLWIND, DASH, WARCRY, NOVA, MULTISHOT, TRAP, ARROW_RAIN, EAGLE }

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
