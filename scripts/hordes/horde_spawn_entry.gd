class_name HordeSpawnEntry
extends Resource
## Um tipo de inimigo que pode compor a horda a partir de certa noite.

@export var enemy: EnemyDef
## Primeira noite em que este inimigo aparece.
@export var unlock_night: int = 1
## Peso relativo no sorteio da composição.
@export var weight: float = 1.0
## Peso extra por noite após o desbloqueio (tornando-o mais comum com o tempo).
@export var weight_growth: float = 0.0
## Máximo por noite (0 = sem limite).
@export var max_per_night: int = 0
## Quantidade mínima garantida na noite de desbloqueio e seguintes.
@export var guaranteed: int = 0
