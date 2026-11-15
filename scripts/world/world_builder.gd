class_name WorldBuilder
extends Node
## Gera o mapa de forma determinística (semente): terreno com regiões, estradas,
## props coletáveis/saqueáveis, a base inicial e os pontos de surgimento.

const MAP_HALF := 120.0
const SPLAT_RES := 256
const BASE_RADIUS := 13.0
const TERRAIN_SHADER := preload("res://assets/effects/shaders/terrain.gdshader")
const TEX := "res://assets/environment/textures/"

var rng := RandomNumberGenerator.new()
var _occupied: Array[Vector3] = []  # x, z, raio (em y)
var _roads: Array[PackedVector2Array] = []
var _splat: Image
var _harvest_count: int = 0
var _loot_count: int = 0

## Saídas usadas pelo World
var nav_region: NavigationRegion3D
var structures_root: Node3D
var harvestables: Dictionary = {}  # id -> Harvestable
var lootables: Dictionary = {}     # id -> Lootable
var structures: Dictionary = {}    # id -> Structure
var spawn_points: Array[Vector3] = []
var regions: Array[Dictionary] = []

func build(world: Node3D, seed_value: int) -> void:
	rng.seed = seed_value
	_splat = Image.create(SPLAT_RES, SPLAT_RES, false, Image.FORMAT_RGBA8)
	_splat.fill(Color(0, 0, 0, 1))
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	nav_region.navigation_mesh = _make_navmesh()
	world.add_child(nav_region)
	structures_root = Node3D.new()
	structures_root.name = "Structures"
	world.add_child(structures_root)

	_define_roads()
	_build_ground()
	_build_borders()
	_reserve(Vector3.ZERO, BASE_RADIUS + 6.0)
	_build_forest()
	_build_quarry()
	_build_city()
	_build_farm()
	_build_contaminated()
	_scatter_wilds()
	_build_base(world)
	_define_spawns()
	_apply_terrain_material()
	_build_foliage(world)

func _make_navmesh() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = 0.4
	nm.cell_height = 0.25
	nm.agent_radius = 0.8
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.5
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Layers.WORLD
	nm.filter_baking_aabb = AABB(Vector3(-MAP_HALF, -2, -MAP_HALF), Vector3(MAP_HALF * 2, 10, MAP_HALF * 2))
	return nm

# --- Terreno ---------------------------------------------------------------------

var _ground_mesh: MeshInstance3D

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(MAP_HALF * 2 + 40, 2, MAP_HALF * 2 + 40)
	cs.shape = box
	cs.position.y = -1.0
	body.add_child(cs)
	_ground_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(MAP_HALF * 2 + 40, MAP_HALF * 2 + 40)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	_ground_mesh.mesh = plane
	body.add_child(_ground_mesh)
	nav_region.add_child(body)

func _apply_terrain_material() -> void:
	_paint_roads()
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("grass_tex", load(TEX + "grass.jpg"))
	mat.set_shader_parameter("dirt_tex", load(TEX + "dirt.jpg"))
	mat.set_shader_parameter("stone_tex", load(TEX + "stone_floor.jpg"))
	mat.set_shader_parameter("corrupt_tex", load(TEX + "corrupted.jpg"))
	_splat.generate_mipmaps()
	mat.set_shader_parameter("splat", ImageTexture.create_from_image(_splat))
	var noise := FastNoiseLite.new()
	noise.seed = rng.seed
	noise.frequency = 0.02
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.seamless = true
	nt.width = 256
	nt.height = 256
	mat.set_shader_parameter("noise_tex", nt)
	mat.set_shader_parameter("map_size", MAP_HALF * 2.0)
	_ground_mesh.material_override = mat

# --- Vegetação decorativa ------------------------------------------------------------

var _blocked: PackedByteArray

