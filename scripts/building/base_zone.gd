class_name BaseZone
extends Area3D
## Área interna da base. Ao entrar, o herói deposita automaticamente a mochila
## no armazém. Também define onde serviços da base (reparo, fabricação) funcionam.

static var hero_inside: bool = false

@export var radius: float = 15.0

func _ready() -> void:
	hero_inside = false
	collision_layer = 0
	collision_mask = Layers.HERO
	monitoring = true
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = 6.0
	cs.shape = sh
	cs.position.y = 3.0
	add_child(cs)
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)

func _on_enter(b: Node3D) -> void:
	if b is Hero:
		hero_inside = true
		_deposit()

func _on_exit(b: Node3D) -> void:
	if b is Hero:
		hero_inside = false

func _deposit() -> void:
	var summary := ResourceManager.deposit_all()
	if summary.is_empty():
		return
	var parts: PackedStringArray = []
	for id: StringName in summary:
		parts.append("%d %s" % [summary[id], ResourceManager.item_name(id)])
	EventBus.notify("Depositado no armazém: " + ", ".join(parts), Color(0.6, 1.0, 0.6))
	AudioManager.play(&"deposit")

func _physics_process(_delta: float) -> void:
	# Itens coletados enquanto já está dentro da base também são guardados.
	if hero_inside and ResourceManager.has_depositable():
		_deposit()
