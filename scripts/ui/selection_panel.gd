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
var _extra: HFlowContainer
var _extra_sig: String = ""

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
	var head := HBoxContainer.new()
	col.add_child(head)
	_name = UIStyle.label("", 18, UIStyle.GOLD)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_name)
	# Fechar (no celular não há "clicar fora" com o mouse).
	var close := UIStyle.button("×", 18)
	close.custom_minimum_size = Vector2(34, 30)
	close.pressed.connect(func() -> void: select(null))
	head.add_child(close)
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
	# Ações extras (reparar, recrutar no Quartel, escolher especialização da torre): refeitas quando mudam.
	_extra = HFlowContainer.new()
	_extra.add_theme_constant_override("h_separation", 6)
	_extra.add_theme_constant_override("v_separation", 6)
	col.add_child(_extra)
	visible = false
	EventBus.object_selected.connect(select)

## Distância do herói a partir da qual o card fecha sozinho (construções, recursos, saqueáveis).
const AUTO_CLOSE_DISTANCE := 28.0

func select(n: Node) -> void:
	_target = n
	_sig = ""
	visible = n != null
	if n != null:
		_refresh()

func _process(_delta: float) -> void:
	if visible:
		_refresh()

func _refresh() -> void:
	if _target == null or not is_instance_valid(_target):
		visible = false
		return
	var hero := GameManager.hero
	if hero and _target is Node3D and not (_target is Enemy) and (_target as Node3D).global_position.distance_to(hero.global_position) > AUTO_CLOSE_DISTANCE:
		select(null)
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
		var extra := "Destruída — repare para voltar a funcionar." if b.is_dead() else (b.info_text() if b.has_paths() else b.def.stats_text(b.level))
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
	_update_extra()
	_hp.get_parent().visible = health != null
	if health:
		_hp.max_value = health.max_health
		_hp.value = health.current
		_hp_label.text = "%d / %d" % [int(health.current), int(health.max_health)]

func _update_actions(b: Building) -> void:
	_actions.visible = true
	var sig := "%d|%s|%s|%d|%d" % [b.level, b.branch, b.is_dead(), TimeManager.wave(), ResourceManager.storage.to_dict().hash() + ResourceManager.hero_inventory.to_dict().hash()]
	if sig == _sig:
		return
	_sig = sig
	_upgrade_btn.visible = not b.needs_branch()
	if b.can_upgrade():
		var cost := b.next_upgrade_cost()
		var nxt := TowerPaths.tier(b.def.id, b.branch, b.level + 1)
		_upgrade_btn.text = ("%s: " % nxt["name"] if not nxt.is_empty() else "Melhorar: ") + ResourceManager.cost_to_string(cost)
		_upgrade_btn.tooltip_text = String(nxt.get("desc", ""))
		_upgrade_btn.disabled = not ResourceManager.can_afford(cost)
	elif b.has_paths() and b.level == 4 and not b.is_dead():
		_upgrade_btn.text = "Nível 5 na horda %d" % TowerPaths.unlock_wave(5)
		_upgrade_btn.disabled = true
	else:
		_upgrade_btn.text = "Nível máximo" if b.level >= b.max_level() else "Repare antes"
		_upgrade_btn.disabled = true
	_demolish_btn.text = "Demolir (devolve %d%%)" % int(b.def.refund * 100)

func _update_extra() -> void:
	var st := _target as Structure
	var army: Army = GameManager.world.get(&"army") if GameManager.world else null
	var barracks := _target is Building and (_target as Building).def.category == BuildingDef.Category.BARRACKS
	var sig := ""
	if st:
		sig = "%s|%d|%d|%s" % [st.name, int(st.missing_health() / 5.0), int(st.health.dead), ResourceManager.storage.to_dict().hash() + ResourceManager.hero_inventory.to_dict().hash()]
		if barracks and army:
			sig += "|%d|%d|%d" % [army.alive_count(), army.queue.size(), TimeManager.wave()]
		if _target is Building:
			sig += "|%d%s" % [(_target as Building).level, (_target as Building).branch]
	if sig == _extra_sig:
		return
	_extra_sig = sig
	for c in _extra.get_children():
		c.queue_free()
	if st == null:
		_extra.visible = false
		return
	var cost := st.repair_cost()
	if not cost.is_empty():
		var rb := UIStyle.button("Reparar: " + ResourceManager.cost_to_string(cost), 14)
		rb.icon = UIStyle.hud_icon("upgrade")
		rb.expand_icon = true
		rb.custom_minimum_size = Vector2(0, 40)
		rb.pressed.connect(func() -> void:
			EventBus.notify(st.repair_with_materials(), UIStyle.GOLD)
			_extra_sig = "")
		_extra.add_child(rb)
	if _target is Building:
		_add_branch_buttons(_target as Building)
	if barracks and army:
		for d in army.defs:
			var why := army.block_reason(d)
			if why != "" and not why.begins_with("Faltam") and not why.begins_with("Exército"):
				continue  # ainda bloqueado pela horda: não polui o card
			var b := UIStyle.button("Recrutar %s: %s" % [d.display_name, ResourceManager.cost_to_string(d.cost)], 13)
			b.custom_minimum_size = Vector2(0, 38)
			b.disabled = why != ""
			b.tooltip_text = why if why != "" else d.description
			b.pressed.connect(func() -> void:
				EventBus.notify(army.recruit(d), Color(0.55, 0.85, 1.0))
				_extra_sig = "")
			_extra.add_child(b)
		var left := army.auto_seconds_left()
		if left >= 0.0:
			_extra.add_child(UIStyle.label("Guarda grátis em %ds" % ceili(left), 12, Color(0.6, 0.85, 1.0)))
	_extra.visible = _extra.get_child_count() > 0

## Torre no nível 3: escolha da especialização (preenchido pelas trilhas de evolução).
func _add_branch_buttons(b: Building) -> void:
	if not b.needs_branch():
		return
	var why := b.branch_block_reason()
	var cost := TowerPaths.cost(b.def, 4)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UIStyle.label("Escolha a especialização (%s):" % ResourceManager.cost_to_string(cost), 13, UIStyle.GOLD))
	for br: String in ["a", "b"]:
		var data := TowerPaths.branch(b.def.id, br)
		var t4 := TowerPaths.tier(b.def.id, br, 4)
		var row := VBoxContainer.new()
		var bt := UIStyle.button("%s %s" % ["⚔" if br == "a" else "✦", data["name"]], 15)
		bt.custom_minimum_size = Vector2(300, 40)
		bt.disabled = why != ""
		bt.tooltip_text = t4["desc"]
		bt.pressed.connect(func() -> void:
			EventBus.notify(b.choose_branch(br), UIStyle.GOLD)
			_sig = ""
			_extra_sig = "")
		row.add_child(bt)
		var d := UIStyle.label("%s • depois: %s" % [data["short"], TowerPaths.tier(b.def.id, br, 5)["name"]], 12, UIStyle.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(300, 0)
		row.add_child(d)
		box.add_child(row)
	if why != "":
		box.add_child(UIStyle.label(why, 12, UIStyle.RED))
	_extra.add_child(box)

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
