class_name ThirdParty
## Modelos CC0 de terceiros (assets/third_party, créditos em CREDITS.md):
## vegetação e pedras (Quaternius Stylized Nature), cemitério (KayKit Halloween Bits)
## e objetos de cenário (Quaternius Fantasy Props / Medieval Village).

const DIR := "res://assets/third_party/"
const NATURE := "quaternius_nature"
const HALLOWEEN := "kaykit_halloween"
const PROPS := "quaternius_props"
const VILLAGE := "quaternius_village"

const TREES: Array[String] = ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"]
const PINES: Array[String] = ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"]
const DEAD_TREES: Array[String] = ["DeadTree_1", "DeadTree_2", "DeadTree_3"]

static var _scenes: Dictionary = {}
static var _meshes: Dictionary = {}

static func path(pack: String, model: String) -> String:
	var p := DIR + pack + "/" + model + ".gltf"
	return p if ResourceLoader.exists(p) else DIR + pack + "/" + model + ".glb"

static func has(pack: String, model: String) -> bool:
	return ResourceLoader.exists(path(pack, model))

static func scene(pack: String, model: String) -> PackedScene:
	var key := pack + "/" + model
	if not _scenes.has(key):
		_scenes[key] = load(path(pack, model)) as PackedScene
	return _scenes[key]

## Instância do modelo. height > 0 escala para essa altura.
static func instance(pack: String, model: String, height: float = -1.0, shadows: bool = true) -> Node3D:
	var n := scene(pack, model).instantiate() as Node3D
	if height > 0.0:
		var a := aabb(pack, model)
		n.scale = Vector3.ONE * (height / maxf(0.01, a.size.y))
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

## Malha única (todas as superfícies) e transformação local, para MultiMesh.
static func mesh_data(pack: String, model: String) -> Array:
	var key := pack + "/" + model
	if _meshes.has(key):
		return _meshes[key]
	var n := scene(pack, model).instantiate() as Node3D
	var mis := n.find_children("*", "MeshInstance3D", true, false)
	var out: Array = [null, Transform3D.IDENTITY]
	if not mis.is_empty():
		var mi := mis[0] as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var node: Node = mi
		while node != n and node is Node3D:
			xf = (node as Node3D).transform * xf
			node = node.get_parent()
		out = [mi.mesh, xf]
	n.free()
	_meshes[key] = out
	return out

static func aabb(pack: String, model: String) -> AABB:
	var d := mesh_data(pack, model)
	if d[0] == null:
		return AABB(Vector3.ZERO, Vector3.ONE)
	return (d[1] as Transform3D) * (d[0] as Mesh).get_aabb()

## Objeto sólido de cenário: modelo + colisão em caixa (bloqueia herói, zumbis e a navegação).
static func solid(pack: String, model: String, height: float, shrink: float = 0.8) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var vis := instance(pack, model, height)
	body.add_child(vis)
	var a := aabb(pack, model)
	var s := vis.scale.x
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(a.size.x * s * shrink, a.size.y * s, a.size.z * s * shrink)
	col.shape = box
	col.position = a.get_center() * s
	body.add_child(col)
	return body
