class_name C1ExpeditionHud
extends Control
## Read-only screen HUD. Parent owns gameplay, shortcut handling and CanvasLayer.
## Call refresh after adding to the tree. No timers, Input polling or world writes.

signal pause_requested
signal resume_requested
signal bus_start_requested

# Matches the verified P03-2 ActorVisual identities; no dependency on that class.
const IDENTITY_COLORS: Array[Color] = [Color("80ddd8"), Color("f2c37f")]
const TONES: Dictionary[String, Color] = {
	"normal": Color("dbe8eb"), "info": Color("80ddd8"),
	"warning": Color("f2c37f"), "danger": Color("ffaca7"),
}

var _paused: bool = false
var _mission: Label
var _objective: Label
var _progress: Label
var _currency: Label
var _time_label: Label
var _time_text: Label
var _time_hint: Label
var _time_box: VBoxContainer
var _pause_state: Label
var _bus_status: Label
var _hint: Label
var _pause_button: Button
var _bus_button: Button
var _help_button: Button
var _help: PanelContainer
var _members: Array[Dictionary] = []
var _members_parent: BoxContainer
var _day: Label
var _objective_toggle: Button
var _objective_expanded: bool = true
var _threat_details: PanelContainer
var _threat_content: Label
var _member_details: Label
var _member_details_panel: PanelContainer
var _member_detail_index: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_top()
	_build_actions()
	_build_help()
	# Let native traversal include objective, threat, member and skill controls.
	# No initial focus: Space continues to mean pause in the world.
	visibility_changed.connect(_on_visibility_changed)
	refresh({})


func _unhandled_key_input(event: InputEvent) -> void:
	# Native no-focus Tab entry only searches direct Viewport Control children.
	# This HUD lives under its owner's CanvasLayer; seed existing UI navigation
	# locally, then let Control handle the focus ring. Never intercept Space.
	if not is_visible_in_tree() or get_viewport().gui_get_focus_owner() != null:
		return
	if event.is_action_pressed("ui_focus_next", false, true):
		_pause_button.grab_focus()
	elif event.is_action_pressed("ui_focus_prev", false, true):
		_help_button.grab_focus()
	else:
		return
	get_viewport().set_input_as_handled()


func refresh(state: Dictionary) -> void:
	# Read primitives only; never retain, sort, mutate or duplicate caller objects.
	_mission.text = _text(state, "mission_title", "地点未提供")
	_mission.tooltip_text = _mission.text
	_progress.text = "搜集 %s    击退 %s" % [
		_text(state, "search_progress_text", "—"), _text(state, "defeated_text", "—"),
	]
	_day.text = _text(state, "day_text", "天数 —")
	_objective.text=_text(state,"objective")
	_objective.visible=_objective_expanded and not _objective.text.is_empty()
	_objective_toggle.text = "收起目标 −" if _objective_expanded else "展开目标 +"
	_currency.text = "货币 %s" % _text(state, "currency_text", "—")
	var delta: String = _text(state, "currency_delta_text")
	if not delta.is_empty():
		_currency.text += "    本次 %s" % delta
	if state.get("resource_text") is String: _currency.text = state.resource_text
	_currency.tooltip_text = "货币 " + _text(state,"currency_text","—") + "\n本次 " + delta
	_paused = state.get("paused", false) == true
	_pause_state.text = "已暂停" if _paused else "出击中"
	_pause_state.add_theme_color_override("font_color", TONES["warning"] if _paused else TONES["info"])
	_pause_button.text = "继续" if _paused else "暂停"
	var time_data: Dictionary = _dictionary(state.get("time", {}))
	_time_box.visible = time_data.get("visible", true) == true and not _text(time_data, "text").is_empty()
	_time_label.text = _text(time_data, "label", "出击时间")
	_time_text.text = _text(time_data, "text")
	_time_hint.text = _text(time_data, "hint")
	_time_hint.visible = not _time_hint.text.is_empty()
	_time_text.add_theme_color_override("font_color", _tone(time_data))
	_threat_content.text = _text(time_data,"explanation",_text(time_data,"hint")) + "\n威胁随行动时间推进；不会阻止巴士归航。\n打开此说明不暂停行动。"
	_bus_status.text = _text(state, "bus_status_text", "巴士状态未提供")
	_bus_status.add_theme_color_override("font_color", _tone(_dictionary(state.get("bus", {}))))
	_bus_button.text = _text(state, "bus_action_label", "发动巴士")
	_bus_button.disabled = state.get("bus_action_enabled", false) != true
	_hint.text = _text(state, "status_hint")
	_hint.visible = not _hint.text.is_empty()
	_hint.tooltip_text = _hint.text
	var supplied: Variant = state.get("survivors", [])
	var members: Array[Dictionary] = []
	if supplied is Array:
		for value: Variant in supplied:
			if value is Dictionary:
				members.append(value)
	members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("id",0)) < int(b.get("id",0)))
	var count: int = members.size() if not members.is_empty() else 2
	while _members.size() < count:
		_build_member(_members_parent, _members.size())
	for index: int in range(_members.size()):
		_members[index].box.visible = index < count
	for index: int in range(count):
		var member: Dictionary = {}
		if index < members.size():
			member = members[index]
		_refresh_member(index, member)
	if _member_detail_index >= 0 and _member_detail_index < count:
		_member_details.text = String(_members[_member_detail_index].get("detail",""))
	# Disabled native buttons can still receive explicit focus neighbors.
	# Release existing focus and remove this action from keyboard navigation.
	if _bus_button.disabled:
		_bus_button.release_focus()
	_bus_button.focus_mode = Control.FOCUS_NONE if _bus_button.disabled else Control.FOCUS_ALL


