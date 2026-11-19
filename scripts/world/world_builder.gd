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
## Malha só dos aliados (soldados): contorna paliçada e construções, passa pelos portões.
var ally_nav_region: NavigationRegion3D
var structures_root: Node3D
var harvestables: Dictionary = {}  # id -> Harvestable
var lootables: Dictionary = {}     # id -> Lootable
var structures: Dictionary = {}    # id -> Structure
var spawn_points: Array[Vector3] = []
var regions: Array[Dictionary] = []

func build(world: Node3D, seed_value: int) -> void:
	rng.seed = seed_value
	PropFactory.style_rng.seed = seed_value + 4242
	_splat = Image.create(SPLAT_RES, SPLAT_RES, false, Image.FORMAT_RGBA8)
	_splat.fill(Color(0, 0, 0, 1))
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	nav_region.navigation_mesh = _make_navmesh()
	world.add_child(nav_region)
	structures_root = Node3D.new()
	structures_root.name = "Structures"
	ally_nav_region = NavigationRegion3D.new()
	ally_nav_region.name = "AllyNavRegion"
	ally_nav_region.navigation_layers = 2
	var anm := _make_navmesh()
	anm.geometry_collision_mask = Layers.WORLD | Layers.STRUCTURES
	anm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	anm.geometry_source_group_name = &"ally_nav_source"
	ally_nav_region.navigation_mesh = anm
	world.add_child(ally_nav_region)
	nav_region.add_to_group(&"ally_nav_source")
	structures_root.add_to_group(&"ally_nav_source")
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
	_build_scenery()
	_define_spawns()
	_apply_terrain_material()
	_build_foliage(world)
	_build_decor(world)

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

## Chão dividido em blocos: cada bloco só recebe as luzes próximas (o renderizador
## web limita as luzes por objeto; um chão único perderia a lanterna e as tochas).
var _ground_chunks: Array[MeshInstance3D] = []
const GROUND_CHUNKS := 8

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
	var full := MAP_HALF * 2 + 40.0
	var step := full / GROUND_CHUNKS
	var plane := PlaneMesh.new()
	plane.size = Vector2(step, step)
	for gx in GROUND_CHUNKS:
		for gz in GROUND_CHUNKS:
			var chunk := MeshInstance3D.new()
			chunk.mesh = plane
			chunk.position = Vector3(-full * 0.5 + step * (gx + 0.5), 0, -full * 0.5 + step * (gz + 0.5))
			body.add_child(chunk)
			_ground_chunks.append(chunk)
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
	for chunk in _ground_chunks:
		chunk.material_override = mat

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
	f.build(MAP_HALF - 2.0, Settings.grass_density(), _is_grass, rng.seed + 7)

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
		"enemies": [_enemy("zombie"), _enemy("zombie_fast"), _enemy("skeleton_minion")], "weights": [0.6, 0.25, 0.15], "hp_mult": 1.0})

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
		"enemies": [_enemy("zombie"), _enemy("zombie_fast"), _enemy("zombie_brute"), _enemy("zombie_exploder"), _enemy("zombie_spitter"), _enemy("skeleton_minion"), _enemy("skeleton_warrior"), _enemy("skeleton_mage")],
		"weights": [0.24, 0.2, 0.14, 0.08, 0.08, 0.14, 0.06, 0.06], "hp_mult": 1.25})

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
		if ThirdParty.has(ThirdParty.BLENDER, "burned_cart"):
			wagon = ThirdParty.instance(ThirdParty.BLENDER, "burned_cart")
		elif ModelLibrary.has("cart"):
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

# --- Cenário de terceiros (CC0) ------------------------------------------------------

var _srng := RandomNumberGenerator.new()

## Objeto sólido (com colisão) do pacote, reservando a área no mapa.
func _place_solid(pack: String, model: String, p: Vector3, height: float, rot_y: float, radius: float, parent: Node3D = null) -> void:
	if not ThirdParty.has(pack, model):
		return
	var b := ThirdParty.solid(pack, model, height)
	b.position = p
	b.rotation.y = rot_y
	(parent if parent else nav_region).add_child(b)
	_reserve(p, radius)

