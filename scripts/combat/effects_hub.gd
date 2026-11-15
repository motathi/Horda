class_name EffectsHub
extends Node3D
## Central de efeitos visuais com pooling (textos de dano, sangue, lascas,
## itens no chão, marcadores). Acesso estático: EffectsHub.spawn_blood(...).

static var _inst: EffectsHub

var _texts: ObjectPool
var _blood: ObjectPool
var _debris: ObjectPool
var _stone: ObjectPool
var _heal: ObjectPool
var _pickups: ObjectPool
var _arrows: ObjectPool
var _marker: MeshInstance3D
var _marker_t: float = 0.0

func _enter_tree() -> void:
	_inst = self

func _exit_tree() -> void:
	if _inst == self:
		_inst = null

func _ready() -> void:
	_texts = _make_pool("Texts", func() -> Node: return FloatingText.new(), 32)
	_blood = _make_pool("Blood", func() -> Node: return _make_burst(Color(0.55, 0.05, 0.04), 18, 0.6, 4.0, 0.07), 24)
	_debris = _make_pool("Debris", func() -> Node: return _make_burst(Color(0.55, 0.38, 0.2), 10, 0.7, 4.5, 0.09), 8)
	_stone = _make_pool("Stone", func() -> Node: return _make_burst(Color(0.6, 0.6, 0.62), 10, 0.7, 4.5, 0.1), 8)
	_heal = _make_pool("Heal", func() -> Node: return _make_burst(Color(0.4, 1.0, 0.4), 24, 1.0, 2.0, 0.08, -3.0), 4)
	_pickups = _make_pool("Pickups", func() -> Node: return ResourcePickup.new(), 24)
	_arrows = _make_pool("Arrows", func() -> Node: return Projectile.new(), 16)
	_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.35
	torus.outer_radius = 0.5
	_marker.mesh = torus
	_marker.material_override = MaterialLib.flat(Color(0.3, 1.0, 0.3), 0.5, 2.0)
	_marker.visible = false
	add_child(_marker)
	EventBus.damage_dealt.connect(_on_damage_dealt)

func _make_pool(n: String, f: Callable, pre: int) -> ObjectPool:
	var p := ObjectPool.new()
	p.name = n
	p.factory = f
	p.prewarm = pre
	add_child(p)
	return p

func _make_burst(color: Color, amount: int, life: float, speed: float, size: float, gravity: float = -12.0) -> BurstEffect:
	var b := BurstEffect.new()
	b.one_shot = true
	b.emitting = false
	b.amount = amount
	b.lifetime = life
	b.explosiveness = 0.95
	b.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 75.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, gravity, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color = color
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0))
	curve.curve = c
	pm.scale_curve = curve
	b.process_material = pm
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	b.draw_pass_1 = mesh
	return b

# --- API estática ------------------------------------------------------------

static func float_text(pos: Vector3, txt: String, color: Color, size: int = 44) -> void:
	if _inst:
		(_inst._texts.acquire() as FloatingText).activate(pos, txt, color, size, 1.2)

static func spawn_blood(pos: Vector3, big: bool = false) -> void:
	if _inst:
		(_inst._blood.acquire() as BurstEffect).activate(pos, Color(0.5, 0.06, 0.04) if randf() < 0.7 else Color(0.3, 0.45, 0.1), 1.0 if big else 0.6)

static func spawn_debris(pos: Vector3, stone: bool = false) -> void:
	if _inst:
		var pool := _inst._stone if stone else _inst._debris
		(pool.acquire() as BurstEffect).activate(pos, Color(0.6, 0.6, 0.62) if stone else Color(0.55, 0.38, 0.2))

static func spawn_heal(pos: Vector3) -> void:
	if _inst:
		(_inst._heal.acquire() as BurstEffect).activate(pos + Vector3.UP * 0.5, Color(0.4, 1.0, 0.45))

static func drop_item(pos: Vector3, id: StringName, amount: int) -> void:
	if _inst == null or amount <= 0:
		return
	if Coop.is_host():
		Coop.host_drop(pos, id, amount)  # saque compartilhado: todos veem
	else:
		spawn_pickup_local(pos, id, amount)

