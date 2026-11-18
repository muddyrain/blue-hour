class_name GrowthPanel
extends PanelContainer
## A usable factual journal; unverified character/trait progression stays unavailable.

signal closed
signal navigation_requested(action: StringName)


var selected_member_id: int = 1
var member_buttons: Array[Button] = []
var buttons_by_id: Dictionary[int,Button] = {}
var training_button: Button
var back_button: Button
var status: Label
var action_summary: Label
var records: VBoxContainer
var scroll: ScrollContainer
var _data: Dictionary = {}
var _sheet: PixelSheet
var _portrait: TextureRect
var _identity: Label
var _gender: GenderBadge
var _alias: Label
var _life: Label
var _subtitle: Label
var _members_list: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", CampStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	_sheet = PixelSheet.new()
	_sheet.page_title = "行动记录"
	_sheet.active_tab = &"roster"
	add_child(_sheet)
	_sheet.closed.connect(navigation_requested.emit.bind(&"camp"))
	_sheet.navigation_requested.connect(navigation_requested.emit)
	var body: Control = _sheet.body
	PixelSheet.line(body, Rect2(310, 16, 1, 552))
	var member_scroll: ScrollContainer = ScrollContainer.new()
	member_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	member_scroll.follow_focus = true
	body.add_child(member_scroll)
	PixelSheet.place(member_scroll, Rect2(16, 16, 278, 182))
	_members_list = VBoxContainer.new()
	_members_list.add_theme_constant_override("separation", 10)
	_members_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	member_scroll.add_child(_members_list)
	PixelSheet.line(body, Rect2(16, 210, 278, 1))
	_identity = PixelSheet.label(body, "", Rect2(24, 222, 196, 44), 32)
	_gender = GenderBadge.new()
	body.add_child(_gender)
	PixelSheet.place(_gender, Rect2(238, 232, 50, 28))
	_alias = PixelSheet.label(body, "", Rect2(24, 272, 264, 30), 18, CampStyle.MUTED, false)
	_alias.clip_text = true
	_portrait = PixelSheet.art(body, null, Rect2(60, 312, 206, 216))
	_life = PixelSheet.label(body, "", Rect2(24, 534, 264, 42), 18, CampStyle.MUTED, false)
	_life.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	body.add_child(scroll)
	PixelSheet.place(scroll, Rect2(334, 16, 754, 484))
	var detail: VBoxContainer = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 16)
	scroll.add_child(detail)
	var heading: Label = _label(detail, "成长与特性", 30)
	heading.add_theme_font_override("font", CampStyle.BOLD_FONT)
	status = _label(detail, "", 22)
	_subtitle = _label(detail, "", 18)
	_subtitle.add_theme_color_override("font_color", CampStyle.MUTED)
	var section_rule: ColorRect = PixelMenu.divider(detail)
	action_summary = _label(detail, "", 28)
	action_summary.add_theme_font_override("font", CampStyle.BOLD_FONT)
	records = VBoxContainer.new()
	records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	records.add_theme_constant_override("separation", 16)
	detail.add_child(records)
	detail.move_child(action_summary, 0)
	detail.move_child(records, 1)
	detail.move_child(section_rule, 2)
	back_button = PixelSheet.button(body, "返回档案 / Esc", Rect2(334, 516, 256, 52), 25)
	back_button.pressed.connect(closed.emit)
	training_button = PixelSheet.button(body, "食物训练 · 尚未开放", Rect2(606, 516, 482, 52), 22)
	training_button.disabled = true
	training_button.focus_mode = Control.FOCUS_NONE


