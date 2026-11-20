class_name TitleBackdrop
extends Node3D
## Cena 3D animada atrás da tela inicial: a fortaleza em ruínas com a muralha e o portão, à noite,
## sob a lua e a névoa, com uma horda de zumbis caminhando para o portão, um herói de guarda, tochas,
## fogueira-farol, pira em chamas, brasas subindo, corvos circulando e raios com trovão.
## A câmera passeia devagar e muda de ângulo a cada submenu (focus()).

const SHOTS := {
	"main": [Vector3(17.0, 6.5, 36.0), Vector3(-1.0, 3.6, 6.0)],
	"new": [Vector3(-4.5, 2.6, 25.5), Vector3(0.6, 2.0, 17.0)],
	"coop": [Vector3(-22.0, 9.5, 20.0), Vector3(0.0, 4.0, 2.0)],
	"settings": [Vector3(5.0, 19.0, 30.0), Vector3(0.0, 0.0, 8.0)],
}
const BASE_R := 13.0
const ZOMBIE_DEFS := ["res://data/enemies/zombie.tres", "res://data/enemies/zombie.tres",
	"res://data/enemies/zombie_fast.tres", "res://data/enemies/zombie_brute.tres"]

var cam: Camera3D
var _env: Environment
var _moon: DirectionalLight3D
var _t: float = 0.0
var _shot_from: Array = SHOTS["main"]
var _shot_to: Array = SHOTS["main"]
var _shot_k: float = 1.0
var _zombies: Array = []  # [CharacterModel, velocidade]
var _hero: CharacterModel
var _crows: Array[Node3D] = []
var _bolt: MeshInstance3D
var _bolt_t: float = 0.0
var _next_bolt: float = 2.2
var _flash: float = 0.0
var _groan_t: float = 3.0
var _crow_t: float = 5.0
var _hero_attack_t: float = 4.0

func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_fortress()
	_build_surroundings()
	_build_horde()
	_build_crows()
	_build_fx()
	cam = Camera3D.new()
	cam.fov = 52.0
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
	_apply_camera(0.0)

## Leva a câmera para o enquadramento do submenu (com transição suave).
func focus(shot: String) -> void:
	if not SHOTS.has(shot):
		return
	_shot_from = _current_shot()
	_shot_to = SHOTS[shot]
	_shot_k = 0.0

## Raio imediato (usado na entrada do logotipo).
func strike() -> void:
	_next_bolt = 0.0

func _current_shot() -> Array:
	var k := _ease(_shot_k)
	return [(_shot_from[0] as Vector3).lerp(_shot_to[0], k), (_shot_from[1] as Vector3).lerp(_shot_to[1], k)]

static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

# --------------------------------------------------------------------------- montagem

func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.015, 0.018, 0.035)
	sky_mat.sky_horizon_color = Color(0.13, 0.06, 0.06)
	sky_mat.ground_horizon_color = Color(0.08, 0.04, 0.035)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.01)
	sky_mat.sun_angle_max = 2.2
	sky_mat.sun_curve = 0.05
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.32, 0.36, 0.5)
	_env.ambient_light_energy = 0.5
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.07, 0.07, 0.1)
	_env.fog_density = 0.012
	_env.fog_sky_affect = 0.35
	_env.glow_enabled = true
	_env.glow_intensity = 0.9
	_env.glow_bloom = 0.15
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	# Lua: luz fria por trás da fortaleza (o disco aparece no céu).
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.62, 0.7, 0.95)
	_moon.light_energy = 0.55
	_moon.rotation_degrees = Vector3(-18.0, 200.0, 0.0)
	_moon.shadow_enabled = Settings.shadows_enabled()
	_moon.directional_shadow_max_distance = 70.0
	add_child(_moon)

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(260, 260)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = MaterialLib.textured("dirt", Color(0.42, 0.36, 0.3), 0.08)
	add_child(mi)
	# Capim seco e vegetação rasteira (o mesmo sistema do mapa), fora da fortaleza e da trilha.
	var f := Foliage.new()
	add_child(f)
	f.build(46.0, Settings.grass_density() * 0.9, func(p: Vector3) -> bool:
		return p.length() > BASE_R + 3.0 and absf(p.x) > 3.0 or p.z > 48.0, 77)