## Saque só deste jogador (ou base para o compartilhado do coop).
static func spawn_pickup_local(pos: Vector3, id: StringName, amount: int) -> ResourcePickup:
	if _inst == null:
		return null
	var p := _inst._pickups.acquire() as ResourcePickup
	p.activate(pos, id, amount)
	return p

## Equipamento no chão (GearPickup).
static func drop_gear(pos: Vector3, item: GearItem) -> void:
	if _inst == null or item == null:
		return
	if Coop.is_host():
		Coop.host_drop_gear(pos, item)
	else:
		spawn_gear_local(pos, item)

static func spawn_gear_local(pos: Vector3, item: GearItem) -> GearPickup:
	return GearPickup.spawn(_inst, pos, item) if _inst else null

static func spawn_arrow(from: Vector3, target: Enemy, info: DamageInfo, speed: float) -> void:
	if _inst:
		(_inst._arrows.acquire() as Projectile).activate(from, target, info, speed)

static func spawn_marker(pos: Vector3) -> void:
	if _inst:
		_inst._marker.global_position = pos + Vector3.UP * 0.05
		_inst._marker.visible = true
		_inst._marker_t = 0.6

static func spawn_slash(pos: Vector3, yaw: float) -> void:
	if _inst == null:
		return
	var arc := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.1
	torus.outer_radius = 1.4
	torus.rings = 16
	torus.ring_segments = 4
	arc.mesh = torus
	arc.scale = Vector3(1, 0.08, 1)
	arc.material_override = MaterialLib.unshaded(Color(1.0, 0.9, 0.6, 0.5))
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_inst.add_child(arc)
	arc.global_position = pos
	arc.rotation.y = yaw
	var tw := arc.create_tween()
	tw.tween_property(arc, "scale", Vector3(1.4, 0.02, 1.4), 0.15)
	tw.tween_callback(arc.queue_free)

## Anel que se expande no chão (área de habilidade).
static func spawn_ring(pos: Vector3, radius: float, color: Color, duration: float) -> void:
	if _inst == null:
		return
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.86
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(color, 0.9)
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_inst.add_child(ring)
	ring.global_position = pos
	ring.scale = Vector3(radius * 0.2, 0.15, radius * 0.2)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3(radius, 0.15, radius), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, duration * 1.3)
	tw.tween_callback(ring.queue_free)

## Explosão (esfera brilhante que cresce + clarão + estilhaços).
static func spawn_explosion(pos: Vector3, radius: float, color: Color = Color(0.55, 0.22, 0.95)) -> void:
	if _inst == null:
		return
	var orb := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	orb.mesh = sph
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(color.r, color.g, color.b, 0.42)
	orb.material_override = m
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_inst.add_child(orb)
	orb.global_position = pos + Vector3.UP * 0.5
	orb.scale = Vector3.ONE * 0.4
	var light := OmniLight3D.new()
	light.light_color = color.lightened(0.3)
	light.light_energy = 3.5
	light.omni_range = radius * 2.5
	orb.add_child(light)
	var tw := orb.create_tween()
	tw.tween_property(orb, "scale", Vector3(radius, radius * 0.6, radius), 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.5)
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.5)
	tw.tween_callback(orb.queue_free)
	for i in 4:
		spawn_debris(pos + Vector3(randf_range(-radius, radius) * 0.5, 0.6, randf_range(-radius, radius) * 0.5), true)

## Virote da balista: voa em linha reta (efeito visual; o dano é aplicado pela torre).
static func spawn_bolt(from: Vector3, to: Vector3, speed: float) -> void:
	if _inst == null:
		return
	var bolt := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.06
	c.bottom_radius = 0.06
	c.height = 1.8
	c.radial_segments = 5
	bolt.mesh = c
	bolt.material_override = MaterialLib.flat(Color(0.45, 0.3, 0.18))
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var trail := MeshInstance3D.new()
	var q := BoxMesh.new()
	q.size = Vector3(0.06, 2.6, 0.06)
	trail.mesh = q
	trail.position.y = -2.0
	trail.material_override = MaterialLib.unshaded(Color(1.0, 0.95, 0.75, 0.4))
	bolt.add_child(trail)
	_inst.add_child(bolt)
	bolt.global_position = from
	var dir := (to - from).normalized()
	# O cilindro aponta em +Y: alinha +Y com a direção do voo.
	bolt.global_basis = Basis(Quaternion(Vector3.UP, dir))
	var tw := bolt.create_tween()
	tw.tween_property(bolt, "global_position", to, from.distance_to(to) / maxf(1.0, speed))
	tw.tween_callback(bolt.queue_free)