## Carroça queimada do Blender (ou a carroça do pacote, se o modelo não existir).
func _place_wagon(p: Vector3, rot_y: float) -> void:
	if ThirdParty.has(ThirdParty.BLENDER, "burned_cart"):
		_place_solid(ThirdParty.BLENDER, "burned_cart", p, ThirdParty.aabb(ThirdParty.BLENDER, "burned_cart").size.y, rot_y, 2.6)
	else:
		_place_solid(ThirdParty.VILLAGE, "Prop_Wagon", p, 2.0, rot_y, 2.4)

func _try_place_s(center: Vector2, half: Vector2, radius: float, road_margin: float = 2.0) -> Variant:
	for i in 14:
		var p := Vector3(center.x + _srng.randf_range(-half.x, half.x), 0, center.y + _srng.randf_range(-half.y, half.y))
		if _free_at(p, radius) and not _near_road(p, road_margin + radius):
			return p
	return null

func _build_scenery() -> void:
	_srng.seed = rng.seed + 777
	_build_cemetery()
	_build_base_props()
	_build_ruins()
	_build_survivors()
	_build_horror_props()
	# Cidade: barracas, carroças, barris e cercas de ferro.
	var city := Vector2(80, 12)
	for i in 5:
		var p: Variant = _try_place_s(city, Vector2(30, 42), 2.2, 1.0)
		if p != null:
			_place_solid(ThirdParty.PROPS, "Stall_Cart_Empty" if i % 2 == 0 else "Stall_Empty", p, 2.6, _srng.randf() * TAU, 2.2)
	for i in 3:
		var p2: Variant = _try_place_s(city, Vector2(30, 42), 2.4, 1.0)
		if p2 != null:
			_place_wagon(p2, _srng.randf() * TAU)
	var B := ThirdParty.BLENDER
	if ThirdParty.has(B, "oil_drums"):
		# Tambores de óleo enferrujados (dois com fogueira acesa à noite) e pilhas de entulho.
		var drums_h := ThirdParty.aabb(B, "oil_drums").size.y
		var rubble_h := ThirdParty.aabb(B, "rubble_pile").size.y
		for i in 6:
			var dp: Variant = _try_place_s(city, Vector2(30, 42), 1.6, 1.0)
			if dp != null:
				var body := ThirdParty.solid(B, "oil_drums", drums_h, 0.7)
				body.position = dp
				body.rotation.y = _srng.randf() * TAU
				nav_region.add_child(body)
				_reserve(dp, 1.6)
				if i < 2:
					_burning_barrel(body)
		for i in 7:
			var rp: Variant = _try_place_s(city, Vector2(30, 42), 1.5, 1.0)
			if rp != null:
				_place_solid(B, "rubble_pile", rp, rubble_h, _srng.randf() * TAU, 1.5)
	else:
		for i in 12:
			var p3: Variant = _try_place_s(city, Vector2(30, 42), 0.8, 1.0)
			if p3 != null:
				var m: String = ["Barrel", "Barrel_Apples", "Crate_Wooden", "Crate_Metal"][_srng.randi() % 4]
				_place_solid(ThirdParty.PROPS, m, p3, _srng.randf_range(0.9, 1.2), _srng.randf() * TAU, 0.8)
	for i in 6:
		var p4: Variant = _try_place_s(city, Vector2(30, 42), 1.6, 1.5)
		if p4 != null:
			_place_solid(ThirdParty.VILLAGE, "Prop_MetalFence_Ornament", p4, 1.6, _srng.randf() * PI, 1.6)
	# Fazenda: caixotes de maçã, barris, carroça e cercas de madeira.
	var farm := Vector2(-35, 78)
	for i in 8:
		var fp: Variant = _try_place_s(farm, Vector2(35, 30), 0.8)
		if fp != null:
			var fm: String = ["FarmCrate_Apple", "Barrel_Apples", "Barrel", "Bucket_Wooden_1"][_srng.randi() % 4]
			_place_solid(ThirdParty.PROPS, fm, fp, 0.9 if fm != "Bucket_Wooden_1" else 0.5, _srng.randf() * TAU, 0.8)
	for i in 8:
		var wp: Variant = _try_place_s(farm, Vector2(38, 32), 1.4)
		if wp != null:
			_place_solid(ThirdParty.VILLAGE, "Prop_WoodenFence_Single", wp, 1.3, _srng.randf() * PI, 1.4)
	var wg: Variant = _try_place_s(farm, Vector2(30, 26), 2.4)
	if wg != null:
		_place_wagon(wg, _srng.randf() * TAU)

