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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_top()
	_build_actions()
	_build_help()
	# Deliberately no initial focus: Space continues to mean pause in the world.
	_pause_button.focus_next = _pause_button.get_path_to(_bus_button)
	_bus_button.focus_next = _bus_button.get_path_to(_help_button)
	_help_button.focus_next = _help_button.get_path_to(_pause_button)
	_pause_button.focus_previous = _pause_button.get_path_to(_help_button)
	_help_button.focus_previous = _help_button.get_path_to(_bus_button)
	_bus_button.focus_previous = _bus_button.get_path_to(_pause_button)
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
	_progress.text = "%s    搜集 %s    击退 %s" % [
		_text(state, "day_text", "天数 —"),
		_text(state, "search_progress_text", "—"), _text(state, "defeated_text", "—"),
	]
	_currency.text = "货币 %s" % _text(state, "currency_text", "—")
	var delta: String = _text(state, "currency_delta_text")
	if not delta.is_empty():
		_currency.text += "    本次 %s" % delta
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
	_bus_status.text = _text(state, "bus_status_text", "巴士状态未提供")
	_bus_status.add_theme_color_override("font_color", _tone(_dictionary(state.get("bus", {}))))
	_bus_button.text = _text(state, "bus_action_label", "发动巴士")
	_bus_button.disabled = state.get("bus_action_enabled", false) != true
	_hint.text = _text(state, "status_hint")
	_hint.visible = not _hint.text.is_empty()
	var members: Variant = state.get("survivors", [])
	for index: int in range(2):
		var member: Dictionary = {}
		if members is Array:
			for value: Variant in members:
				if value is Dictionary and value.get("id", 0) == index + 1:
					member = value
					break
		_refresh_member(index, member)
	# Disabled native buttons can still receive explicit focus neighbors.
	# Release existing focus and remove this action from keyboard navigation.
	if _bus_button.disabled:
		_bus_button.release_focus()
	_bus_button.focus_mode = Control.FOCUS_NONE if _bus_button.disabled else Control.FOCUS_ALL


func hide_screen() -> void:
	hide()


func _build_top() -> void:
	var panel: PanelContainer = _panel(self, "MissionPanel")
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 16
	panel.offset_top = 16
	panel.offset_right = -16
	var row: HBoxContainer = HBoxContainer.new()
	_passive(row)
	panel.add_child(row)
	var mission_box: VBoxContainer = _column(row)
	mission_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mission = _label(mission_box, "MissionTitle", 20)
	_wrap(_mission)
	_progress = _label(mission_box, "Progress", 16)
	_wrap(_progress)
	_currency = _label(mission_box, "Currency", 16)
	_wrap(_currency)
	_time_box = _column(row)
	_time_box.custom_minimum_size.x = 160
	_time_box.size_flags_horizontal = Control.SIZE_FILL
	_time_label = _label(_time_box, "TimeLabel", 16)
	_time_text = _label(_time_box, "TimeText", 26)
	_time_hint = _label(_time_box, "TimeHint", 15)
	for label: Label in [_time_label, _time_text, _time_hint]:
		_wrap(label)
	for index: int in range(2):
		_build_member(row, index)


func _build_member(parent: Control, index: int) -> void:
	var box: VBoxContainer = _column(parent)
	box.name = "Member%d" % (index + 1)
	box.custom_minimum_size.x = 176
	var title: Label = _label(box, "Identity", 18)
	title.add_theme_color_override("font_color", IDENTITY_COLORS[index])
	_wrap(title)
	var health: Label = _label(box, "Health", 16)
	_wrap(health)
	var bar: ProgressBar = ProgressBar.new()
	bar.name = "HealthBar"
	bar.custom_minimum_size.y = 6
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	_passive(bar)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = IDENTITY_COLORS[index]
	bar.add_theme_stylebox_override("fill", fill)
	box.add_child(bar)
	_members.append({"title": title, "health": health, "bar": bar})


func _build_actions() -> void:
	var panel: PanelContainer = _panel(self, "ActionsPanel")
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -596
	panel.offset_right = -16
	panel.offset_top = -156
	panel.offset_bottom = -16
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var column: VBoxContainer = _column(panel)
	var status_row: HBoxContainer = HBoxContainer.new()
	_passive(status_row)
	column.add_child(status_row)
	_pause_state = _label(status_row, "PauseState", 16)
	_pause_state.custom_minimum_size.x = 80
	_bus_status = _label(status_row, "BusStatus", 18)
	_bus_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wrap(_bus_status)
	_hint = _label(column, "StatusHint", 16)
	_wrap(_hint)
	var row: HBoxContainer = HBoxContainer.new()
	_passive(row)
	column.add_child(row)
	_pause_button = _button(row, "PauseButton", "暂停", _request_pause)
	_pause_button.custom_minimum_size.x = 108
	_bus_button = _button(row, "BusButton", "发动巴士", _request_bus)
	_bus_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bus_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_help() -> void:
	_help_button = _button(self, "HelpButton", "操作帮助", _toggle_help)
	_help_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help_button.offset_left = 16
	_help_button.offset_top = -60
	_help_button.offset_right = 144
	_help_button.offset_bottom = -16
	_help = _panel(self, "HelpPanel")
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.offset_left = 16
	_help.offset_right = 544
	_help.offset_top = -252
	_help.offset_bottom = -72
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var content: Label = _label(_help, "HelpText", 18)
	content.text = "左键地面：移动 / 改目标\n左键补给店：搜集；再点同一建筑取消\n鼠标点击后空格：暂停 / 继续\nTab 切换按钮；聚焦时 Space / Enter 确认\n暂停中仍可下令；WASD 镜头；滚轮缩放"
	_wrap(content)
	_help.hide()


func _refresh_member(index: int, state: Dictionary) -> void:
	var title: Label = _members[index]["title"]
	var health: Label = _members[index]["health"]
	var bar: ProgressBar = _members[index]["bar"]
	title.text = "%02d  %s" % [index + 1, _text(state, "label", "队员 %d" % (index + 1))]
	var hp: Variant = state.get("hp")
	var maximum: Variant = state.get("max_hp")
	if not _finite_number(hp) or not _finite_number(maximum) or float(maximum) <= 0.0:
		health.text = "生命 — / —"
		bar.value = 0.0
		bar.modulate.a = 0.35
		return
	var safe_hp: float = clampf(float(hp), 0.0, float(maximum))
	health.text = "生命 %s / %s" % [str(ceili(safe_hp)), str(ceili(float(maximum)))]
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


func _toggle_help() -> void:
	_help.visible = not _help.visible
	_help_button.text = "收起帮助" if _help.visible else "操作帮助"


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_help.hide()
		_help_button.text = "操作帮助"
		for button: Button in [_pause_button, _bus_button, _help_button]:
			button.release_focus()


func _panel(parent: Control, node_name: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Wheel events must not escape an opaque panel into the camera behind it.
	panel.mouse_force_pass_scroll_events = false
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
