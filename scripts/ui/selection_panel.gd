class_name SelectionPanel
extends PanelContainer
## Informações do objeto selecionado (inimigo, construção, recurso, saqueável).

var _target: Node = null
var _portrait: TextureRect
var _name: Label
var _info: Label
var _hp: ProgressBar
var _hp_label: Label
var _actions: HBoxContainer
var _upgrade_btn: Button
var _demolish_btn: Button
var _sig: String = ""

func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	custom_minimum_size = Vector2(330, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_portrait = UIStyle.icon(null, 72)
	row.add_child(_portrait)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	_name = UIStyle.label("", 18, UIStyle.GOLD)
	col.add_child(_name)
	var st := Control.new()
	st.custom_minimum_size = Vector2(0, 16)
	_hp = UIStyle.bar(UIStyle.RED, 16)
	_hp.set_anchors_preset(Control.PRESET_FULL_RECT)
	st.add_child(_hp)
	_hp_label = UIStyle.label("", 12)
	_hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_child(_hp_label)
	col.add_child(st)
	_info = UIStyle.label("", 13, UIStyle.TEXT_DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(220, 0)
	col.add_child(_info)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	_upgrade_btn = UIStyle.button("Melhorar", 15)
	_upgrade_btn.icon = UIStyle.hud_icon("upgrade")
	_upgrade_btn.expand_icon = true
	_upgrade_btn.custom_minimum_size = Vector2(0, 40)
	_upgrade_btn.pressed.connect(_on_upgrade)
	_actions.add_child(_upgrade_btn)
	_demolish_btn = UIStyle.button("Demolir", 15)
	_demolish_btn.icon = UIStyle.hud_icon("demolish")
	_demolish_btn.expand_icon = true
	_demolish_btn.custom_minimum_size = Vector2(0, 40)
	_demolish_btn.pressed.connect(_on_demolish)
	_actions.add_child(_demolish_btn)
	col.add_child(_actions)
	_actions.visible = false
	visible = false
	EventBus.object_selected.connect(select)

func select(n: Node) -> void:
	_target = n
	visible = true
	_refresh()

func _process(_delta: float) -> void:
	if visible:
		_refresh()

func _refresh() -> void:
	if _target == null or not is_instance_valid(_target):
		visible = false
		return
	var health: HealthComponent = null
	if _target is Enemy:
		var e := _target as Enemy
		if e.is_dead():
			visible = false
			return
		_portrait.texture = e.def.portrait
		_name.text = e.display_name()
		health = e.health
		_info.text = "%s\nDano %d  •  Armadura %d  •  Vel. %.1f" % [e.def.description, int(e.damage_value), int(e.health.armor), e.def.move_speed]
	elif _target is Building:
		var b := _target as Building
		_portrait.texture = b.def.icon()
		_name.text = b.display_name()
		health = b.health
		var extra := "Destruída — repare no menu da base." if b.is_dead() else b.def.stats_text(b.level)
		_info.text = extra
		_update_actions(b)
	elif _target is Structure:
		var s := _target as Structure
		_portrait.texture = load("res://assets/ui/icons/base_core.jpg")
		_name.text = s.display_name()
		health = s.health
		_info.text = "Destruída — repare no menu da base (B)." if s.is_dead() else ("Coração da base. Se cair, o jogo termina." if s.kind == Structure.Kind.CORE else "Bloqueia zumbis. Repare com Madeira (B).")
	elif _target is Harvestable:
		var h := _target as Harvestable
		_portrait.texture = ResourceManager.get_def(h.item_id).icon
		_name.text = h.display_name()
		_info.text = h.info_text()
	elif _target is Lootable:
		var l := _target as Lootable
		_portrait.texture = load("res://assets/ui/icons/res_scrap.jpg")
		_name.text = l.display_name()
		_info.text = l.info_text()
	else:
		visible = false
		return
	if not (_target is Building):
		_actions.visible = false
	_hp.get_parent().visible = health != null
	if health:
		_hp.max_value = health.max_health
		_hp.value = health.current
		_hp_label.text = "%d / %d" % [int(health.current), int(health.max_health)]

func _update_actions(b: Building) -> void:
	_actions.visible = true
	var sig := "%d|%s|%d" % [b.level, b.is_dead(), ResourceManager.storage.to_dict().hash() + ResourceManager.hero_inventory.to_dict().hash()]
	if sig == _sig:
		return
	_sig = sig
	if b.can_upgrade():
		var cost := b.next_upgrade_cost()
		_upgrade_btn.text = "Melhorar: " + ResourceManager.cost_to_string(cost)
		_upgrade_btn.disabled = not ResourceManager.can_afford(cost)
	else:
		_upgrade_btn.text = "Nível máximo" if b.level >= b.def.max_level else "Repare antes"
		_upgrade_btn.disabled = true
	_demolish_btn.text = "Demolir (devolve %d%%)" % int(b.def.refund * 100)

func _on_upgrade() -> void:
	if _target is Building:
		EventBus.notify((_target as Building).upgrade(), UIStyle.GOLD)
		_sig = ""

func _on_demolish() -> void:
	if _target is Building:
		var back := (_target as Building).demolish()
		EventBus.notify("Pedido de demolição enviado ao anfitrião." if Coop.is_client() else "Demolido. Devolvido ao armazém: " + (ResourceManager.cost_to_string(back) if not back.is_empty() else "nada"), UIStyle.TEXT)
		_target = null
		visible = false
