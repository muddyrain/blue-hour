class_name CampSceneView
extends Control
## Read-only scene adapter: emit original intentions, never edit campaign data.

signal action_requested(action: StringName, member_id: int)

const CAPTIONS: Dictionary[StringName, String] = {
	&"bus": "巴士停靠\n选择出击目标 →",
	&"crew": "同行者集合棚\n名册 / 等级档案 →",
	&"weapons": "武器整备\n仓库 / 维修 / 配装 →",
	&"supplies": "物资堆场\n查看钱粮与今日口粮",
	&"training": "篝火休憩\n训练尚未开放",
}

var input_allowed: Callable
var world: CampSceneWorld
var hotspots: Dictionary[StringName, Button] = {}
var member_buttons: Dictionary[int, Button] = {}
var footer_buttons: Dictionary[StringName, Button] = {}
var resource_text: Label
var eligibility_text: Label
var notice: Label
var info_close: Button
var _info: Control
var _info_title: Label
var _info_body: Label
var _data: Dictionary = {}
var _daily: Dictionary = {}
var _last_focus: String = "bus"


func _ready() -> void:
	world = CampSceneWorld.new()
	world.name = "TransitYard"
	add_child(world)
	resized.connect(_resize_world)
	_resize_world()
	var header: PanelContainer = PanelContainer.new()
	header.name = "CampHud"
	header.add_theme_stylebox_override("panel", CampStyle.box(Color("102730"), Color("638983"), 12))
	CampStyle.place(header, Rect2(24, 16, 1232, 82))
	add_child(header)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	header.add_child(row)
	var title: VBoxContainer = VBoxContainer.new()
	title.custom_minimum_size.x = 344
	row.add_child(title)
	title.add_child(CampStyle.label("蓝时驿站 / 河岸停靠院", 24))
	title.add_child(CampStyle.label("营地场景原型 · PROJECT_TEMP", 16, CampStyle.TEAL))
	var state: VBoxContainer = VBoxContainer.new()
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(state)
	resource_text = CampStyle.label("", 20)
	state.add_child(resource_text)
	eligibility_text = CampStyle.label("", 17, CampStyle.AMBER)
	state.add_child(eligibility_text)
	for action: StringName in CampSceneLayout.AREAS:
		var button: Button = _hotspot(action, CampSceneLayout.AREAS[action], CAPTIONS[action])
		hotspots[action] = button
	for id: int in [1, 2, 3, 4, 5]:
		var point: Vector2 = CampSceneLayout.member_position(id)
		var button: Button = _hotspot(StringName("member%d" % id), Rect2(point + Vector2(-69, -99), Vector2(138, 173)), "")
		button.set_meta("member_id", id)
		member_buttons[id] = button
	var footer: PanelContainer = PanelContainer.new()
	footer.add_theme_stylebox_override("panel", CampStyle.box(Color("102730"), Color("34535d"), 8))
	CampStyle.place(footer, Rect2(24, 650, 1232, 54))
	add_child(footer)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	footer.add_child(actions)
	notice = CampStyle.label("Tab选设施 · Enter/Space确认 · Esc关闭当前页", 17)
	notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice.clip_text = true
	actions.add_child(notice)
	for action: StringName in [&"sound", &"legacy", &"home", &"quit"]:
		var button: Button = Button.new()
		button.name = String(action)
		button.text = {&"sound":"声音", &"legacy":"原营地入口", &"home":"返回首页", &"quit":"退出游戏"}[action]
		button.custom_minimum_size.x = 108 if action == &"legacy" else 96
		button.pressed.connect(_request.bind(action, 0))
		actions.add_child(button)
		footer_buttons[action] = button
	_build_info()
	visibility_changed.connect(_shown)
	clear()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or (input_allowed.is_valid() and not input_allowed.call()):
		return
	if not event.is_action_pressed("ui_focus_next") and not event.is_action_pressed("ui_focus_prev") and not event.is_action_pressed("ui_accept"):
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if info_visible():
		if focus != info_close:
			info_close.grab_focus()
			get_viewport().set_input_as_handled()
	elif focus == null or not is_ancestor_of(focus):
		restore_focus()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()


