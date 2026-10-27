class_name B1Audition
extends Control
## Independent simulated events. Does not instantiate or control a sortie.

const CUE_LABELS: Dictionary = {
	&"ui_confirm": "界面确认", &"ui_back": "界面返回", &"fire": "开火",
	&"hit": "命中", &"collect_complete": "搜集完成", &"bus_start": "巴士发动",
}

var preferences: AudioPreferences
var audio: B1AudioService
var settings_override: String = ""
var _sliders: Dictionary[String, HSlider] = {}
var _numbers: Dictionary[String, Label] = {}
var _mute: CheckButton
var _pause: Button
var _status: Label
var _clock: Label
var _demo_timer: Timer
var _world: Node
var _world_elapsed: float = 0.0
var _world_paused: bool = false
var _burst_left: int = 0
var _burst_clock: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var path: String = settings_override
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--b1-settings="):
			path = argument.trim_prefix("--b1-settings=")
	# The audition never falls back to the app's user directory.
	var local_root: String = ProjectSettings.globalize_path("res://.local/")
	var normalized: String = path.replace("\\", "/").simplify_path()
	if not normalized.is_absolute_path() or not normalized.begins_with(local_root):
		push_error("B1 audition requires --b1-settings=<absolute B-worktree .local path>")
		get_tree().quit(2)
		return
	preferences = AudioPreferences.new(normalized)
	audio = B1AudioService.new(preferences)
	add_child(audio)
	_build_ui()
	preferences.diagnosed.connect(_show_diagnostic)
	audio.diagnosed.connect(_show_diagnostic)
	preferences.changed.connect(_sync_controls)
	preferences.load_preferences()
	_sync_controls()
	_world = Node.new()
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)
	_demo_timer = Timer.new()
	_demo_timer.wait_time = 0.1
	_demo_timer.timeout.connect(_tick_world)
	_world.add_child(_demo_timer)
	_demo_timer.start()
	print("B1_AUDITION_READY settings=%s audio_driver=%s" % [normalized, AudioServer.get_driver_name()])


func _process(delta: float) -> void:
	if _burst_left <= 0 or _world_paused:
		return
	_burst_clock -= delta
	if _burst_clock <= 0.0:
		audio.play_world(&"fire")
		audio.play_world(&"hit")
		_burst_left -= 1
		_burst_clock = 0.07


func _exit_tree() -> void:
	if is_instance_valid(audio):
		audio.shutdown()
	# This scene owns only the demonstration tree pause.
	if _world_paused:
		get_tree().paused = false


func set_demo_paused(value: bool) -> void:
	_world_paused = value
	audio.set_world_paused(value)
	get_tree().paused = value
	_pause.text = "恢复世界" if value else "暂停世界"
	audio.play_ui(&"ui_confirm")


func stop_demo() -> void:
	_burst_left = 0
	audio.stop_world()
	_status.text = "世界声音已停止；仍可使用界面声音。"


func _build_ui() -> void:
	# Same palette, system font fallback and base button treatment as main.tscn.
	theme = Theme.new()
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC"])
	theme.default_font = font
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", Color(0.80, 0.87, 0.89))
	for style_name: String in ["normal", "hover", "pressed", "focus"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.11, 0.23, 0.30) if style_name == "normal" else Color(0.17, 0.36, 0.44)
		style.set_corner_radius_all(8)
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		if style_name == "focus":
			style.bg_color = Color.TRANSPARENT
			style.set_border_width_all(2)
			style.border_color = Color(0.5, 0.9, 0.85)
		theme.set_stylebox(style_name, "Button", style)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var scroll: ScrollContainer = ScrollContainer.new()
	margin.add_child(scroll)
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 16)
	scroll.add_child(column)
	var heading: Label = _label("蓝时归航 · 声音试听", column)
	heading.add_theme_font_size_override("font_size", 32)
	heading.add_theme_color_override("font_color", Color(0.43, 0.78, 0.77))
	_label("B1 原创候选 / 按钮模拟事件，尚未接入正常出击。", column)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	column.add_child(grid)
	for cue: StringName in CUE_LABELS:
		_button(CUE_LABELS[cue], grid, _play_cue.bind(cue))
	for key: String in AudioPreferences.VOLUME_KEYS:
		var row: HBoxContainer = HBoxContainer.new()
		column.add_child(row)
		var title: Label = _label({"master_volume": "总音量", "sfx_volume": "世界音效", "ui_volume": "界面音量"}[key], row)
		title.custom_minimum_size.x = 135
		var slider: HSlider = HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(240, 36)
		slider.value_changed.connect(_volume_changed.bind(key))
		row.add_child(slider)
		_sliders[key] = slider
		_numbers[key] = _label("", row)
		_numbers[key].custom_minimum_size.x = 65
	_mute = CheckButton.new()
	_mute.text = "总静音（保留音量）"
	_mute.toggled.connect(preferences.set_muted)
	column.add_child(_mute)
	var world_row: HBoxContainer = HBoxContainer.new()
	world_row.add_theme_constant_override("separation", 12)
	column.add_child(world_row)
	_pause = _button("暂停世界", world_row, _toggle_pause)
	_button("停止世界声音", world_row, stop_demo)
	_button("连续触发 × 12", world_row, _start_burst)
	_clock = _label("模拟世界：0.0 秒", column)
	_label("暂停会冻结世界与已有世界声音；界面仍可操作。暂停期间的新世界声音丢弃。", column)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	_button("保存声音设置", actions, _save)
	_button("重新加载", actions, _reload)
	_button("退出试听", actions, _quit)
	_status = _label("", column)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 64
	_status.add_theme_font_size_override("font_size", 16)


func _label(text: String, parent: Node) -> Label:
	var label: Label = Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _button(text: String, parent: Node, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _sync_controls() -> void:
	var values: Dictionary = preferences.snapshot()
	for key: String in _sliders:
		_sliders[key].set_value_no_signal(float(values[key]) * 100.0)
		_numbers[key].text = "%d%%" % roundi(float(values[key]) * 100.0)
	_mute.set_pressed_no_signal(values["muted"])


func _volume_changed(value: float, key: String) -> void:
	preferences.set_volume(key, value / 100.0)


func _play_cue(cue: StringName) -> void:
	var played: bool = audio.play_ui(cue) if cue in [&"ui_confirm", &"ui_back"] else audio.play_world(cue)
	_status.text = "%s：%s" % [CUE_LABELS[cue], "已触发" if played else "未播放（暂停、限频或并发已满）"]


func _show_diagnostic(message: String) -> void:
	_status.text = message


func _tick_world() -> void:
	_world_elapsed += 0.1
	_clock.text = "模拟世界：%.1f 秒" % _world_elapsed


func _toggle_pause() -> void:
	set_demo_paused(not _world_paused)


func _start_burst() -> void:
	if _world_paused:
		_status.text = "请恢复世界后再连续试听"
		return
	_burst_left = 12
	_burst_clock = 0.0


func _save() -> void:
	if preferences.save_preferences() == OK:
		audio.play_ui(&"ui_confirm")


func _reload() -> void:
	preferences.load_preferences()


func _quit() -> void:
	audio.shutdown()
	get_tree().quit()
