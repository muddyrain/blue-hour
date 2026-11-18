class_name SortiePauseMenu
extends CanvasLayer
## Presentation only. Main owns pause restoration, departure and durable state.

signal resume_requested
signal bus_requested
signal home_requested
signal quit_requested
signal exit_confirmed
signal exit_cancelled
signal suspend_requested
var suspend_available: bool = false
var suspend_enabled: bool = true
var suspend_message: String = ""

var root: Control
var panel: PanelContainer
var heading: Label
var body: Label
var _body_scroll: ScrollContainer
var _lead: Label
var _safe_actions: GridContainer
var _danger_actions: VBoxContainer
var buttons: Array[Button] = []
var confirming: bool = false


func _ready() -> void:
	layer = 30
	root = Control.new()
	root.theme = CampStyle.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.mouse_force_pass_scroll_events = false
	add_child(root)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.02, 0.08, 0.13, 0.76)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size.x = 780
	panel.mouse_force_pass_scroll_events = false
	var style: StyleBoxFlat = CampStyle.box(CampStyle.INK, CampStyle.EDGE, 28)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	heading = CampStyle.label("", 32)
	column.add_child(heading)
	PixelMenu.divider(column)
	_lead = CampStyle.label("", 20)
	_lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_lead)
	_body_scroll = ScrollContainer.new()
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.follow_focus = true
	_body_scroll.focus_mode = Control.FOCUS_ALL
	_body_scroll.mouse_force_pass_scroll_events = false
	column.add_child(_body_scroll)
	body = Label.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size.x = 700
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 18)
	body.add_theme_constant_override("line_spacing", 5)
	body.add_theme_color_override("font_color", CampStyle.MUTED)
	_body_scroll.add_child(body)
	_safe_actions = GridContainer.new()
	_safe_actions.columns = 2
	_safe_actions.add_theme_constant_override("h_separation", 14)
	_safe_actions.add_theme_constant_override("v_separation", 12)
	column.add_child(_safe_actions)
	PixelMenu.divider(column)
	_danger_actions = VBoxContainer.new()
	column.add_child(_danger_actions)
	for index: int in range(5):
		var button: C1HudButton = C1HudButton.new()
		button.custom_minimum_size.y = 56
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 21)
		button.mouse_force_pass_scroll_events = false
		_safe_actions.add_child(button)
		buttons.append(button)
	root.hide()
	root.resized.connect(_fit_body)
	get_window().focus_exited.connect(func() -> void:
		for button: Button in buttons:
			(button as C1HudButton)._cancel_confirm())


func show_pause(was_paused: bool) -> void:
	confirming = false
	heading.text = "出击已暂停"
	body.text = "发动巴士后，集合所有存活成员即可撤离。\n集合不会取消搜集，队员完成作业后归队；也可再点原搜集点取消。\n" + ("关闭菜单后仍保持原暂停，可在 HUD 继续。" if was_paused else "关闭菜单后继续出击。")
	var labels: Array = ["继续出击（保持原暂停）" if was_paused else "继续出击", "定位巴士并正常撤离", "危险退出到首页…", "退出游戏 / 安全选项…"]
	var actions: Array = [resume_requested.emit, bus_requested.emit, home_requested.emit, quit_requested.emit]
	if suspend_available:
		body.text += "\n安全暂存保留当前战场，不算回营；恢复后须重新暂存。\n再次闪退且无新暂存或完整结果，原旅程仍可能无法继续。"
		labels.append("安全暂存并返回首页")
		actions.append(suspend_requested.emit)
	if not suspend_message.is_empty():
		body.text += "\n" + suspend_message
	_split_message()
	_actions(labels,actions)


func show_exit(title: String, message: String, danger: String, offer_suspend: bool = false) -> void:
	confirming = true
	heading.text = title
	body.text = message
	_split_message()
	var labels: Array = ["取消 / 留在当前页面", danger]
	var actions: Array = [exit_cancelled.emit, exit_confirmed.emit]
	if offer_suspend:
		labels.append("安全暂存并退出游戏" if danger.contains("游戏") else "安全暂存并返回首页")
		actions.append(suspend_requested.emit)
	_actions(labels, actions)


