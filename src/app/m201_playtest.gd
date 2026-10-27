class_name M201Playtest
extends P03Playtest
## Reuses the real sortie regression. Fixtures are explicitly separate from DD observations.


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("M2-01 playtest requires a native rendering window.")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	app.get_node("World").child_entered_tree.connect(_connect_feedback)
	print("BH_M201_VERIFY build=%s display=%s input=engine_events_and_gameplay_intents" % [Expedition.BUILD_ID, DisplayServer.get_name()])
	await _capture("m201-001-camp")
	await _click_control("Interface/Screen/Title/Practice")
	var practice: Expedition = app.expedition
	await _wait(2.8)
	var first_event: int = _feedback.size()
	await _key(KEY_U)
	_expect(practice.enemies.size() == 1, "U input enters the explicit durable-target practice condition")
	var target: FieldActor = practice.enemies[0]
	await _capture("m201-002-far-target")
	await _wait(1.4)
	_expect(target.health == 540.0, "prototype range: visible far target receives no damage")
	practice.toggle_pause()
	await _capture("m201-003-paused")
	var before_pause: Dictionary = _world_state(practice)
	await _wait(1.2)
	_expect(_world_state(practice) == before_pause, "pause freezes actual combat, countdown and render state")
	await _capture("m201-004-paused-still")
	practice.toggle_pause()
	practice.command_move(Vector2(1264, 824))
	await _wait(0.8)
	await _capture("m201-005-moving-fire")
	var moving_hit: bool = false
	for event: Dictionary in _feedback.slice(first_event):
		if event["kind"] == "shot" and event["moving"] and event["target"] == target.actor_id:
			moving_hit = true
	_expect(target.health < 540.0 and moving_hit, "DD-OBS-011/025: actual damage and shot events during movement")
	practice.command_move(Vector2(896, 824))
	await _wait(2.8)
	await _capture("m201-006-retreated")
	var after_retreat: float = target.health
	await _wait(0.6)
	_expect(target.health == after_retreat and practice.survivors[0].aim == Vector2.ZERO, "prototype range: retreat stops shots while target remains alive")
	await _capture("m201-007-outside-quiet")
	practice.command_move(Vector2(1232, 824))
	await _wait(1.5)
	_expect(target.health < after_retreat, "prototype range: re-entry resumes damage through shared combat")
	await _capture("m201-008-reenter")
	practice.request_extraction()
	await _capture("m201-009-practice-result")
	await _check_finished(practice)
	await _capture("m201-010-practice-frozen")
	await _click_control("Interface/Screen/Result/Continue")
	_expect(app.day == 2 and app.cash == 53 and app.crew_health[0] == 200.0 and app.settled_sorties == 0, "durable practice target does not alter campaign")
	await _sortie_regression()
	var report: Dictionary = {
		"build": Expedition.BUILD_ID, "display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"input": "engine viewport mouse/key events and gameplay intents; desktop checked separately",
		"behavior_checks": _checks - _captures.size(), "capture_checks": _captures.size(), "checks": _checks,
		"failures": _failures, "captures": _captures, "combat_events": _feedback,
		"cash": app.cash, "day": app.day, "settled_sorties": app.settled_sorties,
		"reference_limits": "DD moving fire and timer separation/qualitative colour only; isolated range, pursuit, obstacle B and night remain unverified",
	}
	var file: FileAccess = FileAccess.open(output_dir.path_join("run-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("BH_M201_VERIFY behavior_checks=%d capture_checks=%d failures=%d" % [_checks - _captures.size(), _captures.size(), _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _world_state(sortie: Expedition) -> Dictionary:
	var state: Dictionary = super._world_state(sortie)
	state["timing"] = sortie.time_status()
	state["time_colour"] = sortie._hud._time_fill.bg_color
	state["time_bar"] = sortie._hud._time_bar.value
	return state


func _key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame
