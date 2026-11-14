class_name InventoryPanel
extends PanelContainer
## Janela de inventário (I / Tab): mochila do herói e armazém da base.

var _bag_grid: GridContainer
var _storage_grid: GridContainer
var _bag_title: Label
var _dirty: bool = true

func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style(UIStyle.BG, UIStyle.GOLD))
	custom_minimum_size = Vector2(560, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UIStyle.label("Inventário", 24, UIStyle.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UIStyle.button("X", 16)
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)
	_bag_title = UIStyle.label("Mochila", 18)
	col.add_child(_bag_title)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = 8
	col.add_child(_bag_grid)
	col.add_child(HSeparator.new())
	col.add_child(UIStyle.label("Armazém da Base", 18))
	_storage_grid = GridContainer.new()
	_storage_grid.columns = 8
	col.add_child(_storage_grid)
	var hint := UIStyle.label("Recursos da mochila são guardados automaticamente ao entrar na base.\nCarne e curativos ficam com o herói para uso em campo (teclas 1 e 2).", 13, UIStyle.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(540, 0)
	col.add_child(hint)
	visible = false
	visibility_changed.connect(func() -> void: _dirty = true)

func _process(_delta: float) -> void:
	if visible and _dirty:
		_dirty = false
		_rebuild()

func _rebuild() -> void:
	# Inventários podem ser recriados no reset; reconecta se necessário.
	if not ResourceManager.hero_inventory.changed.is_connected(_mark):
		ResourceManager.hero_inventory.changed.connect(_mark)
		ResourceManager.storage.changed.connect(_mark)
	var inv := ResourceManager.hero_inventory
	_bag_title.text = "Mochila (%d / %d de peso)" % [inv.used_weight(), inv.capacity]
	_fill(_bag_grid, inv.items())
	_fill(_storage_grid, ResourceManager.storage.items())

func _mark() -> void:
	_dirty = true

func _fill(grid: GridContainer, items: Dictionary) -> void:
	for c in grid.get_children():
		c.queue_free()
	if items.is_empty():
		grid.add_child(UIStyle.label("(vazio)", 14, UIStyle.TEXT_DIM))
		return
	var keys := items.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id: StringName in keys:
		grid.add_child(UIStyle.item_slot(id, items[id], 52))
