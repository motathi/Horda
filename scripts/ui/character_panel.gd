class_name CharacterPanel
extends PanelContainer
## Janela do personagem (P ou toque no retrato): distribui pontos de atributo,
## mostra os valores finais do herói e dá acesso ao inventário.

signal inventory_requested

const ICONS := {
	&"strength": "attr_str", &"agility": "attr_agi", &"vitality": "attr_vit",
	&"intelligence": "attr_int", &"engineering": "attr_eng",
}

var hero: Hero
var _title: Label
var _points: Label
var _rows: Dictionary = {}  # id -> {value: Label, plus: Button}
var _stats: Label
var _stats2: Label
var _respec: Button
var _feedback: Label
var _attr_box: VBoxContainer
var _gear_box: VBoxContainer
var _tab: int = 0
var _tab_btns: Array[Button] = []
var _slot_btns: Array[Button] = []
var _bag_grid: GridContainer
var _detail_name: Label
var _detail_text: Label
var _btn_equip: Button
var _btn_salvage: Button
var _selected: GearItem = null
var _selected_equipped: bool = false
var _gear_dirty: bool = true

func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style(UIStyle.BG, UIStyle.GOLD))
	custom_minimum_size = Vector2(640, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_title = UIStyle.label("Personagem", 24, UIStyle.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := UIStyle.button("X", 16)
	close.custom_minimum_size = Vector2(44, 40)
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	col.add_child(tabs)
	var group := ButtonGroup.new()
	for i in 2:
		var tb := UIStyle.button(["Atributos", "Equipamento"][i], 17)
		tb.toggle_mode = true
		tb.button_group = group
		tb.button_pressed = i == 0
		tb.custom_minimum_size = Vector2(150, 40)
		tb.pressed.connect(_set_tab.bind(i))
		tabs.add_child(tb)
		_tab_btns.append(tb)
	_attr_box = VBoxContainer.new()
	_attr_box.add_theme_constant_override("separation", 6)
	col.add_child(_attr_box)
	_points = UIStyle.label("", 18, UIStyle.GOLD)
	_attr_box.add_child(_points)
	for id in AttributeConfig.IDS:
		_attr_box.add_child(_make_row(id))
	_gear_box = _build_gear_box()
	_gear_box.visible = false
	col.add_child(_gear_box)
	col.add_child(HSeparator.new())
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 24)
	col.add_child(grid)
	_stats = UIStyle.label("", 15)
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_stats)
	_stats2 = UIStyle.label("", 15)
	_stats2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_stats2)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	col.add_child(bar)
	var inv := UIStyle.button("Inventário" if Platform.touch else "Inventário (I)", 16)
	inv.custom_minimum_size = Vector2(0, 44)
	inv.pressed.connect(func() -> void: inventory_requested.emit())
	bar.add_child(inv)
	_respec = UIStyle.button("", 16)
	_respec.custom_minimum_size = Vector2(0, 44)
	_respec.pressed.connect(_on_respec)
	bar.add_child(_respec)
	_feedback = UIStyle.label("", 14, UIStyle.TEXT_DIM)
	_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_feedback)
	visible = false
	visibility_changed.connect(func() -> void:
		_feedback.text = ""
		_gear_dirty = true
		# Abre direto nos equipamentos (onde aparece o que veio dos baús), a não ser que haja pontos para gastar.
		if visible and GameManager.hero:
			_set_tab(0 if (GameManager.hero as Hero).attr_points > 0 else 1))

func _set_tab(i: int) -> void:
	_tab = i
	_tab_btns[i].set_pressed_no_signal(true)
	_attr_box.visible = i == 0
	_gear_box.visible = i == 1
	_respec.visible = i == 0
	_gear_dirty = true

func show_gear_tab() -> void:
	visible = true
	_set_tab(1)

# --- Aba Equipamento -----------------------------------------------------------