func _build_foliage(world: Node3D) -> void:
	# Grade de 1 m marcando onde NÃO plantar (props, base).
	var n := int(MAP_HALF * 2)
	_blocked = PackedByteArray()
	_blocked.resize(n * n)
	for o in _occupied:
		var r := int(o.y * 0.7)
		var cx := int(o.x + MAP_HALF)
		var cz := int(o.z + MAP_HALF)
		for z in range(cz - r, cz + r + 1):
			for x in range(cx - r, cx + r + 1):
				if x >= 0 and z >= 0 and x < n and z < n and (x - cx) * (x - cx) + (z - cz) * (z - cz) <= r * r:
					_blocked[z * n + x] = 1
	var f := Foliage.new()
	f.name = "Foliage"
	world.add_child(f)
	f.build(MAP_HALF - 2.0, 0.38 if Platform.low_end else 0.55, _is_grass, rng.seed + 7)

func _is_grass(p: Vector3) -> bool:
	var n := int(MAP_HALF * 2)
	var x := int(p.x + MAP_HALF)
	var z := int(p.z + MAP_HALF)
	if x < 0 or z < 0 or x >= n or z >= n or _blocked[z * n + x] == 1:
		return false
	if p.length() < BASE_RADIUS + 2.5:
		return false
	var c := _px(Vector2(p.x, p.z))
	var col := _splat.get_pixel(clampi(c.x, 0, SPLAT_RES - 1), clampi(c.y, 0, SPLAT_RES - 1))
	return col.r < 0.35 and col.g < 0.35 and col.b < 0.35

func _px(p: Vector2) -> Vector2i:
	return Vector2i(int((p.x / (MAP_HALF * 2) + 0.5) * SPLAT_RES), int((p.y / (MAP_HALF * 2) + 0.5) * SPLAT_RES))

## Pinta um círculo no canal escolhido (0=terra, 1=pedra, 2=corrupção).
func _paint_circle(center: Vector2, radius: float, channel: int, strength: float = 1.0) -> void:
	var c := _px(center)
	var r := int(radius / (MAP_HALF * 2) * SPLAT_RES) + 1
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if x < 0 or y < 0 or x >= SPLAT_RES or y >= SPLAT_RES:
				continue
			var d := Vector2(x - c.x, y - c.y).length() / float(r)
			if d > 1.0:
				continue
			var col := _splat.get_pixel(x, y)
			var v := strength * (1.0 - smoothstep(0.6, 1.0, d))
			match channel:
				0: col.r = maxf(col.r, v)
				1: col.g = maxf(col.g, v)
				2: col.b = maxf(col.b, v)
			_splat.set_pixel(x, y, col)

func _paint_rect(center: Vector2, size: Vector2, channel: int) -> void:
	var step := 2.0
	var x := -size.x * 0.5
	while x <= size.x * 0.5:
		var y := -size.y * 0.5
		while y <= size.y * 0.5:
			_paint_circle(center + Vector2(x, y), 2.5, channel)
			y += step
		x += step

func _define_roads() -> void:
	_roads.append(_road_path([Vector2(0, -10), Vector2(-6, -50), Vector2(5, -85), Vector2(-4, -112)]))
	_roads.append(_road_path([Vector2(10, 0), Vector2(45, 6), Vector2(80, 4), Vector2(112, 10)]))
	_roads.append(_road_path([Vector2(0, 10), Vector2(-12, 45), Vector2(-25, 80), Vector2(-30, 112)]))
	_roads.append(_road_path([Vector2(-10, 0), Vector2(-50, -6), Vector2(-112, 4)]))
	_roads.append(_road_path([Vector2(45, 6), Vector2(70, -40), Vector2(88, -80)]))

