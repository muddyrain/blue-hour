class_name C1ExpeditionHud
extends Control
## Read-only screen HUD. Parent owns gameplay, shortcut handling and CanvasLayer.
## Call refresh after adding to the tree. No timers, Input polling or world writes.

signal pause_requested
signal resume_requested
signal objective_locate_requested(objective_id: String)
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
var persona_details: PersonaDetails
var _persona_cards: Array[PersonaCard] = []
var _persona_models: Dictionary = {}
var _persona_id: int = 0
var _members_panel: PanelContainer
var _has_exploration_rows: bool=false
var _exploration_objectives: ExplorationObjectives
var _member_scroll: ScrollContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_top()
	_build_actions()
	_build_help()
	# Let native traversal include objective, threat, member and skill controls.
	# No initial focus: Space continues to mean pause in the world.
	visibility_changed.connect(_on_visibility_changed)
	get_viewport().size_changed.connect(_fit_persona_members)
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
	var rows: Array[Dictionary]=[]
	for row: Dictionary in state.get("exploration_objectives",[]): rows.append(row)
	_has_exploration_rows=not rows.is_empty()
	_exploration_objectives.present(rows)
	_exploration_objectives.visible=not rows.is_empty() and _objective_expanded
	_objective.text=_text(state,"objective")
	_objective.visible=_objective_expanded and not _objective.text.is_empty()
	_objective_toggle.text = "−" if _objective_expanded else "+"
	_progress.visible = not _has_exploration_rows
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
	_time_hint.text = _text(time_data, "compact_hint", _text(time_data, "hint").trim_prefix("威胁 · "))
	_time_hint.tooltip_text = _text(time_data, "hint")
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
	if _bus_button.disabled: _bus_button.release_focus()
	_bus_button.focus_mode=Control.FOCUS_NONE if _bus_button.disabled else Control.FOCUS_ALL
	var persona_mode: bool=not members.is_empty() and members[0].has("persona")
	_members_panel.offset_left=-188 if persona_mode else -224
	# Old HUD rows retain their reviewed direct VBox layout. Only new cards
	# need a bounded scrolling client; otherwise ScrollContainer shrinks labels.
	if persona_mode and _members_parent.get_parent()!=_member_scroll:
		_members_parent.reparent(_member_scroll)
	elif not persona_mode and _members_parent.get_parent()==_member_scroll:
		_members_parent.reparent(_member_scroll.get_parent())
	_member_scroll.visible=persona_mode
	_members_panel.anchor_bottom=0.0
	_members_panel.offset_bottom=0
	for row: Dictionary in _members: row.box.visible=not persona_mode
	for card: PersonaCard in _persona_cards: card.visible=persona_mode
	if persona_mode:
		_persona_models.clear()
		while _persona_cards.size()<members.size():
			var card: PersonaCard=PersonaCard.new()
			_members_parent.add_child(card)
			card.selected.connect(open_persona)
			_persona_cards.append(card)
		for index: int in range(_persona_cards.size()):
			_persona_cards[index].visible=index<members.size()
			if index<members.size():
				var model: Dictionary=members[index].persona
				_persona_models[int(model.id)]=model
				_persona_cards[index].present(model,true)
				_compact_persona_card(_persona_cards[index])
		if _persona_id>0 and _persona_models.has(_persona_id): persona_details.present(_persona_models[_persona_id])
		_fit_persona_members()
		# Font/theme minimum sizes settle after compact cards are populated.
		_fit_persona_members.call_deferred()
		return
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
	panel.custom_minimum_size.x = 264
	panel.size.x = 264
	var mission_box: VBoxContainer = _column(panel)
	mission_box.add_theme_constant_override("separation",4)
	var heading: HBoxContainer = HBoxContainer.new()
	heading.add_theme_constant_override("separation",8)
	_passive(heading)
	mission_box.add_child(heading)
	_mission = _label(heading, "MissionTitle", 16)
	_mission.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mission.clip_text = true
	_mission.mouse_filter = Control.MOUSE_FILTER_PASS
	_objective_toggle = _button(heading,"ObjectiveToggle","−",_toggle_objective)
	_objective_toggle.custom_minimum_size = Vector2(28,24)
	_objective_toggle.tooltip_text = "展开 / 收起目标"
	_objective_toggle.add_theme_font_size_override("font_size",13)
	_progress = _label(mission_box, "Progress", 14)
	_objective = _label(mission_box,"Objective",15)
	_wrap(_objective)
	_exploration_objectives=ExplorationObjectives.new()
	mission_box.add_child(_exploration_objectives)
	_exploration_objectives.locate_requested.connect(func(id: String) -> void: objective_locate_requested.emit(id))
	_exploration_objectives.hide()
	var time_panel: PanelContainer = _panel(self,"TimePanel")
	time_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	time_panel.offset_left = -152
	time_panel.offset_right = 152
	time_panel.offset_top = 16
	_time_box = _column(time_panel)
	_time_box.add_theme_constant_override("separation",3)
	_time_box.mouse_filter = Control.MOUSE_FILTER_PASS
	var time_row: HBoxContainer = HBoxContainer.new()
	time_row.add_theme_constant_override("separation",12)
	_passive(time_row)
	_time_box.add_child(time_row)
	_day = _label(time_row,"Day",14)
	_day.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_time_label = _label(_time_box, "TimeLabel", 13)
	_time_label.hide()
	_time_text = _label(time_row, "TimeText", 25)
	_time_text.custom_minimum_size.x = 78
	_time_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_hint = _label(time_row, "TimeHint", 13)
	_time_hint.custom_minimum_size.x = 58
	_time_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_time_hint.clip_text = true
	var explanation: Button = _button(self,"ThreatExplanation","?",_toggle_threat)
	explanation.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	explanation.offset_left=116
	explanation.offset_right=144
	explanation.offset_top=24
	explanation.offset_bottom=50
	explanation.custom_minimum_size=Vector2(28,26)
	explanation.add_theme_font_size_override("font_size",13)
	explanation.tooltip_text="查看当前威胁；不暂停行动。"
	_threat_details = _panel(self,"ThreatDetails")
	_threat_details.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_threat_details.offset_left=-160
	_threat_details.offset_right=160
	_threat_details.offset_top=76
	_threat_content = _label(_threat_details,"ThreatText",15)
	_wrap(_threat_content)
	_threat_details.mouse_filter=Control.MOUSE_FILTER_STOP
	_threat_details.hide()
	var resource_panel: PanelContainer = _panel(self,"ResourcesPanel")
	resource_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	resource_panel.offset_left=-264
	resource_panel.offset_right=-16
	resource_panel.offset_top=16
	var resources: HBoxContainer = HBoxContainer.new()
	resources.add_theme_constant_override("separation",8)
	_passive(resources)
	resource_panel.add_child(resources)
	_currency = _label(resources,"Currency",13)
	_wrap(_currency)
	_currency.mouse_filter=Control.MOUSE_FILTER_PASS
	_pause_button = _button(resources,"PauseButton","暂停",_request_pause)
	_pause_button.custom_minimum_size=Vector2(44,32)
	_pause_button.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	_pause_button.add_theme_font_size_override("font_size",14)
	var members_panel: PanelContainer = _panel(self,"MembersPanel")
	_members_panel=members_panel
	members_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	members_panel.offset_left=-224
	members_panel.offset_right=-16
	members_panel.offset_top=88
	var list: VBoxContainer = _column(members_panel)
	_label(list,"TeamTitle",12).text="行动小队"
	_members_parent = VBoxContainer.new()
	_members_parent.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_members_parent.add_theme_constant_override("separation",4)
	_passive(_members_parent)
	_member_scroll=ScrollContainer.new()
	_member_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_member_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_member_scroll.follow_focus=true
	_member_scroll.mouse_force_pass_scroll_events=false
	list.add_child(_member_scroll)
	_member_scroll.add_child(_members_parent)
	for index: int in range(2):
		_build_member(_members_parent,index)
	_member_details_panel = _panel(self,"MemberDetails")
	_member_details_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_member_details_panel.offset_left=-532
	_member_details_panel.offset_right=-232
	_member_details_panel.offset_top=180
	_member_details_panel.mouse_filter=Control.MOUSE_FILTER_STOP
	_member_details = _label(_member_details_panel,"MemberText",15)
	_wrap(_member_details)
	_member_details_panel.hide()
	persona_details=PersonaDetails.new()
	add_child(persona_details)
	persona_details.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	persona_details.offset_left=-620
	persona_details.offset_right=-200
	persona_details.offset_top=88
	persona_details.offset_bottom=-72
	persona_details.anchor_bottom=1.0
	persona_details.closed.connect(func() -> void: _persona_id=0)
	persona_details.hide()


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
	panel.offset_left = -144
	panel.offset_right = 144
	panel.offset_top = -68
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
	_pause_state.hide()
	_bus_status = _label(status, "BusStatus", 12)
	_wrap(_bus_status)
	_bus_button = _button(row, "BusButton", "发动巴士", _request_bus)
	_bus_button.custom_minimum_size=Vector2(124,32)
	_bus_button.add_theme_font_size_override("font_size",14)
	_bus_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint = _label(self, "StatusHint", 14)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left=-260
	_hint.offset_right=260
	_hint.offset_top=-104
	_hint.offset_bottom=-72
	_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_hint.clip_text=true
	_hint.mouse_filter=Control.MOUSE_FILTER_PASS
	_hint.add_theme_color_override("font_outline_color",Color("10232b"))
	_hint.add_theme_constant_override("outline_size",3)


