class_name EnemyDef
extends Resource
## Dados de um tipo de inimigo. A cena zombie.tscn é configurada a partir disto.

enum Behavior { MELEE, CHARGER, BRUTE, EXPLODER, SPITTER, LEAPER }

@export var id: StringName
@export var display_name: String = "Zumbi"
@export_multiline var description: String = ""
@export var portrait: Texture2D
@export var behavior: Behavior = Behavior.MELEE

@export_group("Atributos")
@export var max_health: float = 60.0
@export var armor: float = 0.0
@export var damage: float = 8.0
@export var attack_range: float = 1.6
@export var attack_cooldown: float = 1.4
@export var move_speed: float = 3.2
@export var aggro_range: float = 12.0
## Multiplicador de dano contra muros e construções.
@export var structure_damage_mult: float = 1.0
@export var xp_reward: int = 10

@export_group("Especial")
## Explosivo: raio da explosão. Cuspidor: raio da poça de ácido. Saltador: raio do impacto.
@export var special_radius: float = 0.0
## Cuspidor: distância mínima que mantém do herói. Saltador: alcance máximo do salto.
@export var special_range: float = 0.0
## Explosivo: pavio (s). Saltador: recarga do salto (s). Cuspidor: duração da poça (s).
@export var special_time: float = 0.0
## Multiplicador de dano da habilidade especial.
@export var special_mult: float = 1.0
## Cor do brilho/efeito especial.
@export var special_color: Color = Color(0.5, 1.0, 0.2)

@export_group("Visual")
@export var model_scale: float = 1.0
@export var skin_tint: Color = Color(0.7, 0.85, 0.6)
@export var cloth_tint: Color = Color(0.35, 0.3, 0.4)
@export var hunch: float = 0.35

@export_group("Saque")
@export var loot: LootTable
