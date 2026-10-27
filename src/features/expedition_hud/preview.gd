class_name C1HudPreview
extends Node
## Explicit test harness. Only this controller may pause the real SceneTree.

const HudScene: PackedScene = preload("res://src/features/expedition_hud/expedition_hud.tscn")
const Background = preload("res://src/features/expedition_hud/preview_background.gd")
const HudTheme: Theme = preload("res://assets/ui/c1/hud_theme.tres")

var hud: C1ExpeditionHud
var world_clicks: int = 0
var world_scrolls: int = 0
var shortcut_count: int = 0
var pause_intents: int = 0
var resume_intents: int = 0
var bus_intents: int = 0
var sample_index: int = 0
var background: Node2D
var _sample: Dictionary = {}
var _label: Label
var _focus_label: Label
var _probe_label: Label
var _pause_test: Button
var _visibility_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	background = Background.new()
	add_child(background)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = HudScene.instantiate() as C1ExpeditionHud
	layer.add_child(hud)
	hud.pause_requested.connect(_on_pause)
	hud.resume_requested.connect(_on_resume)
	hud.bus_start_requested.connect(_on_bus)
	_build_toolbar(layer)
	for node: Node in hud.find_children("*", "Button", true, false):
		node.focus_entered.connect(_update_probe.call_deferred)
		node.focus_exited.connect(_update_probe.call_deferred)
	hud.find_child("HelpPanel", true, false).visibility_changed.connect(_update_probe.call_deferred)
	select_sample(0)
	if DisplayServer.get_name() != "headless":
		get_window().title = "C1 出击 HUD · UI 样本（未接入正式出击）"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--c1-sample="):
			select_sample(int(argument.get_slice("=", 1)))
	print("C1_PREVIEW display=%s viewport=%s" % [DisplayServer.get_name(), get_viewport().get_visible_rect().size])


func _unhandled_input(event: InputEvent) -> void:
	# Same GUI-before-world path as the verified Expedition._unhandled_input.
	if event.is_action_pressed("squad_command"):
		world_clicks += 1
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause_sortie"):
		shortcut_count += 1
		set_engine_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_zoom_in") or event.is_action_pressed("camera_zoom_out"):
		world_scrolls += 1
		get_viewport().set_input_as_handled()
	_update_probe()


func select_sample(index: int) -> void:
	get_tree().paused = false
	sample_index = posmod(index, C1HudSamples.TITLES.size())
	_sample = C1HudSamples.make_sample(sample_index)
	hud.refresh(_sample)
	_update_probe()


func set_engine_paused(value: bool) -> void:
	get_tree().paused = value
	_sample["paused"] = value
	hud.refresh(_sample)
	_update_probe()


func _on_pause() -> void:
	pause_intents += 1
	set_engine_paused(true)


func _on_resume() -> void:
	resume_intents += 1
	set_engine_paused(false)


func _on_bus() -> void:
	bus_intents += 1
	# An intent counter demonstrates the boundary without simulating evacuation.
	_update_probe()


func _build_toolbar(layer: CanvasLayer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "PreviewToolbar"
	panel.theme = HudTheme
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_force_pass_scroll_events = false
	layer.add_child(panel)
	panel.position = Vector2(16, 176)
	panel.size = Vector2(760, 100)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	column.add_child(_label)
	_probe_label = Label.new()
	_probe_label.add_theme_font_size_override("font_size", 14)
	column.add_child(_probe_label)
	_focus_label = Label.new()
	_focus_label.add_theme_font_size_override("font_size", 14)
	column.add_child(_focus_label)
	var row: HBoxContainer = HBoxContainer.new()
	column.add_child(row)
	_preview_button(row, "上一样本", func() -> void: select_sample(sample_index - 1))
	_preview_button(row, "下一样本", func() -> void: select_sample(sample_index + 1))
	_pause_test = _preview_button(row, "", func() -> void: set_engine_paused(not get_tree().paused))
	_visibility_button = _preview_button(row, "隐藏 HUD", _toggle_hud)


func _preview_button(parent: Control, title: String, action: Callable) -> Button:
	var button: Button = C1HudButton.new()
	button.text = title
	button.add_theme_font_size_override("font_size", 16)
	button.mouse_force_pass_scroll_events = false
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _toggle_hud() -> void:
	hud.visible = not hud.visible
	_visibility_button.text = "隐藏 HUD" if hud.visible else "显示 HUD"


func _update_probe() -> void:
	if not is_instance_valid(hud):
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	_focus_label.text = "焦点 %s  |  帮助 %s" % [str(focus.name) if focus != null else "无", "开" if hud.find_child("HelpPanel", true, false).visible else "关"]
	_label.text = "UI 样本 %d / %d · %s · 原创静态预览背景" % [sample_index + 1, C1HudSamples.TITLES.size(), C1HudSamples.TITLES[sample_index]]
	_probe_label.text = "世界点击 %d  滚轮 %d  |  意图 暂停 %d / 继续 %d / 巴士 %d  |  空格快捷键 %d" % [world_clicks, world_scrolls, pause_intents, resume_intents, bus_intents, shortcut_count]
	_pause_test.text = "引擎暂停：开" if get_tree().paused else "引擎暂停：关"
