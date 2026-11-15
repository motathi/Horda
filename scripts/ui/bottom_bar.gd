class_name BottomBar
extends PanelContainer
## HUD inferior: retrato do herói, vida, ataque, consumíveis e mochila.

var _hero: Hero
var _hp_bar: ProgressBar
var _hp_label: Label
var _stats: Label
var _bag_bar: ProgressBar
var _bag_label: Label
var _attack_cd: ProgressBar
var _slot_counts: Dictionary = {}
var _slot_nodes: Array[Control] = []
var _portrait: TextureRect
var _mid: VBoxContainer
var _name_label: Label

func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	var portrait_frame := PanelContainer.new()
	portrait_frame.add_theme_stylebox_override("panel", UIStyle.panel_style(Color.BLACK, UIStyle.GOLD, 2, 2))
	_portrait = UIStyle.icon(load("res://assets/characters/portrait_hero.jpg"), 96)
	portrait_frame.add_child(_portrait)
	row.add_child(portrait_frame)
	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(320, 0)
	_mid = mid
	mid.add_theme_constant_override("separation", 4)
	row.add_child(mid)
	_name_label = UIStyle.label("Sobrevivente", 20, UIStyle.GOLD)
	mid.add_child(_name_label)
	var hp_stack := Control.new()
	hp_stack.custom_minimum_size = Vector2(0, 22)
	_hp_bar = UIStyle.bar(Color(0.2, 0.75, 0.22), 22)
	_hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_stack.add_child(_hp_bar)
	_hp_label = UIStyle.label("", 15)
	_hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_stack.add_child(_hp_label)
	mid.add_child(hp_stack)
	_stats = UIStyle.label("", 14, UIStyle.TEXT_DIM)
	mid.add_child(_stats)
	var bag_row := HBoxContainer.new()
	bag_row.add_child(UIStyle.label("Mochila", 14, UIStyle.TEXT_DIM))
	_bag_bar = UIStyle.bar(UIStyle.BRONZE, 12)
	_bag_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bag_row.add_child(_bag_bar)
	_bag_label = UIStyle.label("", 14)
	bag_row.add_child(_bag_label)
	mid.add_child(bag_row)
	var sep := VSeparator.new()
	row.add_child(sep)
	_slot_nodes.append(sep)
	# Ataque básico (clique esquerdo) com indicador de recarga
	for c: Control in [_ability_slot(load("res://assets/ui/icons/ability_attack.jpg"), "LMB", "Ataque em arco\nClique esquerdo / Espaço: golpeia na direção do cursor.\nTambém coleta madeira e pedra."),
			_consumable_slot(&"meat", "1"), _consumable_slot(&"bandage", "2")]:
		row.add_child(c)
		_slot_nodes.append(c)

## Celular: esconde os atalhos (viram botões de toque) e reduz o painel.
func set_compact() -> void:
	for n in _slot_nodes:
		n.visible = false
	_stats.visible = false
	_portrait.custom_minimum_size = Vector2(60, 60)
	_mid.custom_minimum_size = Vector2(220, 0)
	_name_label.add_theme_font_size_override("font_size", 16)

func bind(h: Hero) -> void:
	_hero = h
	h.attack_cooldown_changed.connect(func(r: float) -> void: _attack_cd.value = r * 100.0)

func _ability_slot(tex: Texture2D, key: String, tip: String) -> Control:
	var box := VBoxContainer.new()
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UIStyle.panel_style(Color.BLACK, UIStyle.BRONZE, 2, 2))
	frame.tooltip_text = tip
	var st := Control.new()
	st.custom_minimum_size = Vector2(64, 64)
	frame.add_child(st)
	var ic := UIStyle.icon(tex, 64)
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	st.add_child(ic)
	_attack_cd = ProgressBar.new()
	_attack_cd.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	_attack_cd.show_percentage = false
	_attack_cd.set_anchors_preset(Control.PRESET_FULL_RECT)
	_attack_cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0, 0, 0, 0.6)
	_attack_cd.add_theme_stylebox_override("fill", fill)
	_attack_cd.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	st.add_child(_attack_cd)
	box.add_child(frame)
	var k := UIStyle.label(key, 13, UIStyle.TEXT_DIM)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(k)
	return box

func _consumable_slot(id: StringName, key: String) -> Control:
	var def := ResourceManager.get_def(id)
	var box := VBoxContainer.new()
	var b := Button.new()
	b.custom_minimum_size = Vector2(64, 64)
	b.icon = def.icon
	b.expand_icon = true
	b.tooltip_text = "%s [%s]\n%s" % [def.display_name, key, def.description]
	b.add_theme_stylebox_override("normal", UIStyle.panel_style(Color.BLACK, UIStyle.BRONZE, 2, 2))
	b.add_theme_stylebox_override("hover", UIStyle.panel_style(Color.BLACK, UIStyle.GOLD, 2, 2))
	b.add_theme_stylebox_override("pressed", UIStyle.panel_style(Color.BLACK, Color.WHITE, 2, 2))
	b.pressed.connect(func() -> void:
		if _hero:
			_hero.use_consumable(id))
	var cnt := UIStyle.label("0", 16, Color.WHITE)
	cnt.position = Vector2(40, 42)
	b.add_child(cnt)
	_slot_counts[id] = cnt
	box.add_child(b)
	var k := UIStyle.label(key, 13, UIStyle.TEXT_DIM)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(k)
	return box

func _process(_delta: float) -> void:
	if _hero == null:
		return
	var h := _hero.health
	_hp_bar.max_value = h.max_health
	_hp_bar.value = h.current
	_hp_label.text = "%d / %d" % [int(h.current), int(h.max_health)]
	_stats.text = "Dano %d  •  Armadura %d  •  Crítico %d%%  •  Arma nv. %d" % [int(_hero.damage()), int(h.armor), int(_hero.crit_chance * 100), _hero.weapon_level]
	var inv := ResourceManager.hero_inventory
	_bag_bar.max_value = inv.capacity
	_bag_bar.value = inv.used_weight()
	_bag_label.text = "%d/%d" % [inv.used_weight(), inv.capacity]
	for id: StringName in _slot_counts:
		var n := inv.count(id) + (ResourceManager.storage.count(id) if BaseZone.hero_inside else 0)
		(_slot_counts[id] as Label).text = str(n)