func _build_gear_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 8)
	box.add_child(slots)
	for slot in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 70)
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.expand_icon = false
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_constant_override("icon_max_width", 52)
		b.pressed.connect(func() -> void:
			if hero and hero.equipped(slot):
				_select(hero.equipped(slot), true))
		slots.add_child(b)
		_slot_btns.append(b)
	box.add_child(UIStyle.label("Bolsa de equipamentos", 15, UIStyle.TEXT_DIM))
	_bag_grid = GridContainer.new()
	_bag_grid.columns = 8
	_bag_grid.add_theme_constant_override("h_separation", 6)
	_bag_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_bag_grid)
	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", UIStyle.panel_style(UIStyle.BG_LIGHT, UIStyle.BRONZE_DARK, 1, 6))
	detail.custom_minimum_size = Vector2(0, 128)
	box.add_child(detail)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 12)
	detail.add_child(dh)
	var dv := VBoxContainer.new()
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dh.add_child(dv)
	_detail_name = UIStyle.label("Selecione um item", 18)
	dv.add_child(_detail_name)
	_detail_text = UIStyle.label("", 14, UIStyle.TEXT_DIM)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_detail_text)
	var btns := VBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	dh.add_child(btns)
	_btn_equip = UIStyle.button("Equipar", 16)
	_btn_equip.custom_minimum_size = Vector2(150, 44)
	_btn_equip.pressed.connect(_on_equip)
	btns.add_child(_btn_equip)
	_btn_salvage = UIStyle.button("Desmontar", 16)
	_btn_salvage.custom_minimum_size = Vector2(150, 44)
	_btn_salvage.pressed.connect(_on_salvage)
	btns.add_child(_btn_salvage)
	return box

func _item_style(c: Color, selected: bool) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(c.r * 0.18, c.g * 0.18, c.b * 0.18, 0.95)
	st.border_color = Color.WHITE if selected else c
	st.set_border_width_all(3 if selected else 2)
	st.set_corner_radius_all(6)
	return st

func _rebuild_gear() -> void:
	_gear_dirty = false
	for slot in 3:
		var b := _slot_btns[slot]
		var it := hero.equipped(slot)
		b.icon = it.def.icon() if it else null
		b.text = ("%s\n%s" % [it.display_name(), it.rarity_name()]) if it else "%s\n(vazio)" % EquipmentDef.slot_name(slot)
		var c := it.color() if it else Color(0.35, 0.32, 0.28)
		for st_name in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st_name, _item_style(c, it != null and it == _selected))
		b.add_theme_color_override("font_color", c if it else UIStyle.TEXT_DIM)
	for c2 in _bag_grid.get_children():
		c2.queue_free()
	for it2: GearItem in hero.gear_bag:
		var ib := Button.new()
		ib.custom_minimum_size = Vector2(62, 62)
		ib.focus_mode = Control.FOCUS_NONE
		ib.icon = it2.def.icon()
		ib.expand_icon = true
		ib.tooltip_text = "%s (%s)\n%s" % [it2.display_name(), it2.rarity_name(), it2.stats_text()]
		for st_name in ["normal", "hover", "pressed"]:
			ib.add_theme_stylebox_override(st_name, _item_style(it2.color(), it2 == _selected))
		ib.pressed.connect(_select.bind(it2, false))
		_bag_grid.add_child(ib)
	for i in range(hero.gear_bag.size(), Gear.BAG_SIZE):
		var empty := Panel.new()
		empty.custom_minimum_size = Vector2(62, 62)
		empty.add_theme_stylebox_override("panel", _item_style(Color(0.25, 0.23, 0.2), false))
		_bag_grid.add_child(empty)
	_update_detail()

func _select(it: GearItem, is_equipped: bool) -> void:
	_selected = it
	_selected_equipped = is_equipped
	_gear_dirty = true

func _update_detail() -> void:
	if _selected == null or (not hero.gear_bag.has(_selected) and not hero.equipment.values().has(_selected)):
		_selected = null
		_detail_name.text = "Selecione um item"
		_detail_name.add_theme_color_override("font_color", Color.WHITE)
		_detail_text.text = "Equipamentos caem de chefes, elites e contêineres, ou são feitos na Forja (menu da base, B)."
		_btn_equip.disabled = true
		_btn_salvage.disabled = true
		return
	var it := _selected
	_detail_name.text = "%s — %s" % [it.display_name(), it.rarity_name()]
	_detail_name.add_theme_color_override("font_color", it.color())
	var txt := "%s • nível %d\n%s" % [EquipmentDef.slot_name(it.def.slot), it.item_level, it.stats_text()]
	var cur := hero.equipped(it.def.slot)
	if not _selected_equipped and cur:
		txt += "\n[Equipado agora: %s %s]" % [cur.display_name(), cur.rarity_name()]
	_detail_text.text = txt
	_btn_equip.text = "Remover" if _selected_equipped else "Equipar"
	_btn_equip.disabled = false
	_btn_salvage.disabled = _selected_equipped
	_btn_salvage.text = "Desmontar (+%s)" % ResourceManager.cost_to_string(it.salvage_value()) if not _selected_equipped else "Desmontar"