## Terror no cenário (modelos do Blender): estacas com cabeças à beira das estradas e na
## Área Contaminada, e piras de corpos — duas delas ardem à noite (fogo e luz).
func _build_horror_props() -> void:
	var B := ThirdParty.BLENDER
	if not ThirdParty.has(B, "pike_heads"):
		return
	var pike_h := ThirdParty.aabb(B, "pike_heads").size.y
	var pyre_h := ThirdParty.aabb(B, "corpse_pyre").size.y
	# Estacas de aviso ao longo das estradas, saindo da base.
	var placed := 0
	for road in _roads:
		for k in range(10, road.size(), 9):
			if placed >= 14:
				break
			var r: Vector2 = road[k]
			var side := 1.0 if (k / 9) % 2 == 0 else -1.0
			var dir := (road[mini(k + 1, road.size() - 1)] - road[maxi(k - 1, 0)]).normalized()
			var off := Vector2(-dir.y, dir.x) * 4.6 * side
			var p := Vector3(r.x + off.x, 0, r.y + off.y)
			if p.length() < BASE_RADIUS + 14.0 or not _free_at(p, 1.0):
				continue
			_place_solid(B, "pike_heads", p, pike_h, _srng.randf() * TAU, 1.0)
			placed += 1
	for i in 5:
		var cp: Variant = _try_place_s(Vector2(88, -88), Vector2(24, 24), 1.0)
		if cp != null:
			_place_solid(B, "pike_heads", cp, pike_h, _srng.randf() * TAU, 1.0)
	# Piras: Área Contaminada, cidade e fazenda; as duas primeiras queimam à noite.
	var spots := [[Vector2(88, -88), Vector2(22, 22)], [Vector2(80, 12), Vector2(28, 38)], [Vector2(88, -88), Vector2(22, 22)],
		[Vector2(-35, 78), Vector2(32, 26)], [Vector2(0, 0), Vector2(90, 90)]]
	for i in spots.size():
		var pp: Variant = _try_place_s(spots[i][0], spots[i][1], 2.0)
		if pp == null or (pp as Vector3).length() < BASE_RADIUS + 12.0:
			continue
		var body := ThirdParty.solid(B, "corpse_pyre", pyre_h)
		body.position = pp
		body.rotation.y = _srng.randf() * TAU
		nav_region.add_child(body)
		_reserve(pp, 2.0)
		if i < 2:
			_burning_pyre(body)

## Fogueira no tambor do centro (origem do modelo oil_drums), só à noite.
func _burning_barrel(body: Node3D) -> void:
	var fx := Node3D.new()
	fx.add_to_group("night_lights")
	body.add_child(fx)
	var fire := EffectsHub.make_fire_particles(0.9)
	fire.position.y = 0.95
	fire.visible = false
	fx.add_child(fire)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.22)
	light.light_energy = 2.0
	light.omni_range = 7.0
	light.position.y = 1.3
	light.visible = false
	light.add_to_group("reveal_lights")
	light.set_meta(&"reveal_radius", 6.0)
	fx.add_child(light)

## Fogo e luz na pira (só à noite: grupo night_lights; revela Espreitadores).
func _burning_pyre(body: Node3D) -> void:
	var fx := Node3D.new()
	fx.add_to_group("night_lights")
	body.add_child(fx)
	var fire := EffectsHub.make_fire_particles(1.8)
	fire.position.y = 0.9
	fire.visible = false
	fx.add_child(fire)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.2)
	light.light_energy = 2.4
	light.omni_range = 8.0
	light.position.y = 1.4
	light.visible = false
	light.add_to_group("reveal_lights")
	light.set_meta(&"reveal_radius", 7.0)
	fx.add_child(light)