func hide_screen() -> void:
	hide()


func place_help_above_lane() -> void:
	# The compact HUD reserves the same help position for every map layout.
	pass


func _build_top() -> void:
	var panel: PanelContainer = _panel(self, "MissionPanel")
	panel.position = Vector2(16,16)
	panel.custom_minimum_size.x = 296
	panel.size.x = 296
	var mission_box: VBoxContainer = _column(panel)
	mission_box.add_theme_constant_override("separation",4)
	var heading: HBoxContainer = HBoxContainer.new()
	heading.add_theme_constant_override("separation",8)
	_passive(heading)
	mission_box.add_child(heading)
	_mission = _label(heading, "MissionTitle", 18)
	_mission.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mission.clip_text = true
	_mission.mouse_filter = Control.MOUSE_FILTER_PASS
	_objective_toggle = _button(heading,"ObjectiveToggle","收起目标 −",_toggle_objective)
	_objective_toggle.custom_minimum_size = Vector2(86,28)
	_objective_toggle.add_theme_font_size_override("font_size",13)
	_progress = _label(mission_box, "Progress", 14)
	_objective = _label(mission_box,"Objective",15)
	_wrap(_objective)
	var time_panel: PanelContainer = _panel(self,"TimePanel")
	time_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	time_panel.offset_left = -104
	time_panel.offset_right = 104
	time_panel.offset_top = 16
	_time_box = _column(time_panel)
	_time_box.add_theme_constant_override("separation",1)
	_time_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_day = _label(_time_box,"Day",14)
	_day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label = _label(_time_box, "TimeLabel", 13)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_text = _label(_time_box, "TimeText", 26)
	_time_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_hint = _label(_time_box, "TimeHint", 14)
	_time_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var explanation: Button = _button(self,"ThreatExplanation","威胁说明",_toggle_threat)
	explanation.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	explanation.offset_left=-55
	explanation.offset_right=55
	explanation.offset_top=130
	explanation.offset_bottom=158
	explanation.custom_minimum_size.y=28
	explanation.add_theme_font_size_override("font_size",13)
	explanation.tooltip_text="查看当前攻势；不暂停行动。"
	_threat_details = _panel(self,"ThreatDetails")
	_threat_details.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_threat_details.offset_left=-160
	_threat_details.offset_right=160
	_threat_details.offset_top=164
	_threat_content = _label(_threat_details,"ThreatText",15)
	_wrap(_threat_content)
	_threat_details.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_threat_details.hide()
	var resource_panel: PanelContainer = _panel(self,"ResourcesPanel")
	resource_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	resource_panel.offset_left=-240
	resource_panel.offset_right=-16
	resource_panel.offset_top=16
	var resources: VBoxContainer = _column(resource_panel)
	resources.add_theme_constant_override("separation",4)
	_currency = _label(resources,"Currency",14)
	_wrap(_currency)
	_currency.mouse_filter=Control.MOUSE_FILTER_PASS
	_pause_button = _button(resources,"PauseButton","暂停",_request_pause)
	_pause_button.custom_minimum_size.y=30
	_pause_button.add_theme_font_size_override("font_size",14)
	var members_panel: PanelContainer = _panel(self,"MembersPanel")
	members_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	members_panel.offset_left=-224
	members_panel.offset_right=-16
	members_panel.offset_top=128
	var list: VBoxContainer = _column(members_panel)
	_label(list,"TeamTitle",13).text="行动小队"
	_members_parent = VBoxContainer.new()
	_members_parent.add_theme_constant_override("separation",4)
	_passive(_members_parent)
	list.add_child(_members_parent)
	for index: int in range(2):
		_build_member(_members_parent,index)
	_member_details_panel = _panel(self,"MemberDetails")
	_member_details_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_member_details_panel.offset_left=-532
	_member_details_panel.offset_right=-232
	_member_details_panel.offset_top=180
	_member_details_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_member_details = _label(_member_details_panel,"MemberText",15)
	_wrap(_member_details)
	_member_details_panel.hide()


