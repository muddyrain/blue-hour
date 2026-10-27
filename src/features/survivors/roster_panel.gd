class_name RosterPanel
extends PanelContainer
## Camp management view of real profiles. No XP, healing or death buttons.

signal call_sign_requested(member_id: int, call_sign: String)
signal equipment_requested(member_id: int)
signal growth_requested(member_id: int)
signal closed

var member_buttons: Array[Button] = []
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
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 32)
	column.add_child(row)
	var members: VBoxContainer = VBoxContainer.new()
	members.custom_minimum_size.x = 290
	members.add_theme_constant_override("separation", 12)
	row.add_child(members)
	for member_id: int in [1, 2]:
		var button: Button = Button.new()
		button.icon = SurvivorRoster.definition(member_id).portrait
		button.add_theme_constant_override("icon_max_width", 72)
		button.expand_icon = true
		button.custom_minimum_size = Vector2(290, 108)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(func() -> void:
			selected_member_id = member_id
			refresh(_data)
		)
		members.add_child(button)
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
	growth_button = Button.new()
	growth_button.text = "成长与特性 / 行动记录 →"
	growth_button.custom_minimum_size.y = 44
	growth_button.pressed.connect(func() -> void: growth_requested.emit(selected_member_id))
	members.add_child(growth_button)
	var detail: VBoxContainer = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	row.add_child(detail)
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
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 30
	message.add_theme_font_size_override("font_size", 16)
	column.add_child(message)
	back_button = Button.new()
	back_button.text = "返回营地 / Esc"
	back_button.custom_minimum_size.y = 44
	back_button.pressed.connect(func() -> void: closed.emit())
	column.add_child(back_button)


func refresh(data: Dictionary, feedback: String = "") -> void:
	_data = data.duplicate(true)
	for member_id: int in [1, 2]:
		var entry: Dictionary = SurvivorRoster.member(_data.crew, member_id)
		var button: Button = member_buttons[member_id - 1]
		var list_name: String = entry.call_sign if entry.call_sign.length() <= 5 else entry.call_sign.left(4) + "…"
		var definition: SurvivorDefinition = SurvivorRoster.definition(member_id)
		button.tooltip_text = "%s · %s\n呼号：%s" % [definition.default_display_name, definition.gender_text(), entry.call_sign]
		button.text = "%02d  %s\n%s · %.0f / 200" % [member_id, list_name,
			"存活" if entry.condition == "active" else "倒地", float(entry.health)]
		button.add_theme_color_override("font_color", SurvivorRoster.definition(member_id).colour)
	var member: Dictionary = SurvivorRoster.member(_data.crew, selected_member_id)
	var base: SurvivorDefinition = SurvivorRoster.definition(selected_member_id)
	_portrait.texture = base.portrait
	_identity.text = base.default_display_name
	_call_sign.text = "呼号：%s" % member.call_sign
	_condition.text = "同行者 %02d · 生命 %.0f / 200 · %s" % [selected_member_id, float(member.health),
		"存活" if member.condition == "active" else "倒地（非永久离队）"]
	_gender_title.set_definition(base)
	_gender_detail.set_definition(base)
	_identity.add_theme_color_override("font_color", base.colour)
	_health.value = float(member.health)
	_health.add_theme_stylebox_override("fill", CampStyle.box(base.colour, base.colour, 0))
	var item: Dictionary = WeaponInventory.for_member(_data, selected_member_id)
	_equipment.text = "当前装备：无，原装备已回库存" if item.is_empty() else "当前装备  /  %s" % WeaponInventory.definition(item.weapon_id).display_name
	_equipment.tooltip_text = item.get("instance_id", "")
	_service.text = "归航战绩\n出击 %d 次   /   击退 %d   /   累计受伤 %.0f\n等级与特性成长尚未启用。" % [int(member.service.sorties), int(member.service.kills), float(member.service.damage_received)]
	name_edit.text = member.call_sign
	equipment_button.disabled = member.condition != "active"
	message.text = feedback if not feedback.is_empty() else "正式姓名固定；呼号随队伍出击，战绩在正式归航后更新。"
