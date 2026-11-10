class_name RosterPanel
extends PanelContainer
## Camp management view of real profiles. No XP, healing or death buttons.

signal call_sign_requested(member_id: int, call_sign: String)
signal equipment_requested(member_id: int)
signal growth_requested(member_id: int)
signal training_requested(member_id: int)
signal closed
signal navigation_requested(action: StringName)

var player_mode: bool = false

var member_buttons: Array[Button] = []
var buttons_by_id: Dictionary[int,Button] = {}
var death_equipment: Dictionary = {}
var name_edit: LineEdit
var save_button: Button
var equipment_button: Button
var back_button: Button
var message: Label
var selected_member_id: int = 1
var _data: Dictionary = {}
var _portrait: TextureRect
var _identity: Label
var _call_sign: Label
var _condition: Label
var _gender_title: GenderBadge
var _gender_detail: GenderBadge
var _member_genders: Array[GenderBadge] = []
var _health: ProgressBar
var _equipment: Label
var _service: Label
var growth_button: Button
var _members_list: VBoxContainer
var persona_details: PersonaDetails
var _legacy_detail: VBoxContainer
var _detail_host: ScrollContainer
var _history_link: Button
var _heading: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 48
	offset_right = -48
	offset_top = 104
	offset_bottom = -24
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("10232d")
	style.border_color = Color("34535d")
	style.set_border_width_all(1)
	for side: Side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_content_margin(side, 20)
	add_theme_stylebox_override("panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var heading: Label = Label.new()
	heading.text = "幸存者 / 同行者档案"
	heading.add_theme_font_size_override("font_size", 32)
	column.add_child(heading)
	_heading = heading
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 32)
	column.add_child(row)
	var members: VBoxContainer = VBoxContainer.new()
	members.custom_minimum_size.x = 290
	members.add_theme_constant_override("separation", 12)
	var member_scroll: ScrollContainer = ScrollContainer.new()
	member_scroll.custom_minimum_size.x = 310
	member_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	member_scroll.follow_focus = true
	row.add_child(member_scroll)
	member_scroll.add_child(members)
	_members_list = members
	growth_button = Button.new()
	growth_button.text = "成长与特性 / 行动记录 →"
	growth_button.custom_minimum_size.y = 44
	growth_button.pressed.connect(func() -> void: growth_requested.emit(selected_member_id))
	column.add_child(growth_button)
	var detail: VBoxContainer = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	var detail_scroll: ScrollContainer = ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(detail_scroll)
	_detail_host=detail_scroll
	_legacy_detail=detail
	detail_scroll.add_child(detail)
	persona_details=PersonaDetails.new()
	persona_details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	persona_details.size_flags_vertical=Control.SIZE_EXPAND_FILL
	persona_details.custom_minimum_size.y=220
	# Replace the scroll's direct child only when the explicit new mode is selected.
	persona_details.equipment_requested.connect(func(id: int) -> void: equipment_requested.emit(id))
	persona_details.training_requested.connect(func(id: int) -> void: training_requested.emit(id))
	persona_details.closed.connect(func() -> void:
		# The original leave guard owns whether camp closes; a cancelled rename
		# confirmation must leave this read-only pane visible beside the editor.
		persona_details.show()
		closed.emit()
	)
	var identity_row: HBoxContainer = HBoxContainer.new()
	detail.add_child(identity_row)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(148, 144)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	identity_row.add_child(_portrait)
	var identity_details: VBoxContainer = VBoxContainer.new()
	identity_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_details.add_theme_constant_override("separation", 5)
	identity_row.add_child(identity_details)
	var name_heading: HBoxContainer = HBoxContainer.new()
	name_heading.add_theme_constant_override("separation", 16)
	identity_details.add_child(name_heading)
	_identity = Label.new()
	_identity.add_theme_font_size_override("font_size", 24)
	name_heading.add_child(_identity)
	_gender_title = GenderBadge.new()
	name_heading.add_child(_gender_title)
	_call_sign = Label.new()
	_call_sign.add_theme_font_size_override("font_size", 20)
	identity_details.add_child(_call_sign)
	_condition = Label.new()
	_condition.add_theme_font_size_override("font_size", 18)
	identity_details.add_child(_condition)
	_health = ProgressBar.new()
	_health.max_value = 200.0
	_health.custom_minimum_size.y = 12
	_health.show_percentage = false
	_health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_child(_health)
	_equipment = Label.new()
	_equipment.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_equipment.add_theme_font_size_override("font_size", 20)
	detail.add_child(_equipment)
	_service = Label.new()
	_service.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_service.add_theme_font_size_override("font_size", 18)
	detail.add_child(_service)
	_gender_detail = GenderBadge.new()
	_gender_detail.prefix = "性别："
	detail.add_child(_gender_detail)
	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	column.add_child(name_row)
	name_edit = LineEdit.new()
	name_edit.max_length = 12
	name_edit.placeholder_text = "自定义呼号（1–12字）"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size.y = 44
	name_row.add_child(name_edit)
	save_button = Button.new()
	save_button.text = "保存呼号"
	save_button.pressed.connect(func() -> void: call_sign_requested.emit(selected_member_id, name_edit.text))
	name_row.add_child(save_button)
	equipment_button = Button.new()
	equipment_button.text = "管理该队员装备 →"
	equipment_button.pressed.connect(func() -> void: equipment_requested.emit(selected_member_id))
	name_row.add_child(equipment_button)
	_history_link=Button.new()
	_history_link.text="行动记录 →"
	_history_link.pressed.connect(func() -> void: growth_requested.emit(selected_member_id))
	name_row.add_child(_history_link)
	_history_link.hide()
	_detail_host.resized.connect(func() -> void:
		if PersonaState.enabled(_data): persona_details.custom_minimum_size.y=maxf(220.0,_detail_host.size.y)
	)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 30
	message.add_theme_font_size_override("font_size", 16)
	column.add_child(message)
	back_button = Button.new()
	back_button.text = "返回营地 / Esc"
	back_button.custom_minimum_size.y = 44
	back_button.pressed.connect(func() -> void: closed.emit())
	if player_mode:
		var footer: HBoxContainer = HBoxContainer.new()
		column.add_child(footer)
		footer.add_child(back_button)
		for action: StringName in [&"weapons", &"workshop", &"supplies", &"bus"]:
			var button: Button = Button.new()
			button.text = {&"weapons":"装备仓", &"workshop":"工坊", &"supplies":"补给", &"bus":"巴士"}[action]
			button.pressed.connect(navigation_requested.emit.bind(action))
			footer.add_child(button)
	else:
		column.add_child(back_button)
	get_viewport().size_changed.connect(_fit_viewport)


