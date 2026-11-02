class_name SurvivalPilotPlaytest
extends MigrationPlaytest
## Normal-start proof stays separate from explicit low-HP rehearsal controllers.


func _run() -> void:
	if not output_dir.is_absolute_path() or "/.local/" not in output_dir.replace("\\", "/") or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	var mode: String = "normal"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--pilot-case="):
			mode = arg.trim_prefix("--pilot-case=")
	await _settle()
	if mode == "blocked":
		_expect(app._progress_blocked and "上次行动中断" in app._progress_message, "no READY has an honest blocked continuation, no invented recovery")
		await _capture("interruption-blocked.png")
	else:
		await _enter()
		_initial = app.camp_snapshot()
		if mode == "normal":
			_expect(_initial.food == 2 and _initial.cash == 53 and _initial.day == 2 and _initial.weapons.size() == 2 and _initial.crew.all(func(row: Dictionary) -> bool: return row.health == 200) and _initial.journey.seed == "NONE", "normal200HP/2food starter values, never low-HP rehearsal")
		if mode == "reopen":
			_map = 1
		if mode == "shortage":
			await _shortage()
		elif mode in ["normal", "reopen"]:
			await _capture("normal-camp.png")
			await _normal_sortie()
		else:
			_expect(mode in ["continue", "create"], "known pilot case")
			await _capture("continued-camp.png")
	var state: Dictionary = app.progress_session.inspect()
	_write(output_dir.path_join("report.json"), {"pid":OS.get_process_id(),"checks":_checks,"failures":_failures,"case":mode,"camp":app.camp_snapshot(),"initial":_initial,"state":state.get("state"),"reason":state.get("reason",""),"visible_member_ids":app._camp_backdrop.visible_member_ids,"reports":_reports,"combat_events":_events,"display":DisplayServer.get_name(),"input_layer":"viewport events and actual gameplay intentions, not OS"})
	app.audio.shutdown()
	OS.delay_msec(150)
	get_tree().quit(0 if _failures == 0 else 1)


func _enter() -> void:
	if app._requires_continue:
		await super._enter()
		return
	await _capture("new-journey-entry.png")
	await _tap(app._home_button)
	_expect(app._new_game_confirmation.visible and not app.run_save.has_files(), "normal UI requires explicit first confirmation before any base write")
	await _capture("normal-start-confirmation.png")
	await _tap(app._new_game_confirmation.get_cancel_button())
	_expect(not app.run_save.has_files(), "cancel initial pilot creates no base")
	await _tap(app._home_button)
	await _key_battle(KEY_ESCAPE)
	_expect(not app.run_save.has_files() and not app._new_game_confirmation.visible, "Esc cancels without writing")
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	_expect(not app._progress_blocked and app._camp_open and app.progress_session.inspect().state == "CAMP", "first base and run/root binding durable before sortie")
	_expect(app._camp_backdrop.visible_member_ids == [1, 2], "only both actual original live portraits appear")


func _shortage() -> void:
	var before: Dictionary = app.camp_snapshot()
	await _open_map(0)
	var sortie: Expedition = app.expedition
	_expect(not sortie.battle_drill and sortie.drill_panel.buttons.is_empty(), "normal pilot never enables near-enemy rehearsal")
	sortie.request_search(&"cash")
	for frame: int in range(3600):
		if sortie.searched:
			break
		await _step(sortie)
	sortie.request_bus_action()
	for frame: int in range(180):
		if sortie.phase == Expedition.Phase.BOARDING:
			break
		await _step(sortie)
	sortie.request_bus_gather()
	for frame: int in range(3600):
		if sortie.phase == Expedition.Phase.FINISHED:
			break
		await _step(sortie)
	_expect(app._progress_blocked and app._pending_settlement.is_empty() and "生存政策尚未开放" in app._progress_message, "shortage refuses unapproved policy and reports blocked result")
	_expect(TransactionReceipt.same(before, app.camp_snapshot()), "no successful resource/day/death result is applied")
	await _capture("shortage-blocked.png")
	var body: Label = app.get_node("Interface/Screen/Result/Scroll/Body")
	_expect(body.get_line_count() >= 3 and body.get_minimum_size().y <= body.size.y, "blocked explanation wraps inside its actual result control")
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_expect(not app._camp_open and app._progress_blocked and not app.get_node("Interface/Screen/Title/Start").visible, "blocked result returns only to a blocked home, never a playable old camp")
	await _capture("shortage-blocked-home.png")