## Cemitério na Área Contaminada: cripta, portal, cercas, lápides, caixões, ossos e lanternas.
func _build_cemetery() -> void:
	var c := Vector2(88, -88)
	var yard := Vector3(c.x - 6, 0, c.y + 4)
	_place_solid(ThirdParty.HALLOWEEN, "crypt", yard + Vector3(0, 0, -7), 4.8, 0.0, 4.0)
	_place_solid(ThirdParty.HALLOWEEN, "arch_gate", yard + Vector3(0, 0, 8.5), 3.6, 0.0, 2.0)
	# Cerca ao redor do pátio (com a entrada pelo portal).
	for i in 12:
		var ang := i * TAU / 12.0
		var fp := yard + Vector3(sin(ang) * 9.5, 0, cos(ang) * 9.5)
		if absf(fp.x - yard.x) < 2.5 and fp.z > yard.z:
			continue
		_place_solid(ThirdParty.HALLOWEEN, "fence_broken" if _srng.randf() < 0.3 else "fence", fp, 1.4, ang + PI * 0.5, 1.2)
	# Fileiras de túmulos.
	var graves := ["grave_A", "grave_B", "gravestone", "gravemarker_A", "gravemarker_B"]
	for row in 3:
		for col in 5:
			var gp := yard + Vector3(-6 + col * 3.0 + _srng.randf_range(-0.4, 0.4), 0, -2 + row * 3.2 + _srng.randf_range(-0.3, 0.3))
			if _free_at(gp, 0.5):
				var g: String = graves[_srng.randi() % graves.size()]
				_place_solid(ThirdParty.HALLOWEEN, g, gp, _srng.randf_range(0.9, 1.3), _srng.randf_range(-0.2, 0.2), 0.7)
	for i in 3:
		var cp: Variant = _try_place_s(c, Vector2(24, 24), 1.2)
		if cp != null:
			_place_solid(ThirdParty.HALLOWEEN, "coffin", cp, 0.7, _srng.randf() * TAU, 1.2)
	for i in 4:
		var lp: Variant = _try_place_s(c, Vector2(22, 22), 0.6)
		if lp != null:
			_place_solid(ThirdParty.HALLOWEEN, "lantern_standing" if i % 2 == 0 else "post_skull", lp, 1.8, _srng.randf() * TAU, 0.6)
	for i in 2:
		var sp: Variant = _try_place_s(c, Vector2(22, 22), 1.0)
		if sp != null:
			_place_solid(ThirdParty.HALLOWEEN, "shrine_candles", sp, 1.6, _srng.randf() * TAU, 1.0)

## Oficina e estandartes dentro da base (perto da paliçada, longe dos portões).
func _build_base_props() -> void:
	var r := BASE_RADIUS - 3.2
	var forge_ang := 2.0
	var fc := Vector3(sin(forge_ang) * r, 0, -cos(forge_ang) * r)
	_place_solid(ThirdParty.PROPS, "Anvil", fc, 0.9, forge_ang, 0.7)
	_place_solid(ThirdParty.PROPS, "Workbench", fc + Vector3(1.8, 0, -1.2).rotated(Vector3.UP, -forge_ang), 1.1, forge_ang, 1.0)
	_place_solid(ThirdParty.PROPS, "WeaponStand", fc + Vector3(-1.8, 0, -0.6).rotated(Vector3.UP, -forge_ang), 1.6, forge_ang, 0.8)
	var dummy_ang := 4.3
	_place_solid(ThirdParty.PROPS, "Dummy", Vector3(sin(dummy_ang) * r, 0, -cos(dummy_ang) * r), 1.8, dummy_ang, 0.6)
	for ang: float in [0.9, 1.25, 3.9, 5.15]:
		var cp := Vector3(sin(ang) * r, 0, -cos(ang) * r)
		var m: String = ["Barrel", "Crate_Wooden", "Barrel_Apples", "Chest_Wood"][int(ang * 10) % 4]
		_place_solid(ThirdParty.PROPS, m, cp, 1.0, ang, 0.7)
	# Estandartes nos dois lados de cada portão.
	for base_ang: float in [0.0, PI]:
		for off: float in [-0.32, 0.32]:
			var ang := base_ang + off
			if ThirdParty.has(ThirdParty.PROPS, "Banner_1"):
				var bn := ThirdParty.instance(ThirdParty.PROPS, "Banner_1", 3.4)
				bn.position = Vector3(sin(ang) * (BASE_RADIUS - 1.6), 0, -cos(ang) * (BASE_RADIUS - 1.6))
				bn.rotation.y = -ang + PI
				structures_root.add_child(bn)

