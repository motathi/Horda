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
	_points = UIStyle.label("", 18, UIStyle.GOLD)
	col.add_child(_points)
	for id in AttributeConfig.IDS:
		col.add_child(_make_row(id))
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
	visibility_changed.connect(func() -> void: _feedback.text = "")

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
	_title.text = "Personagem — Nível %d" % hero.level
	_points.text = "Pontos disponíveis: %d" % hero.attr_points if hero.attr_points > 0 else "Sem pontos livres — ganhe %d a cada nível (XP %d / %d)" % [hero.attr_cfg.points_per_level, hero.xp, hero.xp_to_next()]
	_points.add_theme_color_override("font_color", UIStyle.GOLD if hero.attr_points > 0 else UIStyle.TEXT_DIM)
	for id: StringName in _rows:
		var r: Dictionary = _rows[id]
		(r["value"] as Label).text = str(hero.attr(id))
		(r["plus"] as Button).disabled = hero.attr_points <= 0
		(r["desc"] as Label).text = "Por ponto: " + hero.attr_cfg.per_point_text(id)
	var h := hero.health
	_stats.text = "Vida  %d  (+%.1f/s)\nEnergia  %d  (+%.1f/s)\nDano  %d\nCarga  %d" % [
		int(h.max_health), h.regen_per_second, int(hero.max_energy), hero.energy_regen, int(hero.damage()), hero.carry_capacity()]
	_stats2.text = "Ataques/s  %.2f   •  Crítico  %d%%\nMovimento  %.1f m/s\nHabilidades  %d%% poder  •  -%d%% recarga\nConstruções  +%d%% vida  •  +%d%% dano" % [
		hero.attack_speed(), roundi(hero.crit() * 100), hero.current_move_speed(),
		roundi(hero.ability_power() * 100), roundi((1.0 - hero.cooldown_mult()) * 100),
		roundi((hero.building_hp_mult() - 1.0) * 100), roundi((hero.building_damage_mult() - 1.0) * 100)]
	var spent := hero.spent_points()
	_respec.disabled = spent == 0
	_respec.text = "Redistribuir (%s)" % ResourceManager.cost_to_string(hero.respec_cost()) if spent > 0 else "Redistribuir"
