class_name M301Playtest
extends M202Playtest
## Each invocation is one real native process; the Python runner owns restarts.

var _mode: String = "first"
var _expected: Dictionary = {}


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--m301-mode="):
			_mode = argument.trim_prefix("--m301-mode=")
		if argument.begins_with("--m301-expected="):
			var previous: RunSave = RunSave.new(argument.trim_prefix("--m301-expected="))
			_expect(previous.load_save() == OK, "previous process snapshot independently validates")
			_expected = previous.snapshot
	app.get_node("World").child_entered_tree.connect(_connect_feedback)
	app.audio_requested.connect(func(cue: StringName, world: bool, accepted: bool) -> void:
		_audio_events.append({"cue":String(cue),"world":world,"accepted":accepted})
	)
	await _capture("m301-001-boot")
	if _mode != "first":
		_expect(app._requires_continue and app._continue_button.visible, "new process offers explicit Continue")
		_expect(app._pending_save == _expected, "disk snapshot exactly matches preceding process camp")
		await _click_screen(app._continue_button.get_global_rect().get_center())
		_expect(app.camp_snapshot() == _expected, "Continue restores all fields without another settlement")
		app.continue_game()
		_expect(app.camp_snapshot() == _expected, "repeated Continue cannot grant resources")
		var unchanged: String = FileAccess.get_sha256(app.run_save.path)
		await _click_control("Interface/Screen/Title/Reset")
		_expect(app._new_game_confirmation.visible, "existing progress requires explicit new-game confirmation")
		await _capture("m301-002-new-game-confirmation")
		await _key(KEY_ESCAPE)
		_expect(not app._new_game_confirmation.visible, "Escape dismisses embedded New Game confirmation")
		_expect(app.camp_snapshot() == _expected and FileAccess.get_sha256(app.run_save.path) == unchanged,
			"cancel New Game preserves memory and exact saved bytes")
		await _capture("m301-003-continued-camp")
	else:
		_expect(not app.run_save.has_files() and not app._requires_continue, "clean isolated profile starts without disk writes")
	await _click_control("Interface/Screen/Title/Sound")
	var panel: SoundSettingsPanel = app.sound_settings
	if _mode == "first":
		await _click_screen(panel.sliders["master_volume"].get_global_rect().get_center())
		await _click_screen(panel.sliders["sfx_volume"].get_global_rect().get_center())
		await _click_screen(panel.sliders["ui_volume"].get_global_rect().get_center())
		await _click_screen(panel.save_button.get_global_rect().get_center())
		_expect(panel.message.text.begins_with("已保存"), "existing B1 panel explicitly saves non-default sound preferences")
	else:
		_expect(app.audio_preferences.snapshot() == {"master_volume":0.5,"sfx_volume":0.5,"ui_volume":0.5,"muted":false},
			"independent audio preferences also survive real process restart")
	await _capture("m301-004-sound")
	await _click_screen(panel.back_button.get_global_rect().get_center())
	if _mode == "reopen":
		await _click_control("Interface/Screen/Title/Start")
		await _click_screen(app.mission_select.choices[1].get_global_rect().get_center())
		_expect(app.expedition.day == app.day and app.expedition.loot == 0 and not app.expedition.searched,
			"third process can start the next clean normal sortie")
		for index: int in range(2):
			_expect(app.expedition.survivors[index].health == float(_expected.crew[index].health), "restored health is actually used by next sortie")
		await _capture("m301-005-next-sortie")
	else:
		await _complete_sortie()
	var file: FileAccess = FileAccess.open(output_dir.path_join("camp.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(app.camp_snapshot(), "\t") + "\n")
	file.close()
	file = FileAccess.open(output_dir.path_join("run-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"mode":_mode,"pid":OS.get_process_id(),"display":DisplayServer.get_name(),
		"audio_driver":AudioServer.get_driver_name(),"checks":_checks,"failures":_failures,
		"captures":_captures,"results":_results,"input_trace":_input_trace,"state":app.camp_snapshot(),"audio_requests":_audio_events,
		"combat_events":_feedback,"save_sha256":FileAccess.get_sha256(app.run_save.path),
		"backup_sha256":FileAccess.get_sha256(app.run_save.path + ".bak") if FileAccess.file_exists(app.run_save.path + ".bak") else "",
		"input":"native renderer, engine viewport events and ordinary gameplay intents; not human hardware play"}, "\t") + "\n")
	file.close()
	print("BH_M301_VERIFY mode=%s pid=%d checks=%d failures=%d" % [_mode, OS.get_process_id(), _checks, _failures.size()])
	if _mode == "reopen":
		app._quit()
	else:
		await _click_control("Interface/Screen/Title/Quit")


func _complete_sortie() -> void:
	var before: Dictionary = app.camp_snapshot()
	await _click_control("Interface/Screen/Title/Start")
	await _click_screen(app.mission_select.choices[1].get_global_rect().get_center())
	var sortie: Expedition = app.expedition
	var hud: C1ExpeditionHud = sortie._hud.view
	_expect(sortie.initial_cash == int(before.cash) and sortie.day == int(before.day), "normal HUD and rules receive actual camp progress")
	await _capture("m301-005-arrival")
	await _hud_inputs(sortie)
	sortie.command_move(Vector2(928, 650))
	sortie.request_search()
	await _until_inside(sortie)
	await _wait(1.0)
	sortie.toggle_pause()
	var progress: float = sortie.search_progress
	sortie.request_search()
	sortie.request_search()
	_expect(sortie.search_progress == progress and sortie.loot == 0, "search cancellation retains current rules and cannot pay twice")
	sortie.toggle_pause()
	await _until_inside(sortie)
	while sortie.enemies.is_empty() and sortie.elapsed < 15.0:
		await _wait(0.1)
	if not sortie.enemies.is_empty():
		sortie.command_move(sortie.enemies[0].position)
		await _wait(7.0)
	_expect(not _feedback.is_empty(), "ordinary expedition emits real combat events")
	await _capture("m301-006-combat")
	sortie.command_move(Vector2(928, 650))
	while sortie.elapsed < sortie.tuning.bus_ready_seconds:
		await _wait(0.1)
	await _click_screen(hud._bus_button.get_global_rect().get_center())
	_expect(sortie.phase == Expedition.Phase.ENGINE, "actual HUD starts bus with unchanged rule")
	await _key(KEY_SPACE)
	_expect(sortie.is_paused and app.audio._world_paused, "engine pause freezes world and audio")
	await _capture("m301-007-engine-paused")
	await _key(KEY_SPACE)
	await _wait(3.2)
	await _capture("m301-008-waiting")
	var limit: int = 0
	while not sortie.searched and limit < 450:
		await _wait(0.1)
		limit += 1
	_expect(sortie.searched and sortie.loot == 4 and hud._currency.text.contains("+4"), "normal search grants one real reward and HUD matches")
	await _capture("m301-009-collected")
	await _click_world(sortie, sortie.layout.bus_door)
	limit = 0
	while app.phase != app.Phase.RESULT and limit < 350:
		await _wait(0.1)
		limit += 1
	_expect(app.phase == app.Phase.RESULT and app.cash == int(before.cash) and app._pending_settlement.cash == int(before.cash) + 4,
		"normal extraction previews one reward until camp confirmation")
	var settled: Dictionary = app._pending_settlement.duplicate(true)
	var stale: Callable = app._finish_callback
	stale.call({})
	_expect(app._pending_settlement == settled and app.camp_snapshot() == before, "duplicate finished callback ignored at result")
	await _capture("m301-010-result")
	await _check_finished(sortie)
	await _click_control("Interface/Screen/Result/Continue")
	stale.call({})
	app.return_to_title()
	_expect(not app._progress_dirty and app.run_save.load_save() == OK and app.run_save.snapshot == settled,
		"return to camp saves once; repeated return and stale callback cannot settle again")
	_expect(app.cash == int(before.cash) + 4 and app.settled_sorties == int(before.settled_sorties) + 1,
		"one additional settlement after any previous process")
	if _mode == "second":
		var backup: RunSave = RunSave.new(app.progress_path)
		_expect(backup.load_save(true) == OK and backup.snapshot == before, "last valid camp retained byte-readable in backup")
	for cue: String in ["fire", "hit", "collect_complete", "bus_start"]:
		_expect(_audio_count(cue) > 0, "actual gameplay still binds sound cue " + cue)
	await _wait(1.0)
	await _capture("m301-011-saved-camp")
