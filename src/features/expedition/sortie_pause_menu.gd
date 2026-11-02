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
var buttons: Array[Button] = []
var confirming: bool = false


func _ready() -> void:
	layer = 30
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.mouse_force_pass_scroll_events = false
	add_child(root)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.03, 0.07, 0.12, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size.x = 680
	panel.mouse_force_pass_scroll_events = false
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("162d41")
	style.border_color = Color("8fb9cd")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 30)
	column.add_child(heading)
	body = Label.new()
	body.custom_minimum_size.x = 616
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 18)
	column.add_child(body)
	for index: int in range(5):
		var button: C1HudButton = C1HudButton.new()
		button.custom_minimum_size.y = 44
		button.add_theme_font_size_override("font_size", 18)
		column.add_child(button)
		buttons.append(button)
	root.hide()
	get_window().focus_exited.connect(func() -> void:
		for button: Button in buttons:
			(button as C1HudButton)._cancel_confirm())


func show_pause(was_paused: bool) -> void:
	confirming = false
	heading.text = "已暂停"
	body.text = "如何撤离\n发动巴士后，集合所有存活成员；搜集未完成也可撤离。\n集合不会取消搜集，工人完成后再归队。\n" + ("关闭菜单后仍保持原暂停，可在 HUD 继续。" if was_paused else "关闭菜单后继续出击。")
	var labels: Array = ["继续出击（保持原暂停）" if was_paused else "继续出击", "定位巴士并正常撤离", "危险退出到首页…", "退出游戏 / 安全选项…"]
	var actions: Array = [resume_requested.emit, bus_requested.emit, home_requested.emit, quit_requested.emit]
	if suspend_available:
		body.text += "\n暂存后可继续原战场，不算回营；每次恢复后须重新暂存。\n再次闪退且无新暂存或完整结果，原旅程仍可能无法继续。"
		labels.append("安全暂存并返回首页")
		actions.append(suspend_requested.emit)
	if not suspend_message.is_empty():
		body.text += "\n" + suspend_message
	_actions(labels,actions)


func show_exit(title: String, message: String, danger: String, offer_suspend: bool = false) -> void:
	confirming = true
	heading.text = title
	body.text = message
	var labels: Array = ["取消 / 留在当前页面", danger]
	var actions: Array = [exit_cancelled.emit, exit_confirmed.emit]
	if offer_suspend:
		labels.append("安全暂存并退出游戏" if danger.contains("游戏") else "安全暂存并返回首页")
		actions.append(suspend_requested.emit)
	_actions(labels, actions)


func close() -> void:
	root.hide()
	confirming = false


func _actions(labels: Array, actions: Array) -> void:
	for index: int in range(buttons.size()):
		var button: Button = buttons[index]
		for connection: Dictionary in button.pressed.get_connections():
			button.pressed.disconnect(connection.callable)
		button.visible = index < labels.size()
		button.disabled = index == 4 and not confirming and not suspend_enabled
		if button.visible:
			button.text = labels[index]
			button.pressed.connect(actions[index])
	# Keep stable signal/test references while placing the safe action before danger.
	var column: Node = buttons[0].get_parent()
	var order: Array[int] = [0, 1, 4, 2, 3]
	if confirming:
		order.assign([0, 2, 1, 3, 4])
	for index: int in range(order.size()):
		column.move_child(buttons[order[index]], 2 + index)
	var focusable: Array[Button] = []
	for index: int in order:
		var button: Button = buttons[index]
		if button.visible and not button.disabled:
			focusable.append(button)
	for index: int in range(focusable.size()):
		focusable[index].focus_next = focusable[index].get_path_to(focusable[(index+1)%focusable.size()])
		focusable[index].focus_previous = focusable[index].get_path_to(focusable[(index+focusable.size()-1)%focusable.size()])
	root.show()
	buttons[0].grab_focus.call_deferred()