func _build_help() -> void:
	_help_button = _button(self, "HelpButton", "?", _toggle_help)
	_help_button.tooltip_text="操作帮助"
	_help_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help_button.offset_left = 16
	_help_button.offset_top = -48
	_help_button.offset_right = 48
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
	_help.mouse_filter=Control.MOUSE_FILTER_STOP
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
	_objective_toggle.text="−" if _objective_expanded else "+"
	_exploration_objectives.visible=_objective_expanded and _has_exploration_rows


func _toggle_threat() -> void:
	_threat_details.visible=not _threat_details.visible


func open_persona(id: int) -> void:
	if not _persona_models.has(id): return
	_persona_id=id
	persona_details.present(_persona_models[id])
	persona_details.grab_focus()


func _toggle_member(index: int) -> void:
	_member_details_panel.visible=not (_member_details_panel.visible and _member_detail_index==index)
	_member_detail_index=index
	_member_details.text=String(_members[index].get("detail",""))


func _toggle_help() -> void:
	_help.visible = not _help.visible
	_help_button.text = "×" if _help.visible else "?"


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_help.hide()
		_threat_details.hide()
		_member_details_panel.hide()
		_help_button.text = "?"
		for button: Button in [_pause_button, _bus_button, _help_button]:
			button.release_focus()


