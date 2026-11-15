class_name DayNightVisuals
extends Node
## Atmosfera de terror: traduz o TimeManager em luz, céu e neblina (dia nublado,
## entardecer cor de sangue, noite escura), acende as lanternas dos heróis, controla a
## lua de sangue (hordas de chefe) e as tempestades (relâmpagos, trovões e chuva) e
## toca os sons de ambiente (corvos de dia; gemidos, gritos e sussurros à noite).

@export var sun_path: NodePath
@export var env_path: NodePath

static var current: DayNightVisuals

var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _lights_on: bool = false
## Direção do sol aplicada; só muda quando a diferença passa de SUN_STEP (graus).
## Girar a luz um pouquinho a cada quadro faz as sombras "cintilarem".
var _sun_applied := Vector2(INF, INF)
const SUN_STEP := 0.5

const DAY_SUN := Color(0.95, 0.88, 0.76)    # sol pálido de dia nublado
const DUSK_SUN := Color(1.0, 0.34, 0.16)    # entardecer cor de sangue
const NIGHT_MOON := Color(0.45, 0.58, 0.8)
const BLOOD_MOON := Color(1.0, 0.2, 0.12)
const LANTERN := Color(1.0, 0.7, 0.4)

## Lua de sangue: a noite da horda de chefe (o céu já avermelha no entardecer).
var blood_moon: bool = false
## Tempestade nesta noite: relâmpagos, trovões e chuva.
var storm: bool = false
var _flash: float = 0.0       # brilho do relâmpago (0..1)
var _bolt_t: float = 4.0
var _groan_t: float = 4.0
var _creepy_t: float = 14.0
var _crow_t: float = 8.0
var _howled: bool = false
var _rain: GPUParticles3D
var _blood_tint: float = 0.0  # 0..1, suaviza a entrada da lua de sangue

func _enter_tree() -> void:
	current = self

func _exit_tree() -> void:
	if current == self:
		current = null
	AudioManager.storm = false

func _ready() -> void:
	_sun = get_node(sun_path)
	add_to_group(&"quality_sun")
	_env = (get_node(env_path) as WorldEnvironment).environment
	_sky = _env.sky.sky_material as ProceduralSkyMaterial
	_build_rain()
	apply_quality()
	TimeManager.phase_changed.connect(_on_phase_changed)
	_roll_night()

## Decide lua de sangue e tempestade da rodada. Determinístico pela rodada,
## então anfitrião e convidados veem o mesmo clima sem sincronizar nada.
func _roll_night() -> void:
	var w := TimeManager.wave()
	var horde: HordeDirector = GameManager.world.get(&"horde") if GameManager.world else null
	blood_moon = horde != null and horde.config.is_boss_wave(w)
	storm = not blood_moon and (w == 1 or (w * 37 + 11) % 100 < 40)

func _on_phase_changed(phase: int, _day: int) -> void:
	if phase == TimeManager.Phase.DAWN:
		_roll_night()
		_howled = false
	elif phase == TimeManager.Phase.NIGHT:
		_roll_night()
		if blood_moon:
			EventBus.banner.emit("LUA DE SANGUE", "Os mortos estão mais famintos esta noite...", Color(0.95, 0.15, 0.1))
		elif storm:
			EventBus.notify("Uma tempestade se aproxima. Fique perto da luz.", Color(0.6, 0.75, 1.0))

func is_storming() -> bool:
	return storm and TimeManager.phase == TimeManager.Phase.NIGHT

