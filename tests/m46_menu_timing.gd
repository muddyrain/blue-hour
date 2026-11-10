extends "res://tests/playable_flow.gd"
## Measures the real camp-to-card callback on each engine's first visit.


func _journey() -> void:
	await _tap(app._home_button)
	if app._opening_picker.visible:
		await _tap(app._opening_picker.choices["scavenge"])
	await _tap(app._new_game_confirmation.get_ok_button())
	var camp: Dictionary = app.camp_snapshot()
	_check(app.camp_scene.is_visible_in_tree(), "normal new journey opens camp")
	if "--flow-menu-cancel" in OS.get_cmdline_user_args():
		await _cancel_during_wait(camp)
		return
	var cold: Dictionary = await _open_and_measure()
	if cold.is_empty():
		return
	var offers: Array = app.mission_select.daily_offers.duplicate(true)
	await _tap(app.mission_select.cancel_button)
	_check(app.camp_scene.is_visible_in_tree() and not app.mission_select.visible, "back returns from cards to camp")
	var reopened: Dictionary = await _open_and_measure()
	_check(TransactionReceipt.same({"offers":offers}, {"offers":app.mission_select.daily_offers}),
		"reopening keeps exact candidate identities and layouts")
	await _tap(app.mission_select.cancel_button)
	_check(TransactionReceipt.same(camp, app.camp_snapshot()), "browsing and cancel leave camp unchanged")
	var identities: Array[Dictionary] = []
	for offer: Dictionary in offers:
		identities.append({"id":offer.get("id", ""), "type":offer.get("type", ""),
			"intel":offer.get("billboard_target", {}), "signature":RecordEncoding.fingerprint(offer),
			"layout":RecordEncoding.fingerprint(offer.get("layout", {}))})
	_write("menu-timing.json", {"pid":OS.get_process_id(), "seed":camp.journey.seed,
		"day":camp.day, "cold":cold, "reopened":reopened, "candidates":identities})


func _click(button: BaseButton) -> int:
	await RenderingServer.frame_post_draw
	var point: Vector2 = button.get_global_rect().get_center()
	var pressed: InputEventMouseButton = InputEventMouseButton.new()
	pressed.position = point
	pressed.global_position = point
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.pressed = true
	viewport.push_input(pressed, true)
	await RenderingServer.frame_post_draw
	var started: int = Time.get_ticks_usec()
	pressed = pressed.duplicate()
	pressed.pressed = false
	viewport.push_input(pressed, true)
	return started


func _cancel_during_wait(camp: Dictionary) -> void:
	var menu: MissionSelect = app.mission_select
	var started: int = await _click(app.camp_scene.hotspots[&"bus"])
	await RenderingServer.frame_post_draw
	var feedback_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	_check(menu.visible and menu.get("loading") == true and not menu.cancel_button.disabled,
		"a rendered cold waiting panel is visible with an enabled return button")
	var canceled_at: int = await _click(menu.cancel_button)
	await RenderingServer.frame_post_draw
	_check(app.get("_mission_worker") != null and app.camp_scene.is_visible_in_tree() and not menu.visible,
		"actual mouse return leaves the waiting panel while generation is pending")
	while app.get("_mission_worker") != null and Time.get_ticks_usec() - canceled_at < 90000000:
		await RenderingServer.frame_post_draw
	var discarded_ms: float = (Time.get_ticks_usec() - canceled_at) / 1000.0
	_check(app.get("_mission_worker") == null and not menu.visible and TransactionReceipt.same(camp, app.camp_snapshot()),
		"late generation completion leaves the canceled menu hidden and preserves the camp")
	var reopened: Dictionary = await _open_and_measure()
	var offers: Array = menu.daily_offers.duplicate(true)
	await _tap(menu.cancel_button)
	var repeated: Dictionary = await _open_and_measure()
	_check(not offers.is_empty() and TransactionReceipt.same({"offers":offers}, {"offers":menu.daily_offers}),
		"reopening and repeating after cancellation preserves exact generated candidates")
	_write("cancel-wait.json", {"pid":OS.get_process_id(), "feedback_ms":feedback_ms,
		"discarded_completion_ms":discarded_ms, "reopened":reopened, "repeated":repeated,
		"offers_fingerprint":RecordEncoding.fingerprint({"offers":offers})})


func _open_and_measure() -> Dictionary:
	var started: int = await _click(app.camp_scene.hotspots[&"bus"])
	var previous: int = started
	var largest: int = 0
	var visible_at: int = -1
	var waiting_return: bool = false
	while Time.get_ticks_usec() - started < 90000000:
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		largest = maxi(largest, now - previous)
		previous = now
		if not app.mission_select.is_visible_in_tree():
			continue
		if visible_at < 0:
			visible_at = now - started
		if not app.mission_select.daily_offers.is_empty() and app.mission_select.choices[0].is_visible_in_tree() and not app.mission_select.choices[0].disabled:
			return {"feedback_ms":visible_at / 1000.0, "cards_ms":(now - started) / 1000.0,
				"max_frame_ms":largest / 1000.0, "waiting_return_visible":waiting_return}
		waiting_return = app.mission_select.cancel_button.is_visible_in_tree() and not app.mission_select.cancel_button.disabled
	_check(false, "bus interaction presents usable cards before timeout")
	return {}