func _build_member(parent: Control, index: int) -> void:
	var box: VBoxContainer = _column(parent)
	box.name = "Member%d" % (index + 1)
	box.add_theme_constant_override("separation",1)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation",2)
	_passive(row)
	box.add_child(row)
	var title: Label = _label(row, "Identity", 16)
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.clip_text=true
	var info: Button = _button(row,"MemberInfo","· · ·",func() -> void: _toggle_member(index))
	info.custom_minimum_size = Vector2(28,22)
	info.add_theme_font_size_override("font_size",12)
	info.tooltip_text="查看姓名、生命与完整工作状态。"
	var health: Label = _label(box, "Health", 14)
	health.autowrap_mode = TextServer.AUTOWRAP_OFF
	var bar: ProgressBar = ProgressBar.new()
	bar.name = "HealthBar"
	bar.custom_minimum_size.y = 5
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	_passive(bar)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = IDENTITY_COLORS[index % 2]
	bar.add_theme_stylebox_override("fill", fill)
	box.add_child(bar)
	var status: Label = _label(box,"Activity",14)
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.clip_text=true
	status.mouse_filter=Control.MOUSE_FILTER_PASS
	var ammo: Label = _label(box,"Ammo",13)
	ammo.autowrap_mode=TextServer.AUTOWRAP_OFF
	ammo.clip_text=true
	ammo.mouse_filter=Control.MOUSE_FILTER_PASS
	_members.append({"ammo":ammo,"box":box,"title":title,"health":health,"bar":bar,"status":status,"detail":""})


func _build_actions() -> void:
	var panel: PanelContainer = _panel(self, "ActionsPanel")
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -206
	panel.offset_right = 206
	panel.offset_top = -84
	panel.offset_bottom = -16
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var column: VBoxContainer = _column(panel)
	column.add_theme_constant_override("separation",3)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	_passive(row)
	column.add_child(row)
	var status: VBoxContainer = _column(row)
	status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_pause_state = _label(status, "PauseState", 12)
	_bus_status = _label(status, "BusStatus", 14)
	_wrap(_bus_status)
	_bus_button = _button(row, "BusButton", "发动巴士", _request_bus)
	_bus_button.custom_minimum_size=Vector2(150,36)
	_bus_button.add_theme_font_size_override("font_size",15)
	_bus_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint = _label(self, "StatusHint", 14)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left=-260
	_hint.offset_right=260
	_hint.offset_top=-124
	_hint.offset_bottom=-92
	_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_hint.clip_text=true
	_hint.mouse_filter=Control.MOUSE_FILTER_PASS
	_hint.add_theme_color_override("font_outline_color",Color("10232b"))
	_hint.add_theme_constant_override("outline_size",3)


func _build_help() -> void:
	_help_button = _button(self, "HelpButton", "操作帮助", _toggle_help)
	_help_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help_button.offset_left = 16
	_help_button.offset_top = -48
	_help_button.offset_right = 120
	_help_button.offset_bottom = -16
	_help_button.custom_minimum_size.y=32
	_help_button.add_theme_font_size_override("font_size",14)
	_help = _panel(self, "HelpPanel")
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.offset_left = 216
	_help.offset_right = 644
	_help.offset_top = -266
	_help.offset_bottom = -96
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var content: Label = _label(_help, "HelpText", 15)
	content.text = "左键地面：移动 / 改目标\n左键建筑：派遣；再点同栋只取消该任务\n空格：暂停 / 继续；Esc：菜单\nWASD 镜头；滚轮缩放\nTab 切换按钮，Space / Enter 确认\nQ 治疗；E 瞄准空袭；3 释放装备的特殊能力"
	_wrap(content)
	_help.hide()