func refresh(data: Dictionary, feedback: String = "") -> void:
	_data = data.duplicate(true)
	_sync_members()
	_fit_viewport()
	var persona_mode: bool=PersonaState.enabled(_data)
	growth_button.visible=not persona_mode
	back_button.visible=player_mode or not persona_mode
	equipment_button.visible=not persona_mode
	_history_link.visible=persona_mode
	message.visible=not persona_mode or not feedback.is_empty()
	if SurvivorRoster.member(_data.crew,selected_member_id).is_empty(): selected_member_id=int(_data.crew[0].id)
	if persona_mode and persona_details.get_parent()==null:
		_detail_host.remove_child(_legacy_detail)
		_detail_host.add_child(persona_details)
	elif not persona_mode and _legacy_detail.get_parent()==null:
		_detail_host.remove_child(persona_details)
		_detail_host.add_child(_legacy_detail)
	if persona_mode:
		persona_details.present(PersonaViewModel.camp(_data, selected_member_id))
		persona_details.close_button.visible = not player_mode
		persona_details.custom_minimum_size.y = maxf(220.0, _detail_host.size.y)
	if SurvivorRoster.member(_data.crew,selected_member_id).is_empty():
		selected_member_id = int(_data.crew[0].id)
	_heading.text = "幸存者名册 · 存活%d / 历史%d" % [_data.crew.filter(func(m: Dictionary) -> bool: return m.health>0).size(),_data.crew.size()]
	for member_id: int in buttons_by_id:
		var entry: Dictionary = SurvivorRoster.member(_data.crew, member_id)
		var button: Button = buttons_by_id[member_id]
		button.visible = not entry.is_empty()
		if entry.is_empty(): continue
		var list_name: String = entry.call_sign if entry.call_sign.length() <= 5 else entry.call_sign.left(4) + "…"
		var definition: SurvivorDefinition = SurvivorRoster.definition(member_id)
		button.tooltip_text = "%s · %s\n呼号：%s" % [definition.default_display_name, definition.gender_text(), entry.call_sign]
		button.text = "%02d  %s\n%s · %.0f / %.0f" % [member_id, list_name,
			"存活" if entry.condition == "active" else ("已阵亡" if entry.condition == "dead" else "倒地"), float(entry.health),SurvivorGrowth.maximum(_data,entry)]
		if PersonaState.enabled(_data):
			var model: Dictionary=PersonaViewModel.camp(_data,member_id)
			button.text="%s\n%02d %s · HP %.0f/%.0f\n＋%s / －%s"%[model.primary,member_id,list_name,model.hp,model.max_hp,model.positive.name,model.negative.name]
			button.add_theme_font_size_override("font_size",14)
			button.custom_minimum_size.y=100
		button.add_theme_color_override("font_color", SurvivorRoster.definition(member_id).colour)
	var member: Dictionary = SurvivorRoster.member(_data.crew, selected_member_id)
	var base: SurvivorDefinition = SurvivorRoster.definition(selected_member_id)
	_portrait.texture = base.portrait
	_identity.text = base.default_display_name
	_call_sign.text = "呼号：%s" % member.call_sign
	_condition.text = "同行者 %02d · 生命 %.0f / %.0f · %s" % [selected_member_id, float(member.health),SurvivorGrowth.maximum(_data,member),
		"存活" if member.condition == "active" else ("已阵亡 · 只读历史" if member.condition == "dead" else "倒地（非永久离队）")]
	_gender_title.set_definition(base)
	_gender_detail.set_definition(base)
	_identity.add_theme_color_override("font_color", base.colour)
	_health.max_value = SurvivorGrowth.maximum(_data,member)
	_health.value = float(member.health)
	_health.add_theme_stylebox_override("fill", CampStyle.box(base.colour, base.colour, 0))
	var item: Dictionary = WeaponInventory.for_member(_data, selected_member_id)
	_equipment.text = "当前装备：无，原装备已回库存" if item.is_empty() else "当前装备  /  %s" % WeaponInventory.definition(item.weapon_id).display_name
	_equipment.tooltip_text = item.get("instance_id", "")
	_service.text = "归航战绩\n出击 %d 次   /   击退 %d   /   累计受伤 %.0f\n等级与特性成长尚未启用。" % [int(member.service.sorties), int(member.service.kills), float(member.service.damage_received)]
	if GrowthState.is_family(_data):
		_service.text = "等级 Lv%d · 累计 %d XP · 下一级 %d XP\n出击 %d 次 / 击退 %d / 受伤 %.0f\n特性和食物训练尚未开放。" % [int(member.growth.level),int(member.growth.xp_total),GrowthRules.threshold(int(member.growth.level)+1),int(member.service.sorties),int(member.service.kills),float(member.service.damage_received)]
	if TraitState.is_family(_data):
		_service.text = "普通 Lv%d · %d XP · 下一级 %d XP\n%s\n出击%d / 击退%d · %s" % [int(member.growth.level),int(member.growth.xp_total),GrowthRules.threshold(int(member.growth.level)+1),(TraitRules.description(member).replace(" · PROJECT_TEMP", "") if player_mode else TraitRules.description(member)),int(member.service.sorties),int(member.service.kills),("阵亡历史只读，不能训练" if member.health<=0 else "可在篝火查看训练资格") if TrainingState.is_family(_data) else "食物训练未开放"]
	if member.condition=="dead":
		for death: Dictionary in _data.journey.deaths:
			if int(death.member_id)==selected_member_id:
				_service.text += ("\n死亡："+("缺粮减员" if death.cause=="STARVATION" else "战斗阵亡")) if player_mode else "\n死亡：%s · 事务%s" % [death.cause,death.transaction_id]
		var previous: Dictionary = member.growth.last_action
		if not previous.get("recent",[]).is_empty():
			_equipment.text += "\n最近使用：%s" % WeaponInventory.definition(previous.recent[-1].weapon_id).display_name
			if not player_mode: _equipment.tooltip_text += "\n历史实例："+String(previous.recent[-1].instance_id)
		var archived: Dictionary = death_equipment.get(selected_member_id,{})
		if not archived.is_empty():
			_equipment.text += ("\n阵亡时装备：%s" if player_mode else "\n阵亡时装备：%s（原事务记录）") % WeaponInventory.definition(archived.weapon_id).display_name
			_equipment.tooltip_text = "阵亡时的原武器保留在库存，当前归属以库存为准。" if player_mode else "历史实例：%s\n死亡事务：%s；当前归属以库存为准" % [archived.instance_id,archived.transaction_id]
			if WeaponState.is_family(_data):
				_equipment.text += "\n"+WeaponModifiers.description(WeaponInventory.find(_data,archived.instance_id))
	name_edit.text = member.call_sign
	name_edit.editable = member.condition != "dead"
	save_button.disabled = member.condition == "dead"
	equipment_button.disabled = member.condition != "active"
	message.text = feedback if not feedback.is_empty() else "正式姓名固定；呼号随队伍出击，战绩在正式归航后更新。"