func _process(delta: float) -> void:
	var dl := TimeManager.daylight()   # 0 noite .. 1 dia
	var phase := TimeManager.phase
	var r := TimeManager.phase_ratio()
	var night := 1.0 - dl
	# A lua de sangue entra no entardecer do dia da horda de chefe.
	var want_blood := 1.0 if blood_moon and (phase == TimeManager.Phase.NIGHT or phase == TimeManager.Phase.DUSK) else 0.0
	_blood_tint = move_toward(_blood_tint, want_blood * night, delta * 0.4)
	AudioManager.storm = is_storming()
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
		col = NIGHT_MOON.lerp(BLOOD_MOON, _blood_tint)
	else:
		elev = deg_to_rad(lerpf(12.0, 62.0, sin(sun_progress * PI)))
		col = DUSK_SUN.lerp(DAY_SUN, smoothstep(0.35, 0.85, dl)).lerp(BLOOD_MOON, _blood_tint)
	var azim := lerpf(deg_to_rad(-70.0), deg_to_rad(70.0), sun_progress)
	var want := Vector2(rad_to_deg(-elev), rad_to_deg(azim))
	if absf(want.x - _sun_applied.x) >= SUN_STEP or absf(want.y - _sun_applied.y) >= SUN_STEP:
		_sun_applied = want
		_sun.rotation = Vector3(deg_to_rad(want.x), deg_to_rad(want.y), 0)
	_update_lightning(delta)
	var fl := _flash
	_sun.light_color = col.lerp(Color(0.8, 0.88, 1.0), fl)
	_sun.light_energy = lerpf(lerpf(0.5, 0.6, _blood_tint), 1.15, dl) + fl * 2.6
	# Ambiente / céu
	var night_amb := Color(0.3, 0.35, 0.5).lerp(Color(0.48, 0.18, 0.15), _blood_tint)
	var day_amb := Color(0.54, 0.58, 0.63)
	_env.ambient_light_color = night_amb.lerp(day_amb, dl).lerp(Color(0.7, 0.78, 1.0), fl)
	_env.ambient_light_energy = lerpf(0.95, 0.62, dl) + fl * 1.4
	var top_night := Color(0.008, 0.01, 0.022).lerp(Color(0.1, 0.0, 0.0), _blood_tint)
	var hor_night := Color(0.04, 0.045, 0.06).lerp(Color(0.38, 0.04, 0.02), _blood_tint)
	_sky.sky_top_color = top_night.lerp(Color(0.34, 0.4, 0.47), dl).lerp(Color(0.5, 0.55, 0.7), fl)
	_sky.sky_horizon_color = hor_night.lerp(Color(0.6, 0.6, 0.57), dl)
	if phase == TimeManager.Phase.DUSK or phase == TimeManager.Phase.DAWN:
		_sky.sky_horizon_color = _sky.sky_horizon_color.lerp(Color(0.72, 0.12, 0.05), 0.6 * (1.0 - absf(dl - 0.4)))
	_sky.ground_horizon_color = _sky.sky_horizon_color
	# Neblina: névoa cinza de dia, breu à noite (vermelha na lua de sangue).
	_env.fog_enabled = true
	var fog_night := Color(0.05, 0.06, 0.085).lerp(Color(0.22, 0.03, 0.03), _blood_tint)
	_env.fog_light_color = fog_night.lerp(Color(0.56, 0.58, 0.6), dl).lerp(Color(0.5, 0.55, 0.65), fl)
	var storm_fog := 0.002 if is_storming() else 0.0
	_env.fog_density = lerpf(0.0085, 0.0055, dl) + storm_fog
	_env.adjustment_saturation = lerpf(0.6, 0.84, dl)
	_env.adjustment_contrast = lerpf(1.04, 1.1, dl)
	# Tochas e lanternas acendem ao entardecer.
	var want_lights := dl < 0.55
	if want_lights != _lights_on:
		_lights_on = want_lights
		for n in get_tree().get_nodes_in_group("night_lights"):
			for c in n.get_children():
				if c is OmniLight3D or c is GPUParticles3D:
					(c as Node3D).visible = want_lights
	_update_lanterns(night)
	_update_rain()
	_update_sounds(delta, phase)

# --- Lanterna dos heróis -------------------------------------------------------------

func _update_lanterns(night: float) -> void:
	var k := smoothstep(0.35, 0.85, night)
	var t := Time.get_ticks_msec() * 0.001
	for n in get_tree().get_nodes_in_group(&"hero_lantern"):
		var l := n as OmniLight3D
		l.visible = k > 0.01
		if l.visible:
			# Chama tremulando de leve.
			var flicker := 0.9 + 0.06 * sin(t * 9.0 + l.get_instance_id()) + 0.04 * sin(t * 23.0)
			l.light_energy = 2.2 * k * flicker
			l.light_color = LANTERN

# --- Tempestade -----------------------------------------------------------------------

