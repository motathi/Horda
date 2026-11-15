class_name AttributeConfig
extends Resource
## Bônus por ponto de cada atributo do herói (dados em data/config/attributes.tres).

const IDS: Array[StringName] = [&"strength", &"agility", &"vitality", &"intelligence", &"engineering"]
const NAMES := {
	&"strength": "Força", &"agility": "Agilidade", &"vitality": "Vitalidade",
	&"intelligence": "Inteligência", &"engineering": "Engenharia",
}
const COLORS := {
	&"strength": Color(0.95, 0.35, 0.25), &"agility": Color(0.35, 0.9, 0.4), &"vitality": Color(0.95, 0.75, 0.25),
	&"intelligence": Color(0.4, 0.6, 1.0), &"engineering": Color(0.85, 0.6, 0.35),
}

@export var points_per_level: int = 3
## Custo (sucata) por ponto devolvido ao redistribuir.
@export var respec_scrap_per_point: int = 2
@export var respec_min_scrap: int = 10

@export_group("Força")
@export var str_damage_pct: float = 0.05
@export var str_carry: int = 4
@export_group("Agilidade")
@export var agi_attack_speed_pct: float = 0.04
@export var agi_move_speed_pct: float = 0.02
@export var agi_crit: float = 0.01
@export var agi_move_speed_cap: float = 0.4
@export_group("Vitalidade")
@export var vit_hp: float = 18.0
@export var vit_regen: float = 0.4
@export_group("Inteligência")
@export var int_energy: float = 8.0
@export var int_energy_regen: float = 0.5
@export var int_power_pct: float = 0.06
@export var int_cdr_pct: float = 0.02
@export var int_cdr_cap: float = 0.4
@export_group("Engenharia")
@export var eng_building_hp_pct: float = 0.06
@export var eng_building_dmg_pct: float = 0.06

static func display_name(id: StringName) -> String:
	return NAMES.get(id, String(id))

## Texto curto do bônus por ponto (painel de personagem).
func per_point_text(id: StringName) -> String:
	match id:
		&"strength": return "+%d%% dano • +%d de carga" % [roundi(str_damage_pct * 100), str_carry]
		&"agility": return "+%d%% vel. de ataque • +%d%% movimento • +%d%% crítico" % [roundi(agi_attack_speed_pct * 100), roundi(agi_move_speed_pct * 100), roundi(agi_crit * 100)]
		&"vitality": return "+%d de vida • +%.1f vida/s" % [int(vit_hp), vit_regen]
		&"intelligence": return "+%d de energia • +%d%% poder das habilidades • -%d%% recarga" % [int(int_energy), roundi(int_power_pct * 100), roundi(int_cdr_pct * 100)]
		&"engineering": return "+%d%% vida das construções • +%d%% dano de torres e armadilhas" % [roundi(eng_building_hp_pct * 100), roundi(eng_building_dmg_pct * 100)]
	return ""
