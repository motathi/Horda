class_name SelectionPanel
extends PanelContainer
## Informações do objeto selecionado (inimigo, construção, recurso, saqueável).

var _target: Node = null
var _portrait: TextureRect
var _name: Label
var _info: Label
var _hp: ProgressBar
var _hp_label: Label

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
	_hp.get_parent().visible = health != null
	if health:
		_hp.max_value = health.max_health
		_hp.value = health.current
		_hp_label.text = "%d / %d" % [int(health.current), int(health.max_health)]
