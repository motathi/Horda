class_name Tutorial
extends PanelContainer
## Tutorial guiado da primeira partida solo. Mostra um passo por vez, detecta a
## conclusão pelos eventos do jogo e congela o relógio da preparação enquanto ativo.

const REWARD := {&"wood": 25, &"stone": 15, &"scrap": 8}

var hero: Hero
var step: int = 0
var _title: Label
var _text: Label
var _progress: Label
var _start_pos: Vector3
var _steps: Array[Dictionary] = []

static func should_run() -> bool:
	return not Settings.tutorial_done and not Coop.active() and not GameManager.load_from_save and TimeManager.day == 1

func _ready() -> void:
	var t := Platform.touch
	_steps = [
		{"t": "Mova o herói", "d": "Arraste o dedo no lado esquerdo da tela." if t else "Use W, A, S, D (ou clique direito no chão)."},
		{"t": "Colete madeira", "d": "Toque no botão de espadas perto de uma árvore." if t else "Fique perto de uma árvore e ataque (clique esquerdo ou Espaço)."},
		{"t": "Derrote um zumbi", "d": "Saia da base e ataque um zumbi. Fique de olho na sua vida (barra verde)."},
		{"t": "Volte para a base", "d": "Ao entrar na fortaleza, a mochila é guardada no armazém compartilhado."},
		{"t": "Construa uma defesa", "d": "Toque no botão do martelo e escolha uma barricada ou muro." if t else "Pressione G e escolha uma barricada ou muro; clique para construir."},
		{"t": "Use uma habilidade", "d": "Toque no Golpe Giratório (botão com Q) perto de zumbis." if t else "Pressione Q (Golpe Giratório) perto de zumbis."},
		{"t": "Chame a primeira horda", "d": "Toque em \"Chamar agora\" (canto superior direito) quando estiver pronto. Defenda a fortaleza!"},
	]
	add_theme_stylebox_override("panel", UIStyle.hud_panel_style(Color(0.05, 0.08, 0.12, 0.92), 10))
	custom_minimum_size = Vector2(330, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_progress = UIStyle.label("", 13, Color(0.55, 0.85, 1.0))
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_progress)
	var skip := UIStyle.button("Pular tutorial", 12)
	skip.pressed.connect(finish.bind(false))
	head.add_child(skip)
	_title = UIStyle.label("", 19, Color(0.6, 0.9, 1.0))
	col.add_child(_title)
	_text = UIStyle.label("", 14, Color.WHITE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(310, 0)
	col.add_child(_text)
	visible = false

func begin(h: Hero) -> void:
	hero = h
	_start_pos = h.global_position
	visible = true
	TimeManager.running = false  # relógio parado durante o tutorial
	EventBus.item_picked_up.connect(func(id: StringName, _n: int) -> void:
		if step == 1 and id == &"wood":
			_advance())
	EventBus.enemy_killed.connect(func(_e: Node3D, _d: EnemyDef, killer: Node) -> void:
		if step == 2 and killer == hero:
			_advance())
	EventBus.building_placed.connect(func(_b: Node3D) -> void:
		if step == 4:
			_advance())
	hero.ability_cast.connect(func(_i: int) -> void:
		if step == 5:
			_advance())
	EventBus.horde_started.connect(func(_n: int, _t: int) -> void:
		if step == 6:
			finish(true))
	_show()

func _process(_delta: float) -> void:
	if not visible or hero == null:
		return
	if step == 0 and hero.global_position.distance_to(_start_pos) > 6.0:
		_advance()
	elif step == 3 and BaseZone.hero_inside:
		_advance()

func _advance() -> void:
	step += 1
	AudioManager.play(&"objective", -2.0)
	if step == 6:
		TimeManager.running = true  # libera o relógio: a horda vem em 2 minutos (ou ao chamar)
	_show()

func _show() -> void:
	if step >= _steps.size():
		return
	_progress.text = "Tutorial — passo %d de %d" % [step + 1, _steps.size()]
	_title.text = _steps[step]["t"]
	_text.text = _steps[step]["d"]

func finish(completed: bool) -> void:
	if not visible:
		return
	visible = false
	TimeManager.running = true
	Settings.set_value("tutorial_done", true)
	if completed:
		for id: StringName in REWARD:
			ResourceManager.storage.add(id, REWARD[id])
		EventBus.banner.emit("TUTORIAL CONCLUÍDO", "Bônus no armazém: " + ResourceManager.cost_to_string(REWARD), Color(0.55, 0.85, 1.0))
	else:
		EventBus.notify("Tutorial pulado. Ele pode ser refeito em Configurações.", UIStyle.TEXT_DIM)
