class_name SoldierDef
extends Resource
## Tipo de soldado recrutável no Quartel (dados em data/soldiers/*.tres).

enum Attack { MELEE, ARROW, MAGIC }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Aparência (id de HeroSkins: knight, barbarian, ranger, mage...).
@export var skin: String = "knight"
@export var attack: Attack = Attack.MELEE
@export var max_health: float = 160.0
@export var armor: float = 3.0
@export var damage: float = 14.0
@export var attack_range: float = 1.9
@export var attack_cooldown: float = 1.1
@export var move_speed: float = 4.4
@export var aggro_range: float = 13.0
## Mago: raio da explosão.
@export var splash_radius: float = 0.0
@export var cost: Dictionary = {}
@export var train_time: float = 10.0
@export var unlock_wave: int = 1

func portrait() -> Texture2D:
	return HeroSkins.portrait(skin)

func stats_text() -> String:
	var kind: String = ["Corpo a corpo", "À distância", "Magia em área"][attack]
	return "%s • Vida %d • Dano %d • Armadura %d%s" % [kind, int(max_health), int(damage), int(armor), " • Área %.1f m" % splash_radius if splash_radius > 0.0 else ""]