## Vegetação e detalhes sem colisão (MultiMesh por região, para o recorte por câmera funcionar).
func _build_decor(world: Node3D) -> void:
	var drng := RandomNumberGenerator.new()
	drng.seed = rng.seed + 911
	var k := Settings.decor_density()
	var N := ThirdParty.NATURE
	var H := ThirdParty.HALLOWEEN
	var pebbles := [[N, "Pebble_Round_1", 0.15, 0.35], [N, "Pebble_Round_2", 0.15, 0.35], [N, "Pebble_Round_3", 0.15, 0.3]]
	var plan := {
		"Floresta": [Vector2(-25, -78), Vector2(85, 38), [
			[N, "Bush_Common", 70, 0.9, 1.4], [N, "Fern_1", 110, 0.6, 1.0],
			[N, "Mushroom_Common", 40, 0.25, 0.5], [N, "Mushroom_Laetiporus", 15, 0.3, 0.5], [N, "Plant_1_Big", 40, 0.8, 1.3],
			[N, "Clover_1", 60, 0.15, 0.3], [N, "Flower_3_Group", 6, 0.4, 0.7],
			[N, "Grass_Wispy_Tall", 80, 0.5, 0.9], [N, "Rock_Medium_1", 12, 0.6, 1.3], [N, "Rock_Medium_2", 10, 0.6, 1.3]]],
		"Campos": [Vector2.ZERO, Vector2(112, 112), [
			[N, "Bush_Common", 50, 0.9, 1.3], [N, "Flower_4_Group", 8, 0.4, 0.7], [N, "Grass_Wispy_Tall", 70, 0.5, 0.9],
			[N, "Fern_1", 40, 0.6, 1.0], [N, "Grass_Common_Tall", 80, 0.5, 0.9], [N, "Rock_Medium_3", 20, 0.6, 1.2]]],
		"Fazenda": [Vector2(-35, 78), Vector2(40, 34), [
			[N, "Flower_4_Group", 6, 0.4, 0.7], [N, "Grass_Wispy_Tall", 40, 0.5, 0.9], [N, "Bush_Common", 16, 0.9, 1.3]]],
		"Cidade": [Vector2(80, 12), Vector2(30, 42), [[N, "Bush_Common", 10, 0.8, 1.2], [N, "Grass_Wispy_Tall", 30, 0.5, 0.8]]],
		"Contaminada": [Vector2(88, -88), Vector2(26, 26), [
			[H, "ribcage", 10, 0.5, 0.7], [H, "skull", 18, 0.25, 0.32], [H, "bone_A", 25, 0.1, 0.16],
			[N, "Mushroom_Laetiporus", 15, 0.3, 0.5], [H, "tree_dead_medium", 6, 3.0, 4.0], [H, "tree_dead_large", 4, 4.0, 5.5]]],
		"Pedreira": [Vector2(-85, 15), Vector2(28, 32), [[N, "Rock_Medium_1", 15, 0.6, 1.4], [N, "Rock_Medium_2", 12, 0.6, 1.4]]],
	}
	for region: String in plan:
		var spec: Array = plan[region]
		var center: Vector2 = spec[0]
		var half: Vector2 = spec[1]
		var items: Array = (spec[2] as Array).duplicate()
		for pb: Array in pebbles:
			items.append([pb[0], pb[1], 20, pb[2], pb[3]])
		var sc := DecorScatter.new()
		sc.name = "Decor_" + region
		world.add_child(sc)
		for it: Array in items:
			var n := int(int(it[2]) * k)
			var placed := 0
			var tries := 0
			while placed < n and tries < n * 4:
				tries += 1
				var p := Vector3(center.x + drng.randf_range(-half.x, half.x), 0, center.y + drng.randf_range(-half.y, half.y))
				if p.length() < BASE_RADIUS + 5.0 or not _free_at(p, 0.5) or _near_road(p, 2.2):
					continue
				sc.add(it[0], it[1], p, drng.randf_range(it[3], it[4]), drng.randf() * TAU)
				placed += 1
		sc.commit(Settings.quality >= 2)

