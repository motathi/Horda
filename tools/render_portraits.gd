extends Node3D
## Renderiza retratos 256x256 dos heróis KayKit (assets/characters/portrait_<id>.png).
##   xvfb-run godot --rendering-method gl_compatibility res://tools/render_portraits.tscn

func _ready() -> void:
	get_window().size = Vector2i(256, 256)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.08, 0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.5, 0.6)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 35, 0)
	key.light_energy = 1.3
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_color = Color(1.0, 0.75, 0.45)
	rim.light_energy = 1.6
	add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	for sk: Dictionary in HeroSkins.LIST:
		if sk["id"] == HeroSkins.DEFAULT:
			continue
		var inst := (load(CharacterModel.rigged_path(sk["model"])) as PackedScene).instantiate() as Node3D
		add_child(inst)
		inst.rotation.y = -PI * 0.5 + deg_to_rad(25)  # frente (+X) virada para a câmera, levemente de lado
		var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		ap.play("idle")
		ap.advance(0.4)
		var aabb := AABB()
		var first := true
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			var b := mi.global_transform * mi.get_aabb()
			aabb = b if first else aabb.merge(b)
			first = false
		var h := aabb.size.y
		var target := Vector3(0, aabb.position.y + h * 0.66, 0)
		cam.position = target + Vector3(0, h * 0.06, h * 1.75)
		cam.look_at(target)
		for i in 6:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://assets/characters/portrait_%s.png" % sk["id"]))
		print("retrato ", sk["id"])
		inst.queue_free()
		await get_tree().process_frame
	get_tree().quit()