func _build_fortress() -> void:
	var B := ThirdParty.BLENDER
	if ThirdParty.has(B, "keep_ruin"):
		var keep := ThirdParty.instance(B, "keep_ruin")
		add_child(keep)
		var beacon := keep.find_child("Beacon", true, false) as Node3D
		var top := beacon.position if beacon else Vector3(0, 7.8, 0)
		_fire(top, 1.4, 3.4, 16.0)
	# Anel de paliçada com o portão de frente para a câmera (mesma montagem da base do jogo).
	var segments := 20
	var seg_len := 2.0 * PI * BASE_R / segments + 0.15
	for i in segments:
		var ang := (i + 0.5) * TAU / segments
		var pos := Vector3(sin(ang) * BASE_R, 0, -cos(ang) * BASE_R)
		var holder := Node3D.new()
		holder.position = pos
		holder.rotation.y = -ang
		add_child(holder)
		if i == segments / 2:
			_gate(holder, seg_len)
		elif ThirdParty.has(B, "ring_wall_a"):
			var w := ThirdParty.instance(B, "ring_wall_b" if i % 3 == 1 else "ring_wall_a")
			w.scale = Vector3(seg_len * 1.08 / 4.2, 1.0, 1.0)
			holder.add_child(w)
	# Tochas dentro da muralha (menos no celular: cada luz pesa no renderizador web).
	for i in (2 if Platform.low_end else 4):
		var ang := i * TAU / 4 + 0.4
		var t := PropFactory.make_torch()
		t.position = Vector3(sin(ang) * (BASE_R - 2.0), 0, -cos(ang) * (BASE_R - 2.0))
		(t.get_node("Light") as OmniLight3D).omni_range = 7.0
		add_child(t)

func _gate(holder: Node3D, length: float) -> void:
	var B := ThirdParty.BLENDER
	if ThirdParty.has(B, "ring_gate"):
		var door := ThirdParty.instance(B, "ring_gate")
		door.scale = Vector3(length * 0.84 / 3.55, 1.0, 1.0)
		holder.add_child(door)
	for sx: float in [-1.0, 1.0]:
		if ThirdParty.has(B, "ring_tower"):
			var tower := ThirdParty.instance(B, "ring_tower")
			tower.position = Vector3(sx * (length * 0.5 + 0.75), 0, 0.2)
			holder.add_child(tower)
		var torch := Node3D.new()
		torch.position = Vector3(sx * (length * 0.5 + 0.75), 4.3, -0.9)
		holder.add_child(torch)
		torch.add_child(EffectsHub.make_fire_particles(0.6))
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.58, 0.24)
		l.light_energy = 2.2
		l.omni_range = 8.0
		torch.add_child(l)

func _fire(pos: Vector3, size: float, energy: float, rng: float) -> void:
	var fire := EffectsHub.make_fire_particles(size)
	fire.position = pos
	add_child(fire)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.52, 0.2)
	light.light_energy = energy
	light.omni_range = rng
	light.position = pos + Vector3(0, 0.6, 0)
	light.set_meta(&"base", energy)
	light.add_to_group(&"title_flicker")
	add_child(light)

func _build_surroundings() -> void:
	var B := ThirdParty.BLENDER
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var trees := ["pine_dry_a", "pine_dry_b", "tree_dry_a", "tree_dead_a", "pine_dry_a", "tree_dry_b", "tree_dead_b"]
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 500:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(19.0, 60.0)
		var p := Vector3(sin(a) * r, 0, -cos(a) * r)
		# Trilha da horda livre (frente da fortaleza, de onde a câmera olha).
		if p.z > 8.0 and absf(p.x) < 15.0 + (p.z - 8.0) * 0.25:
			continue
		var m: String = trees[rng.randi() % trees.size()]
		if not ThirdParty.has(B, m):
			continue
		var t := ThirdParty.instance(B, m, rng.randf_range(6.0, 9.5))
		t.position = p
		t.rotation.y = rng.randf() * TAU
		add_child(t)
		placed += 1
	for i in 16:
		var a := rng.randf() * TAU
		var r := rng.randf_range(15.0, 40.0)
		var m: String = ["rock_boulder_a", "rock_boulder_b", "rock_slab", "rock_small_a"][i % 4]
		if ThirdParty.has(B, m):
			var rk := ThirdParty.instance(B, m)
			rk.position = Vector3(sin(a) * r, 0, -cos(a) * r)
			rk.rotation.y = rng.randf() * TAU
			rk.scale = Vector3.ONE * rng.randf_range(0.7, 1.4)
			add_child(rk)
	# Restos na trilha: carroça queimada, pira de corpos em chamas, estacas com cabeças.
	for spec: Array in [["burned_cart", Vector3(-9.5, 0, 27.0), 0.5], ["corpse_pyre", Vector3(10.5, 0, 24.0), 0.0],
			["pike_heads", Vector3(-5.5, 0, 18.5), 0.3], ["pike_heads", Vector3(6.0, 0, 19.0), -0.4],
			["spikes", Vector3(0.0, 0, 15.6), 0.0], ["car_wreck_a", Vector3(15.0, 0, 33.0), 2.2]]:
		if ThirdParty.has(B, spec[0]):
			var o := ThirdParty.instance(B, spec[0])
			o.position = spec[1]
			o.rotation.y = spec[2]
			add_child(o)
	_fire(Vector3(10.5, 1.0, 24.0), 1.1, 2.6, 11.0)
	# Tochas fincadas ao longo da trilha: iluminam a horda que se aproxima.
	for tp: Vector3 in [Vector3(-7.5, 0, 31.0), Vector3(6.5, 0, 40.0), Vector3(-6.0, 0, 48.0)]:
		var t := PropFactory.make_torch()
		t.position = tp
		var l := t.get_node("Light") as OmniLight3D
		l.omni_range = 11.0
		l.light_energy = 2.6
		add_child(t)

