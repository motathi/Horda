class_name PropFactory
## Monta props do cenário (árvores, rochas, casas, carros, caixas) a partir de
## primitivas e das texturas pintadas à mão. Retorna corpos prontos para a cena.

const LOOT_DIR := "res://data/loot/"

static func _mi(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.rotation_degrees = rot
	m.scale = scl
	m.material_override = mat
	parent.add_child(m)
	return m

static func _box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

static func _collision(body: CollisionObject3D, shape: Shape3D, pos: Vector3 = Vector3.ZERO, rot_y: float = 0.0) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	cs.rotation.y = rot_y
	body.add_child(cs)

# --- Árvores -------------------------------------------------------------------

## Escolhe o modelo das árvores sem consumir o gerador principal do mapa
## (assim a geração continua igual e os saves seguem válidos).
static var style_rng := RandomNumberGenerator.new()

## Árvores modeladas no Blender (tools/blender_trees.py): folhosas e pinheiros secos, mortas e queimadas.
const BLENDER_TREES: Array[String] = ["tree_dry_a", "tree_dry_b"]
const BLENDER_PINES: Array[String] = ["pine_dry_a", "pine_dry_b"]

static func _third_party_tree(dead: bool) -> Node3D:
	var r := style_rng.randf()
	var t: Node3D = null
	var B := ThirdParty.BLENDER
	if dead:
		# Mortas: 70% secas e retorcidas, 30% queimadas.
		var m := "tree_dead_a" if r < 0.7 else "tree_dead_b"
		if ThirdParty.has(B, m):
			t = ThirdParty.instance(B, m, style_rng.randf_range(4.5, 6.5))
	else:
		var pool := BLENDER_TREES if r < 0.45 else BLENDER_PINES
		var m2: String = pool[style_rng.randi() % pool.size()]
		if ThirdParty.has(B, m2):
			t = ThirdParty.instance(B, m2, style_rng.randf_range(5.5, 8.5))
	if t:
		t.rotation.y = style_rng.randf() * TAU
	return t

static func make_tree(rng: RandomNumberGenerator, dead: bool = false) -> Harvestable:
	var h := Harvestable.new()
	h.kind = Harvestable.Kind.TREE
	h.item_id = &"wood"
	h.hits = 4 if dead else 6
	h.yield_min = 1
	h.yield_max = 3
	var sh := CylinderShape3D.new()
	sh.radius = 0.55
	sh.height = 4.0
	_collision(h, sh, Vector3(0, 2, 0))
	var v := Node3D.new()
	var tp := _third_party_tree(dead)
	if tp:
		v.add_child(tp)
		h.setup_visual(v)
		return h
	if not dead and ModelLibrary.has("tree"):
		var g := rng.randf_range(0.85, 1.1)
		var t := ModelLibrary.instance_height("tree", rng.randf_range(5.5, 8.5), Color(g * rng.randf_range(0.9, 1.05), g, g * rng.randf_range(0.85, 1.0)))
		t.rotation.y = rng.randf() * TAU
		v.add_child(t)
		h.setup_visual(v)
		return h
	var s := rng.randf_range(0.85, 1.35)
	v.scale = Vector3.ONE * s
	v.rotation.y = rng.randf() * TAU
	var bark := MaterialLib.textured("bark", Color(0.9, 0.8, 0.7) if not dead else Color(0.55, 0.5, 0.5), 1.0)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.4
	trunk.height = 3.2
	trunk.radial_segments = 8
	_mi(v, trunk, Vector3(0, 1.6, 0), bark)
	if dead:
		for i in 3:
			var br := CylinderMesh.new()
			br.top_radius = 0.03
			br.bottom_radius = 0.1
			br.height = 1.4
			br.radial_segments = 5
			_mi(v, br, Vector3(0, 2.4 + i * 0.3, 0), bark, Vector3(rng.randf_range(35, 60), i * 120.0, 0)).position += Vector3(cos(i * 2.1) * 0.3, 0, sin(i * 2.1) * 0.3)
	else:
		var hue := rng.randf_range(-0.04, 0.05)
		var leaf_col := Color.from_hsv(0.27 + hue, 0.55, rng.randf_range(0.7, 1.0))
		var leaves := MaterialLib.textured("leaves", leaf_col, 1.4)
		var crown := SphereMesh.new()
		crown.radius = 1.6
		crown.height = 2.6
		crown.radial_segments = 10
		crown.rings = 6
		_mi(v, crown, Vector3(0, 3.6, 0), leaves)
		var crown2 := SphereMesh.new()
		crown2.radius = 1.1
		crown2.height = 1.9
		crown2.radial_segments = 9
		crown2.rings = 5
		_mi(v, crown2, Vector3(0.5, 4.7, 0.2), leaves)
		_mi(v, crown2, Vector3(-0.7, 4.2, -0.4), leaves, Vector3.ZERO, Vector3.ONE * 0.85)
	h.setup_visual(v)
	return h

# --- Rochas --------------------------------------------------------------------

static func make_rock(rng: RandomNumberGenerator, big: bool = true) -> Harvestable:
	var h := Harvestable.new()
	h.kind = Harvestable.Kind.ROCK
	h.item_id = &"stone"
	h.hits = 7 if big else 4
	h.yield_min = 1
	h.yield_max = 2
	var r := rng.randf_range(1.0, 1.6) if big else rng.randf_range(0.5, 0.8)
	var sh := SphereShape3D.new()
	sh.radius = r * 0.95
	_collision(h, sh, Vector3(0, r * 0.4, 0))
	var v := Node3D.new()
	# Pedras lascadas modeladas no Blender (tools/blender_rocks.py); o modelo vem do style_rng.
	var bm: String = (["rock_boulder_a", "rock_boulder_b"] if big else ["rock_small_a", "rock_small_b"])[style_rng.randi() % 2]
	if ThirdParty.has(ThirdParty.BLENDER, bm):
		var rk := ThirdParty.instance(ThirdParty.BLENDER, bm)
		var a := ThirdParty.aabb(ThirdParty.BLENDER, bm)
		var sc := r * 2.3 / maxf(0.1, maxf(a.size.x, a.size.z))
		rk.scale = Vector3(sc, sc * style_rng.randf_range(0.85, 1.3), sc)
		rk.rotation.y = style_rng.randf() * TAU
		v.add_child(rk)
		h.setup_visual(v)
		return h
	if ModelLibrary.has("rock"):
		var g := rng.randf_range(0.6, 0.8)
		var rm := ModelLibrary.instance_footprint("rock", r * 2.3, Color(g, g, g * 1.05))
		rm.rotation.y = rng.randf() * TAU
		rm.scale.y *= rng.randf_range(0.9, 1.5)
		v.add_child(rm)
		if big:
			var r2 := ModelLibrary.instance_footprint("rock", r * 1.2, Color(g * 0.95, g * 0.95, g))
			r2.position = Vector3(r * 0.9, 0, r * 0.4)
			r2.rotation.y = rng.randf() * TAU
			v.add_child(r2)
		h.setup_visual(v)
		return h
	var mat := MaterialLib.textured("rock", Color(0.95, 0.95, 1.0), 0.6)
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 1.6
	m.radial_segments = 7
	m.rings = 4
	_mi(v, m, Vector3(0, r * 0.35, 0), mat, Vector3(rng.randf_range(-10, 10), rng.randf() * 360.0, 0), Vector3(rng.randf_range(0.9, 1.3), 1, rng.randf_range(0.8, 1.1)))
	if big:
		var m2 := SphereMesh.new()
		m2.radius = r * 0.55
		m2.height = r
		m2.radial_segments = 6
		m2.rings = 3
		_mi(v, m2, Vector3(r * 0.7, r * 0.2, r * 0.3), mat, Vector3(0, rng.randf() * 360.0, 0))
	h.setup_visual(v)
	return h

# --- Saqueáveis ----------------------------------------------------------------

static func make_lootable(kind: String, rng: RandomNumberGenerator) -> Lootable:
	var l := Lootable.new()
	var v := Node3D.new()
	match kind:
		"cart":
			l.display_label = "Carroça Abandonada"
			l.loot = load(LOOT_DIR + "farm_crate.tres")
			l.duration = 2.0
			l.restock_days = 3
			if ThirdParty.has(ThirdParty.BLENDER, "burned_cart"):
				v.add_child(ThirdParty.instance(ThirdParty.BLENDER, "burned_cart"))
			elif ModelLibrary.has("cart"):
				var c := ModelLibrary.instance_footprint("cart", 3.4)
				v.add_child(c)
			else:
				_mi(v, _box_mesh(Vector3(1.6, 0.8, 3.0)), Vector3(0, 0.7, 0), MaterialLib.textured("planks", Color.WHITE))
			var shc := BoxShape3D.new()
			shc.size = Vector3(1.8, 1.6, 3.2)
			_collision(l, shc, Vector3(0, 0.8, 0))
		"car":
			l.display_label = "Carro Destruído"
			l.loot = load(LOOT_DIR + "car_wreck.tres")
			l.duration = 2.5
			l.restock_days = 4
			# Carcaça modelada no Blender (tools/blender_scenery.py), em duas cores.
			var wreck := "res://assets/models/blender/car_wreck_%s.glb" % ["a", "b"][rng.randi() % 2]
			if ResourceLoader.exists(wreck):
				v.add_child((load(wreck) as PackedScene).instantiate())
				var shw := BoxShape3D.new()
				shw.size = Vector3(2.0, 1.6, 4.0)
				_collision(l, shw, Vector3(0, 0.8, 0))
				l.setup_visual(v)
				return l
			var rust := MaterialLib.textured("metal", Color(rng.randf_range(0.6, 1.0), rng.randf_range(0.5, 0.8), rng.randf_range(0.5, 0.8)), 0.8, true, 0.6)
			_mi(v, _box_mesh(Vector3(1.9, 0.8, 4.0)), Vector3(0, 0.75, 0), rust)
			_mi(v, _box_mesh(Vector3(1.7, 0.7, 2.0)), Vector3(0, 1.5, 0.3), rust)
			_mi(v, _box_mesh(Vector3(1.6, 0.5, 0.05)), Vector3(0, 1.55, -0.72), MaterialLib.flat(Color(0.15, 0.2, 0.25, 0.8), 0.1), Vector3(-25, 0, 0))
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.38
			wheel.bottom_radius = 0.38
			wheel.height = 0.3
			for p in [Vector3(-0.95, 0.38, 1.3), Vector3(0.95, 0.38, 1.3), Vector3(-0.95, 0.38, -1.3), Vector3(0.95, 0.38, -1.3)]:
				_mi(v, wheel, p, MaterialLib.flat(Color(0.08, 0.08, 0.08)), Vector3(0, 0, 90))
			v.rotation.z = deg_to_rad(rng.randf_range(-4, 4))
			var sh := BoxShape3D.new()
			sh.size = Vector3(2.0, 1.8, 4.1)
			_collision(l, sh, Vector3(0, 0.9, 0))
		_:
			var labels := {"crate": "Caixa de Suprimentos", "farm": "Caixote da Fazenda", "cabinet": "Armário Abandonado", "cache": "Esconderijo Contaminado"}
			var tables := {"crate": "crate_supplies", "farm": "farm_crate", "cabinet": "city_cabinet", "cache": "contaminated_cache"}
			l.display_label = labels.get(kind, "Caixa")
			l.loot = load(LOOT_DIR + String(tables.get(kind, "crate_supplies")) + ".tres")
			l.duration = 1.4 if kind != "cache" else 2.2
			l.restock_days = 3
			var mat := MaterialLib.textured("planks", Color(1, 0.92, 0.8) if kind != "cache" else Color(0.6, 0.85, 0.6), 1.0)
			if kind == "cabinet":
				_mi(v, _box_mesh(Vector3(1.2, 1.8, 0.6)), Vector3(0, 0.9, 0), mat)
				_mi(v, _box_mesh(Vector3(0.05, 1.5, 0.05)), Vector3(0, 0.95, -0.31), MaterialLib.flat(Color(0.2, 0.15, 0.1)))
				var sh2 := BoxShape3D.new()
				sh2.size = Vector3(1.2, 1.8, 0.6)
				_collision(l, sh2, Vector3(0, 0.9, 0))
			else:
				var s := 1.0 if kind != "cache" else 1.2
				_mi(v, _box_mesh(Vector3(1.0, 0.8, 0.8) * s), Vector3(0, 0.4 * s, 0), mat)
				_mi(v, _box_mesh(Vector3(1.05, 0.12, 0.85) * s), Vector3(0, 0.82 * s, 0), MaterialLib.textured("metal", Color(0.7, 0.7, 0.7), 1.0))
				if rng.randf() < 0.5:
					_mi(v, _box_mesh(Vector3(0.6, 0.5, 0.6)), Vector3(0.7, 0.25, 0.4), mat, Vector3(0, 25, 0))
				var sh3 := BoxShape3D.new()
				sh3.size = Vector3(1.0, 0.9, 0.8) * s
				_collision(l, sh3, Vector3(0, 0.45 * s, 0))
	l.setup_visual(v)
	return l

# --- Construções do cenário ----------------------------------------------------

static func make_house(rng: RandomNumberGenerator, ruined: bool) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Layers.WORLD
	b.collision_mask = 0
	# Casas e barracos modelados no Blender (tools/blender_town.py); o modelo vem do style_rng.
	var r := style_rng.randf()
	var bm := "house_ruin_b" if ruined else ("house_ruin_a" if r < 0.6 else ("shack_a" if r < 0.8 else "shack_b"))
	if ThirdParty.has(ThirdParty.BLENDER, bm):
		var hm := ThirdParty.instance(ThirdParty.BLENDER, bm)
		hm.scale = Vector3.ONE * style_rng.randf_range(0.95, 1.1)
		b.add_child(hm)
		var a := ThirdParty.aabb(ThirdParty.BLENDER, bm)
		var sb := BoxShape3D.new()
		sb.size = Vector3(a.size.x * 0.85, minf(a.size.y, 4.0), a.size.z * 0.85) * hm.scale.x
		_collision(b, sb, Vector3(a.get_center().x, sb.size.y * 0.5, a.get_center().z) * hm.scale.x)
		return b
	if ModelLibrary.has("house"):
		var g := rng.randf_range(0.85, 1.05)
		var m := ModelLibrary.instance_footprint("house", rng.randf_range(8.0, 10.0), Color(g, g * 0.97, g * 0.93))
		b.add_child(m)
		var sz := ModelLibrary.size_of("house") * m.scale.x
		var shm := BoxShape3D.new()
		shm.size = Vector3(sz.x * 0.85, sz.y * 0.6, sz.z * 0.85)
		_collision(b, shm, Vector3(0, sz.y * 0.3, 0))
		return b
	var w := rng.randf_range(6, 9)
	var d := rng.randf_range(5, 8)
	var h := rng.randf_range(3.2, 4.2) * (0.6 if ruined else 1.0)
	var wall := MaterialLib.textured("planks", Color(rng.randf_range(0.75, 1.0), rng.randf_range(0.7, 0.9), rng.randf_range(0.6, 0.8)), 0.5)
	var roof := MaterialLib.textured("metal", Color(rng.randf_range(0.6, 0.9), 0.45, 0.35), 0.4)
	var stone := MaterialLib.textured("rock", Color(0.8, 0.8, 0.85), 0.5)
	_mi(b, _box_mesh(Vector3(w + 0.4, 0.5, d + 0.4)), Vector3(0, 0.25, 0), stone)
	_mi(b, _box_mesh(Vector3(w, h, d)), Vector3(0, h * 0.5 + 0.4, 0), wall)
	# Porta e janelas
	var dark := MaterialLib.flat(Color(0.08, 0.06, 0.05))
	_mi(b, _box_mesh(Vector3(1.1, 2.0, 0.1)), Vector3(0, 1.4, -d * 0.5 - 0.02), dark)
	for sx: float in [-1.0, 1.0]:
		_mi(b, _box_mesh(Vector3(1.0, 0.9, 0.1)), Vector3(sx * w * 0.3, h * 0.6 + 0.4, -d * 0.5 - 0.02), MaterialLib.flat(Color(0.95, 0.75, 0.35) if rng.randf() < 0.15 else Color(0.1, 0.12, 0.14)))
	if not ruined:
		var p := PrismMesh.new()
		p.size = Vector3(w + 0.8, 2.2, d + 0.8)
		_mi(b, p, Vector3(0, h + 0.4 + 1.1, 0), roof)
	else:
		for i in 4:
			_mi(b, _box_mesh(Vector3(rng.randf_range(0.5, 1.5), 0.3, rng.randf_range(0.4, 1.0))), Vector3(rng.randf_range(-w, w) * 0.6, 0.15, -d * 0.5 - rng.randf_range(0.6, 2.0)), wall, Vector3(0, rng.randf() * 180.0, 0))
	var sh := BoxShape3D.new()
	sh.size = Vector3(w, h + 0.4, d)
	_collision(b, sh, Vector3(0, (h + 0.4) * 0.5, 0))
	return b

static func make_barn(rng: RandomNumberGenerator) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Layers.WORLD
	var red := MaterialLib.textured("planks", Color(0.75, 0.25, 0.18), 0.4)
	var roof := MaterialLib.textured("metal", Color(0.55, 0.5, 0.5), 0.3)
	_mi(b, _box_mesh(Vector3(10, 5, 14)), Vector3(0, 2.5, 0), red)
	var p := PrismMesh.new()
	p.size = Vector3(11, 3.5, 15)
	_mi(b, p, Vector3(0, 6.75, 0), roof)
	_mi(b, _box_mesh(Vector3(3.5, 3.6, 0.1)), Vector3(0, 1.8, -7.02), MaterialLib.flat(Color(0.12, 0.08, 0.06)))
	var sh := BoxShape3D.new()
	sh.size = Vector3(10, 5, 14)
	_collision(b, sh, Vector3(0, 2.5, 0))
	return b

static func make_fence(length: float) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Layers.WORLD
	var wood := MaterialLib.textured("planks", Color(0.85, 0.75, 0.6), 1.0)
	var n := int(length / 2.0) + 1
	for i in n:
		_mi(b, _box_mesh(Vector3(0.15, 1.2, 0.15)), Vector3(-length * 0.5 + i * length / (n - 1), 0.6, 0), wood)
	_mi(b, _box_mesh(Vector3(length, 0.12, 0.08)), Vector3(0, 0.95, 0), wood)
	_mi(b, _box_mesh(Vector3(length, 0.12, 0.08)), Vector3(0, 0.5, 0), wood)
	var sh := BoxShape3D.new()
	sh.size = Vector3(length, 1.2, 0.3)
	_collision(b, sh, Vector3(0, 0.6, 0))
	return b

static func make_haystack(rng: RandomNumberGenerator) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Layers.WORLD
	var hay := MaterialLib.textured("cloth", Color(1.0, 0.85, 0.4), 1.5)
	var c := CylinderMesh.new()
	c.top_radius = 0.9
	c.bottom_radius = 0.9
	c.height = 1.4
	_mi(b, c, Vector3(0, 0.9, 0), hay, Vector3(0, 0, 90), Vector3.ONE)
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.4, 1.8, 1.8)
	_collision(b, sh, Vector3(0, 0.9, 0))
	return b