func _on_equip() -> void:
	if _selected == null:
		return
	var msg := hero.unequip(_selected.def.slot) if _selected_equipped else hero.equip(_selected)
	_selected_equipped = not _selected_equipped and msg.begins_with("Equipado")
	_feedback.text = msg
	_feedback.add_theme_color_override("font_color", UIStyle.GOLD)
	_gear_dirty = true

func _on_salvage() -> void:
	if _selected == null or _selected_equipped:
		return
	_feedback.text = hero.salvage(_selected)
	_feedback.add_theme_color_override("font_color", UIStyle.GOLD)
	_selected = null
	_gear_dirty = true

func _make_row(id: StringName) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon := TextureRect.new()
	icon.texture = UIStyle.hud_icon(ICONS[id])
	icon.custom_minimum_size = Vector2(46, 46)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name_l := UIStyle.label(AttributeConfig.display_name(id), 18, AttributeConfig.COLORS[id])
	text.add_child(name_l)
	var desc := UIStyle.label("", 14, UIStyle.TEXT_DIM)
	desc.set_meta(&"attr", id)
	text.add_child(desc)
	var value := UIStyle.label("0", 24, Color.WHITE)
	value.custom_minimum_size = Vector2(44, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	var plus := UIStyle.button("+", 22)
	plus.custom_minimum_size = Vector2(52, 46)
	plus.tooltip_text = "Gastar 1 ponto em " + AttributeConfig.display_name(id)
	plus.pressed.connect(_on_plus.bind(id))
	row.add_child(plus)
	_rows[id] = {"value": value, "plus": plus, "desc": desc}
	return row

func _on_plus(id: StringName) -> void:
	if hero == null:
		return
	var why := hero.add_attribute(id)
	_feedback.text = why if why != "" else "+1 em %s" % AttributeConfig.display_name(id)
	_feedback.add_theme_color_override("font_color", UIStyle.RED if why != "" else UIStyle.GOLD)

func _on_respec() -> void:
	if hero == null:
		return
	var why := hero.respec()
	_feedback.text = why if why != "" else "Pontos devolvidos. Distribua novamente."
	_feedback.add_theme_color_override("font_color", UIStyle.RED if why != "" else UIStyle.GOLD)
	if why != "":
		AudioManager.play(&"ui_error", -6.0)

func _process(_delta: float) -> void:
	if not visible or hero == null:
		return
	if not hero.gear_changed.is_connected(_on_gear_changed):
		hero.gear_changed.connect(_on_gear_changed)
	if _tab == 1 and _gear_dirty:
		_rebuild_gear()
	_title.text = "Personagem — Nível %d" % hero.level
	_points.text = "Pontos disponíveis: %d" % hero.attr_points if hero.attr_points > 0 else "Sem pontos livres — ganhe %d a cada nível (XP %d / %d)" % [hero.attr_cfg.points_per_level, hero.xp, hero.xp_to_next()]
	_points.add_theme_color_override("font_color", UIStyle.GOLD if hero.attr_points > 0 else UIStyle.TEXT_DIM)
	for id: StringName in _rows:
		var r: Dictionary = _rows[id]
		(r["value"] as Label).text = str(hero.attr(id))
		(r["plus"] as Button).disabled = hero.attr_points <= 0
		(r["desc"] as Label).text = "Por ponto: " + hero.attr_cfg.per_point_text(id)
	var h := hero.health
	_stats.text = "Vida  %d  (+%.1f/s)\nEnergia  %d  (+%.1f/s)\nDano  %d  •  Armadura  %d\nCarga  %d  •  Alcance  %.1f m" % [
		int(h.max_health), h.regen_per_second, int(hero.max_energy), hero.energy_regen, int(hero.damage()), int(h.armor), hero.carry_capacity(), hero.reach()]
	_stats2.text = "Ataques/s  %.2f   •  Crítico  %d%%\nMovimento  %.1f m/s\nHabilidades  %d%% poder  •  -%d%% recarga\nConstruções  +%d%% vida  •  +%d%% dano" % [
		hero.attack_speed(), roundi(hero.crit() * 100), hero.current_move_speed(),
		roundi(hero.ability_power() * 100), roundi((1.0 - hero.cooldown_mult()) * 100),
		roundi((hero.building_hp_mult() - 1.0) * 100), roundi((hero.building_damage_mult() - 1.0) * 100)]
	var spent := hero.spent_points()
	_respec.disabled = spent == 0
	_respec.text = "Redistribuir (%s)" % ResourceManager.cost_to_string(hero.respec_cost()) if spent > 0 else "Redistribuir"

func _on_gear_changed() -> void:
	_gear_dirty = true
