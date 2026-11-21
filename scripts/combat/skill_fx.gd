class_name SkillFx
extends RefCounted
## Efeitos visuais das habilidades dos heróis. As formas vêm do Blender (tools/blender_skill_fx.py →
## assets/models/blender/skill_fx.glb) e todas usam o shader aditivo skill_fx.gdshader (núcleo claro, borda
## colorida, ruído que dissolve). Tudo é só visual: dano e lógica continuam nas habilidades.

const GLB := "res://assets/models/blender/skill_fx.glb"
const SHADER := preload("res://assets/effects/shaders/skill_fx.gdshader")
const NOISE := preload("res://assets/effects/textures/fx_noise.png")

# Paletas (núcleo, borda).
const KNIGHT_FIRE := [Color(1.0, 0.95, 0.75), Color(1.0, 0.42, 0.06)]
const KNIGHT_GOLD := [Color(1.0, 0.97, 0.8), Color(1.0, 0.72, 0.18)]
const WIND := [Color(1.0, 1.0, 1.0), Color(0.45, 0.75, 1.0)]
const ARCANE := [Color(0.95, 0.85, 1.0), Color(0.62, 0.22, 1.0)]
const HUNTER := [Color(0.95, 1.0, 0.85), Color(0.35, 0.95, 0.45)]
const STEEL := [Color(1.0, 0.98, 0.85), Color(1.0, 0.6, 0.15)]
const SKY := [Color(1.0, 1.0, 0.95), Color(0.55, 0.85, 1.0)]

static var _meshes: Dictionary = {}

static func mesh(name: String) -> Mesh:
	if _meshes.is_empty():
		if not ResourceLoader.exists(GLB):
			return null
		var root := (load(GLB) as PackedScene).instantiate()
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			_meshes[String(mi.name)] = mi.mesh
		root.free()
	return _meshes.get(name)

static func material(pal: Array, intensity: float = 2.0, mode: int = 0, extra: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"noise_tex", NOISE)
	m.set_shader_parameter(&"core_color", pal[0])
	m.set_shader_parameter(&"edge_color", pal[1])
	m.set_shader_parameter(&"intensity", intensity)
	m.set_shader_parameter(&"mode", mode)
	for k: String in extra:
		m.set_shader_parameter(StringName(k), extra[k])
	return m

## Coloca uma forma no mundo (ou presa a `parent`). Retorna null se o GLB não existir.
static func spawn(name: String, mat: ShaderMaterial, pos: Vector3, parent: Node = null) -> MeshInstance3D:
	var hub := EffectsHub.instance()
	var m := mesh(name)
	if m == null or (hub == null and parent == null):
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else hub).add_child(mi)
	if parent:
		mi.position = pos
	else:
		mi.global_position = pos
	return mi

static func _param(mi: Node, mat: ShaderMaterial, key: StringName, from: float, to: float, dur: float, delay: float = 0.0) -> Tween:
	var tw := mi.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter(key, v), from, to, dur)
	return tw

## Some (dissolve + fade) e se apaga.
static func _vanish(mi: MeshInstance3D, mat: ShaderMaterial, dur: float, delay: float = 0.0) -> void:
	if mi == null:
		return
	var tw := mi.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(func(v: float) -> void:
		mat.set_shader_parameter(&"fade", 1.0 - v)
		mat.set_shader_parameter(&"dissolve", v * 0.9), 0.0, 1.0, dur)
	tw.tween_callback(mi.queue_free)

# --- Cavaleiro ---------------------------------------------------------------------

