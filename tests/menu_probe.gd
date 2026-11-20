extends Node
## Captura a tela inicial: entrada, menu, submenus (novo jogo, configurações, coop).
## xvfb-run ... res://tests/menu_probe.tscn -- <pasta>

func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var menu := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	if OS.get_environment("MENU_FRAMES") != "":
		# Sequência de quadros da entrada (para montar um GIF).
		for i in 64:
			await _wait(0.1)
			await _shot(out, "f_%03d" % i)
		get_tree().quit()
		return
	for t: float in [1.1, 3.5]:
		await _wait(t if t < 2.0 else 2.4)
		await _shot(out, "menu_%.1f" % t)
	await _wait(3.0)
	await _shot(out, "menu_idle")
	for sub: String in ["new", "settings", "coop"]:
		menu.call("_go", sub)
		await _wait(2.6)
		await _shot(out, "menu_" + sub)
	get_tree().quit()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(out: String, n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
	print("captura: ", n)
