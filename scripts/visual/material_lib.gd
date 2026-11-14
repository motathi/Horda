class_name MaterialLib
## Cache de materiais compartilhados (evita duplicar materiais por entidade).

const TEX := "res://assets/environment/textures/"
static var _cache: Dictionary = {}
static var _flash: StandardMaterial3D

static func textured(tex_name: String, tint: Color = Color.WHITE, uv_scale: float = 1.0, triplanar: bool = true, roughness: float = 0.85) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [tex_name, tint.to_html(), uv_scale, triplanar, roughness]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + tex_name + ".jpg") as Texture2D
	m.albedo_color = tint
	m.roughness = roughness
	m.uv1_triplanar = triplanar
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3.ONE * uv_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m

static func flat(color: Color, roughness: float = 0.8, emission: float = 0.0) -> StandardMaterial3D:
	var key := "flat|%s|%s|%s" % [color.to_html(), roughness, emission]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache[key] = m
	return m

static func unshaded(color: Color) -> StandardMaterial3D:
	var key := "unshaded|%s" % color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m

## Sobreposição branca usada no "flash" de dano.
static func flash() -> StandardMaterial3D:
	if _flash == null:
		_flash = StandardMaterial3D.new()
		_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash.albedo_color = Color(1, 1, 1, 0.65)
		_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _flash