func _refresh_member(index: int, state: Dictionary) -> void:
	var title: Label = _members[index]["title"]
	var health: Label = _members[index]["health"]
	var bar: ProgressBar = _members[index]["bar"]
	var member_id: int = int(state.get("id", index + 1))
	var full_name: String = _text(state,"label","队员 %d" % member_id)
	title.tooltip_text = full_name
	var call_sign: String = _text(state,"call_sign",full_name)
	title.text = "%02d  %s" % [member_id,call_sign]
	_members[index].status.text = _text(state,"status")
	_members[index].ammo.text = _text(state,"ammo")
	_members[index].ammo.visible=not _members[index].ammo.text.is_empty()
	_members[index].status.tooltip_text=_text(state,"detail",_text(state,"status"))
	_members[index].ammo.tooltip_text=_text(state,"ammo")
	_members[index].detail=full_name + "\n" + _text(state,"detail",_text(state,"status")) + "\n" + _text(state,"ammo")
	var colour: Color = state.get("colour", IDENTITY_COLORS[index % 2])
	title.add_theme_color_override("font_color", colour)
	(bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = colour
	var hp: Variant = state.get("hp")
	var maximum: Variant = state.get("max_hp")
	if not _finite_number(hp) or not _finite_number(maximum) or float(maximum) <= 0.0:
		health.text = "生命 — / —"
		bar.value = 0.0
		bar.modulate.a = 0.35
		return
	var safe_hp: float = clampf(float(hp), 0.0, float(maximum))
	health.text = "HP %s/%s" % [str(ceili(safe_hp)), str(ceili(float(maximum)))]
	if _finite_number(state.get("level")) and int(state.level) > 0:
		health.text += " · Lv%d" % int(state.level)
	_members[index].detail += "\n" + health.text
	bar.value = safe_hp / float(maximum)
	bar.modulate.a = 1.0


func _request_pause() -> void:
	if not is_visible_in_tree():
		return
	if _paused:
		resume_requested.emit()
	else:
		pause_requested.emit()


func _request_bus() -> void:
	if is_visible_in_tree() and not _bus_button.disabled:
		bus_start_requested.emit()


func _toggle_objective() -> void:
	_objective_expanded=not _objective_expanded
	_objective.visible=_objective_expanded and not _objective.text.is_empty()
	_objective_toggle.text="收起目标 −" if _objective_expanded else "展开目标 +"


func _toggle_threat() -> void:
	_threat_details.visible=not _threat_details.visible


func _toggle_member(index: int) -> void:
	_member_details_panel.visible=not (_member_details_panel.visible and _member_detail_index==index)
	_member_detail_index=index
	_member_details.text=String(_members[index].get("detail",""))


func _toggle_help() -> void:
	_help.visible = not _help.visible
	_help_button.text = "收起帮助" if _help.visible else "操作帮助"


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_help.hide()
		_threat_details.hide()
		_member_details_panel.hide()
		_help_button.text = "操作帮助"
		for button: Button in [_pause_button, _bus_button, _help_button]:
			button.release_focus()


func _panel(parent: Control, node_name: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Wheel events must not escape an opaque panel into the camera behind it.
	panel.mouse_force_pass_scroll_events = false
	var style: StyleBoxFlat = get_theme_stylebox("panel","PanelContainer").duplicate() as StyleBoxFlat
	style.content_margin_left=12
	style.content_margin_right=12
	style.content_margin_top=10
	style.content_margin_bottom=10
	panel.add_theme_stylebox_override("panel",style)
	parent.add_child(panel)
	return panel


func _column(parent: Control) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	_passive(box)
	parent.add_child(box)
	return box


func _label(parent: Control, node_name: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", font_size)
	_passive(label)
	parent.add_child(label)
	return label


func _button(parent: Control, node_name: String, title: String, action: Callable) -> Button:
	var button: Button = C1HudButton.new()
	button.name = node_name
	button.text = title
	button.custom_minimum_size.y = 44
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_force_pass_scroll_events = false
	button.focus_mode = Control.FOCUS_ALL
	for state: String in ["normal","hover","pressed","disabled"]:
		var style: StyleBox = get_theme_stylebox(state,"Button").duplicate() as StyleBox
		style.content_margin_left=6
		style.content_margin_right=6
		style.content_margin_top=4
		style.content_margin_bottom=4
		button.add_theme_stylebox_override(state,style)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _passive(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _wrap(label: Label) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _text(data: Dictionary, key: String, fallback: String = "") -> String:
	var value: Variant = data.get(key)
	return str(value) if value is String and not value.is_empty() else fallback


func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _tone(data: Dictionary) -> Color:
	return TONES.get(_text(data, "tone", "normal"), TONES["normal"])


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
