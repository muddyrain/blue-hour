class_name GrowthPanel
extends PanelContainer
## A usable factual journal; unverified character/trait progression stays unavailable.

signal closed

var selected_member_id: int = 1
var member_buttons: Array[Button] = []
var training_button: Button
var back_button: Button
var status: Label
var action_summary: Label
var records: VBoxContainer
var scroll: ScrollContainer
var _data: Dictionary = {}
var _portrait: TextureRect
var _identity: Label
var _gender: GenderBadge
var _alias: Label
var _life: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 48
	offset_right = -48
	offset_top = 104
	offset_bottom = -24
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel",CampStyle.box(Color("10232d"),Color("34535d"),20))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	add_child(column)
	_label(column,"成长与特性 / 行动记录",30)
	_label(column,"成长规则待校准；本页记录真实出击事实，不折算经验。",16)
	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override("separation",24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var members: VBoxContainer = VBoxContainer.new()
	members.custom_minimum_size.x = 248
	body.add_child(members)
	for id: int in [1,2]:
		var button: Button = Button.new()
		button.text = SurvivorRoster.definition(id).default_display_name
		button.custom_minimum_size.y = 42
		button.add_theme_font_size_override("font_size",20)
		button.add_theme_color_override("font_color",SurvivorRoster.definition(id).colour)
		button.pressed.connect(func() -> void:
			selected_member_id = id
			refresh(_data))
		members.add_child(button)
		member_buttons.append(button)
	var identity_row: HBoxContainer = HBoxContainer.new()
	members.add_child(identity_row)
	_identity = _label(identity_row,"",24)
	_gender = GenderBadge.new()
	identity_row.add_child(_gender)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(180,150)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	members.add_child(_portrait)
	_alias = _label(members,"",18)
	_life = _label(members,"",18)
	var detail: VBoxContainer = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation",8)
	body.add_child(detail)
	status = _label(detail,"",18)
	training_button = Button.new()
	training_button.text = "食物训练 · 尚未开放"
	training_button.disabled = true
	training_button.focus_mode = Control.FOCUS_NONE
	training_button.tooltip_text = "本角色训练费用与效果尚未校准；不会扣粮、升级或回血。"
	training_button.custom_minimum_size.y = 40
	detail.add_child(training_button)
	action_summary = _label(detail,"",18)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail.add_child(scroll)
	records = VBoxContainer.new()
	records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	records.add_theme_constant_override("separation",6)
	scroll.add_child(records)
	back_button = Button.new()
	back_button.text = "返回同行者档案 / Esc"
	back_button.custom_minimum_size.y = 44
	back_button.pressed.connect(func() -> void: closed.emit())
	column.add_child(back_button)


func refresh(data: Dictionary) -> void:
	_data = data.duplicate(true)
	var member: Dictionary = SurvivorRoster.member(_data.crew,selected_member_id)
	var definition: SurvivorDefinition = SurvivorRoster.definition(selected_member_id)
	_identity.text = definition.default_display_name
	_identity.add_theme_color_override("font_color",definition.colour)
	_gender.set_definition(definition)
	_portrait.texture = definition.portrait
	_alias.text = "呼号：" + String(member.call_sign)
	_life.text = "生命 %.0f / 200 · 已有战绩保留" % float(member.health)
	status.text = "人物等级：尚未开放　/　经验：未换算\n个人特性：未确定　/　特性进度：尚未开放"
	for child: Node in records.get_children():
		records.remove_child(child)
		child.queue_free()
	scroll.scroll_vertical = 0
	var action: Dictionary = member.growth.last_action
	if action.is_empty():
		action_summary.text = "尚无本版本行动明细"
		_label(records,"旧战绩完整保留；从本版本的实际出击开始记录。\n没有回填历史经验或升级。",18)
		return
	var map_name: String = "旧街修理巷" if action.map_id == "repair_lane" else "青禾市场环路"
	action_summary.text = "最近行动 · %s · %s\n确认击退 %d · 显示最近 %d 条" % [map_name,
		"已撤离" if action.evacuated else "行动结束",int(action.total),action.recent.size()]
	if action.recent.is_empty():
		_label(records,"此次没有个人确认击退记录；本版本不将战绩换算为经验。",18)
	for receipt: Dictionary in action.recent:
		var seconds: int = int(receipt.at_ms) / 1000
		_label(records,"%02d:%02d　%s · 确认击退" % [seconds / 60,seconds % 60,
			WeaponInventory.definition(receipt.weapon_id).display_name],18)


func _label(parent: Node, text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label
