class_name TechDef
extends Resource
## Tecnologia pesquisável na base (dados em data/tech/*.tres).

enum Branch { DEFENSE, ECONOMY, HERO }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon_name: String = ""
@export var branch: Branch = Branch.DEFENSE
@export var cost: Dictionary = {}
## Segundos de pesquisa (tempo de jogo, inclusive durante a horda).
@export var research_time: float = 60.0
@export var requires: Array[StringName] = []
@export var min_wave: int = 1
## Efeitos somados ao concluir: tower_damage_pct, tower_speed_pct, tower_range_pct, wall_hp_pct,
## core_hp_pct, struct_regen, harvest_bonus, carry, loot_mult, gear_chance, passive_income,
## sharpen_max, forge_luck, hero_damage_pct, health_regen, heal_mult, energy_regen, cdr_pct, hero_hp.
@export var effects: Dictionary = {}

func icon() -> Texture2D:
	return UIStyle.hud_icon(icon_name)

static func branch_name(b: int) -> String:
	return ["Defesa", "Economia", "Herói"][b]
