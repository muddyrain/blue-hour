extends "res://tests/m49_comparison_flow.gd"
## Same frozen RESULT_READY bytes at the same Windows path, in both source versions.

func _resume() -> void:
	var source: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--frozen-expected="):
			source = argument.trim_prefix("--frozen-expected=")
	var expected: Dictionary = RecordEncoding.unpack(JSON.parse_string(FileAccess.get_file_as_string(source)))
	_check(expected.get("error") == OK, "retained original return expectation authenticates")
	if expected.get("error") != OK:
		return
	var before: Dictionary = app.progress_session.inspect()
	_check(before.error == OK and before.receipt.phase == "RESULT_READY" and before.hash == expected.payload.ready_hash,
		"independent process offers exactly the original frozen return hash")
	var button: BaseButton = app._continue_button
	var offset: Vector2 = Vector2.ZERO
	if not app._hunger_consented:
		await _tap(button)
		_check(app._hunger_confirmation.visible, "normal continuation reaches its explicit consent")
		button = app._hunger_confirmation.get_ok_button()
		offset = Vector2(app._hunger_confirmation.position)
	var measured: Dictionary = await preload("res://tests/m49_native_probe.gd").measure(app, viewport, button,
		func() -> bool: return app.camp_scene.is_visible_in_tree() and not app._progress_blocked and not app._requires_continue and app.get("_progress_busy") != true, offset)
	_check(not measured.get("timeout", false) and TransactionReceipt.same(app.camp_snapshot(), expected.payload.camp),
		"real continuation confirms the complete original return exactly once")
	var head: Dictionary = app.progress_session.inspect()
	var repeated: Dictionary = app.progress_session.activate()
	_check(head.error == OK and repeated.error == OK and head.hash == repeated.hash, "repeated confirmation retains the one original committed result")
	measured.ready_hash = expected.payload.ready_hash
	measured.committed_hash = head.get("hash", "")
	measured.pid = OS.get_process_id()
	measured.scope = "EXACT_FROZEN_RESULT_READY_NATIVE_RECOVERY_CONFIRMATION"
	_write("frozen-return.json", measured)
