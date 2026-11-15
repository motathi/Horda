class_name BuildingDef
extends Resource
## Dados de uma construção do jogador (muro, torre, armadilha).

enum Category { WALL, TOWER, TRAP }
## Flecha teleguiada, virote perfurante (linha), bala de canhão (área), raio em cadeia.
enum TowerKind { ARROW, PIERCE, SPLASH, CHAIN }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon_name: String = ""
@export var category: Category = Category.WALL
## item_id -> quantidade
@export var cost: Dictionary = {}
@export var max_health: float = 300.0
@export var armor: float = 2.0
## Área ocupada no chão (largura X, profundidade Z) e altura.
@export var footprint: Vector2 = Vector2(3, 1)
@export var height: float = 2.5
@export var max_level: int = 3
## Custo da melhoria para o nível N = custo base * multiplicador * (N - 1).
@export var upgrade_cost_mult: float = 0.8
## Fração do custo investido devolvida ao demolir.
@export var refund: float = 0.5
## Fica disponível a partir da preparação desta horda.
@export var unlock_wave: int = 1

@export_group("Torre")
@export var tower_range: float = 14.0
@export var tower_damage: float = 18.0
@export var attacks_per_second: float = 1.0
@export var projectile_speed: float = 30.0
@export var tower_kind: TowerKind = TowerKind.ARROW
## Canhão: raio da explosão. Balista: largura da linha perfurante.
@export var splash_radius: float = 0.0
## Torre elétrica: número de alvos do raio.
@export var chain_count: int = 0
## Atordoamento aplicado a cada alvo (s).
@export var stun_time: float = 0.0

@export_group("Armadilha")
@export var trap_damage: float = 14.0
@export var trap_interval: float = 0.8
## Vida que a armadilha perde a cada inimigo atingido.
@export var trap_wear: float = 6.0

func icon() -> Texture2D:
	return UIStyle.hud_icon(icon_name)

func is_unlocked() -> bool:
	return TimeManager.wave() >= unlock_wave

func upgrade_cost(to_level: int) -> Dictionary:
	var c := {}
	for id: StringName in cost:
		c[id] = int(ceil(int(cost[id]) * upgrade_cost_mult * (to_level - 1)))
	return c

func stats_text(level: int = 1) -> String:
	var hp := int(max_health * (1.0 + 0.5 * (level - 1)))
	match category:
		Category.TOWER:
			var t := "Vida %d • Dano %d\nAlcance %d m • %.1f tiros/s" % [hp, int(tower_damage * (1.0 + 0.4 * (level - 1))), int(tower_range + 1.5 * (level - 1)), attacks_per_second * (1.0 + 0.15 * (level - 1))]
			match tower_kind:
				TowerKind.PIERCE: t += "\nAtravessa a fila inteira"
				TowerKind.SPLASH: t += "\nExplosão de %.1f m" % splash_radius
				TowerKind.CHAIN: t += "\nRaio salta em %d alvos" % chain_count
			return t
		Category.TRAP:
			return "Durabilidade %d • Dano %d a cada %.1fs" % [hp, int(trap_damage * (1.0 + 0.4 * (level - 1))), trap_interval]
		_:
			return "Vida %d • Armadura %d" % [hp, int(armor + (level - 1))]
