extends SceneTree
## Engine-injected events through the actual GUI/unhandled-input pipeline.
## Headless layout checks do not claim rendering or desktop input validation.

const Preview: PackedScene = preload("res://src/features/expedition_hud/preview.tscn")

var _preview: C1HudPreview
var _hud: C1ExpeditionHud
var _results: Array[Dictionary] = []
var _failures: int = 0
var _report_path: String = ""
var _capture_dir: String = ""
var _expected_size: Vector2i = Vector2i(1280, 720)
var _layouts: Array[Dictionary] = []
var _mixed_sequences: Array[Dictionary] = []
var _active_sequence: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--c1-report="):
			_report_path = argument.trim_prefix("--c1-report=")
		elif argument.begins_with("--c1-capture="):
			_capture_dir = argument.trim_prefix("--c1-capture=")
		elif argument.begins_with("--c1-resolution="):
			var parts: PackedStringArray = argument.get_slice("=", 1).split("x")
			_expected_size = Vector2i(int(parts[0]), int(parts[1]))
	# Headless DisplayServer ignores --resolution and starts at 64x64. Resize
	# only its Window fixture, leaving the project's KEEP + canvas_items intact.
	if DisplayServer.get_name() == "headless":
		root.size = _expected_size
	_preview = Preview.instantiate() as C1HudPreview
	root.add_child(_preview)
	_hud = _preview.hud
	await _settle()
	_expect(OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/c1-user/")), "engine user data is isolated inside C1")
	_expect(ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items", "original canvas_items stretch retained")
	_expect(root.size == _expected_size, "Window size matches requested resolution")
	_expect(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "project KEEP aspect is retained (16:10 adds letterboxing)")
	var input_hashes: Dictionary = _input_hashes()
	await _check_read_only()
	await _check_layout()
	await _check_input()
	_preview.queue_free()
	await _settle()
	_preview = Preview.instantiate() as C1HudPreview
	root.add_child(_preview)
	_hud = _preview.hud
	await _check_mixed_input()
	paused = false
	var final_hashes: Dictionary = _input_hashes()
	_expect(input_hashes == final_hashes, "C1 source bytes stay stable throughout this run")
	var metadata: Dictionary = {
		"engine": Engine.get_version_info()["string"], "display": DisplayServer.get_name(),
		"window_size": [root.size.x, root.size.y],
		"viewport_size": [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
		"headless_window_fixture": DisplayServer.get_name() == "headless",
		"stretch_mode": "canvas_items", "stretch_aspect": "keep", "layouts": _layouts,
		"engine_input_injection": true, "desktop_input": false,
		"failures": _failures, "checks": _results,
		"mixed_sequences": _mixed_sequences,
		"source_sha256_at_start": input_hashes, "source_sha256_at_end": final_hashes,
	}
	if not _report_path.is_empty():
		var file: FileAccess = FileAccess.open(_report_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(metadata, "\t") + "\n")
		else:
			_expect(false, "write requested report")
	_preview.queue_free()
	await process_frame
	print("C1_CHECK checks=%d failures=%d display=%s" % [_results.size(), _failures, DisplayServer.get_name()])
	quit(0 if _failures == 0 else 1)


func _check_read_only() -> void:
	var state: Dictionary = C1HudSamples.make_sample(1)
	var original: Dictionary = state.duplicate(true)
	var node_count: int = _hud.find_children("*", "", true, false).size()
	for index: int in range(300):
		_hud.refresh(state)
	_expect(state == original, "300 refreshes preserve caller arrays and dictionaries")
	_expect(node_count == _hud.find_children("*", "", true, false).size(), "refresh does not accumulate nodes")
	var pause_button: Button = _control("PauseButton") as Button
	_expect(pause_button.pressed.get_connections().size() == 1, "refresh does not accumulate action connections")
	state["survivors"].reverse()
	_hud.refresh(state)
	var health1: Label = _hud.find_child("Member1", true, false).find_child("Health", true, false) as Label
	var bar1: ProgressBar = _hud.find_child("Member1", true, false).find_child("HealthBar", true, false) as ProgressBar
	_expect(health1.text == "生命 196 / 200" and is_equal_approx(bar1.value, 0.98), "identity and HP follow id, not caller array order")
	state["survivors"] = [{"id": 1, "hp": -20, "max_hp": 200}]
	_hud.refresh(state)
	_expect(bar1.value == 0.0 and state["survivors"][0]["hp"] == -20, "negative HP clamps only its display")
	state["survivors"][0]["hp"] = 300
	_hud.refresh(state)
	_expect(bar1.value == 1.0 and health1.text == "生命 200 / 200", "over-max HP does not overflow bar or numeric display")
	for invalid: Variant in [null, "bad", INF, NAN]:
		state["survivors"][0]["hp"] = invalid
		_hud.refresh(state)
		_expect(health1.text == "生命 — / —" and bar1.value == 0.0, "invalid HP produces explicit unknown: %s" % str(invalid))
	state["survivors"][0] = {"id": 1, "hp": 100, "max_hp": 0}
	_hud.refresh(state)
	_expect(health1.text == "生命 — / —", "zero max HP avoids division by zero")
	_hud.refresh({"survivors": "invalid", "time": null, "bus": null})
	_expect(not _control("TimeText").is_visible_in_tree() and (_control("BusButton") as Button).disabled, "missing or malformed optional containers fail closed")
	_expect((_control("Currency") as Label).text == "货币 —", "missing currency never invents a balance or delta")
	_expect(not paused, "HUD refresh never pauses the engine")


func _check_layout() -> void:
	for index: int in range(C1HudSamples.TITLES.size()):
		_preview.select_sample(index)
		await _settle()
		var good: bool = true
		var visible_area: Rect2 = root.get_visible_rect()
		var layout: Dictionary = {"sample": index, "controls": []}
		for node: Node in _hud.find_children("*", "Control", true, false):
			var control: Control = node as Control
			if not control.is_visible_in_tree():
				continue
			layout["controls"].append({"name": str(control.name), "rect": str(control.get_global_rect())})
			if not visible_area.grow(1).encloses(control.get_global_rect()):
				print("LAYOUT outside %s %s viewport %s" % [control.name, control.get_global_rect(), visible_area])
				good = false
			if control is Label:
				var label: Label = control as Label
				if not label.text.is_empty() and label.get_line_count() * label.get_line_height() > label.size.y + 2:
					print("LAYOUT text clipped %s lines=%d height=%s" % [label.name, label.get_line_count(), label.size.y])
					good = false
		_expect(good, "all visible controls and text fit sample %d" % index)
		_layouts.append(layout)
		_expect(not _control("MissionPanel").get_global_rect().intersects(_control("ActionsPanel").get_global_rect()), "mission and action panels stay separate sample %d" % index)
		var center: Vector2 = root.get_visible_rect().size * 0.5
		_expect(not _control("MissionPanel").get_global_rect().has_point(center) and not _control("ActionsPanel").get_global_rect().has_point(center), "map center remains clear sample %d" % index)
		if index in [0, 2, 3, 4, 5]:
			await _capture("sample-%d" % index)
	_preview.select_sample(2)
	_expect(not paused and (_control("PauseButton") as Button).text == "继续", "paused=true sample is explicitly distinct from real engine pause")


func _check_input() -> void:
	_preview.select_sample(1)
	await _settle()
	var pause_button: Button = _control("PauseButton") as Button
	var bus_button: Button = _control("BusButton") as Button
	var help_button: Button = _control("HelpButton") as Button
	var before: int = _preview.world_clicks
	await _click(pause_button.get_global_rect().get_center())
	_expect(paused and _preview.pause_intents == 1 and _preview.world_clicks == before, "pause click emits once, pauses via controller, does not hit world")
	var ticks: int = _preview.background.get("simulation_ticks")
	await create_timer(0.08, true).timeout
	_expect(_preview.background.get("simulation_ticks") == ticks, "real SceneTree pause freezes pausable probe")
	await _capture("engine-paused")
	await _click(pause_button.get_global_rect().get_center())
	_expect(not paused and _preview.resume_intents == 1 and _preview.world_clicks == before, "continue remains operable during real engine pause")
	await _click(bus_button.get_global_rect().get_center())
	_expect(_preview.bus_intents == 1 and _preview.world_clicks == before, "enabled bus emits once without world click")
	_preview.select_sample(0)
	await _settle()
	await _click(bus_button.get_global_rect().get_center())
	_expect(_preview.bus_intents == 1 and _preview.world_clicks == before, "disabled bus emits nothing and absorbs click")
	await _click(_control("MissionPanel").get_global_rect().position + Vector2(4, 4))
	_expect(_preview.world_clicks == before, "opaque information panel intentionally absorbs click")
	await _click(root.get_visible_rect().size * 0.5)
	_expect(_preview.world_clicks == before + 1, "transparent center passes to world exactly once")
	before = _preview.world_clicks
	await _click(help_button.get_global_rect().get_center())
	var help: Control = _control("HelpPanel")
	await _click(help.get_global_rect().get_center())
	_expect(help.visible and _preview.world_clicks == before, "help toggle and help content do not hit world")
	var scrolls: int = _preview.world_scrolls
	await _click(help.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP)
	_expect(_preview.world_scrolls == scrolls, "help panel does not leak scroll to camera")
	await _capture("help-open")
	await _click(help_button.get_global_rect().get_center())
	await _click(help.get_global_rect().get_center())
	_expect(not help.visible and _preview.world_clicks == before + 1, "closed help leaves no residual hit region")
	_preview.select_sample(1)
	bus_button.grab_focus()
	var intents: int = _preview.bus_intents
	var shortcuts: int = _preview.shortcut_count
	await _key(KEY_SPACE)
	_expect(_preview.bus_intents == intents + 1 and _preview.shortcut_count == shortcuts, "focused bus consumes Space once without global pause")
	intents = _preview.bus_intents
	await _key_edge(KEY_SPACE, true)
	await _key_edge(KEY_SPACE, true, true)
	_expect(bus_button.has_theme_stylebox_override("normal") and _preview.bus_intents == intents, "held confirm shows press without repeating intent")
	await _capture("keyboard-pressed")
	_preview.select_sample(0)
	await _key_edge(KEY_SPACE, false)
	_expect(_preview.bus_intents == intents, "disabling held action cancels its pending confirm")
	_preview.select_sample(1)
	bus_button.grab_focus()
	await _key_edge(KEY_ENTER, true)
	bus_button.release_focus()
	await _key_edge(KEY_ENTER, false)
	_expect(_preview.bus_intents == intents and not bus_button.has_theme_stylebox_override("normal"), "focus loss cancels pending confirm")
	bus_button.grab_focus()
	await _key(KEY_ENTER)
	_expect(_preview.bus_intents == intents + 1, "Enter activates focused action exactly once")
	pause_button.grab_focus()
	var pause_count: int = _preview.pause_intents
	await _key(KEY_SPACE)
	_expect(_preview.pause_intents == pause_count + 1 and _preview.shortcut_count == shortcuts and paused, "focused pause consumes Space once without duplicate shortcut")
	await _key(KEY_SPACE)
	_expect(not paused, "focused continue resumes actual engine pause")
	root.gui_release_focus()
	await _key(KEY_SPACE)
	_expect(paused and _preview.shortcut_count == shortcuts + 1, "unfocused Space follows world shortcut exactly once")
	_preview.set_engine_paused(false)
	await _click(help_button.get_global_rect().get_center())
	_hud.hide_screen()
	await _settle()
	before = _preview.world_clicks
	await _click(pause_button.get_global_rect().get_center())
	await _click(help.get_global_rect().get_center())
	_expect(_preview.world_clicks == before + 2 and root.gui_get_focus_owner() == null, "hidden HUD releases focus and every hit region")
	_hud.show()
	await _settle()
	_expect(not help.visible, "HUD reappears with help collapsed")
	var point: Vector2 = pause_button.get_global_rect().get_center()
	_hud.queue_free()
	await _settle()
	before = _preview.world_clicks
	await _click(point)
	_expect(_preview.world_clicks == before + 1, "freed HUD leaves no residual input blocker")


func _check_mixed_input() -> void:
	var help_button: Button = _control("HelpButton") as Button
	var bus_button: Button = _control("BusButton") as Button
	var pause_button: Button = _control("PauseButton") as Button
	var help: Control = _control("HelpPanel")
	await _sequence_start("mouse_help_space")
	var before: Dictionary = _sequence_state()
	await _click(help_button.get_global_rect().get_center())
	_sequence_step("mouse help completed")
	_expect(root.gui_get_focus_owner() == null and help.visible, "mouse help click opens help and releases focus")
	await _key(KEY_SPACE)
	_sequence_step("Space completed")
	_expect(paused and help.visible and _preview.shortcut_count == before["shortcuts"] + 1 and _preview.bus_intents == before["bus"] and _preview.pause_intents == before["pause"] and _preview.world_clicks == before["world_clicks"], "mouse help then Space pauses via world without closing help or another intent")
	await _capture("mouse-help-space")

	await _sequence_start("mouse_bus_space")
	before = _sequence_state()
	await _click(bus_button.get_global_rect().get_center())
	_sequence_step("mouse enabled bus completed")
	_expect(root.gui_get_focus_owner() == null and _preview.bus_intents == before["bus"] + 1, "mouse bus click emits once and releases focus")
	await _key(KEY_SPACE)
	_sequence_step("Space completed")
	_expect(paused and _preview.shortcut_count == before["shortcuts"] + 1 and _preview.bus_intents == before["bus"] + 1 and _preview.pause_intents == before["pause"] and _preview.world_clicks == before["world_clicks"], "mouse bus then Space pauses without a second bus intent")

	await _sequence_start("tab_help_space_enter")
	before = _sequence_state()
	await _tab_to(help_button)
	await _key(KEY_SPACE)
	_sequence_step("Space completed")
	_expect(help.visible and help_button.has_focus() and not paused and _preview.shortcut_count == before["shortcuts"] and _preview.bus_intents == before["bus"] and _preview.pause_intents == before["pause"], "Tab-focused help Space opens once and retains keyboard focus")
	var text: Label = _control("HelpText") as Label
	_expect(text.get_line_count() * text.get_line_height() <= text.size.y + 2 and root.get_visible_rect().encloses(help.get_global_rect()), "expanded keyboard help text fits viewport")
	await _capture("tab-help-focus")
	await _key(KEY_ENTER)
	_sequence_step("Enter completed")
	_expect(not help.visible and help_button.has_focus() and _preview.shortcut_count == before["shortcuts"] and _preview.world_clicks == before["world_clicks"], "Tab-focused help Enter closes once without world input")
	root.gui_release_focus()
	await _key(KEY_TAB, true)
	_sequence_step("Shift+Tab enters from no focus")
	_expect(help_button.has_focus(), "Shift+Tab enters HUD at help when no control owns focus")

	await _sequence_start("tab_bus_space_enter")
	before = _sequence_state()
	await _tab_to(bus_button)
	await _key(KEY_SPACE)
	_sequence_step("Space completed")
	_expect(bus_button.has_focus() and _preview.bus_intents == before["bus"] + 1 and not paused and _preview.shortcut_count == before["shortcuts"], "Tab-focused bus Space emits once and retains keyboard focus")
	await _capture("tab-bus-focus")
	await _key(KEY_ENTER)
	_sequence_step("Enter completed")
	_expect(bus_button.has_focus() and _preview.bus_intents == before["bus"] + 2 and _preview.shortcut_count == before["shortcuts"] and _preview.pause_intents == before["pause"] and _preview.world_clicks == before["world_clicks"], "Tab-focused bus Enter emits once without world input")
	await _key(KEY_TAB, true)
	_sequence_step("Shift+Tab completed")
	_expect(pause_button.has_focus(), "Shift+Tab from bus returns to pause")

	await _sequence_start("focused_bus_disabled_then_space")
	await _tab_to(bus_button)
	before = _sequence_state()
	_preview.select_sample(0)
	await _settle()
	_sequence_step("external refresh disables bus")
	_expect(bus_button.disabled and root.gui_get_focus_owner() == null, "disabling focused bus releases focus without moving it to pause")
	await _key(KEY_SPACE)
	_sequence_step("Space completed")
	_expect(paused and _preview.shortcut_count == before["shortcuts"] + 1 and _preview.bus_intents == before["bus"] and _preview.pause_intents == before["pause"], "disabled bus then Space uses world pause without a bus intent")
	await _key(KEY_TAB)
	await _key(KEY_TAB)
	_sequence_step("Tab ring skips disabled bus")
	_expect(help_button.has_focus() and _preview.bus_intents == before["bus"], "Tab navigation skips disabled bus and reaches help")

	await _sequence_start("mouse_pause_space_resume")
	before = _sequence_state()
	await _click(pause_button.get_global_rect().get_center())
	_sequence_step("mouse pause completed")
	_expect(paused and _preview.pause_intents == before["pause"] + 1 and root.gui_get_focus_owner() == null, "mouse pause emits once and releases focus")
	var ticks: int = _preview.background.get("simulation_ticks")
	await create_timer(0.08, true).timeout
	_expect(_preview.background.get("simulation_ticks") == ticks, "mixed mouse pause freezes background tick")
	await _key(KEY_SPACE)
	_sequence_step("Space completed")
	_expect(not paused and _preview.shortcut_count == before["shortcuts"] + 1 and _preview.resume_intents == before["resume"] and _preview.bus_intents == before["bus"] and _preview.world_clicks == before["world_clicks"], "mouse pause then Space resumes once through world shortcut")
	ticks = _preview.background.get("simulation_ticks")
	await create_timer(0.08, true).timeout
	_expect(_preview.background.get("simulation_ticks") > ticks, "resumed background tick advances again")
	_hud.hide_screen()
	await _key(KEY_TAB)
	_sequence_step("Tab while HUD hidden")
	_expect(root.gui_get_focus_owner() == null, "hidden HUD does not bootstrap focus from Tab")
	_hud.show()


func _sequence_start(case_name: String) -> void:
	_preview.set_engine_paused(false)
	_hud.hide_screen()
	_hud.show()
	_preview.select_sample(1)
	root.gui_release_focus()
	await _settle()
	_active_sequence = {"case": case_name, "steps": []}
	_mixed_sequences.append(_active_sequence)
	_sequence_step("initial ready sample; no focus")


func _sequence_state() -> Dictionary:
	var focus: Control = root.gui_get_focus_owner()
	return {"focus": str(focus.name) if focus != null else "none",
		"paused": paused, "pause": _preview.pause_intents, "resume": _preview.resume_intents,
		"bus": _preview.bus_intents, "help_open": _control("HelpPanel").visible,
		"shortcuts": _preview.shortcut_count, "world_clicks": _preview.world_clicks,
		"bus_disabled": (_control("BusButton") as Button).disabled,
		"background_ticks": _preview.background.get("simulation_ticks")}


func _sequence_step(action: String) -> void:
	var state: Dictionary = _sequence_state()
	state["action"] = action
	_active_sequence["steps"].append(state)
	print("C11_INPUT %s %s" % [_active_sequence["case"], JSON.stringify(state)])


func _tab_to(button: Button) -> void:
	# Actual Tab events, never grab_focus: the focus graph is part of this test.
	for attempt: int in range(8):
		await _key(KEY_TAB)
		_sequence_step("Tab %d completed" % (attempt + 1))
		if button.has_focus():
			break
	_expect(button.has_focus(), "real Tab navigation reaches %s" % button.name)


func _input_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for folder: String in ["src/features/expedition_hud", "tests/expedition_hud", "assets/ui/c1"]:
		for filename: String in DirAccess.get_files_at("res://" + folder):
			if filename.get_extension() in ["gd", "tscn", "tres", "uid", "py"]:
				var path: String = folder.path_join(filename)
				hashes[path] = FileAccess.get_sha256("res://" + path)
	for path: String in ["project.godot", ".godot-version"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	return hashes


func _control(node_name: String) -> Control:
	return _hud.find_child(node_name, true, false) as Control


func _settle() -> void:
	for frame: int in range(5):
		await process_frame


func _click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await _settle()


func _key(code: Key, shift: bool = false) -> void:
	for pressed: bool in [true, false]:
		await _key_edge(code, pressed, false, shift)
	await _settle()


func _key_edge(code: Key, pressed: bool, echo: bool = false, shift: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	event.shift_pressed = shift
	root.push_input(event, true)
	await process_frame


func _capture(label: String) -> void:
	if _capture_dir.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		_expect(false, "headless mode must not fabricate render evidence")
		return
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	var filename: String = "%dx%d-%s.png" % [pixels.get_width(), pixels.get_height(), label]
	_expect(pixels.save_png(_capture_dir.path_join(filename)) == OK, "save real Godot viewport " + filename)


func _expect(condition: bool, description: String) -> void:
	_results.append({"check": description, "passed": condition})
	print("%s %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		_failures += 1
