class_name DecorScatter
extends Node3D
## Vegetação e detalhes sem colisão (arbustos, samambaias, flores, cogumelos, pedrinhas,
## ossos) desenhados com MultiMeshInstance3D: um draw call por tipo, barato no celular.

var _buckets: Dictionary = {}  # "pack/model" -> Array[Transform3D]

## Agenda uma cópia do modelo na posição (escala relativa à altura nativa do modelo).
func add(pack: String, model: String, pos: Vector3, height: float, yaw: float) -> void:
	if not ThirdParty.has(pack, model):
		return
	var key := pack + "/" + model
	if not _buckets.has(key):
		_buckets[key] = []
	var a := ThirdParty.aabb(pack, model)
	var s := height / maxf(0.01, a.size.y)
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos)
	(_buckets[key] as Array).append(xf)

## Cria as MultiMeshInstance3D (chamar uma vez depois de todos os add).
func commit(shadows: bool) -> void:
	for key: String in _buckets:
		var parts := key.split("/")
		var d := ThirdParty.mesh_data(parts[0], parts[1])
		if d[0] == null:
			continue
		var local := d[1] as Transform3D
		var list: Array = _buckets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = d[0]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, (list[i] as Transform3D) * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = parts[1]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	_buckets.clear()

func count() -> int:
	var n := 0
	for c in get_children():
		n += (c as MultiMeshInstance3D).multimesh.instance_count
	return n
