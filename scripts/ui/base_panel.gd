class_name BasePanel
extends PanelContainer
## Menu da base (B): reparos, melhoria da arma e fabricação.

var services: BaseServices
var hero: Hero
var _rows: VBoxContainer
var _status: Label
var _where: Label
var _t: float = 0.0
var _signature: String = ""

func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style(UIStyle.BG, UIStyle.GOLD))
	custom_minimum_size = Vector2(520, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UIStyle.label("Base — Oficina e Reparos", 24, UIStyle.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UIStyle.button("X", 16)
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)
	_where = UIStyle.label("", 14)
	col.add_child(_where)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	col.add_child(_rows)
	_status = UIStyle.label("", 15, UIStyle.GOLD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	visible = false
	visibility_changed.connect(_rebuild)

func _process(delta: float) -> void:
	if not visible:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		# Só reconstrói quando algo relevante mudou (evita "perder" cliques).
		var sig := _make_signature()
		if sig != _signature:
			_rebuild()

func _make_signature() -> String:
	if services == null or hero == null:
		return ""
	return "%s|%d|%d|%d|%s|%s" % [BaseZone.hero_inside, int(services.walls_missing_hp()), int(services.core_missing_hp()),
		hero.weapon_level, ResourceManager.storage.to_dict(), ResourceManager.hero_inventory.to_dict()]

func _rebuild() -> void:
	if not visible or services == null or hero == null:
		return
	_signature = _make_signature()
	_where.text = "Você está na base." if BaseZone.hero_inside else "Você precisa estar dentro da base para usar estes serviços."
	_where.add_theme_color_override("font_color", UIStyle.GREEN if BaseZone.hero_inside else UIStyle.RED)
	for c in _rows.get_children():
		c.queue_free()
	var wall_cost := services.wall_repair_cost()
	_add_row("Reparar muros e portões", "Vida faltando: %d" % int(services.walls_missing_hp()), wall_cost,
		func() -> String: return services.repair_walls(), not wall_cost.is_empty(), true)
	var core_cost := services.core_repair_cost()
	_add_row("Reparar Núcleo", "Vida faltando: %d" % int(services.core_missing_hp()), core_cost,
		func() -> String: return services.repair_core(), not core_cost.is_empty(), true)
	var can_sharp := services.can_sharpen(hero)
	var sharp_cost := services.sharpen_cost(hero) if can_sharp else {}
	_add_row("Afiar arma (nv. %d para %d)" % [hero.weapon_level, hero.weapon_level + 1] if can_sharp else "Arma no nível máximo",
		"+%d de dano por nível" % int(Hero.SHARPEN_BONUS), sharp_cost,
		func() -> String: return services.sharpen(hero), can_sharp, false)
	for r in services.recipes:
		_add_row("Fabricar: %s" % r.display_name, r.description, r.inputs,
			func() -> String: return services.craft(r), true, false)

## partial: o serviço aceita pagamento parcial (repara o quanto der).
func _add_row(title: String, sub: String, cost: Dictionary, action: Callable, available: bool, partial: bool) -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIStyle.panel_style(UIStyle.BG_LIGHT, UIStyle.BRONZE_DARK, 1, 3))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UIStyle.label(title, 17))
	info.add_child(UIStyle.label(sub, 13, UIStyle.TEXT_DIM))
	h.add_child(info)
	var cost_box := HBoxContainer.new()
	for id: StringName in cost:
		var need := int(cost[id])
		var have := ResourceManager.available(id)
		var slot := HBoxContainer.new()
		slot.add_child(UIStyle.icon(ResourceManager.get_def(id).icon, 28))
		slot.add_child(UIStyle.label("%d/%d" % [mini(have, need), need], 14, UIStyle.GREEN if have >= need else UIStyle.RED))
		cost_box.add_child(slot)
	h.add_child(cost_box)
	var btn := UIStyle.button("Executar", 15)
	var affordable := ResourceManager.can_afford(cost) or (partial and _any(cost))
	btn.disabled = not (available and affordable and BaseZone.hero_inside)
	btn.pressed.connect(func() -> void:
		_status.text = action.call()
		_rebuild())
	h.add_child(btn)
	_rows.add_child(row)

func _any(cost: Dictionary) -> bool:
	for id: StringName in cost:
		if ResourceManager.available(id) > 0:
			return true
	return false
