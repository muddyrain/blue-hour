class_name M401Playtest
extends M304Playtest
## Opt-in production UI proof, using the same legal gameplay and immutable states.


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--m304-mode="):
			_sequence = argument.trim_prefix("--m304-mode=")
	if _sequence in ["inspect", "corrupt"]:
		await _inspect_ui()
		return
	await _wait(0.5)
	await _capture("m401-001-home")
	if app._home_button.visible:
		await _click_screen(app._home_button.get_global_rect().get_center())
		await _capture("m401-002-entered-camp")
	await super._run()


func _capture(file_name: String) -> void:
	await _wait(0.6)
	await super._capture(file_name)
	if file_name in ["m401-001-home", "m401-002-entered-camp", "m304-002-roster", "m304-003-profile-equipment",
		"m302-005-mission-choices", "m302-010-result-preview", "m304-010-saved-service"]:
		await _wait(1.6)


func _select_sortie(has_food: bool) -> void:
	await super._select_sortie(has_food)
	var camera: FieldCamera = app.expedition.camera
	var position_before: Vector2 = camera.position
	var zoom_before: float = camera.zoom.x
	camera.zoom_at(Vector2(640,360),0.78 / zoom_before)
	camera.pan_by(Vector2(1070,650)-camera.position)
	await _capture("m401-003-street-wide")
	await _wait(1.6)
	camera.zoom_at(Vector2(640,360),zoom_before / camera.zoom.x)
	camera.pan_by(position_before-camera.position)


func _inspect_ui() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--m304-expected="):
			var saved: RunSave = RunSave.new(argument.trim_prefix("--m304-expected="))
			_expect(saved.load_save() == OK, "UI inspection uses checked real campaign snapshot")
			_expected = saved.snapshot
	_initial_save_hash = _hash(app.run_save.path)
	_initial_backup_hash = _hash(app.run_save.path + ".bak")
	_mode = _sequence
	await _capture("m401-001-home")
	if _sequence == "corrupt":
		_expect(app._progress_blocked and app._backup_button.visible and app._status.visible, "ordinary home visibly offers checked backup for corrupt save")
		await _capture("m401-008-corrupt-home")
		await _click_screen(app._backup_button.get_global_rect().get_center())
		_expect(app.camp_snapshot() == _expected and _hash(app.run_save.path) == _initial_save_hash, "backup choice restores exact camp without replacing invalid bytes")
		_before = app.camp_snapshot()
		await _capture("m401-009-backup-camp")
		await _finish_proof()
		return
	await _click_screen(app._continue_button.get_global_rect().get_center())
	_expect(app.camp_snapshot() == _expected, "redesigned Continue restores complete existing v4 state")
	_before = app.camp_snapshot()
	await _click_control("Interface/Screen/Title/Reset")
	_expect(app._new_game_confirmation.visible, "new game still requires confirmation")
	await _capture("m401-010-new-game-confirmation")
	await _key(KEY_ESCAPE)
	_expect(app.camp_snapshot() == _before and _hash(app.run_save.path) == _initial_save_hash, "new-game cancel preserves all campaign bytes")
	await _rename(1, "蓝时归航观察员一号同行者")
	await _rename(2, "暮色归航观察员二号同行者")
	_before = app.camp_snapshot()
	await _click_screen(app._roster_button.get_global_rect().get_center())
	await _capture("m401-004-long-names")
	_expect(app.roster_panel.back_button.get_global_rect().end.y <= 720.5, "long-name roster back stays on screen")
	await _click_screen(app.roster_panel.equipment_button.get_global_rect().get_center())
	await _capture("m401-005-long-inventory")
	for button: Button in app.loadout_panel.equip_buttons:
		_expect(button.get_global_rect().end.x <= 1280.5 and button.get_global_rect().end.y <= 720.5, "long-name equip controls stay on screen")
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	var bytes: String = _hash(app.run_save.path)
	await _select_sortie(false)
	await _key(KEY_SPACE)
	_expect(not app.expedition._food_site.prop.searchable and app.camp_snapshot() == _before, "scavenge visually closes supermarket and grants no new food or campaign change")
	await _capture("m401-007-scavenge-closed-market")
	_expect(_hash(app.run_save.path) == bytes, "paused uncompleted sortie cannot overwrite camp")
	await _finish_proof()
