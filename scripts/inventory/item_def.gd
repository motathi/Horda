class_name ItemDef
extends Resource
## Definição de dados de um item (recurso, consumível; equipamentos na Fase 2).

enum Category { RESOURCE, CONSUMABLE }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.RESOURCE
@export var icon: Texture2D
## Quanto ocupa no inventário do herói (capacidade é por peso).
@export var weight: int = 1
## Cor usada no chão / textos flutuantes.
@export var color: Color = Color.WHITE
## Consumíveis: cura instantânea e cura ao longo do tempo.
@export var heal_instant: float = 0.0
@export var heal_over_time: float = 0.0
@export var heal_duration: float = 0.0

## Itens que o herói pode consumir (teclas 1/2) e por isso mantém na mochila.
func is_usable() -> bool:
	return heal_instant > 0.0 or heal_over_time > 0.0
