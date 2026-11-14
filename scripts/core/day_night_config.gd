class_name DayNightConfig
extends Resource
## Durações (em segundos) de cada período do ciclo. Editável por dados.

@export var dawn_duration: float = 120.0
@export var day_duration: float = 600.0
@export var dusk_duration: float = 120.0
@export var night_duration: float = 480.0
## Horário de relógio (0-24) correspondente ao início de cada período — só visual.
@export var dawn_clock_start: float = 5.0
@export var day_clock_start: float = 7.0
@export var dusk_clock_start: float = 18.0
@export var night_clock_start: float = 20.0
## Aviso (segundos antes da noite) para o jogador voltar à base.
@export var night_warning_time: float = 60.0