func refresh(data: Dictionary, daily: Dictionary, can_depart: bool, reason: String) -> void:
	_data = data.duplicate(true)
	_daily = daily.duplicate(true)
	world.refresh(data.crew)
	resource_text.text = "第%d天   货币%d   食物%d   在营%d人" % [data.day, data.cash, data.food, world.visible_member_ids.size()]
	eligibility_text.text = "%s · 今日需%d粮%s" % [reason, daily.required, " / 缺口%d" % int(daily.shortage) if daily.shortage > 0 else " / 库存足够"]
	hotspots[&"bus"].disabled = not can_depart
	hotspots[&"bus"].tooltip_text = "选择出击目标" if can_depart else reason
	hotspots[&"crew"].set_meta("member_id", world.visible_member_ids[0] if not world.visible_member_ids.is_empty() else 0)
	for id: int in member_buttons:
		var button: Button = member_buttons[id]
		button.visible = id in world.visible_member_ids
		if not button.visible:
			continue
		if RescuePoolState.is_family(data):
			button.position = world.residents[id].position+Vector2(-50,-99)
			button.size = Vector2(100,173)
		var member: Dictionary = SurvivorRoster.member(data.crew, id)
		var caption: Label = button.get_node("Caption") as Label
		var short_name: String = member.call_sign if member.call_sign.length() <= 5 else member.call_sign.left(4) + "…"
		caption.text = "%02d %s\n生命%.0f%s" % [id, short_name, member.health, " · Lv%d" % int(member.growth.level) if GrowthState.is_family(data) else ""]
		if RescuePoolState.is_family(data):
			caption.text = "%02d %s\n生命%.0f\nLv%d" % [id,short_name.left(4),member.health,int(member.growth.level)]
			caption.add_theme_font_size_override("font_size",16)
			caption.offset_top = -70
		caption.add_theme_color_override("font_color", SurvivorRoster.definition_for(member).colour)
		button.tooltip_text = "%02d %s · %s\n点击查看档案" % [id, SurvivorRoster.definition_for(member).default_display_name, member.call_sign]
	var caption: Label = hotspots[&"training"].get_node("Caption") as Label
	caption.text = "篝火训练\n食物换个人Trait进度 →" if TrainingState.is_family(data) else "篝火休憩\n训练尚未开放"
	_link_focus()


func clear() -> void:
	if world == null:
		return
	world.refresh([])
	for button: Button in member_buttons.values():
		button.hide()
	_info.hide()
	_data.clear()
	_daily.clear()


func info_visible() -> bool:
	return is_instance_valid(_info) and _info.visible


func open_info(action: StringName) -> void:
	if _data.is_empty():
		return
	if action == &"training":
		_info_title.text = "营地训练尚未开放"
		_info_body.text = "这里暂时是休憩与集合的篝火。\n个人特性和食物训练将在后续阶段单独设计。\n查看此处不会消耗食物、增加经验或改变属性。"
		if TraitState.is_family(_data):
			_info_body.text = "这里暂时是休憩与集合的篝火。\n个人特性通过本人真实出击行动成长；食物训练尚未开放。\n查看此处不会消耗食物、增加经验或改变属性。"
	else:
		_info_title.text = "物资堆场 / 当前营地"
		_info_body.text = "食物 %d · 货币 %d · 武器 %d 件\n今日口粮需求 %d · %s\n实际搜集、归航与整备结果由原营地系统结算。" % [_data.food, _data.cash, _data.weapons.size(), _daily.required, "库存足够" if _daily.shortage == 0 else "缺口%d，建议出击搜集" % int(_daily.shortage)]
	_info.show()
	info_close.grab_focus()