## Projétil em arco (bala de canhão). on_land é chamado no impacto.
static func spawn_lob(from: Vector3, to: Vector3, duration: float, arc: float, on_land: Callable) -> void:
	if _inst == null:
		return
	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.32
	sph.height = 0.64
	sph.radial_segments = 10
	sph.rings = 6
	ball.mesh = sph
	ball.material_override = MaterialLib.flat(Color(0.12, 0.12, 0.14), 0.4)
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_inst.add_child(ball)
	ball.global_position = from
	var tw := ball.create_tween()
	tw.tween_method(func(t: float) -> void:
		var p := from.lerp(to, t)
		p.y += sin(t * PI) * arc
		ball.global_position = p, 0.0, 1.0, duration)
	tw.tween_callback(func() -> void:
		ball.queue_free()
		on_land.call())

## Raio elétrico entre os pontos (segmentos brilhantes que somem rápido).
static func spawn_lightning(points: PackedVector3Array, color: Color = Color(0.55, 0.8, 1.0)) -> void:
	if _inst == null or points.size() < 2:
		return
	var root := Node3D.new()
	_inst.add_child(root)
	var mat := MaterialLib.unshaded(Color(color.r, color.g, color.b, 0.9))
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		# Zigue-zague: dois segmentos por salto com um ponto deslocado no meio.
		var mid := (a + b) * 0.5 + Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.6), randf_range(-0.5, 0.5))
		for seg: Array in [[a, mid], [mid, b]]:
			var p0: Vector3 = seg[0]
			var p1: Vector3 = seg[1]
			var m := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.09, p0.distance_to(p1), 0.09)
			m.mesh = box
			m.material_override = mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(m)
			m.global_position = (p0 + p1) * 0.5
			var dir := (p1 - p0).normalized()
			if dir.length() > 0.0:
				m.global_basis = Basis(Quaternion(Vector3.UP, dir))
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.5
	light.omni_range = 6.0
	root.add_child(light)
	light.global_position = points[0]
	var tw := root.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.18)
	tw.tween_callback(root.queue_free)

## Fogo preso a um nó (zumbis queimando ao amanhecer).
static func attach_fire(target: Node3D) -> Node3D:
	var f := make_fire_particles(0.8)
	target.add_child(f)
	return f

static func make_fire_particles(size: float) -> Node3D:
	var p := GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.8
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35 * size
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 1.0 * size
	pm.initial_velocity_max = 2.2 * size
	pm.gravity = Vector3(0, 1.5, 0)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.3, 1.0))
	grad.set_color(1, Color(0.8, 0.15, 0.02, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0.2))
	curve.curve = c
	pm.scale_curve = curve
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.45 * size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _soft_dot()
	q.material = mat
	p.draw_pass_1 = q
	return p

static var _dot: GradientTexture2D

## Textura radial suave usada pelas partículas de fogo.
static func _soft_dot() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 64
		_dot.height = 64
	return _dot

func pickups_to_save() -> Array:
	var out := []
	for c in _pickups.get_children():
		var rp := c as ResourcePickup
		if rp and rp.visible:
			out.append(rp.to_save())
	return out

static func instance() -> EffectsHub:
	return _inst

func _process(delta: float) -> void:
	if _marker_t > 0.0:
		_marker_t -= delta
		_marker.scale = Vector3.ONE * (0.5 + _marker_t)
		if _marker_t <= 0.0:
			_marker.visible = false

func _on_damage_dealt(target: Node3D, info: DamageInfo, amount: float) -> void:
	if not Settings.damage_numbers:
		return
	var pos := target.global_position + Vector3.UP * 2.2
	var txt := str(int(round(amount)))
	if target is Hero:
		float_text(pos, "-" + txt, Color(1.0, 0.3, 0.25), 40)
	elif target is Structure:
		if randf() < 0.35:
			float_text(pos + Vector3.UP, txt, Color(1.0, 0.6, 0.2), 34)
	elif info.is_crit:
		float_text(pos, txt + "!", Color(1.0, 0.85, 0.15), 64)
	elif info.source is Hero:
		float_text(pos, txt, Color(1, 1, 1), 46)