func _panel(parent: Control, node_name: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Wheel events must not escape an opaque panel into the camera behind it.
	panel.mouse_force_pass_scroll_events = false
	var style: StyleBoxFlat = get_theme_stylebox("panel","PanelContainer").duplicate() as StyleBoxFlat
	style.content_margin_left=8
	style.content_margin_right=8
	style.content_margin_top=6
	style.content_margin_bottom=6
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


func _fit_persona_members() -> void:
	if _persona_cards.is_empty() or not _persona_cards[0].visible: return
	var height: float=0.0
	var count: int=0
	for card: PersonaCard in _persona_cards:
		if card.visible:
			height+=card.get_combined_minimum_size().y
			count+=1
	height+=4.0*maxi(0,count-1)
	var client_height: float=maxf(40.0,get_viewport_rect().size.y-88.0-16.0-40.0)
	_member_scroll.custom_minimum_size.y=minf(height,client_height)
	_members_panel.reset_size()


func _compact_persona_card(card: PersonaCard) -> void:
	# Only field presentation changes. The shared card retains its complete model
	# and the same details for camp, rescue and field selection.
	card.custom_minimum_size.x=148
	card.portrait_button.custom_minimum_size=Vector2(40,40)
	card.info_button.custom_minimum_size=Vector2(22,24)
	card.primary_label.add_theme_font_size_override("font_size",13)
	card.name_label.hide()
	card.health_label.hide()
	card.ammo_label.hide()
	card.positive_label.get_parent().hide()
	card.health_bar.custom_minimum_size.y=4
	card.health_bar.tooltip_text=card.health_label.text
	card.status_label.add_theme_font_size_override("font_size",12)
	card.status_label.text=_short_activity(card.status_label.text)
	card.reset_size()


func _short_activity(value: String) -> String:
	# The complete destination stays on the tooltip and in the selected detail.
	if value.begins_with("搜寻") or value.begins_with("搜刮"): return "搜刮中"
	if value.begins_with("前往"): return "前往目标"
	if value.contains("阵亡"): return "阵亡"
	return value