func close_info() -> void:
	_info.hide()
	restore_focus()


func restore_focus() -> void:
	if not is_visible_in_tree() or info_visible():
		return
	var button: Button = find_child(_last_focus, true, false) as Button
	if button != null and button.is_visible_in_tree() and not button.disabled:
		button.grab_focus()
	elif not hotspots[&"bus"].disabled:
		hotspots[&"bus"].grab_focus()
	else:
		hotspots[&"crew"].grab_focus()


func _hotspot(action: StringName, rect: Rect2, text: String) -> Button:
	var button: Button = Button.new()
	button.name = String(action)
	button.mouse_force_pass_scroll_events = false
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", CampStyle.box(Color(0.1, 0.24, 0.25, 0.18), CampStyle.TEAL, 0))
	button.add_theme_stylebox_override("pressed", CampStyle.box(Color(0.3, 0.27, 0.15, 0.22), CampStyle.AMBER, 0))
	button.add_theme_stylebox_override("focus", CampStyle.box(Color(0, 0, 0, 0), CampStyle.AMBER, 0))
	CampStyle.place(button, rect)
	add_child(button)
	button.pressed.connect(func() -> void: _request(action, int(button.get_meta("member_id", 0))))
	button.mouse_entered.connect(_announce.bind(button, text))
	button.focus_entered.connect(_announce.bind(button, text))
	var label: Label = CampStyle.label(text, 18)
	label.name = "Caption"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -52
	label.offset_bottom = -4
	label.add_theme_color_override("font_outline_color", Color("142a31"))
	label.add_theme_constant_override("outline_size", 6)
	button.add_child(label)
	return button


func _request(action: StringName, member_id: int) -> void:
	if info_visible():
		return
	if String(action).begins_with("member"):
		action_requested.emit(&"crew", member_id)
	else:
		action_requested.emit(action, member_id)


func _announce(button: Button, text: String) -> void:
	_last_focus = String(button.name)
	if notice != null:
		notice.text = text.replace("\n", " · ") if not text.is_empty() else button.tooltip_text.replace("\n", " · ")
		notice.tooltip_text = notice.text


func _link_focus() -> void:
	var sequence: Array[Button] = []
	for action: StringName in [&"bus", &"crew", &"weapons", &"supplies", &"training"]:
		if not hotspots[action].disabled:
			sequence.append(hotspots[action])
	for id: int in [1, 2, 3, 4, 5]:
		if member_buttons[id].visible:
			sequence.append(member_buttons[id])
	for button: Button in footer_buttons.values():
		sequence.append(button)
	for index: int in range(sequence.size()):
		sequence[index].focus_next = sequence[(index + 1) % sequence.size()].get_path()
		sequence[index].focus_previous = sequence[(index - 1 + sequence.size()) % sequence.size()].get_path()


func _build_info() -> void:
	_info = Control.new()
	_info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_info.mouse_filter = Control.MOUSE_FILTER_STOP
	_info.mouse_force_pass_scroll_events = false
	add_child(_info)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.07, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_force_pass_scroll_events = false
	_info.add_child(dim)
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(centre)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.x = 680
	panel.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.PANEL, CampStyle.TEAL, 28))
	centre.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	panel.add_child(column)
	_info_title = CampStyle.label("", 28)
	column.add_child(_info_title)
	_info_body = CampStyle.label("", 20)
	_info_body.custom_minimum_size = Vector2(620, 126)
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_info_body)
	info_close = Button.new()
	info_close.text = "返回营地 / Esc"
	info_close.custom_minimum_size.y = 48
	info_close.pressed.connect(close_info)
	column.add_child(info_close)
	info_close.focus_next = info_close.get_path()
	info_close.focus_previous = info_close.get_path()
	_info.hide()


func _shown() -> void:
	if is_visible_in_tree():
		restore_focus.call_deferred()


func _resize_world() -> void:
	world.scale = size / CampSceneLayout.SIZE
