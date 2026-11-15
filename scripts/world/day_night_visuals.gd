class_name DayNightVisuals
extends Node
## Traduz o estado do TimeManager em luz, céu, neblina e luzes noturnas.

@export var sun_path: NodePath
@export var env_path: NodePath

var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _lights_on: bool = false
var _groan_t: float = 4.0
## Direção do sol aplicada; só muda quando a diferença passa de SUN_STEP (graus).
## Girar a luz um pouquinho a cada quadro faz as sombras "cintilarem".
var _sun_applied := Vector2(INF, INF)
const SUN_STEP := 0.5

const DAY_SUN := Color(1.0, 0.9, 0.72)
const DUSK_SUN := Color(1.0, 0.55, 0.3)
const NIGHT_MOON := Color(0.45, 0.55, 0.95)

func _ready() -> void:
	_sun = get_node(sun_path)
	add_to_group(&"quality_sun")
	apply_quality()
	_env = (get_node(env_path) as WorldEnvironment).environment
	_sky = _env.sky.sky_material as ProceduralSkyMaterial

func _process(delta: float) -> void:
	var dl := TimeManager.daylight()   # 0 noite .. 1 dia
	var phase := TimeManager.phase
	var r := TimeManager.phase_ratio()
	# Ângulo do sol ao longo do dia (nascente -> poente); à noite, a "lua".
	var sun_progress := 0.0
	match phase:
		TimeManager.Phase.DAWN: sun_progress = r * 0.12
		TimeManager.Phase.DAY: sun_progress = 0.12 + r * 0.76
		TimeManager.Phase.DUSK: sun_progress = 0.88 + r * 0.12
		_: sun_progress = r
	var elev: float
	var col: Color
	if phase == TimeManager.Phase.NIGHT:
		elev = deg_to_rad(35.0 + 20.0 * sin(r * PI))
		col = NIGHT_MOON
	else:
		elev = deg_to_rad(lerpf(12.0, 62.0, sin(sun_progress * PI)))
		col = DUSK_SUN.lerp(DAY_SUN, smoothstep(0.3, 0.8, dl))
	var azim := lerpf(deg_to_rad(-70.0), deg_to_rad(70.0), sun_progress)
	var want := Vector2(rad_to_deg(-elev), rad_to_deg(azim))
	if absf(want.x - _sun_applied.x) >= SUN_STEP or absf(want.y - _sun_applied.y) >= SUN_STEP:
		_sun_applied = want
		_sun.rotation = Vector3(deg_to_rad(want.x), deg_to_rad(want.y), 0)
	_sun.light_color = col
	var night_energy := 0.5
	_sun.light_energy = lerpf(night_energy, 1.45, dl)
	# Ambiente / céu
	var night_amb := Color(0.24, 0.28, 0.5)
	var day_amb := Color(0.62, 0.7, 0.85)
	_env.ambient_light_color = night_amb.lerp(day_amb, dl)
	_env.ambient_light_energy = lerpf(0.7, 0.65, dl)
	_sky.sky_top_color = Color(0.03, 0.04, 0.1).lerp(Color(0.32, 0.55, 0.9), dl)
	_sky.sky_horizon_color = Color(0.12, 0.08, 0.14).lerp(Color(0.85, 0.78, 0.65), dl)
	if phase == TimeManager.Phase.DUSK or phase == TimeManager.Phase.DAWN:
		_sky.sky_horizon_color = _sky.sky_horizon_color.lerp(Color(0.95, 0.4, 0.2), 0.5 * (1.0 - absf(dl - 0.4)))
	_sky.ground_horizon_color = _sky.sky_horizon_color
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.06, 0.07, 0.14).lerp(Color(0.75, 0.78, 0.85), dl)
	_env.fog_density = lerpf(0.012, 0.0015, dl)
	_env.adjustment_saturation = lerpf(0.8, 1.22, dl)
	# Tochas acendem ao entardecer.
	var want_lights := dl < 0.55
	if want_lights != _lights_on:
		_lights_on = want_lights
		for n in get_tree().get_nodes_in_group("night_lights"):
			for c in n.get_children():
				if c is OmniLight3D or c is GPUParticles3D:
					(c as Node3D).visible = want_lights
	# Gemidos distantes à noite (atmosfera de terror).
	if phase == TimeManager.Phase.NIGHT and GameManager.is_playing():
		_groan_t -= delta
		if _groan_t <= 0.0:
			_groan_t = randf_range(5.0, 11.0)
			var hero := GameManager.hero
			if hero:
				var a := randf() * TAU
				AudioManager.play_3d(&"groan", hero.global_position + Vector3(cos(a), 0, sin(a)) * 25.0, -2.0)

## Configurações: sombras ligadas só nas qualidades Média e Alta.
func apply_quality() -> void:
	if _sun:
		_sun.shadow_enabled = Settings.shadows_enabled()
