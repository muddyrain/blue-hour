extends "res://tests/m49_comparison_flow.gd"
## Supplement only the long task-card loading view's actual first rendered feedback.


func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var state: Dictionary = app.progress_session.inspect()
	var minimum: int = 1 if "--long-driver-preflight" in OS.get_cmdline_user_args() else 100
	_check(state.error == OK and state.state == "CAMP" and int(state.receipt.revision) >= minimum,
		"feedback supplement starts at the genuine original confirmed camp")
	if state.error != OK or state.state != "CAMP":
		return
	comparison_m48 = true
	comparison = {"scope":"TARGETED_LONG_LOADING_VIEW_FEEDBACK_WITH_EXISTING_COMPARISON_OBSERVER",
		"pid":OS.get_process_id(), "path":app.progress_path, "source_camp":RecordEncoding.fingerprint(app.camp_snapshot()),
		"revision":state.receipt.revision, "physical_input":"NOT_VERIFIED",
		"preflight":minimum == 1, "complete_time":"retained but profiler-enabled supplement; do not replace paired primary samples"}
	if not await _comparison_equip(app.camp_snapshot()):
		return
	comparison.post_save_camp = RecordEncoding.fingerprint(app.camp_snapshot())
	comparison.cards = await _measure_native("cards", app.camp_scene.hotspots[&"bus"], func() -> bool:
		return app.mission_select.is_visible_in_tree() and not app.mission_select.loading \
			and not app.mission_select.daily_offers.is_empty() and not app.mission_select.choices[0].disabled)
	comparison.candidates = app.mission_select.daily_offers.map(func(action: Dictionary) -> Dictionary:
		return _comparison_action(action))
	_write("long-feedback.json", comparison)
	await _shot("long-task-cards-ready")
	await _tap(app.mission_select.cancel_button)
