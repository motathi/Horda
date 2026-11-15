extends Node3D
## Prancha de pré-visualização de modelos externos (glTF/GLB) em grade.
##   xvfb-run godot res://tests/asset_preview.tscn -- saida.png colunas arq1.gltf arq2.glb ...

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var cols := int(args[1])
	var files := args.slice(2)
	var rows := ceili(float(files.size()) / cols)
	get_window().size = Vector2i(cols * 220, rows * 240)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.36, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows * 2.4
	cam.position = Vector3((cols - 1) * 1.1, 10, (rows - 1) * 1.2 + 10)
	add_child(cam)
	cam.look_at(Vector3((cols - 1) * 1.1, 0, (rows - 1) * 1.2))
	for i in files.size():
		var ps := load(files[i]) as PackedScene
		var node: Node3D = ps.instantiate() as Node3D if ps else null
		if node == null:
			continue
		var holder := Node3D.new()
		add_child(holder)
		holder.add_child(node)
		await get_tree().process_frame
		var aabb := _aabb(node)
		aabb.position -= holder.global_position
		var s := 1.7 / maxf(0.01, maxf(aabb.size.y, maxf(aabb.size.x, aabb.size.z)))
		node.scale = Vector3.ONE * s
		node.position = -aabb.get_center() * s + Vector3(0, aabb.size.y * 0.5 * s, 0)
		holder.position = Vector3((i % cols) * 2.2, 0, (i / cols) * 2.4)
		holder.rotation_degrees.y = 30
		var lbl := Label3D.new()
		lbl.text = files[i].get_file().get_basename().left(18)
		lbl.font_size = 40
		lbl.pixel_size = 0.004
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0, -0.15, 0.9)
		holder.add_child(lbl)
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()

func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.get_aabb() if mi.is_inside_tree() else mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
