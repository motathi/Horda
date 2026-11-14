class_name BaseServicesConfig
extends Resource
## Custos dos serviços da base (reparos e melhorias). Ajustável sem tocar em código.

@export var wall_hp_per_wood: float = 20.0
## Cada "unidade" de reparo do núcleo custa 1 pedra + 1 sucata.
@export var core_hp_per_unit: float = 45.0
@export var sharpen_max_level: int = 5
## Custo do nível N = custo base * N.
@export var sharpen_base_cost: Dictionary = {&"scrap": 6, &"stone": 3}
