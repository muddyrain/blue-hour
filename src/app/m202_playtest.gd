class_name M202Playtest
extends P03Playtest
## Opt-in renderer/mixer proof. All state changes use real controls or gameplay intents.

var _audio_events: Array[Dictionary] = []
var _recording: AudioEffectRecord
var _record_index: int = -1
var _stage: String = "b"
var _results: Array[Dictionary] = []
var _input_trace: Array[Dictionary] = []


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--m202-stage="):
			_stage = argument.trim_prefix("--m202-stage=")
	if _stage == "restart":
		await _check_restart()
		return
	app.audio_requested.connect(func(cue: StringName, world: bool, accepted: bool) -> void:
		_audio_events.append({"cue":String(cue),"world":world,"accepted":accepted,
			"ms":Time.get_ticks_msec(),"frame":Engine.get_frames_drawn()})
	)
	app.get_node("World").child_entered_tree.connect(_connect_feedback)
	_recording = AudioEffectRecord.new()
	_recording.format = AudioStreamWAV.FORMAT_16_BITS
	_record_index = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, _recording)
	_recording.set_recording_active(true)
	await _capture("m202-001-camp")
	await _click_control("Interface/Screen/Title/Sound")
	var panel: SoundSettingsPanel = app.sound_settings
	_expect(panel.visible, "formal sound settings opens from actual camp button")
	await _wait(0.15)
	await _click_screen(panel.sliders["master_volume"].get_global_rect().get_center())
	await _click_screen(panel.sliders["sfx_volume"].get_global_rect().get_center())
	await _click_screen(panel.sliders["ui_volume"].get_global_rect().get_center())
	await _click_screen(panel.mute_button.get_global_rect().get_center())
	_expect(app.audio_preferences.snapshot()["muted"], "actual mute control takes effect")
	await _capture("m202-002-muted-settings")
	if _stage == "b":
		await _click_screen(panel.mute_button.get_global_rect().get_center())
	await _click_screen(panel.save_button.get_global_rect().get_center())
	_expect(panel.message.text.begins_with("已保存"), "actual formal save reports success")
	await _capture("m202-003-saved-settings")
	var preferences: Dictionary = app.audio_preferences.snapshot()
	if _stage == "full":
		await _click_screen(panel.mute_button.get_global_rect().get_center())
		_expect(not app.audio_preferences.snapshot()["muted"] and panel.message.text.contains("尚未保存"),
			"unsaved unmute is immediate and clearly distinguished from persisted mute")
	var file: FileAccess = FileAccess.open(output_dir.path_join("saved-values.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(preferences, "\t") + "\n")
	file.close()
	await _click_screen(panel.back_button.get_global_rect().get_center())
	if _stage == "inputs":
		await _click_control("Interface/Screen/Title/Start")
		await _click_screen(app.mission_select.choices[1].get_global_rect().get_center())
		await _hud_inputs(app.expedition)
		var trace: FileAccess = FileAccess.open(output_dir.path_join("input-trace.json"), FileAccess.WRITE)
		trace.store_string(JSON.stringify({"results":_results,"trace":_input_trace}, "\t"))
		trace.close()
		trace = FileAccess.open(output_dir.path_join("run-report.json"), FileAccess.WRITE)
		trace.store_string(JSON.stringify({"failures":_failures,"results":_results,"checks":_checks,
			"behavior_checks":_checks-_captures.size(),"capture_checks":_captures.size(),
			"captures":_captures,"audio_driver":AudioServer.get_driver_name()}, "\t"))
		trace.close()
		_recording.set_recording_active(false)
		AudioServer.remove_bus_effect(0, _record_index)
		app.audio.shutdown()
		await _wait(0.2)
		get_tree().quit(0 if _failures.is_empty() else 1)
		return
	await _sortie_regression()
	await _wait(1.5)
	await _capture("m202-004-second-sortie-held")
	for cue: String in ["ui_confirm","ui_back","fire","hit","collect_complete","bus_start"]:
		var requests: int = 0
		var accepted: int = 0
		for event: Dictionary in _audio_events:
			if event["cue"] == cue:
				requests += 1
				accepted += 1 if event["accepted"] else 0
		_expect(requests > 0 and accepted > 0, "normal gameplay requests and service accepts cue " + cue)
	if _stage == "full":
		var shots: int = 0
		var hits: int = 0
		for event: Dictionary in _feedback:
			shots += 1 if event["kind"] == "shot" else 0
			hits += 1 if event.get("applied_damage", 0.0) > 0.0 else 0
		_expect(_audio_count("fire") == shots and _audio_count("hit") == hits,
			"final normal-game requests match real shots and applied damage exactly")
		_expect(_audio_count("collect_complete") == 2 and _audio_count("bus_start") == 2,
			"two sorties issue exactly two collect and bus success requests")
	_recording.set_recording_active(false)
	var recording: AudioStreamWAV = _recording.get_recording()
	_expect(recording != null and recording.save_to_wav(output_dir.path_join("actual-game-mix.wav")) == OK,
		"actual native game AudioServer mix saved; not a speaker listening verdict")
	AudioServer.remove_bus_effect(0, _record_index)
	_recording = null
	var report: Dictionary = {"stage":_stage,"display":DisplayServer.get_name(),"audio_driver":AudioServer.get_driver_name(),
		"window_size":[get_tree().root.size.x,get_tree().root.size.y],
		"checks":_checks,"behavior_checks":_checks-_captures.size(),"capture_checks":_captures.size(),
		"failures":_failures,"captures":_captures,"combat_events":_feedback,"audio_requests":_audio_events,
		"cash":app.cash,"day":app.day,"settled_sorties":app.settled_sorties,"saved_preferences":preferences,"results":_results,"input_trace":_input_trace,
		"input":"engine viewport mouse/key injection and ordinary gameplay intents; not hardware hand-feel",
		"audio_evidence":"AudioServer actual game mix; WASAPI output driver separately recorded; B user listening evidence retained, no invented new listening verdict"}
	file = FileAccess.open(output_dir.path_join("run-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("BH_M202_VERIFY stage=%s checks=%d captures=%d failures=%d" % [_stage,_checks,_captures.size(),_failures.size()])
	app.audio.shutdown()
	await _wait(0.2)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _sortie_regression() -> void:
	if _stage == "b":
		await super._sortie_regression()
		return
	for iteration: int in range(2):
		var before_cash: int = app.cash
		await _click_control("Interface/Screen/Title/Start")
		await _click_screen(app.mission_select.choices[1].get_global_rect().get_center())
		var sortie: Expedition = app.expedition
		var hud: C1ExpeditionHud = sortie._hud.view
		_expect(sortie.loot == 0 and not sortie.searched and not app.audio._world_paused,
			"sortie %d starts clean with world audio resumed" % (iteration + 1))
		await _capture("m202-sortie-%d-arrival" % (iteration + 1))
		if iteration == 0:
			await _hud_inputs(sortie)
		sortie.command_move(Vector2(928, 650))
		sortie.request_search()
		await _until_inside(sortie)
		await _wait(1.0)
		sortie.toggle_pause()
		var progress: float = sortie.search_progress
		sortie.request_search()
		_expect(sortie.search_actor == null and sortie.loot == 0, "indoor cancel does not pay or emit collect success")
		sortie.request_search()
		_expect(sortie.search_progress == progress, "integration preserves TMP-107 partial progress")
		sortie.toggle_pause()
		await _until_inside(sortie)
		if iteration == 0:
			# Ordinary map movement toward a real spawned enemy; no health/spawn edits.
			while sortie.enemies.is_empty() and sortie.elapsed < 15.0:
				await _wait(0.1)
			if not sortie.enemies.is_empty():
				sortie.command_move(sortie.enemies[0].position)
				await _wait(7.0)
			var wounded: bool = false
			for actor: FieldActor in sortie.survivors:
				wounded = wounded or actor.health < actor.max_health
			_expect(wounded, "normal sortie receives real enemy damage without a practice fixture")
			for index: int in range(sortie.survivors.size()):
				var label: Label = hud._members[index]["health"]
				_expect(label.text.contains(str(ceili(sortie.survivors[index].health))), "HUD follows actual member damage")
			await _capture("m202-normal-damage")
			sortie.command_move(Vector2(928, 650))
		while sortie.elapsed < sortie.tuning.bus_ready_seconds:
			await _wait(0.1)
		if iteration == 0:
			await _click_screen(hud._bus_button.get_global_rect().get_center())
			_expect(sortie.phase == Expedition.Phase.ENGINE, "actual HUD bus button accepts exactly one legal engine transition")
			await _key(KEY_SPACE)
			_expect(sortie.is_paused and sortie.phase == Expedition.Phase.ENGINE,
				"mouse bus then Space pauses world without a second bus request")
			await _capture("m202-engine-paused")
			await _key(KEY_SPACE)
		else:
			await _focus_via_tab(hud._bus_button)
			await _key(KEY_ENTER)
			_expect(sortie.phase == Expedition.Phase.ENGINE and not sortie.is_paused,
				"Tab and Enter start the real second bus once without world pause")
			_expect(get_viewport().gui_get_focus_owner() != hud._bus_button, "real engine transition disables bus and drops its keyboard focus")
			await _key(KEY_ENTER)
			_expect(sortie.phase == Expedition.Phase.ENGINE and not sortie.is_paused, "Enter after disabled bus cannot repeat its intent")
		await _wait(3.2)
		_expect(sortie.phase == Expedition.Phase.BOARDING and hud._bus_button.disabled,
			"actual waiting state is disabled in HUD, independent of sortie clock")
		await _capture("m202-sortie-%d-waiting" % (iteration + 1))
		var limit: int = 0
		while not sortie.searched and limit < 450:
			await _wait(0.1)
			limit += 1
		_expect(sortie.searched and sortie.loot == 4 and hud._currency.text.contains("+4"), "actual search reward updates real HUD once")
		sortie.request_search()
		_expect(sortie.loot == 4, "completed building repeat cannot pay or sound twice")
		await _capture("m202-sortie-%d-collected" % (iteration + 1))
		await _click_world(sortie, sortie.layout.bus_door)
		limit = 0
		while app.phase != app.Phase.RESULT and limit < 350:
			await _wait(0.1)
			limit += 1
		_expect(app.phase == app.Phase.RESULT and app._pending_settlement.cash == before_cash + 4 and app.settled_sorties == iteration,
			"sortie %d evacuates and previews exactly one settlement" % (iteration + 1))
		await _capture("m202-sortie-%d-result" % (iteration + 1))
		await _check_finished(sortie)
		_expect(not hud.visible, "result hides C HUD and its focus targets")
		await _click_control("Interface/Screen/Result/Continue")
		await _capture("m202-sortie-%d-camp-held" % (iteration + 1))
	# Leave a genuinely new ordinary sortie visible after two settlements.
	await _click_control("Interface/Screen/Title/Start")
	await _click_screen(app.mission_select.choices[1].get_global_rect().get_center())
	_expect(app.expedition.day == 4 and app.expedition.loot == 0, "third entry recreates clean HUD/listeners after two complete sorties")


func _hud_inputs(sortie: Expedition) -> void:
	var hud: C1ExpeditionHud = sortie._hud.view
	var initial_goal: Vector2 = sortie.goal
	await _click_screen(hud._bus_button.get_global_rect().get_center())
	_expect(hud._bus_button.disabled and sortie.phase == Expedition.Phase.ACTIVE and sortie.goal == initial_goal,
		"disabled actual bus blocks click without leaking a map order")
	await _click_screen(hud._help_button.get_global_rect().get_center())
	await _key(KEY_SPACE)
	_expect(sortie.is_paused and hud._help.visible, "mouse Help then Space pauses once and keeps help open")
	await _capture("m202-help-space")
	var elapsed_before: float = sortie.elapsed
	await _wait(0.5)
	_expect(sortie.elapsed == elapsed_before and app.audio._world_paused, "actual UI pause freezes time and world audio")
	await _key(KEY_SPACE)
	await _click_screen(hud._pause_button.get_global_rect().get_center())
	_expect(sortie.is_paused, "mouse pause toggles once")
	await _key(KEY_SPACE)
	_expect(not sortie.is_paused, "Space after mouse pause resumes once")
	await _focus_via_tab(hud._pause_button)
	await _key(KEY_SPACE)
	_expect(sortie.is_paused, "Tab Pause then Space requests exactly one pause")
	await _key(KEY_ENTER)
	_expect(not sortie.is_paused, "focused Continue Enter requests exactly one resume")
	await _focus_via_tab(hud._help_button)
	var paused: bool = sortie.is_paused
	var was_open: bool = hud._help.visible
	await _key(KEY_SPACE)
	_expect(hud._help.visible != was_open and sortie.is_paused == paused, "Tab Help then Space is UI-only")
	await _key(KEY_ENTER)
	_expect(hud._help.visible == was_open and sortie.is_paused == paused, "focused Help Enter is UI-only")
	await _capture("m202-tab-help")
	await _click_screen(hud._help_button.get_global_rect().get_center())
	if not hud._help.visible:
		await _click_screen(hud._help_button.get_global_rect().get_center())
	var blocked: Vector2 = hud._help.get_global_rect().position + Vector2(480, 24)
	initial_goal = sortie.goal
	var zoom_before: Vector2 = sortie.camera.zoom
	await _click_screen(blocked)
	await _wheel(blocked)
	_expect(sortie.goal == initial_goal and sortie.camera.zoom == zoom_before, "opaque actual help blocks map clicks and camera wheel")
	await _click_screen(hud._help_button.get_global_rect().get_center())
	await _click_screen(blocked)
	_expect(sortie.goal != initial_goal, "collapsed Help releases the same area to actual map orders")
	await _wheel(Vector2(800, 400))
	_expect(sortie.camera.zoom != zoom_before, "transparent map wheel reaches actual camera")
	zoom_before = sortie.camera.zoom
	await _wheel(hud._mission.get_global_rect().get_center())
	_expect(sortie.camera.zoom == zoom_before, "opaque mission panel blocks wheel from actual camera")
	var title: String = sortie.mission_title
	sortie.mission_title = "旧街东侧临时补给站与维修铺交叉路口（中文长地点显示检查）"
	await _wait(0.1)
	await _capture("m202-long-location")
	_expect(hud._mission.text == sortie.mission_title, "long mission metadata maps without substituting preview fixtures")
	sortie.mission_title = title


func _focus_via_tab(target: Control) -> void:
	var attempts: int = 0
	while get_viewport().gui_get_focus_owner() != target and attempts < 6:
		await _key(KEY_TAB)
		attempts += 1
	_expect(get_viewport().gui_get_focus_owner() == target, "real Tab reaches " + String(target.name))


func _wheel(point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	# Synthetic wheel input needs both edges, as in C1.1's own verified helper.
	# Omitting release leaves Viewport mouse capture held by the help panel.
	event.pressed = false
	get_viewport().push_input(event, true)
	await get_tree().process_frame


func _check_restart() -> void:
	var expected_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--m202-expected="):
			expected_path = argument.trim_prefix("--m202-expected=")
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	await _click_control("Interface/Screen/Title/Sound")
	var panel: SoundSettingsPanel = app.sound_settings
	_expect(app.audio_preferences.snapshot() == expected, "new exported process restores all four saved preferences")
	for key: String in AudioPreferences.VOLUME_KEYS:
		_expect(is_equal_approx(panel.sliders[key].value, float(expected[key]) * 100.0), "reopened actual slider restores " + key)
	_expect(panel.mute_button.button_pressed == expected["muted"], "reopened actual mute restores saved bool")
	await _capture("m202-reopened-settings")
	var file: FileAccess = FileAccess.open(output_dir.path_join("run-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"stage":"restart","failures":_failures,"results":_results,"checks":_checks,
		"behavior_checks":_checks-_captures.size(),"capture_checks":_captures.size(),"captures":_captures,
		"audio_driver":AudioServer.get_driver_name(),"preferences":app.audio_preferences.snapshot()}, "\t") + "\n")
	file.close()
	app.audio.shutdown()
	await _wait(0.2)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, label: String) -> void:
	super._expect(condition, label)
	_results.append({"label":label,"passed":condition})


func _audio_count(cue: String) -> int:
	var count: int = 0
	for event: Dictionary in _audio_events:
		count += 1 if event["cue"] == cue else 0
	return count


func _check_finished(sortie: Expedition) -> void:
	await super._check_finished(sortie)
	var stopped: bool = true
	for player: AudioStreamPlayer in app.audio._world_players:
		stopped = stopped and not player.playing
	_expect(stopped and not sortie.combat_feedback.is_connected(app._on_combat_feedback),
		"result stops world sounds and unbinds app event listeners")


func _click_control(path: NodePath) -> void:
	await super._click_control(path)
	if String(path) == "Interface/Screen/Result/Continue":
		await _wait(1.5)


func _key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	event.pressed = false
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	await get_tree().process_frame


func _click_screen(point: Vector2) -> void:
	# Use C1.1's verified viewport-local path, without an OS-pointer frame gap.
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var trace: Dictionary = {"point":point,"hovered":str(hovered.get_path()) if hovered != null else "none"}
	if app.expedition != null:
		trace["help_rect"] = str(app.expedition._hud.view._help_button.get_global_rect())
		trace["help_open"] = app.expedition._hud.view._help.visible
		trace["bus_rect"] = str(app.expedition._hud.view._bus_button.get_global_rect())
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
		# Keep a synthetic click together; native pointer updates between its
		# edges can otherwise move the hover target before button release.
	await get_tree().process_frame
	await get_tree().process_frame
	if app.expedition != null:
		trace["help_after"] = app.expedition._hud.view._help.visible
		trace["phase_after"] = app.expedition.phase
	_input_trace.append(trace)
