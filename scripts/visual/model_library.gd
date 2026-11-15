class_name ModelLibrary
## Modelos 3D gerados (malha otimizada + textura) em res://assets/models/.
## As malhas estão normalizadas: base em y=0, centradas em XZ, frente para +Z.
## Use `instance_*` para criar MeshInstance3D já escalada e virada para -Z.

const DIR := "res://assets/models/"
static var _meshes: Dictionary = {}
static var _mats: Dictionary = {}

static func has(model_name: String) -> bool:
	return ResourceLoader.exists(DIR + model_name + ".res")

static func mesh(model_name: String) -> ArrayMesh:
	if not _meshes.has(model_name):
		_meshes[model_name] = load(DIR + model_name + ".res") as ArrayMesh
	return _meshes[model_name]

static func material(model_name: String, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var key := model_name + "|" + tint.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(DIR + "textures/" + model_name + ".jpg") as Texture2D
		m.albedo_color = tint
		m.roughness = 0.85
		m.metallic = 0.0
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_mats[key] = m
	return _mats[key]

static func size_of(model_name: String) -> Vector3:
	return mesh(model_name).get_aabb().size

## Escala uniforme para a altura desejada.
static func instance_height(model_name: String, height: float, tint: Color = Color.WHITE) -> MeshInstance3D:
	return _make(model_name, height / maxf(0.001, size_of(model_name).y), tint)

## Escala uniforme para a largura (eixo X) desejada.
static func instance_width(model_name: String, width: float, tint: Color = Color.WHITE) -> MeshInstance3D:
	return _make(model_name, width / maxf(0.001, size_of(model_name).x), tint)

## Escala uniforme para que o maior lado horizontal tenha `size`.
static func instance_footprint(model_name: String, size: float, tint: Color = Color.WHITE) -> MeshInstance3D:
	var s := size_of(model_name)
	return _make(model_name, size / maxf(0.001, maxf(s.x, s.z)), tint)

static func _make(model_name: String, s: float, tint: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(model_name)
	mi.material_override = material(model_name, tint)
	mi.scale = Vector3.ONE * s
	mi.rotation.y = PI  # modelos olham para +Z; o jogo usa -Z como frente
	return mi