## Decoração sem colisão (plantações, grama alta, ossos).
static func make_crop_row(length: float, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	var mat := MaterialLib.textured("leaves", Color(0.75, 0.95, 0.4), 2.0)
	var stalk := CylinderMesh.new()
	stalk.top_radius = 0.0
	stalk.bottom_radius = 0.25
	stalk.height = 0.9
	stalk.radial_segments = 5
	var count := int(length / 0.9)
	for i in count:
		var m := MeshInstance3D.new()
		m.mesh = stalk
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.position = Vector3(-length * 0.5 + i * 0.9, 0.45, rng.randf_range(-0.1, 0.1))
		m.scale = Vector3.ONE * rng.randf_range(0.7, 1.2)
		n.add_child(m)
	return n

static func make_torch() -> Node3D:
	var t := Node3D.new()
	t.add_to_group("night_lights")
	# A chama revela Espreitadores por perto.
	t.add_to_group("reveal_lights")
	t.set_meta(&"reveal_radius", 8.0)
	var post := CylinderMesh.new()
	post.top_radius = 0.07
	post.bottom_radius = 0.09
	post.height = 2.2
	_mi(t, post, Vector3(0, 1.1, 0), MaterialLib.textured("bark", Color.WHITE))
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.22
	bowl.bottom_radius = 0.1
	bowl.height = 0.25
	_mi(t, bowl, Vector3(0, 2.25, 0), MaterialLib.flat(Color(0.2, 0.18, 0.16)))
	var fire := EffectsHub.make_fire_particles(0.7)
	fire.position.y = 2.4
	fire.name = "Fire"
	t.add_child(fire)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 2.2
	light.omni_range = 9.0
	light.position.y = 2.6
	t.add_child(light)
	return t
