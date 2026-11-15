extends SceneTree
## Converte GLBs gerados por IA em malhas otimizadas para o jogo:
## decima para um orçamento de triângulos (meshoptimizer via ImporterMesh),
## gera níveis de LOD e extrai a textura para PNG.
##   godot --headless --script res://tools/bake_models.gd -- nome:entrada.glb:triangulos ...
## Saída: res://assets/models/<nome>.res (ArrayMesh) e res://assets/models/textures/<nome>.png

const OUT := "res://assets/models/"

func _init() -> void:
	for job in OS.get_cmdline_user_args():
		var parts := job.split(":")
		_bake(parts[0], parts[1], int(parts[2]))
	quit()

func _bake(name: String, src: String, tris: int) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(src, state) != OK:
		push_error("falha lendo " + src)
		return
	var gm := state.get_meshes()[0] as GLTFMesh
	var im := gm.mesh
	var mat := im.get_surface_material(0) as BaseMaterial3D
	im.generate_lods(25.0, 60.0, [])
	var arrays := im.get_surface_arrays(0)
	var full_tris := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	# Escolhe o LOD mais próximo do orçamento como malha base; os menores viram LODs.
	var base_idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var lods := {}
	var chosen := -1
	for i in im.get_surface_lod_count(0):
		var idx := im.get_surface_lod_indices(0, i)
		if chosen < 0 and idx.size() / 3 <= tris:
			chosen = i
			base_idx = idx
		elif chosen >= 0:
			lods[im.get_surface_lod_size(0, i)] = idx
	if chosen < 0 and im.get_surface_lod_count(0) > 0:
		base_idx = im.get_surface_lod_indices(0, im.get_surface_lod_count(0) - 1)
	arrays[Mesh.ARRAY_INDEX] = base_idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	ResourceSaver.save(mesh, OUT + name + ".res", ResourceSaver.FLAG_COMPRESS)
	if mat and mat.albedo_texture:
		var img := mat.albedo_texture.get_image()
		if img.is_compressed():
			img.decompress()
		if img.get_width() > 1024:
			img.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path(OUT + "textures/" + name + ".png"))
	print("%s: %d -> %d tris, %d LODs" % [name, full_tris, base_idx.size() / 3, lods.size()])
