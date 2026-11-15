extends Node
## Relógio interno e ciclo de rodadas: 2 minutos de preparação (amanhecer, dia,
## entardecer) e a horda (noite), que termina quando todos os zumbis morrem
## (ou no limite de tempo, quando o sol queima os restantes). 100 hordas no total.

enum Phase { DAWN, DAY, DUSK, NIGHT }
const PHASE_NAMES := ["Amanhecer", "Dia", "Entardecer", "Noite"]
const PRESETS := {
	"normal": "res://data/config/day_night_waves.tres",
}
const TOTAL_WAVES := 100

signal phase_changed(phase: Phase, day: int)
signal night_warning(seconds_left: float)

var config: DayNightConfig
var phase: Phase = Phase.DAY
var phase_time: float = 0.0   ## tempo decorrido no período atual
var day: int = 1
var running: bool = false
var time_scale: float = 1.0
var _warned: bool = false

func _ready() -> void:
	setup("normal")

func setup(preset: String) -> void:
	config = load(PRESETS.get(preset, PRESETS.normal)) as DayNightConfig
	day = 1
	phase = Phase.DAWN  # a 1ª rodada também tem os 2 minutos completos
	phase_time = 0.0
	_warned = false
	running = false

func _process(delta: float) -> void:
	if not running or get_tree().paused:
		return
	phase_time += delta * time_scale
	var dur := phase_duration(phase)
	if phase == Phase.DUSK and not _warned and dur - phase_time <= config.night_warning_time:
		_warned = true
		night_warning.emit(dur - phase_time)
	if phase_time >= dur:
		advance_phase()

func phase_duration(p: Phase) -> float:
	match p:
		Phase.DAWN: return config.dawn_duration
		Phase.DAY: return config.day_duration
		Phase.DUSK: return config.dusk_duration
		_: return config.night_duration

func advance_phase() -> void:
	phase_time = 0.0
	_warned = false
	match phase:
		Phase.DAWN: phase = Phase.DAY
		Phase.DAY: phase = Phase.DUSK
		Phase.DUSK: phase = Phase.NIGHT
		Phase.NIGHT:
			phase = Phase.DAWN
			day += 1
	phase_changed.emit(phase, day)

func set_state(p: Phase, d: int, t: float) -> void:
	phase = p
	day = d
	phase_time = t
	_warned = false
	phase_changed.emit(phase, day)

func is_night() -> bool:
	return phase == Phase.NIGHT

## Rodada atual (1..TOTAL_WAVES). A horda da rodada N é a "noite" do dia N.
func wave() -> int:
	return day

## Pula o resto da preparação e chama a horda agora.
func start_horde_now() -> void:
	if phase != Phase.NIGHT and running:
		set_state(Phase.NIGHT, day, 0.0)

## Encerra a horda (todos os zumbis mortos): começa a próxima preparação.
func finish_horde() -> void:
	if phase == Phase.NIGHT:
		advance_phase()

## Tempo restante da preparação (0 durante a horda).
func prep_seconds_left() -> float:
	return seconds_until_night()

func phase_ratio() -> float:
	return clampf(phase_time / phase_duration(phase), 0.0, 1.0)

func phase_name() -> String:
	return PHASE_NAMES[phase]

## Noite atual (ou a próxima, se for dia). A noite do dia N é a noite N.
func night_number() -> int:
	return day

## Horário de relógio 0-24 interpolado dentro do período atual.
func clock_hours() -> float:
	var starts := [config.dawn_clock_start, config.day_clock_start, config.dusk_clock_start, config.night_clock_start]
	var a: float = starts[phase]
	var b: float = starts[(phase + 1) % 4]
	if b < a:
		b += 24.0
	return fmod(lerpf(a, b, phase_ratio()), 24.0)

func clock_string() -> String:
	var h := clock_hours()
	return "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]

## Segundos de jogo até o início da próxima noite (0 se já é noite).
func seconds_until_night() -> float:
	match phase:
		Phase.NIGHT: return 0.0
		Phase.DUSK: return config.dusk_duration - phase_time
		Phase.DAY: return config.day_duration - phase_time + config.dusk_duration
		_: return config.dawn_duration - phase_time + config.day_duration + config.dusk_duration

## Luz do sol 0 (noite) .. 1 (meio-dia) para os visuais.
func daylight() -> float:
	var r := phase_ratio()
	match phase:
		Phase.DAWN: return smoothstep(0.0, 1.0, r) * 0.8
		Phase.DAY: return 0.8 + 0.2 * sin(r * PI)
		Phase.DUSK: return 0.8 * (1.0 - smoothstep(0.0, 1.0, r))
		_: return 0.0