## Ruínas (KayKit Dungeon Pack, CC0): muros quebrados, colunas e escombros espalhados.
func _ruin_cluster(c: Vector3, rot: float) -> void:
	var D := ThirdParty.DUNGEON
	var basis := Basis(Vector3.UP, rot)
	var walls := ["wall_broken", "wall_cracked", "wall_half"]
	_place_solid(D, walls[_srng.randi() % 3], c + basis * Vector3(0, 0, -1.8), _srng.randf_range(2.2, 3.2), rot, 0.0)
	if _srng.randf() < 0.7:
		_place_solid(D, walls[_srng.randi() % 3], c + basis * Vector3(-2.1, 0, 0.2), _srng.randf_range(1.8, 2.8), rot + PI * 0.5, 0.0)
	_place_solid(D, "pillar" if _srng.randf() < 0.5 else "pillar_decorated", c + basis * Vector3(2.4, 0, -1.6), 3.2, rot, 0.0)
	_place_solid(D, "rubble_large" if _srng.randf() < 0.6 else "rubble_half", c + basis * Vector3(0.8, 0, 1.2), 0.9, _srng.randf() * TAU, 0.0)
	_reserve(c, 3.6)

func _build_ruins() -> void:
	var D := ThirdParty.DUNGEON
	if not ThirdParty.has(D, "wall_broken"):
		return
	for spec: Array in [[Vector2(80, 12), Vector2(30, 42), 4], [Vector2(-85, 15), Vector2(26, 30), 3], [Vector2(-25, -78), Vector2(80, 34), 2], [Vector2.ZERO, Vector2(100, 100), 3]]:
		for i in int(spec[2]):
			var p: Variant = _try_place_s(spec[0], spec[1], 3.8, 2.0)
			if p != null and (p as Vector3).length() > 30.0:
				_ruin_cluster(p, _srng.randf() * TAU)
	# Colunas antigas soltas na pedreira.
	for i in 6:
		var cp: Variant = _try_place_s(Vector2(-85, 15), Vector2(26, 30), 1.0)
		if cp != null:
			_place_solid(D, "column", cp, _srng.randf_range(2.2, 3.4), _srng.randf() * TAU, 1.0)
	# Acampamento na base: barris, caixas, mesa quebrada e armas.
	for item: Array in [["keg", Vector3(-8.2, 0, 1.2), 1.1], ["barrel_small_stack", Vector3(7.8, 0, 2.6), 1.2], ["crates_stacked", Vector3(-3.2, 0, -8.6), 1.4],
			["sword_shield", Vector3(3.6, 0, 8.4), 1.2], ["table_long_broken", Vector3(-4.8, 0, 7.2), 0.9], ["stool", Vector3(-3.4, 0, 8.3), 0.5], ["trunk_large_A", Vector3(8.6, 0, -3.8), 0.9]]:
		_place_solid(D, item[0], item[1], item[2], _srng.randf() * TAU, 0.6)

## Sobreviventes da base (Quaternius, CC0): ferreiro, vigias nos portões, conversa e um andarilho.
func _build_survivors() -> void:
	if CharacterModel.rigged_path("npc_peasant_m") == "":
		return
	var forge_ang := 2.0
	var r := BASE_RADIUS - 3.2
	var fc := Vector3(sin(forge_ang) * r, 0, -cos(forge_ang) * r)
	var list: Array = [
		["npc_peasant_m", Survivor.Role.WORK, fc + (Vector3.ZERO - fc).normalized() * 1.3, fc],
		["npc_ranger_m", Survivor.Role.GUARD, Vector3(2.2, 0, -BASE_RADIUS + 2.6), Vector3(2.2, 0, -40)],
		["npc_ranger_f", Survivor.Role.GUARD, Vector3(-2.2, 0, BASE_RADIUS - 2.6), Vector3(-2.2, 0, 40)],
		["npc_peasant_f", Survivor.Role.WANDER, Vector3(6.5, 0, 5.5), Vector3.ZERO],
	]
	if not Platform.low_end:
		list.append(["npc_peasant_f", Survivor.Role.TALK, Vector3(-5.6, 0, 6.6), Vector3(-4.4, 0, 8.4)])
		list.append(["npc_ranger_m", Survivor.Role.TALK, Vector3(-4.4, 0, 8.4), Vector3(-5.6, 0, 6.6)])
	var wander: Array[Vector3] = []
	for i in 6:
		var a := i * TAU / 6.0 + 0.4
		wander.append(Vector3(sin(a) * 7.6, 0, -cos(a) * 7.6))
	for it: Array in list:
		var sv := Survivor.new()
		sv.model_id = it[0]
		sv.role = it[1]
		sv.spot = it[2]
		sv.face_to = it[3]
		sv.wander_points = wander
		sv.name = "Survivor_%s_%d" % [it[0], structures_root.get_child_count()]
		structures_root.add_child(sv)
