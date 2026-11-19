class_name Foliage
extends Node3D
## Vegetação decorativa (grama com vento e flores) em MultiMesh por blocos,
## com distância de visibilidade para manter o desempenho.

const GRASS_SHADER := preload("res://assets/effects/shaders/grass.gdshader")
const FLOWER_SHADER := preload("res://assets/effects/shaders/flower.gdshader")
const GRASS_MESH_SHADER := preload("res://assets/effects/shaders/grass_mesh.gdshader")
## Touceiras de capim modeladas no Blender (tools/blender_ground.py); se faltar, usa o tufo de shader.
const TUFTS_GLB := "res://assets/models/blender/grass_tufts.glb"
const CHUNK := 24.0
const VIS_RANGE := 70.0
const GRASS_VIS := 48.0

## is_grass(Vector3) -> bool decide onde plantar (sem estradas/pedra/props).
func build(map_half: float, density: float, is_grass: Callable, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = GRASS_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.5)
	quad.center_offset = Vector3(0, 0.25, 0)
	quad.material = grass_mat
	# Um quad por tufo: o shader o vira para a câmera (billboard no eixo Y).
	var tuft := _single_mesh(quad)
	var tufts := _blender_tufts()
	var flower_mesh := _flower_mesh()
	# Poucas flores, murchas e desbotadas.
	var flower_colors := [Color(0.62, 0.55, 0.36), Color(0.55, 0.38, 0.36), Color(0.6, 0.58, 0.52)]
	var x := -map_half
	while x < map_half:
		var z := -map_half
		while z < map_half:
			var grass_t: Array[Transform3D] = []
			var by_variant: Array = [[], [], []]
			var flowers: Array[Transform3D] = []
			var fcolors: Array[Color] = []
			# As touceiras do Blender são mais cheias que o tufo antigo: um pouco mais delas.
			var count := int(CHUNK * CHUNK * density * (1.5 if not tufts.is_empty() else 1.0))
			for i in count:
				var p := Vector3(x + rng.randf() * CHUNK, 0, z + rng.randf() * CHUNK)
				if not is_grass.call(p):
					continue
				if not tufts.is_empty():
					var bs := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.2, 1.9))
					# Mais touceiras médias, algumas altas e algumas baixas/mortas.
					var r := rng.randf()
					var vi := 0 if r < 0.55 else (1 if r < 0.75 else 2)
					(by_variant[mini(vi, tufts.size() - 1)] as Array).append(Transform3D(bs, p))
				else:
					var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4))
					grass_t.append(Transform3D(basis, p))
				if rng.randf() < 0.015:
					var fb := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3))
					flowers.append(Transform3D(fb, p + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))))
					fcolors.append(flower_colors[rng.randi() % flower_colors.size()])
			if not grass_t.is_empty():
				_add_multimesh(tuft, grass_t, [])
			for vi in tufts.size():
				var arr: Array[Transform3D] = []
				arr.assign(by_variant[vi])
				if not arr.is_empty():
					# Capim só perto da câmera (ela mostra ~20 m em volta do herói): bem mais leve.
					_add_multimesh(tufts[vi], arr, [], GRASS_VIS)
			if not flowers.is_empty():
				_add_multimesh(flower_mesh, flowers, fcolors)
			z += CHUNK
		x += CHUNK

func _add_multimesh(mesh: Mesh, xforms: Array[Transform3D], colors: Array, vis: float = VIS_RANGE) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = vis * (0.8 if Platform.low_end else 1.0)
	mmi.visibility_range_end_margin = 10.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)

## Malhas das touceiras (tuft_a/b/c) com o material de vento; vazio se o GLB não existir.
func _blender_tufts() -> Array[Mesh]:
	var out: Array[Mesh] = []
	if not ResourceLoader.exists(TUFTS_GLB):
		return out
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_MESH_SHADER
	var scene := (load(TUFTS_GLB) as PackedScene).instantiate()
	for name in ["tuft_a", "tuft_b", "tuft_c"]:
		var mi := scene.find_child(name, true, false) as MeshInstance3D
		if mi == null:
			continue
		var m := (mi.mesh as Mesh).duplicate() as Mesh
		m.surface_set_material(0, mat)
		out.append(m)
	scene.free()
	return out

func _single_mesh(quad: QuadMesh) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(quad, 0, Transform3D.IDENTITY)
	var m := st.commit()
	m.surface_set_material(0, quad.material)
	m.custom_aabb = AABB(Vector3(-0.6, 0, -0.6), Vector3(1.2, 0.8, 1.2))
	return m

func _cross_mesh(quad: QuadMesh) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in [0.0, PI * 0.5]:
		st.append_from(quad, 0, Transform3D(Basis(Vector3.UP, r), Vector3.ZERO))
	var m := st.commit()
	m.surface_set_material(0, quad.material)
	return m

func _flower_mesh() -> ArrayMesh:
	var mat := ShaderMaterial.new()
	mat.shader = FLOWER_SHADER
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var head := SphereMesh.new()
	head.radius = 0.07
	head.height = 0.1
	head.radial_segments = 6
	head.rings = 3
	var stem := CylinderMesh.new()
	stem.top_radius = 0.01
	stem.bottom_radius = 0.015
	stem.height = 0.35
	stem.radial_segments = 4
	st.append_from(stem, 0, Transform3D(Basis(), Vector3(0, 0.175, 0)))
	st.append_from(head, 0, Transform3D(Basis(), Vector3(0, 0.37, 0)))
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m