func _build_horde() -> void:
	var n := 12 if Platform.low_end else 18
	var defs: Array[EnemyDef] = []
	for p: String in ZOMBIE_DEFS:
		defs.append(load(p) as EnemyDef)
	for i in n:
		var z := CharacterModel.new()
		add_child(z)
		var d: EnemyDef = defs[i % defs.size()]
		z.build_zombie(d)
		var speed := randf_range(0.9, 1.5) * (1.7 if d.id == &"zombie_fast" else 1.0) * (0.75 if d.id == &"zombie_brute" else 1.0)
		z.position = Vector3(randf_range(-11.0, 11.0), 0, randf_range(18.0, 62.0))
		_zombies.append([z, speed])
	# Herói de guarda diante do portão, de frente para a horda.
	_hero = CharacterModel.new()
	add_child(_hero)
	_hero.build_hero("knight")
	_hero.position = Vector3(0.6, 0, 17.2)
	_hero.rotation.y = PI

func _build_crows() -> void:
	var path := "res://assets/models/blender/eagle.glb"
	if not ResourceLoader.exists(path):
		return
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.03, 0.035)
	dark.roughness = 0.8
	for i in 4:
		var c := (load(path) as PackedScene).instantiate() as Node3D
		c.scale = Vector3.ONE * 0.75
		for mi: MeshInstance3D in c.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = dark
		var aps := c.find_children("*", "AnimationPlayer", true, false)
		if aps.size() > 0:
			var ap := aps[0] as AnimationPlayer
			for nm in ap.get_animation_list():
				ap.get_animation(nm).loop_mode = Animation.LOOP_LINEAR
			ap.play("glide" if i % 2 == 0 and ap.has_animation("glide") else "fly")
			ap.seek(randf() * 1.5)
		c.set_meta(&"phase", i * TAU / 4.0 + randf() * 0.5)
		c.set_meta(&"radius", randf_range(7.0, 13.0))
		c.set_meta(&"height", randf_range(13.0, 18.0))
		add_child(c)
		_crows.append(c)