func _sync_members() -> void:
	for entry: Dictionary in _data.crew:
		var member_id: int = int(entry.id)
		if buttons_by_id.has(member_id): continue
		var button: Button = Button.new()
		button.icon = SurvivorRoster.definition(member_id).portrait
		button.add_theme_constant_override("icon_max_width", 72)
		button.expand_icon = true
		button.custom_minimum_size = Vector2(290, 86)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(func() -> void:
			selected_member_id = member_id
			refresh(_data)
		)
		_members_list.add_child(button)
		var badge: GenderBadge = GenderBadge.new()
		badge.definition = SurvivorRoster.definition(member_id)
		button.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -59
		badge.offset_right = -9
		badge.offset_top = 10
		badge.offset_bottom = 36
		_member_genders.append(badge)
		member_buttons.append(button)
		buttons_by_id[member_id] = button


func _exit_tree() -> void:
	# Only one detail subtree is mounted at a time; release the retained sibling.
	if is_instance_valid(_legacy_detail) and _legacy_detail.get_parent()==null: _legacy_detail.free()
	if is_instance_valid(persona_details) and persona_details.get_parent()==null: persona_details.free()


func _fit_viewport() -> void:
	if player_mode:
		offset_top = 24.0
		return
	# Compact views need 420px for the shared detail body, including its 140px
	# scroll area with the Windows font metrics. Reclaim the unused title gap.
	offset_top=48.0 if PersonaState.enabled(_data) and get_viewport_rect().size.y<700.0 else 104.0