func close() -> void:
	root.hide()
	confirming = false


func _split_message() -> void:
	# Preserve every fact; the first sentence leads while detailed caveats stay readable.
	var lines: PackedStringArray = body.text.split("\n")
	_lead.text = lines[0]
	body.set_meta("full_message", body.text)
	body.text = "\n".join(lines.slice(1))
	_body_scroll.visible = not body.text.is_empty()


func _actions(labels: Array, actions: Array) -> void:
	for index: int in range(buttons.size()):
		var button: Button = buttons[index]
		for connection: Dictionary in button.pressed.get_connections():
			button.pressed.disconnect(connection.callable)
		button.visible = index < labels.size()
		button.disabled = index == 4 and not confirming and not suspend_enabled
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.remove_theme_stylebox_override(state)
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.remove_theme_color_override(state)
		CampStyle.text_button(button)
		button.custom_minimum_size.y = 56
		button.add_theme_font_size_override("font_size", 21)
		if (confirming and index == 2) or (not confirming and index == 0):
			PixelMenu.primary(button)
		elif (confirming and index == 1) or (not confirming and index == 2):
			button.add_theme_color_override("font_color", CampStyle.DANGER)
			button.add_theme_stylebox_override("normal", CampStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 8))
			button.custom_minimum_size.y = 40
			button.add_theme_font_size_override("font_size", 17)
		else:
			button.add_theme_stylebox_override("normal", CampStyle.box(CampStyle.PANEL, CampStyle.EDGE, 10))
		if button.visible:
			button.text = labels[index]
			button.pressed.connect(actions[index])
	# Keep stable signal/test references while placing the safe action before danger.
	var order: Array[int] = [0, 1, 4, 2, 3]
	if confirming:
		order.assign([0, 2, 1, 3, 4])
	for index: int in order:
		var destination: Node = _danger_actions if (confirming and index == 1) or (not confirming and index == 2) else _safe_actions
		if buttons[index].get_parent() != destination:
			buttons[index].reparent(destination)
		destination.move_child(buttons[index], destination.get_child_count() - 1)
		if destination == _danger_actions:
			buttons[index].size_flags_horizontal = Control.SIZE_SHRINK_END
		else:
			buttons[index].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var focusable: Array[Control] = []
	for index: int in order:
		var button: Button = buttons[index]
		if button.visible and not button.disabled:
			focusable.append(button)
	focusable.append(_body_scroll)
	for index: int in range(focusable.size()):
		focusable[index].focus_next = focusable[index].get_path_to(focusable[(index+1)%focusable.size()])
		focusable[index].focus_previous = focusable[index].get_path_to(focusable[(index+focusable.size()-1)%focusable.size()])
	root.show()
	_body_scroll.scroll_vertical = 0
	_fit_body.call_deferred()
	buttons[0].grab_focus.call_deferred()


func _fit_body() -> void:
	if _body_scroll == null or body == null:
		return
	panel.custom_minimum_size.x = minf(780.0, maxf(560.0, root.size.x - 64.0))
	body.custom_minimum_size.x = panel.custom_minimum_size.x - 56.0
	# Error details can be arbitrarily long; preserve the real message in a
	# scrollable reading area while all departure and cancel actions stay visible.
	var line_height: float = float(body.get_line_height())
	var spacing: float = float(body.get_theme_constant("line_spacing"))
	var lines: int = maxi(1, body.get_line_count())
	var text_height: float = float(lines) * line_height + float(lines - 1) * spacing
	text_height = maxf(text_height, body.get_combined_minimum_size().y)
	var available: float = minf(190.0, maxf(78.0, root.size.y - 450.0))
	# Keep the last visible line whole when a long failure message needs scrolling.
	var visible_lines: int = maxi(1, floori((available + spacing) / maxf(1.0, line_height + spacing)))
	var reading_height: float = float(visible_lines) * line_height + float(visible_lines - 1) * spacing
	_body_scroll.custom_minimum_size.y = minf(text_height, reading_height)
	panel.reset_size()
