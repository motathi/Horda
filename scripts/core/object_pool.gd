class_name ObjectPool
extends Node
## Pool genérico de cenas (efeitos, textos de dano, coletáveis).
## Objetos reciclados devem implementar `activate(...)` e emitir/chamar `release()`
## via `pool.release(obj)` quando terminam.

@export var scene: PackedScene
@export var prewarm: int = 16
## Alternativa a `scene`: função que cria uma nova instância.
var factory: Callable

var _free: Array[Node] = []

func _ready() -> void:
	for i in prewarm:
		_free.append(_create())

func _create() -> Node:
	var n: Node = scene.instantiate() if scene else factory.call()
	n.set_meta("pool", self)
	_set_active(n, false)
	add_child(n)
	return n

func acquire() -> Node:
	var n: Node = _free.pop_back() if not _free.is_empty() else _create()
	_set_active(n, true)
	return n

func release(n: Node) -> void:
	if not is_instance_valid(n) or _free.has(n):
		return
	_set_active(n, false)
	_free.append(n)

func _set_active(n: Node, on: bool) -> void:
	n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if n is Node3D:
		(n as Node3D).visible = on
	elif n is CanvasItem:
		(n as CanvasItem).visible = on
