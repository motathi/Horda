class_name Foliage
extends Node3D
## Vegetação decorativa (grama com vento e flores) em MultiMesh por blocos,
## com distância de visibilidade para manter o desempenho.

const GRASS_SHADER := preload("res://assets/effects/shaders/grass.gdshader")
const FLOWER_SHADER := preload("res://assets/effects/shaders/flower.gdshader")
const CHUNK := 24.0
const VIS_RANGE := 70.0

## is_grass(Vector3) -> bool decide onde plantar (sem estradas/pedra/props).
func build(map_half: float, density: float, is_grass: Callable, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = GRASS_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2(0.75, 0.42)
	quad.center_offset = Vector3(0, 0.21, 0)
	quad.material = grass_mat
	# Dois quads cruzados = tufo visível de qualquer ângulo.
	var tuft := _cross_mesh(quad)
	var flower_mesh := _flower_mesh()
	var flower_colors := [Color(1.0, 0.85, 0.3), Color(0.95, 0.4, 0.55), Color(0.65, 0.55, 1.0), Color(1, 1, 1)]
	var x := -map_half
	while x < map_half:
		var z := -map_half
		while z < map_half:
			var grass_t: Array[Transform3D] = []
			var flowers: Array[Transform3D] = []
			var fcolors: Array[Color] = []
			var count := int(CHUNK * CHUNK * density)
			for i in count:
				var p := Vector3(x + rng.randf() * CHUNK, 0, z + rng.randf() * CHUNK)
				if not is_grass.call(p):
					continue
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4))
				grass_t.append(Transform3D(basis, p))
				if rng.randf() < 0.06:
					var fb := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3))
					flowers.append(Transform3D(fb, p + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))))
					fcolors.append(flower_colors[rng.randi() % flower_colors.size()])
			if not grass_t.is_empty():
				_add_multimesh(tuft, grass_t, [])
			if not flowers.is_empty():
				_add_multimesh(flower_mesh, flowers, fcolors)
			z += CHUNK
		x += CHUNK

func _add_multimesh(mesh: Mesh, xforms: Array[Transform3D], colors: Array) -> void:
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
	mmi.visibility_range_end = VIS_RANGE
	mmi.visibility_range_end_margin = 10.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)

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