func refresh(data: Dictionary) -> void:
	_data = data.duplicate(true)
	_sheet.update_resources(data)
	if SurvivorRoster.member(_data.crew, selected_member_id).is_empty():
		selected_member_id = int(_data.crew[0].id)
	_sync_members()
	for id: int in buttons_by_id:
		var entry: Dictionary = SurvivorRoster.member(_data.crew, id)
		var button: Button = buttons_by_id[id]
		button.visible = not entry.is_empty()
		if entry.is_empty(): continue
		button.text = "%s\n生命 %.0f / %.0f" % [entry.call_sign, float(entry.health), SurvivorGrowth.maximum(_data, entry)]
		button.tooltip_text = PersonaCard.camp_hover(_data, id)
		button.add_theme_stylebox_override("normal", CampStyle.box(CampStyle.SELECTED.darkened(0.16) if id == selected_member_id else Color.TRANSPARENT, CampStyle.EDGE if id == selected_member_id else Color.TRANSPARENT, 8))
	var member: Dictionary = SurvivorRoster.member(_data.crew,selected_member_id)
	var definition: SurvivorDefinition = SurvivorRoster.definition(selected_member_id)
	_identity.text = definition.default_display_name
	_gender.set_definition(definition)
	_portrait.texture = PixelSheet.body_texture(selected_member_id)
	_portrait.modulate = Color.WHITE if member.health > 0 else Color("8a9eae")
	_alias.text = "呼号：" + String(member.call_sign)
	_alias.tooltip_text = String(member.call_sign)
	_life.text = "生命 %.0f / %.0f\n%s" % [float(member.health), SurvivorGrowth.maximum(_data, member), "已阵亡 · 只读历史" if member.condition == "dead" else "已有战绩保留"]
	status.text = "人物等级：尚未开放　/　经验：未换算\n个人特性：未确定　/　特性进度：尚未开放"
	_subtitle.text = "本页保留真实出击事实；此存档尚未开启成长。"
	if GrowthState.is_family(_data):
		_subtitle.text = "个人经验与等级在存活归航后结算。"
		status.text = "人物等级 Lv%d · 累计 %d XP · 下一级 %d XP\n个人特性和食物训练尚未开放。" % [int(member.growth.level),int(member.growth.xp_total),GrowthRules.threshold(int(member.growth.level)+1)]
	if TraitState.is_family(_data):
		_subtitle.text = "人物经验与个人特性分别成长，在存活归航后结算。"
		status.text = "普通 Lv%d · 累计 %d XP · 下一级 %d XP\n%s" % [int(member.growth.level),int(member.growth.xp_total),GrowthRules.threshold(int(member.growth.level)+1),(TraitRules.description(member).replace(" · PROJECT_TEMP", ""))]
		status.text += "\n" + GrowthRules.description(member)
	if TrainingState.is_family(_data):
		_subtitle.text = "人物经验与特性分别成长 · 出击成长归航结算；食物训练营地确认"
	training_button.text = "返回营地后，在篝火进行训练"
	training_button.tooltip_text = "在营地篝火预览1粮换本人特性进度1；训练不增加人物经验、生命或日期。" if TrainingState.is_family(_data) else "本角色训练费用与效果尚未校准；不会扣粮、升级或回血。"
	training_button.text = "食物训练 · 请返回营地篝火" if TrainingState.is_family(_data) else "食物训练 · 尚未开放"
	for child: Node in records.get_children():
		records.remove_child(child)
		child.queue_free()
	scroll.scroll_vertical = 0
	var action: Dictionary = member.growth.last_action
	if action.is_empty():
		action_summary.text = "尚无本版本行动明细"
		_label(records,"每次真实个人击退+10 XP，归航且存活才生效；没有分享以前的经验。" if GrowthState.is_family(_data) else "旧战绩完整保留；从本版本的实际出击开始记录。\n没有回填历史经验或升级。",22)
		return
	var map_name: String = "生成街区" if (RogueLayout.is_map_id(action.map_id) or WorldLayout.is_map_id(action.map_id) or NeighborhoodLayout.is_map_id(action.map_id) or (ExplorationLayout.is_map_id(action.map_id) or WorldgenLayout.is_map_id(action.map_id))) else "旧街修理巷" if action.map_id == "repair_lane" else "青禾市场环路"
	action_summary.text = "最近行动 · %s · %s\n确认击退 %d · 显示最近 %d 条" % [map_name,
		"已撤离" if action.evacuated else "行动结束",int(action.total),action.recent.size()]
	if action.recent.is_empty():
		_label(records,"此次没有个人确认击退；本次经验+0。" if GrowthState.is_family(_data) else "此次没有个人确认击退记录；本版本不将战绩换算为经验。",22)
	for receipt: Dictionary in action.recent:
		var seconds: int = int(receipt.at_ms) / 1000
		_label(records,"%02d:%02d　%s · 确认击退" % [seconds / 60,seconds % 60,
			WeaponInventory.definition(receipt.weapon_id).display_name],22)
		PixelMenu.divider(records)


func _label(parent: Node, text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _sync_members() -> void:
	for member: Dictionary in _data.crew:
		var id: int = int(member.id)
		if buttons_by_id.has(id): continue
		var button: Button = PersonaCard.HoverButton.new()
		button.custom_minimum_size = Vector2(264, 82)
		button.add_theme_font_size_override("font_size", 22)
		button.icon = SurvivorRoster.definition(id).portrait
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 56)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(func() -> void:
			selected_member_id = id
			refresh(_data))
		_members_list.add_child(button)
		_members_list.move_child(button,member_buttons.size())
		member_buttons.append(button)
		buttons_by_id[id] = button