func _build_fx() -> void:
	# Brasas subindo por cima de tudo (vento leve para a direita).
	var p := GPUParticles3D.new()
	p.amount = 60 if Platform.low_end else 120
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.visibility_aabb = AABB(Vector3(-40, -2, -30), Vector3(80, 40, 90))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(26, 1, 26)
	pm.direction = Vector3(0.3, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0.4, 0.3, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.7, 0.25, 0.0))
	grad.add_point(0.15, Color(1.0, 0.6, 0.2, 1.0))
	grad.set_color(grad.get_point_count() - 1, Color(0.8, 0.15, 0.02, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = EffectsHub._soft_dot()
	q.material = mat
	p.draw_pass_1 = q
	p.position = Vector3(0, 0, 18)
	add_child(p)
	# Névoa rasteira: plano com ruído animado no shader, rente ao chão.
	var mist := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(160, 160)
	mist.mesh = pl
	mist.position.y = 0.7
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform vec3 tint = vec3(0.42, 0.45, 0.55);
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * n(p); p *= 2.03; a *= 0.5; } return v; }
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz * 0.06;
	float m = fbm(p + vec2(TIME * 0.025, TIME * 0.01)) * 0.65 + fbm(p * 2.1 - vec2(TIME * 0.04, 0.0)) * 0.35;
	float edge = 1.0 - smoothstep(35.0, 75.0, length(wpos.xz));
	ALBEDO = tint;
	ALPHA = smoothstep(0.38, 0.85, m) * 0.32 * edge;
}
"""
	var smat := ShaderMaterial.new()
	smat.shader = sh
	mist.material_override = smat
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mist)
	# Raio: fita em zigue-zague no céu, acesa por um instante.
	_bolt = MeshInstance3D.new()
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.85, 0.9, 1.0)
	bm.emission_enabled = true
	bm.emission = Color(0.7, 0.8, 1.0)
	bm.emission_energy_multiplier = 3.0
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bolt.material_override = bm
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)

func _bolt_mesh(x: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := Vector3(x, 75.0, -70.0)
	var w := 0.9
	var pts: Array[Vector3] = [p]
	while p.y > 8.0:
		p += Vector3(randf_range(-4.0, 4.0), -randf_range(4.0, 8.0), 0)
		pts.append(p)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var side := Vector3(w * (1.0 - float(i) / pts.size()) + 0.15, 0, 0)
		st.add_vertex(a - side)
		st.add_vertex(a + side)
		st.add_vertex(b + side)
		st.add_vertex(a - side)
		st.add_vertex(b + side)
		st.add_vertex(b - side)
		# Galho lateral de vez em quando.
		if randf() < 0.3:
			var c := b + Vector3(randf_range(-7, 7), -randf_range(3, 7), 0)
			st.add_vertex(b - side * 0.5)
			st.add_vertex(b + side * 0.5)
			st.add_vertex(c)
	return st.commit()

# --------------------------------------------------------------------------- animação

func _process(delta: float) -> void:
	_t += delta
	_shot_k = minf(1.0, _shot_k + delta / 1.8)
	_apply_camera(_t)
	# Horda: caminha até o portão e recomeça lá atrás.
	for e: Array in _zombies:
		var z: CharacterModel = e[0]
		var sp: float = e[1]
		z.position.z -= sp * delta
		z.position.x += sin(_t * 0.7 + z.position.z) * 0.15 * delta
		z.rotation.y = sin(_t * 0.5 + z.position.x) * 0.15
		z.animate(delta, sp / 2.2)
		if z.position.z < 18.5:
			z.position = Vector3(randf_range(-11.0, 11.0), 0, randf_range(56.0, 66.0))
	if _hero:
		_hero.animate(delta, 0.0)
		_hero_attack_t -= delta
		if _hero_attack_t <= 0.0:
			_hero_attack_t = randf_range(4.0, 7.0)
			_hero.play_attack(0.6)
			AudioManager.play(&"swing", -14.0)
	for c in _crows:
		var ph: float = float(c.get_meta(&"phase")) + _t * 0.35
		var r: float = c.get_meta(&"radius")
		var pos := Vector3(cos(ph) * r, float(c.get_meta(&"height")) + sin(_t * 0.8 + r) * 0.8, sin(ph) * r)
		var ahead := Vector3(cos(ph + 0.1) * r, pos.y, sin(ph + 0.1) * r)
		c.position = pos
		c.look_at(ahead, Vector3.UP)
	for l in get_tree().get_nodes_in_group(&"title_flicker"):
		var base: float = l.get_meta(&"base")
		(l as OmniLight3D).light_energy = base * (0.85 + 0.15 * sin(_t * 13.0 + base) * sin(_t * 7.3))
	# Raios.
	_next_bolt -= delta
	if _next_bolt <= 0.0:
		_next_bolt = randf_range(7.0, 14.0)
		_bolt.mesh = _bolt_mesh(randf_range(-45.0, 45.0))
		_bolt.visible = true
		_bolt_t = 0.22
		_flash = 1.0
		var delay := randf_range(0.25, 1.1)
		get_tree().create_timer(delay).timeout.connect(func() -> void: AudioManager.play(&"thunder", -6.0))
	if _bolt_t > 0.0:
		_bolt_t -= delta
		_bolt.visible = _bolt_t > 0.0 and fmod(_bolt_t, 0.08) > 0.03
	_flash = maxf(0.0, _flash - delta * 2.2)
	var f := _flash * (0.6 + 0.4 * sin(_t * 60.0))
	_moon.light_energy = 0.55 + f * 3.5
	_env.ambient_light_energy = 0.5 + f * 1.4
	_env.fog_light_color = Color(0.07, 0.07, 0.1).lerp(Color(0.5, 0.55, 0.7), f * 0.5)
	# Sons de ambiente.
	_groan_t -= delta
	if _groan_t <= 0.0:
		_groan_t = randf_range(3.0, 6.5)
		AudioManager.play(&"groan", -16.0)
	_crow_t -= delta
	if _crow_t <= 0.0:
		_crow_t = randf_range(8.0, 15.0)
		AudioManager.play(&"crow", -12.0)

func _apply_camera(t: float) -> void:
	if cam == null:
		return
	var s := _current_shot()
	var pos: Vector3 = s[0]
	var look: Vector3 = s[1]
	# Passeio lento: órbita pequena e balanço de respiração.
	var orbit := Basis(Vector3.UP, sin(t * 0.06) * 0.12)
	pos = look + orbit * (pos - look) + Vector3(0, sin(t * 0.4) * 0.15, 0)
	cam.global_position = pos
	cam.look_at(look + Vector3(sin(t * 0.23) * 0.2, 0, 0), Vector3.UP)