func _road_path(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var n := int(a.distance_to(b) / 2.0)
		for k in n:
			out.append(a.lerp(b, float(k) / n) + Vector2(sin(k * 0.4) * 1.2, cos(k * 0.3) * 1.2))
	out.append(points[-1])
	return out

func _paint_roads() -> void:
	for road in _roads:
		for p in road:
			_paint_circle(p, 3.2, 0, 1.0)

func _near_road(p: Vector3, margin: float) -> bool:
	var q := Vector2(p.x, p.z)
	for road in _roads:
		for r in road:
			if r.distance_squared_to(q) < margin * margin:
				return true
	return false

# --- Posicionamento ----------------------------------------------------------------

func _reserve(p: Vector3, radius: float) -> void:
	_occupied.append(Vector3(p.x, radius, p.z))

func _free_at(p: Vector3, radius: float) -> bool:
	if absf(p.x) > MAP_HALF - 4.0 or absf(p.z) > MAP_HALF - 4.0:
		return false
	for o in _occupied:
		var dx := o.x - p.x
		var dz := o.z - p.z
		var rr := o.y + radius
		if dx * dx + dz * dz < rr * rr:
			return false
	return true

func _random_in(center: Vector2, half: Vector2) -> Vector3:
	return Vector3(center.x + rng.randf_range(-half.x, half.x), 0, center.y + rng.randf_range(-half.y, half.y))

func _try_place(center: Vector2, half: Vector2, radius: float, road_margin: float = 3.5, attempts: int = 12) -> Variant:
	for i in attempts:
		var p := _random_in(center, half)
		if _free_at(p, radius) and not _near_road(p, road_margin + radius):
			_reserve(p, radius)
			return p
	return null

func _add_harvestable(h: Harvestable, p: Vector3) -> void:
	h.node_id = "h%d" % _harvest_count
	h.name = h.node_id
	_harvest_count += 1
	h.position = p
	nav_region.add_child(h)
	harvestables[h.node_id] = h

func _add_lootable(l: Lootable, p: Vector3, rot_y: float = 0.0) -> void:
	l.node_id = "l%d" % _loot_count
	l.name = l.node_id
	_loot_count += 1
	l.position = p
	l.rotation.y = rot_y
	nav_region.add_child(l)
	lootables[l.node_id] = l

func _add_static(b: Node3D, p: Vector3, rot_y: float = 0.0) -> void:
	b.position = p
	b.rotation.y = rot_y
	nav_region.add_child(b)

func _add_decor(n: Node3D, p: Vector3, rot_y: float = 0.0) -> void:
	n.position = p
	n.rotation.y = rot_y
	nav_region.add_child(n)

# --- Regiões -----------------------------------------------------------------------

func _build_forest() -> void:
	var c := Vector2(-25, -78)
	var half := Vector2(85, 38)
	for i in 230:
		var p: Variant = _try_place(c, half, 1.3)
		if p != null:
			_add_harvestable(PropFactory.make_tree(rng), p)
	for i in 6:
		var p2: Variant = _try_place(c, half, 1.2)
		if p2 != null:
			_add_lootable(PropFactory.make_lootable("crate", rng), p2, rng.randf() * TAU)
	# Carroças abandonadas à beira da estrada da floresta
	for i in 3:
		var rp: Vector2 = _roads[0][8 + i * 12]
		var cpos := Vector3(rp.x + 5.0, 0, rp.y)
		if _free_at(cpos, 2.0):
			_reserve(cpos, 2.0)
			_add_lootable(PropFactory.make_lootable("cart", rng), cpos, rng.randf() * TAU)
	for i in 8:
		var p3: Variant = _try_place(c, half, 1.5)
		if p3 != null:
			_add_harvestable(PropFactory.make_rock(rng, false), p3)
	regions.append({"name": "Floresta", "center": Vector3(c.x, 0, c.y), "radius": 50.0, "max": 10,
		"enemies": [_enemy("zombie")], "weights": [1.0], "hp_mult": 1.0})

func _build_quarry() -> void:
	var c := Vector2(-85, 15)
	var half := Vector2(28, 32)
	for i in 6:
		_paint_circle(Vector2(c.x + rng.randf_range(-20, 20), c.y + rng.randf_range(-25, 25)), rng.randf_range(8, 14), 1, 0.7)
	for i in 34:
		var p: Variant = _try_place(c, half, 2.0)
		if p != null:
			_add_harvestable(PropFactory.make_rock(rng, true), p)
	for i in 14:
		var p2: Variant = _try_place(c, half, 1.0)
		if p2 != null:
			_add_harvestable(PropFactory.make_rock(rng, false), p2)
	for i in 3:
		var p3: Variant = _try_place(c, half, 1.2)
		if p3 != null:
			_add_lootable(PropFactory.make_lootable("crate", rng), p3, rng.randf() * TAU)
	regions.append({"name": "Pedreira", "center": Vector3(c.x, 0, c.y), "radius": 30.0, "max": 6,
		"enemies": [_enemy("zombie")], "weights": [1.0], "hp_mult": 1.0})

func _build_city() -> void:
	var c := Vector2(80, 12)
	_paint_rect(c, Vector2(62, 84), 1)
	# Quarteirões em grade, deixando ruas livres.
	for gx in 3:
		for gz in 4:
			var center := Vector3(c.x - 20 + gx * 20, 0, c.y - 33 + gz * 21)
			if _near_road(center, 7.0):
				center.z += 8.0
			if not _free_at(center, 6.0):
				continue
			var ruined := rng.randf() < 0.35
			var house := PropFactory.make_house(rng, ruined)
			_reserve(center, 6.5)
			_add_static(house, center, deg_to_rad(90.0 * rng.randi_range(0, 3)))
			# Armário saqueável ao lado da casa
			var lp := center + Vector3(rng.randf_range(-4, 4), 0, 5.5)
			if _free_at(lp, 0.8):
				_reserve(lp, 0.8)
				_add_lootable(PropFactory.make_lootable("cabinet" if rng.randf() < 0.5 else "crate", rng), lp, rng.randf() * TAU)
	for i in 14:
		var p: Variant = _try_place(c, Vector2(30, 42), 2.6, 0.0)
		if p != null:
			_add_lootable(PropFactory.make_lootable("car", rng), p, rng.randf() * TAU)
	for i in 10:
		var p2: Variant = _try_place(c, Vector2(30, 42), 1.3)
		if p2 != null:
			_add_harvestable(PropFactory.make_tree(rng, rng.randf() < 0.5), p2)
	regions.append({"name": "Cidade Abandonada", "center": Vector3(c.x, 0, c.y), "radius": 38.0, "max": 12,
		"enemies": [_enemy("zombie"), _enemy("zombie_fast")], "weights": [0.7, 0.3], "hp_mult": 1.0})

func _build_farm() -> void:
	var c := Vector2(-35, 78)
	var barn_pos := Vector3(c.x + 22, 0, c.y - 8)
	_reserve(barn_pos, 10.0)
	_add_static(PropFactory.make_barn(rng), barn_pos, deg_to_rad(15))
	# Campos de plantação
	for f in 3:
		var fc := Vector2(c.x - 22 + f * 16, c.y + 12)
		_paint_rect(fc, Vector2(12, 18), 0)
		for row in 6:
			var rp := Vector3(fc.x, 0, fc.y - 7.5 + row * 3.0)
			_add_decor(PropFactory.make_crop_row(10.0, rng), rp, deg_to_rad(90))
		_reserve(Vector3(fc.x, 0, fc.y), 9.0)
	for i in 5:
		var fp: Variant = _try_place(c, Vector2(35, 30), 4.0)
		if fp != null:
			_add_static(PropFactory.make_fence(8.0), fp, rng.randf() * PI)
	for i in 8:
		var hp: Variant = _try_place(c, Vector2(35, 30), 1.5)
		if hp != null:
			_add_static(PropFactory.make_haystack(rng), hp, rng.randf() * TAU)
	for i in 7:
		var lp: Variant = _try_place(c, Vector2(35, 30), 1.2)
		if lp != null:
			_add_lootable(PropFactory.make_lootable("farm", rng), lp, rng.randf() * TAU)
	for i in 4:
		var cp: Variant = _try_place(c, Vector2(35, 30), 2.2)
		if cp != null:
			_add_lootable(PropFactory.make_lootable("cart", rng), cp, rng.randf() * TAU)
	for i in 16:
		var tp: Variant = _try_place(c, Vector2(40, 34), 1.3)
		if tp != null:
			_add_harvestable(PropFactory.make_tree(rng), tp)
	regions.append({"name": "Fazenda", "center": Vector3(c.x, 0, c.y), "radius": 34.0, "max": 8,
		"enemies": [_enemy("zombie")], "weights": [1.0], "hp_mult": 1.0})

func _build_contaminated() -> void:
	var c := Vector2(88, -88)
	for i in 8:
		_paint_circle(Vector2(c.x + rng.randf_range(-20, 20), c.y + rng.randf_range(-20, 20)), rng.randf_range(10, 18), 2, 1.0)
	for i in 26:
		var p: Variant = _try_place(c, Vector2(26, 26), 1.3)
		if p != null:
			_add_harvestable(PropFactory.make_tree(rng, true), p)
	for i in 5:
		var p2: Variant = _try_place(c, Vector2(24, 24), 1.4)
		if p2 != null:
			_add_lootable(PropFactory.make_lootable("cache", rng), p2, rng.randf() * TAU)
	for i in 10:
		var p3: Variant = _try_place(c, Vector2(26, 26), 2.0)
		if p3 != null:
			_add_harvestable(PropFactory.make_rock(rng, true), p3)
	regions.append({"name": "Área Contaminada", "center": Vector3(c.x, 0, c.y), "radius": 26.0, "max": 9,
		"enemies": [_enemy("zombie"), _enemy("zombie_fast"), _enemy("zombie_brute")], "weights": [0.4, 0.35, 0.25], "hp_mult": 1.25})

func _scatter_wilds() -> void:
	# Árvores e pedras esparsas nas áreas de transição.
	for i in 90:
		var p: Variant = _try_place(Vector2.ZERO, Vector2(110, 110), 1.4)
		if p != null and (p as Vector3).length() > 28.0:
			if rng.randf() < 0.7:
				_add_harvestable(PropFactory.make_tree(rng), p)
			else:
				_add_harvestable(PropFactory.make_rock(rng, rng.randf() < 0.4), p)
	# Caixas isoladas = recompensa por explorar
	for i in 8:
		var lp: Variant = _try_place(Vector2.ZERO, Vector2(105, 105), 1.2)
		if lp != null and (lp as Vector3).length() > 35.0:
			_add_lootable(PropFactory.make_lootable("crate", rng), lp, rng.randf() * TAU)
	# Alguns recursos próximos da base para o começo do jogo.
	for i in 10:
		var bp: Variant = _try_place(Vector2.ZERO, Vector2(32, 32), 1.4)
		if bp != null and (bp as Vector3).length() > 21.0:
			_add_harvestable(PropFactory.make_tree(rng) if i % 3 != 0 else PropFactory.make_rock(rng, false), bp)

func _build_borders() -> void:
	# Paredes invisíveis + linha de árvores densas nas bordas.
	for side in 4:
		var body := StaticBody3D.new()
		body.collision_layer = Layers.WORLD | Layers.STRUCTURES
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(MAP_HALF * 2 + 20, 8, 4) if side < 2 else Vector3(4, 8, MAP_HALF * 2 + 20)
		cs.shape = box
		body.add_child(cs)
		var off := MAP_HALF + 2.0
		body.position = [Vector3(0, 4, -off), Vector3(0, 4, off), Vector3(-off, 4, 0), Vector3(off, 4, 0)][side]
		nav_region.add_child(body)
	var bark := MaterialLib.textured("bark", Color(0.5, 0.45, 0.4))
	var leaves := MaterialLib.textured("leaves", Color(0.35, 0.5, 0.3), 1.0)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.3
	trunk.bottom_radius = 0.5
	trunk.height = 4.0
	var crown := SphereMesh.new()
	crown.radius = 2.6
	crown.height = 4.5
	crown.radial_segments = 8
	crown.rings = 5
	var t := -MAP_HALF
	while t <= MAP_HALF:
		for p in [Vector3(t, 0, -MAP_HALF - 3), Vector3(t, 0, MAP_HALF + 3), Vector3(-MAP_HALF - 3, 0, t), Vector3(MAP_HALF + 3, 0, t)]:
			var n := Node3D.new()
			n.position = p + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
			n.scale = Vector3.ONE * rng.randf_range(1.0, 1.6)
			PropFactory._mi(n, trunk, Vector3(0, 2, 0), bark)
			PropFactory._mi(n, crown, Vector3(0, 5, 0), leaves)
			add_child(n)
		t += 5.0

# --- Base inicial ------------------------------------------------------------------

func _build_base(world: Node3D) -> void:
	_paint_circle(Vector2.ZERO, BASE_RADIUS + 3.0, 0, 0.9)
	_paint_circle(Vector2.ZERO, 5.0, 1, 1.0)
	var wall_scene := preload("res://scenes/buildings/wall.tscn")
	var gate_scene := preload("res://scenes/buildings/gate.tscn")
	var core_scene := preload("res://scenes/buildings/base_core.tscn")
	var core := core_scene.instantiate() as Structure
	core.name = "Core"
	core.structure_id = "core"
	structures_root.add_child(core)
	structures["core"] = core
	# Anel de paliçadas com dois portões (norte e sul).
	var segments := 20
	var seg_len := 2.0 * PI * BASE_RADIUS / segments + 0.15
	for i in segments:
		var ang := (i + 0.5) * TAU / segments
		var pos := Vector3(sin(ang) * BASE_RADIUS, 0, -cos(ang) * BASE_RADIUS)
		var is_gate := i == 0 or i == segments / 2
		var s := (gate_scene if is_gate else wall_scene).instantiate() as Structure
		s.length = seg_len
		s.structure_id = ("gate%d" if is_gate else "wall%d") % i
		s.name = s.structure_id
		s.position = pos
		s.rotation.y = -ang
		structures_root.add_child(s)
		structures[s.structure_id] = s
	# Tochas internas
	for i in 6:
		var ang := i * TAU / 6 + 0.3
		var torch := PropFactory.make_torch()
		torch.position = Vector3(sin(ang) * (BASE_RADIUS - 2.5), 0, cos(ang) * (BASE_RADIUS - 2.5))
		structures_root.add_child(torch)
	# Armazém visual (pilhas de caixas)
	for p in [Vector3(-6.5, 0, 3.5), Vector3(6.5, 0, -2.5)]:
		var wagon: Node3D
		if ModelLibrary.has("cart"):
			wagon = ModelLibrary.instance_footprint("cart", 3.2)
		else:
			wagon = MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(1.2, 1.0, 1.2)
			(wagon as MeshInstance3D).mesh = b
			(wagon as MeshInstance3D).material_override = MaterialLib.textured("planks", Color.WHITE)
			wagon.position.y = 0.5
		wagon.position += p
		wagon.rotation.y = rng.randf() * TAU
		structures_root.add_child(wagon)
	var zone := BaseZone.new()
	zone.name = "BaseZone"
	zone.radius = BASE_RADIUS - 0.5
	world.add_child(zone)

func _define_spawns() -> void:
	for i in 8:
		var ang := i * TAU / 8.0 + 0.2
		var p := Vector3(sin(ang), 0, -cos(ang)) * 104.0
		p.x = clampf(p.x, -MAP_HALF + 8, MAP_HALF - 8)
		p.z = clampf(p.z, -MAP_HALF + 8, MAP_HALF - 8)
		spawn_points.append(p)

func _enemy(id: String) -> EnemyDef:
	return load("res://data/enemies/%s.tres" % id) as EnemyDef