func _update_lightning(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 3.2)
	if not is_storming() or not GameManager.is_playing():
		return
	_bolt_t -= delta
	if _bolt_t > 0.0:
		return
	_bolt_t = randf_range(7.0, 18.0)
	_flash = 1.0
	# Segundo clarão logo depois (relâmpago "piscando").
	get_tree().create_timer(0.14).timeout.connect(func() -> void: _flash = maxf(_flash, 0.75))
	var delay := randf_range(0.4, 2.2)
	var vol := lerpf(0.0, -9.0, delay / 2.2)  # trovão mais distante = mais baixo
	get_tree().create_timer(delay).timeout.connect(func() -> void: AudioManager.play(&"thunder", vol, randf_range(0.85, 1.05)))

## Brilho atual do relâmpago (a interface usa para clarear a tela).
func lightning_flash() -> float:
	return _flash

func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 900
	_rain.lifetime = 0.9
	_rain.preprocess = 0.9
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(26, 0.5, 26)
	pm.direction = Vector3(0.18, -1, 0.1)
	pm.spread = 3.0
	pm.initial_velocity_min = 26.0
	pm.initial_velocity_max = 32.0
	pm.gravity = Vector3(0, -10, 0)
	pm.particle_flag_align_y = true
	_rain.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.035, 0.9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.7, 0.78, 0.9, 0.32)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	_rain.draw_pass_1 = mesh
	_rain.emitting = false
	_rain.visible = false
	add_child(_rain)

func _update_rain() -> void:
	var on := is_storming() and Settings.quality > 0
	if on != _rain.emitting:
		_rain.emitting = on
		if on:
			_rain.visible = true
	if not on and _rain.visible and not _rain.emitting and Engine.get_process_frames() % 60 == 0:
		_rain.visible = false
	var hero := GameManager.hero
	if _rain.visible and hero:
		_rain.global_position = hero.global_position + Vector3(-3, 16, -2)

# --- Sons de terror ---------------------------------------------------------------------

func _update_sounds(delta: float, phase: int) -> void:
	if not GameManager.is_playing():
		return
	var hero := GameManager.hero
	if hero == null:
		return
	var at := func(dist: float) -> Vector3:
		var a := randf() * TAU
		return hero.global_position + Vector3(cos(a), 0, sin(a)) * dist
	if phase == TimeManager.Phase.NIGHT:
		if not _howled and TimeManager.phase_time > 1.5:
			_howled = true
			AudioManager.play_3d(&"howl", at.call(30.0), -1.0, 0.85)
		# Gemidos distantes.
		_groan_t -= delta
		if _groan_t <= 0.0:
			_groan_t = randf_range(5.0, 11.0)
			AudioManager.play_3d(&"groan", at.call(25.0), -2.0)
		# De vez em quando, algo pior: um grito ao longe ou sussurros.
		_creepy_t -= delta
		if _creepy_t <= 0.0:
			_creepy_t = randf_range(16.0, 34.0)
			if randf() < 0.45:
				AudioManager.play_3d(&"scream", at.call(45.0), -6.0, randf_range(0.8, 0.95))
			else:
				AudioManager.play(&"ghost", -15.0, randf_range(0.8, 1.0), "Ambient")
	else:
		# Corvos durante o dia; sussurros no entardecer.
		_crow_t -= delta
		if _crow_t <= 0.0:
			_crow_t = randf_range(12.0, 28.0)
			AudioManager.play_3d(&"crow", at.call(22.0), -5.0)
		if phase == TimeManager.Phase.DUSK:
			_creepy_t -= delta
			if _creepy_t <= 0.0:
				_creepy_t = randf_range(20.0, 35.0)
				AudioManager.play(&"ghost", -18.0, 0.85, "Ambient")
	# Na área contaminada os sussurros não param.
	if AudioManager.dark_amount() > 0.5 and randf() < delta / 9.0:
		AudioManager.play(&"ghost", -12.0, randf_range(0.75, 0.95), "Ambient")

## Configurações: sombras ligadas só nas qualidades Média e Alta; chuva mais leve na Média.
func apply_quality() -> void:
	if _sun:
		_sun.shadow_enabled = Settings.shadows_enabled()
	if _rain:
		_rain.amount = [200, 450, 900][Settings.quality]
