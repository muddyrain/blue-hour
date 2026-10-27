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


func _ready() -> void:
	name = "SoundSettings"
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -280
	offset_right = 280
	offset_top = -232
	offset_bottom = 232
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("122d39")
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	add_theme_stylebox_override("panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	add_child(column)
	var heading: Label = Label.new()
	heading.text = "声音设置"
	heading.add_theme_font_size_override("font_size", 30)
	column.add_child(heading)
	var names: Array[String] = ["总音量", "世界音效", "界面音效"]
	for index: int in range(AudioPreferences.VOLUME_KEYS.size()):
		var key: String = AudioPreferences.VOLUME_KEYS[index]
		var row: HBoxContainer = HBoxContainer.new()
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
	message.custom_minimum_size = Vector2(490, 66)
	message.text = diagnostic if not diagnostic.is_empty() else "音量立即生效；点击保存后，下次启动继续使用。"
	message.add_theme_font_size_override("font_size", 17)
	column.add_child(message)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	column.add_child(actions)
	save_button = Button.new()
	save_button.text = "保存声音设置"
	save_button.custom_minimum_size = Vector2(230, 46)
	save_button.pressed.connect(save)
	actions.add_child(save_button)
	back_button = Button.new()
	back_button.text = "返回营地 / Esc"
	back_button.custom_minimum_size = Vector2(230, 46)
	back_button.pressed.connect(close_panel)
	actions.add_child(back_button)
	preferences.changed.connect(_show_unsaved)


func _exit_tree() -> void:
	if preferences.changed.is_connected(_show_unsaved):
		preferences.changed.disconnect(_show_unsaved)


func _show_unsaved() -> void:
	message.text = "音量已立即应用，尚未保存；返回不会自动写盘。"


func save() -> void:
	var result: Error = preferences.save_preferences()
	if result == OK:
		message.text = "已保存，下次启动将使用这些声音设置。"
		saved.emit()
	else:
		message.text = "保存失败（%s），先前文件已保留。" % error_string(result)


func close_panel() -> void:
	if not visible:
		return
	hide()
	closed.emit()
