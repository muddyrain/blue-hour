class_name SoundSettingsPanel
extends PanelContainer
## Formal app panel; shares its owner's preferences and never creates a service.

signal closed
signal saved

var preferences: AudioPreferences
var diagnostic: String = ""
var sliders: Dictionary[String, HSlider] = {}
var mute_button: CheckButton
var save_button: Button
var back_button: Button
var message: Label
var _scrim: ColorRect


func _ready() -> void:
	name = "SoundSettings"
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -310
	offset_right = 310
	offset_top = -240
	offset_bottom = 240
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	_scrim = ColorRect.new()
	_scrim.name = "SoundSettingsScrim"
	_scrim.color = Color(0.02, 0.06, 0.10, 0.6)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	get_parent().add_child(_scrim)
	get_parent().move_child(_scrim, get_index())
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visibility_changed.connect(func() -> void: _scrim.visible = visible)
	theme = CampStyle.theme(theme)
	add_theme_stylebox_override("panel", CampStyle.box(CampStyle.PANEL, Color.TRANSPARENT, 28))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	add_child(column)
	var heading: Label = Label.new()
	heading.text = "声音设置"
	heading.add_theme_font_size_override("font_size", 30)
	column.add_child(heading)
	var names: Array[String] = ["总音量", "世界音效", "界面音效"]
	for index: int in range(AudioPreferences.VOLUME_KEYS.size()):
		var key: String = AudioPreferences.VOLUME_KEYS[index]
		var row: HBoxContainer = HBoxContainer.new()
		row.custom_minimum_size.y = 40
		row.add_theme_constant_override("separation", 16)
		column.add_child(row)
		var label: Label = Label.new()
		label.text = names[index]
		label.custom_minimum_size.x = 110
		row.add_child(label)
		var slider: HSlider = HSlider.new()
		slider.name = key
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		var value_label: Label = Label.new()
		value_label.custom_minimum_size.x = 56
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
		sliders[key] = slider
		slider.value_changed.connect(func(value: float) -> void:
			preferences.set_volume(key, value / 100.0)
			value_label.text = "%d%%" % int(value)
		)
		var initial: float = float(preferences.snapshot()[key]) * 100.0
		slider.value = initial
		value_label.text = "%d%%" % int(initial)
	mute_button = CheckButton.new()
	mute_button.text = "总静音"
	mute_button.button_pressed = preferences.snapshot()["muted"]
	mute_button.toggled.connect(preferences.set_muted)
	column.add_child(mute_button)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(0, 54)
	message.text = diagnostic if not diagnostic.is_empty() else "音量立即生效；点击保存后，下次启动继续使用。"
	message.add_theme_font_size_override("font_size", 17)
	message.add_theme_color_override("font_color", CampStyle.MUTED)
	column.add_child(message)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	column.add_child(actions)
	save_button = Button.new()
	save_button.text = "保存声音设置"
	save_button.custom_minimum_size = Vector2(0, 50)
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	CampStyle.primary(save_button)
	save_button.pressed.connect(save)
	actions.add_child(save_button)
	back_button = Button.new()
	back_button.text = "返回 / Esc"
	back_button.custom_minimum_size = Vector2(0, 50)
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.pressed.connect(close_panel)
	actions.add_child(back_button)
	actions.move_child(back_button, 0)
	var focus_order: Array[Control] = []
	for key: String in AudioPreferences.VOLUME_KEYS:
		focus_order.append(sliders[key])
	focus_order.append_array([mute_button, back_button, save_button])
	for index: int in range(focus_order.size()):
		var next: NodePath = focus_order[(index + 1) % focus_order.size()].get_path()
		var previous: NodePath = focus_order[(index + focus_order.size() - 1) % focus_order.size()].get_path()
		focus_order[index].focus_next = next
		focus_order[index].focus_previous = previous
		focus_order[index].focus_neighbor_top = previous
		focus_order[index].focus_neighbor_bottom = next
		if focus_order[index] is BaseButton:
			focus_order[index].focus_neighbor_left = previous
			focus_order[index].focus_neighbor_right = next
	preferences.changed.connect(_show_unsaved)


func _exit_tree() -> void:
	if is_instance_valid(_scrim):
		_scrim.queue_free()
	if preferences.changed.is_connected(_show_unsaved):
		preferences.changed.disconnect(_show_unsaved)


func _show_unsaved() -> void:
	message.text = "音量已立即应用，尚未保存；返回不会自动写盘。"
	message.add_theme_color_override("font_color", CampStyle.MUTED)


func save() -> void:
	var result: Error = preferences.save_preferences()
	if result == OK:
		message.text = "已保存，下次启动将使用这些声音设置。"
		message.add_theme_color_override("font_color", CampStyle.TEAL)
		saved.emit()
	else:
		message.text = "保存失败（%s），先前文件已保留。" % error_string(result)
		message.add_theme_color_override("font_color", CampStyle.DANGER)


func close_panel() -> void:
	if not visible:
		return
	hide()
	closed.emit()