## Golpe Giratório: dois rastros de lâmina dando a volta + chão rachado em brasa.
static func whirlwind(pos: Vector3, radius: float, yaw: float) -> void:
	for k in 2:
		var mat := material(KNIGHT_FIRE if k == 0 else [Color(1.0, 0.85, 0.6), Color(0.9, 0.15, 0.05)], 2.6 if k == 0 else 1.8, 0,
			{"tail": 0.9, "head": 0.0, "noise_scroll": Vector2(-3.0, 0.0)})
		var s := spawn("SlashSweep", mat, pos + Vector3.UP * (0.25 + 0.35 * k))
		if s == null:
			return
		var r := radius * (0.92 if k == 0 else 0.7)
		s.scale = Vector3(r, 1.0 + 0.3 * k, r)
		s.rotation.y = yaw + PI * k
		var tw := s.create_tween()
		tw.tween_property(s, "rotation:y", yaw + PI * k + TAU * (1.0 if k == 0 else 1.2), 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_param(s, mat, &"head", 0.0, 1.0, 0.22)
		_vanish(s, mat, 0.25, 0.22)
	var cm := material([Color(1.0, 0.75, 0.35), Color(0.75, 0.12, 0.02)], 1.6, 0, {"tail": 1.0})
	var crack := spawn("GroundCrack", cm, pos + Vector3.UP * 0.03)
	if crack:
		crack.scale = Vector3.ONE * radius * 0.25
		crack.rotation.y = randf() * TAU
		crack.create_tween().tween_property(crack, "scale", Vector3.ONE * radius * 0.95, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_vanish(crack, cm, 0.9, 0.25)

## Investida: linhas de velocidade e escudo de vento presos ao herói enquanto ele avança.
static func dash(hero: Node3D, dir: Vector3, duration: float) -> void:
	var holder := Node3D.new()
	hero.add_child(holder)
	holder.position = Vector3.ZERO
	holder.look_at(hero.global_position + dir, Vector3.UP)
	var lm := material(WIND, 2.2, 0, {"tail": 1.0, "noise_scroll": Vector2(4.0, 0.0)})
	var lines := spawn("SpeedLines", lm, Vector3.ZERO, holder)
	if lines:
		lines.scale = Vector3(1.0, 1.0, 3.2)
	var wm := material([Color(1, 1, 1), Color(1.0, 0.8, 0.35)], 1.6, 0, {"noise_scroll": Vector2(0.0, -2.0), "flicker": 0.6})
	var wedge := spawn("ChargeWedge", wm, Vector3(0, 0, -0.2), holder)
	var life := maxf(0.2, duration) + 0.05
	var tw := holder.create_tween()
	tw.tween_interval(life)
	tw.tween_callback(func() -> void:
		# Ao parar: o rastro fica no lugar e some.
		var p := holder.global_transform
		holder.top_level = true
		holder.global_transform = p
		_vanish(lines, lm, 0.25)
		_vanish(wedge, wm, 0.15))
	tw.tween_interval(0.3)
	tw.tween_callback(holder.queue_free)
	var cm := material([Color(1, 0.9, 0.7), Color(0.6, 0.4, 0.2)], 1.0, 0)
	var skid := spawn("GroundCrack", cm, hero.global_position + Vector3.UP * 0.03)
	if skid:
		skid.scale = Vector3.ONE * 1.3
		_vanish(skid, cm, 0.8, 0.1)

## Grito de Guerra: coroa de choque dourada, coluna de luz e círculo de runas sob os pés.
static func warcry(pos: Vector3) -> void:
	var rm := material(KNIGHT_GOLD, 2.2, 0)
	var rune := spawn("RuneCircle", rm, pos + Vector3.UP * 0.04)
	if rune == null:
		return
	rune.scale = Vector3.ONE * 0.5
	var tw := rune.create_tween()
	tw.tween_property(rune, "scale", Vector3.ONE * 2.4, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(rune, "rotation:y", PI * 0.6, 1.3)
	_vanish(rune, rm, 0.7, 0.6)
	var sm := material(KNIGHT_GOLD, 2.4, 1, {"noise_scroll": Vector2(-1.0, 0.0)})
	var wave := spawn("Shockwave", sm, pos + Vector3.UP * 0.05)
	wave.scale = Vector3(0.7, 1.3, 0.7)
	var tw2 := wave.create_tween()
	tw2.tween_property(wave, "scale", Vector3(4.2, 0.35, 4.2), 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_vanish(wave, sm, 0.35, 0.25)
	var pm := material(KNIGHT_GOLD, 1.8, 1, {"noise_scroll": Vector2(0.0, -2.5), "noise_scale": Vector2(3.0, 1.0)})
	var pillar := spawn("LightPillar", pm, pos)
	pillar.scale = Vector3(0.75, 0.1, 0.75)
	pillar.create_tween().tween_property(pillar, "scale", Vector3(0.95, 4.5, 0.95), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_vanish(pillar, pm, 0.6, 0.3)

## Explosão Arcana (aviso): círculo mágico que se acende no chão até a explosão.
static func nova_telegraph(center: Vector3, radius: float, delay: float) -> void:
	for k in 2:
		var rm := material(ARCANE, 0.6, 0)
		var rune := spawn("RuneCircle", rm, center + Vector3.UP * (0.05 + 0.01 * k))
		if rune == null:
			return
		rune.scale = Vector3.ONE * radius * (1.0 if k == 0 else 0.5)
		var tw := rune.create_tween()
		tw.tween_property(rune, "rotation:y", PI * (0.5 if k == 0 else -0.9), delay + 0.3)
		_param(rune, rm, &"intensity", 0.6, 3.2, delay)
		_vanish(rune, rm, 0.45, delay)

## Explosão Arcana (impacto): cúpula, coluna violeta, cristais voando e chão rachado.
static func nova_burst(center: Vector3, radius: float) -> void:
	var dm := material(ARCANE, 2.4, 3, {"noise_scroll": Vector2(0.6, 1.2)})
	var dome := spawn("Dome", dm, center)
	if dome == null:
		EffectsHub.spawn_explosion(center, radius)
		return
	dome.scale = Vector3(0.3, 0.2, 0.3)
	dome.create_tween().tween_property(dome, "scale", Vector3(radius, radius * 0.6, radius), 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_vanish(dome, dm, 0.4, 0.15)
	var pm := material(ARCANE, 2.2, 1, {"noise_scroll": Vector2(0.0, -3.0), "noise_scale": Vector2(3.0, 1.5)})
	var pillar := spawn("LightPillar", pm, center)
	pillar.scale = Vector3(radius * 0.3, 0.5, radius * 0.3)
	pillar.create_tween().tween_property(pillar, "scale", Vector3(radius * 0.18, 10.0, radius * 0.18), 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_vanish(pillar, pm, 0.45, 0.2)
	var cm := material(ARCANE, 1.8, 0, {"tail": 1.0})
	var crack := spawn("GroundCrack", cm, center + Vector3.UP * 0.03)
	crack.scale = Vector3.ONE * radius
	crack.rotation.y = randf() * TAU
	_vanish(crack, cm, 1.3, 0.3)
	for i in 12:
		var shm := material(ARCANE, 2.0, 3)
		var sh := spawn("Shard", shm, center + Vector3.UP * 0.4)
		var a := i * TAU / 12.0 + randf_range(-0.2, 0.2)
		var out := Vector3(cos(a), 0, sin(a)) * radius * randf_range(0.55, 0.95)
		sh.scale = Vector3.ONE * randf_range(0.9, 1.6)
		sh.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
		var tw := sh.create_tween()
		tw.tween_property(sh, "global_position", center + out + Vector3.UP * randf_range(1.0, 2.6), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(sh, "rotation", sh.rotation + Vector3(4, 6, 2), 0.7)
		tw.tween_property(sh, "global_position", center + out * 1.1 + Vector3.UP * 0.2, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_vanish(sh, shm, 0.3, 0.45)

# --- Caçador -----------------------------------------------------------------------

## Tiro Múltiplo: clarão em leque no arco (as flechas de energia vêm do Projectile com brilho).
static func multishot(from: Vector3, dir: Vector3, half_angle: float) -> void:
	var fm := material(HUNTER, 2.8, 0, {"tail": 1.0})
	var star := spawn("SparkStar", fm, from)
	if star == null:
		return
	star.rotation.y = randf() * TAU
	star.scale = Vector3.ONE * 0.3
	star.create_tween().tween_property(star, "scale", Vector3.ONE * 1.3, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_vanish(star, fm, 0.25, 0.1)
	# Leque de rastros saindo do arco, um por direção.
	for s in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var lm := material(HUNTER, 2.0, 0, {"tail": 1.0, "noise_scroll": Vector2(4.0, 0.0)})
		var ln := spawn("ArrowTrail", lm, from)
		var d := dir.rotated(Vector3.UP, half_angle * s)
		ln.look_at(from - d, Vector3.UP)
		ln.scale = Vector3(1.6, 1.6, 1.0)
		ln.create_tween().tween_property(ln, "scale", Vector3(1.0, 1.0, 5.0), 0.18).set_ease(Tween.EASE_OUT)
		_vanish(ln, lm, 0.25, 0.12)

## Brilho preso a uma flecha (Projectile): flecha de energia + rastro.
static func arrow_glow(parent: Node3D, pal: Array) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	var am := material(pal, 2.2, 2)
	spawn("ArrowGlow", am, Vector3.ZERO, holder)
	var tm := material(pal, 1.8, 0, {"tail": 1.0, "noise_scroll": Vector2(3.0, 0.0)})
	var tr := spawn("ArrowTrail", tm, Vector3(0, 0, 0.4), holder)
	if tr:
		tr.scale = Vector3(1.0, 1.0, 2.2)
	return holder

## Chuva de Flechas: mira girando no chão (a lógica cuida das flechas, que usam a forma ArrowGlow).
static func arrow_rain_marker(center: Vector3, radius: float, duration: float) -> void:
	var m := material([Color(1.0, 0.95, 0.8), Color(1.0, 0.55, 0.12)], 1.6, 0)
	var t := spawn("TargetCircle", m, center + Vector3.UP * 0.05)
	if t == null:
		EffectsHub.spawn_ring(center + Vector3.UP * 0.05, radius, Color(1.0, 0.55, 0.15, 0.18), duration)
		return
	t.scale = Vector3.ONE * radius * 1.4
	var tw := t.create_tween()
	tw.tween_property(t, "scale", Vector3.ONE * radius, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(t, "rotation:y", PI * 0.5 * duration, duration)
	_param(t, m, &"intensity", 2.4, 1.2, 0.4)
	_vanish(t, m, 0.4, maxf(0.1, duration - 0.3))

## Flecha da chuva caindo (forma de energia com rastro) até `land`.
static func falling_arrow(parent: Node, land: Vector3) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	var start := land + Vector3(-1.2, 11.0, 0.6)
	holder.global_position = start
	holder.look_at(land, Vector3.FORWARD)
	var am := material([Color(1.0, 0.95, 0.8), Color(1.0, 0.55, 0.12)], 1.8, 2)
	spawn("ArrowGlow", am, Vector3.ZERO, holder)
	var tm := material([Color(1.0, 0.95, 0.8), Color(1.0, 0.55, 0.12)], 1.4, 0, {"tail": 1.0})
	var tr := spawn("ArrowTrail", tm, Vector3(0, 0, 0.5), holder)
	if tr:
		tr.scale = Vector3(1, 1, 3.0)
	var tw := holder.create_tween()
	tw.tween_property(holder, "global_position", land, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if tr:
			tr.visible = false
		var sm := material([Color(1.0, 0.95, 0.8), Color(1.0, 0.55, 0.12)], 1.6, 0, {"tail": 1.0})
		var st := spawn("SparkStar", sm, land + Vector3.UP * 0.02)
		if st:
			st.scale = Vector3.ONE * 0.35
			st.rotation.y = randf() * TAU
			_vanish(st, sm, 0.2))
	tw.tween_interval(0.45)
	tw.tween_callback(holder.queue_free)

## Armadilha armada: marca de mira verde no chão.
static func trap_armed(pos: Vector3, radius: float) -> void:
	var m := material(HUNTER, 1.4, 0)
	var t := spawn("TargetCircle", m, pos + Vector3.UP * 0.04)
	if t == null:
		return
	t.scale = Vector3.ONE * radius * 2.2
	t.create_tween().tween_property(t, "scale", Vector3.ONE * radius, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_vanish(t, m, 0.5, 0.4)

## Armadilha fechando: estrela de faíscas, rachaduras e lascas de metal.
static func trap_snap(pos: Vector3) -> void:
	var sm := material(STEEL, 3.0, 0, {"tail": 1.0})
	var st := spawn("SparkStar", sm, pos + Vector3.UP * 0.35)
	if st == null:
		return
	st.rotation = Vector3(PI * 0.5, randf() * TAU, 0)
	st.scale = Vector3.ONE * 0.3
	st.create_tween().tween_property(st, "scale", Vector3.ONE * 1.4, 0.1)
	_vanish(st, sm, 0.2, 0.06)
	var cm := material(STEEL, 1.2, 0, {"tail": 1.0})
	var crack := spawn("GroundCrack", cm, pos + Vector3.UP * 0.03)
	crack.scale = Vector3.ONE * 1.4
	_vanish(crack, cm, 0.8, 0.15)
	for i in 6:
		var shm := material(STEEL, 1.8, 3)
		var sh := spawn("Shard", shm, pos + Vector3.UP * 0.3)
		sh.scale = Vector3.ONE * 0.5
		var a := randf() * TAU
		var tw := sh.create_tween()
		tw.tween_property(sh, "global_position", pos + Vector3(cos(a), 0, sin(a)) * randf_range(0.8, 1.5) + Vector3.UP * randf_range(0.6, 1.2), 0.25).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(sh, "rotation", Vector3(5, 3, 1), 0.4)
		_vanish(sh, shm, 0.2, 0.2)

## Águia: rastro espectral preso ao corpo (durante a vida da águia).
static func eagle_trail(eagle: Node3D) -> void:
	for side in [-1.0, 1.0]:
		var m := material(SKY, 0.8, 0, {"tail": 1.0, "noise_scroll": Vector2(2.5, 0.0), "flicker": 0.5})
		var tr := spawn("ArrowTrail", m, Vector3(side * 0.85, 0.05, 0.3), eagle)
		if tr:
			tr.scale = Vector3(2.2, 2.2, 1.3)

## Águia mergulhando no alvo: estrela de impacto, onda curta e penas caindo.
static func eagle_strike(pos: Vector3) -> void:
	var sm := material(SKY, 2.6, 0, {"tail": 1.0})
	var st := spawn("SparkStar", sm, pos + Vector3.UP * 1.0)
	if st == null:
		return
	st.rotation = Vector3(PI * 0.5, randf() * TAU, 0)
	st.scale = Vector3.ONE * 0.4
	st.create_tween().tween_property(st, "scale", Vector3.ONE * 1.6, 0.12)
	_vanish(st, sm, 0.25, 0.05)
	var wm := material(SKY, 1.8, 1)
	var wave := spawn("Shockwave", wm, pos + Vector3.UP * 0.05)
	wave.scale = Vector3(0.4, 0.5, 0.4)
	wave.create_tween().tween_property(wave, "scale", Vector3(2.0, 0.15, 2.0), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_vanish(wave, wm, 0.25, 0.15)
	for i in 7:
		var fm := material([Color(1, 1, 1), Color(0.75, 0.62, 0.45)], 1.2, 0, {"flicker": 0.3})
		var f := spawn("Feather", fm, pos + Vector3.UP * 1.3)
		f.scale = Vector3.ONE * randf_range(0.8, 1.3)
		f.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var a := randf() * TAU
		var to := pos + Vector3(cos(a), 0, sin(a)) * randf_range(0.6, 1.6) + Vector3.UP * randf_range(0.2, 0.9)
		var tw := f.create_tween()
		tw.tween_property(f, "global_position", to + Vector3.UP * 0.8, 0.25).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(f, "rotation", f.rotation + Vector3(2, 4, 1), 1.2)
		tw.tween_property(f, "global_position", to, 0.9).set_trans(Tween.TRANS_SINE)
		_vanish(f, fm, 0.4, 0.8)
