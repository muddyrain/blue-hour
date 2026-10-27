class_name M302Playtest
extends M202Playtest
## Explicit M3-02 native multi-process proof, configured only by opt-in test arguments.


var _mode: String = "day1"
var _expected: Dictionary = {}
var _before: Dictionary = {}
var _sortie_reports: Array[Dictionary] = []
var _initial_save_hash: String = ""
var _initial_backup_hash: String = ""


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--m302-mode="):
			_mode = argument.trim_prefix("--m302-mode=")
		if argument.begins_with("--m302-expected="):
			var previous: RunSave = RunSave.new(argument.trim_prefix("--m302-expected="))
			_expect(previous.load_save() == OK, "preceding process snapshot validates")
			_expected = previous.snapshot
	_initial_save_hash = _hash(app.run_save.path)
	_initial_backup_hash = _hash(app.run_save.path+".bak")
	app.get_node("World").child_entered_tree.connect(_connect_feedback)
	app.audio_requested.connect(func(cue: StringName, world: bool, accepted: bool) -> void:
		_audio_events.append({"cue":String(cue),"world":world,"accepted":accepted,"frame":Engine.get_frames_drawn()})
	)
	await _wait(0.5)
	await _capture("m302-001-boot")
	if _mode == "corrupt":
		_expect(app._progress_blocked and app._backup_button.visible, "corrupt primary visibly blocks normal sortie and offers checked backup")
		await _click_screen(app._backup_button.get_global_rect().get_center())
		_expect(app.camp_snapshot() == _expected and _hash(app.run_save.path) == _initial_save_hash,
			"explicit native backup click restores camp without overwriting corrupt bytes")
		await _capture("m302-002-backup-camp")
		await _finish_proof()
		return
	if _mode != "day1":
		_expect(app._requires_continue and app._pending_save == _expected, "new process offers exact saved/migrated resource snapshot")
		if _mode == "legacy":
			_expect(app._status.text.contains("迁移默认值") and app.run_save.migrated_from == 1, "legacy migration default is disclosed in real window")
		await _click_screen(app._continue_button.get_global_rect().get_center())
		app.continue_game()
		_expect(app.camp_snapshot() == _expected and _hash(app.run_save.path) == _initial_save_hash,
			"Continue and duplicate Continue restore all state with no write or reward")
	else:
		_expect(not app.run_save.has_files() and app.food == 2 and app.cash == 53 and app.day == 2, "fresh progress starts at explicit temporary food seed")
	_before = app.camp_snapshot()
	await _capture("m302-003-camp-resources")
	await _check_audio_preferences()
	if _mode == "day2":
		await _click_control("Interface/Screen/Title/Reset")
		_expect(app._new_game_confirmation.visible, "new game still requires confirmation")
		await _capture("m302-004-new-game-confirmation")
		await _key(KEY_ESCAPE)
		_expect(app.camp_snapshot() == _before and _hash(app.run_save.path) == _initial_save_hash, "cancel new game preserves both resources and saved bytes")
	if _mode == "reopen":
		await _select_sortie(true)
		var sortie: Expedition = app.expedition
		_expect(sortie.initial_food == int(_before.food) and sortie.initial_cash == int(_before.cash), "next sortie receives actual restored food and cash")
		for member: Dictionary in _before.crew:
			_expect(sortie.survivors[int(member.id)-1].health == float(member.health), "next sortie restores stable member health")
		await _key(KEY_SPACE)
		await _capture("m302-005-reopened-sortie")
		await _finish_proof()
		return
	var kinds: Array[StringName] = [&"cash"]
	if _mode == "day1":
		kinds.append(&"food")
	elif _mode in ["day4", "legacy"]:
		kinds.assign([&"food"])
	await _play_action(kinds)
	await _finish_proof()


func _check_audio_preferences() -> void:
	await _click_control("Interface/Screen/Title/Sound")
	var panel: SoundSettingsPanel = app.sound_settings
	if _mode == "day1":
		for key: String in ["master_volume","sfx_volume","ui_volume"]:
			await _click_screen(panel.sliders[key].get_global_rect().get_center())
		await _click_screen(panel.save_button.get_global_rect().get_center())
		_expect(panel.message.text.begins_with("已保存"), "independent B1 preferences saved through real panel")
	else:
		_expect(app.audio_preferences.snapshot() == {"master_volume":0.5,"sfx_volume":0.5,"ui_volume":0.5,"muted":false}, "B1 preferences survive new process, separate from progress schema")
	await _capture("m302-005-sound-settings")
	await _click_screen(panel.back_button.get_global_rect().get_center())


func _select_sortie(has_food: bool) -> void:
	var before: Dictionary = app.camp_snapshot()
	var saved: String = _hash(app.run_save.path)
	await _click_control("Interface/Screen/Title/Start")
	_expect(app.mission_select.visible and app.phase == app.Phase.TITLE, "camp opens actual task choice before creating a sortie")
	if _mode == "day1":
		await _capture("m302-005-mission-choices")
		await _key(KEY_ESCAPE)
		_expect(not app.mission_select.visible and app.camp_snapshot() == before and _hash(app.run_save.path) == saved,
			"Escape cancels mission choice without advancing resources, date or disk")
		await _click_control("Interface/Screen/Title/Start")
	if _mode == "day2":
		await _key(KEY_ENTER)
	else:
		await _click_screen(app.mission_select.choices[1 if has_food else 0].get_global_rect().get_center())
	_expect(app.expedition.supply.id == (&"supermarket" if has_food else &"scavenge"), "chosen task config reaches normal expedition source rewards")
	if not has_food:
		app.expedition.request_search(&"food")
		_expect(app.expedition.search_actor == null and not app.expedition.search_site(&"food").prop.searchable,
			"scavenge task has no fake guaranteed food point or collect event")


func _play_action(kinds: Array[StringName]) -> void:
	await _select_sortie(&"food" in kinds)
	var sortie: Expedition = app.expedition
	sortie.finished.connect(func(report: Dictionary) -> void: _sortie_reports.append(report.duplicate(true)))
	await _capture("m302-006-arrival")
	if _mode == "day1":
		await _hud_inputs(sortie)
	var before_events: int = _audio_count("collect_complete")
	for index: int in range(kinds.size()):
		var kind: StringName = kinds[index]
		var building: Rect2 = sortie.layout.cash_block if kind == &"cash" else sortie.layout.food_block
		var framing: Vector2 = Vector2(880,580) if kind == &"cash" else Vector2(1260,580)
		sortie.camera.pan_by(framing-sortie.camera.position)
		sortie.command_move(Vector2(928,650) if kind == &"cash" else Vector2(1260,650))
		var point: Vector2 = Vector2(building.get_center().x,building.end.y-30)
		await _click_world(sortie,point)
		_expect(sortie.search_actor != null and sortie._active_site == sortie.search_site(kind), "real world click selects actual " + String(kind) + " point")
		await _until_inside(sortie)
		await _wait(1.0)
		await _key(KEY_SPACE)
		var progress: float = sortie.search_site(kind).progress
		await _click_world(sortie,point)
		_expect(sortie.search_actor == null and sortie.search_site(kind).progress == progress, "same-building pause cancel retains TMP work without payout")
		await _click_world(sortie,point)
		await _key(KEY_SPACE)
		await _until_inside(sortie)
		await _capture("m302-007-"+String(kind)+"-searching")
		if index == kinds.size()-1:
			while sortie.elapsed < sortie.tuning.bus_ready_seconds:
				await _wait(0.1)
			var hud: C1ExpeditionHud = sortie._hud.view
			if _mode == "day2":
				await _focus_via_tab(hud._bus_button)
				await _key(KEY_ENTER)
			else:
				await _click_screen(hud._bus_button.get_global_rect().get_center())
			_expect(sortie.phase == Expedition.Phase.ENGINE and sortie.search_actor != null, "bus starts during actual search")
			await _key(KEY_SPACE)
			var clock: float = sortie.elapsed
			await _wait(0.4)
			_expect(sortie.is_paused and sortie.elapsed == clock and app.audio._world_paused, "actual pause freezes timer, search and world audio")
			await _capture("m302-008-engine-paused")
			await _key(KEY_SPACE)
			_expect(not app.audio._world_paused, "world audio resumes with gameplay")
		var limit: int = 0
		while not sortie.search_site(kind).searched and app.phase == app.Phase.EXPEDITION and limit < 600:
			await _wait(0.1)
			limit += 1
		_expect(sortie.search_site(kind).searched and app.camp_snapshot() == _before, "completed search only changes carried resources, camp remains exact")
		var collected: int = _audio_count("collect_complete")
		sortie.request_search(kind)
		_expect(_audio_count("collect_complete") == collected, "completed point cannot replay collect sound")
		await _capture("m302-009-"+String(kind)+"-carried")
	_expect(_audio_count("collect_complete")-before_events == kinds.size(), "exactly one collect event for each actual searched point")
	_expect(sortie.loot == (4 if &"cash" in kinds else 0) and sortie.food_loot == (3 if &"food" in kinds else 0), "carried cash and food match distinct point choices")
	_expect(sortie._hud.view._currency.text.contains("携带+%d" % sortie.food_loot), "real HUD shows actual carried food")
	while sortie.phase == Expedition.Phase.ENGINE:
		await _wait(0.1)
	_expect(sortie.phase == Expedition.Phase.BOARDING, "bus waits for living members with search rules unchanged")
	sortie.camera.pan_by(Vector2(880,580)-sortie.camera.position)
	await _click_world(sortie,sortie.layout.bus_door)
	var limit: int = 0
	while app.phase != app.Phase.RESULT and limit < 400:
		await _wait(0.1)
		limit += 1
	_expect(app.phase == app.Phase.RESULT and not app._pending_settlement.is_empty(), "actual gathering and extraction produce one resource preview")
	var proposal: Dictionary = app._pending_settlement.duplicate(true)
	var callback: Callable = app._finish_callback
	callback.call({})
	_expect(app.camp_snapshot() == _before and app._pending_settlement == proposal, "duplicate finished report cannot bank or consume at result")
	_expect(proposal.last_day.food_required == 2 and proposal.last_day.ration_member_ids == [1,2], "ration transaction identifies the two living candidate ration members")
	for member: Dictionary in proposal.crew:
		_expect(float(member.health) == float(_sortie_reports[0].health[int(member.id)-1]), "shortage never changes actual post-combat health")
	await _capture("m302-010-result-preview")
	await _check_finished(sortie)
	await _wait(0.7)
	await _click_control("Interface/Screen/Result/Continue")
	callback.call({})
	app.return_to_title()
	if _mode == "day3":
		_expect(app._progress_dirty and app._retry_button.visible and app._status.text.contains("保存失败"), "real locked-file failure is visible in final native camp")
		_expect(_hash(app.run_save.path) == _initial_save_hash and _hash(app.run_save.path+".bak") == _initial_backup_hash, "native write failure preserves both prior file hashes")
		await _capture("m302-011-locked-save-failure")
		_write_json("release-lock.request",{"day":app.day,"food":app.food,"cash":app.cash})
		var waiting: int = 0
		while not FileAccess.file_exists(output_dir.path_join("lock-released.json")) and waiting < 200:
			await _wait(0.05)
			waiting += 1
		_expect(FileAccess.file_exists(output_dir.path_join("lock-released.json")), "runner acknowledges actual Windows handle release")
		await _click_screen(app._retry_button.get_global_rect().get_center())
	_expect(app.camp_snapshot() == proposal and not app._progress_dirty, "camp confirms exactly one transaction; any retry only persists it")
	_expect(app.run_save.load_save() == OK and app.run_save.snapshot == proposal, "saved snapshot matches ledger, health and identity exactly")
	if _mode == "day3":
		_expect(app.food == 0 and app.last_day.food_shortage == 1 and app._title.get_node("Camp").text.contains("缺"), "actual third day has visible shortage without hidden food debt or damage")
		_expect(HungerOutcome.candidate(app.last_day).loss_count == 1 and app._title.get_node("Camp").text.contains("损失候选1人"), "isolated shortage exposes unapplied loss candidate instead of claiming harmless original hunger")
	if _mode == "day4":
		_expect(app.food == 1 and app.last_day.food_found == 3 and app.last_day.cash_gained == 0, "food-only sortie recovers from shortage while currency stays unchanged")
	if _mode == "legacy":
		_expect(_hash(app.run_save.path+".bak") == _initial_save_hash, "native v1 upgrade retains exact old primary as backup")
		_expect(FileAccess.file_exists(app.run_save.path+".v1-"+_initial_save_hash+".json"), "native migration also retains immutable v1 original")
	_expect(_audio_count("bus_start") == 1 and _audio_accepted("collect_complete") > 0, "B1 accepts real collection and one bus event")
	if _mode == "day1":
		_expect(_audio_count("fire") > 0 and _audio_accepted("fire") > 0, "normal combat still emits and accepts fire audio")
	await _wait(1.0)
	await _capture("m302-012-saved-camp")


func _finish_proof() -> void:
	_write_json("camp.json",app.camp_snapshot())
	_write_json("run-report.json",{"mode":_mode,"pid":OS.get_process_id(),"display":DisplayServer.get_name(),
		"audio_driver":AudioServer.get_driver_name(),"window_size":[get_tree().root.size.x,get_tree().root.size.y],
		"checks":_checks,"behavior_checks":_checks-_captures.size(),"capture_checks":_captures.size(),
		"failures":_failures,"captures":_captures,"results":_results,"input_trace":_input_trace,
		"before":_before,"state":app.camp_snapshot(),"sortie_reports":_sortie_reports,
		"audio_requests":_audio_events,"combat_events":_feedback,"save_sha256":_hash(app.run_save.path),
		"backup_sha256":_hash(app.run_save.path+".bak"),"initial_save_sha256":_initial_save_hash,
		"input":"native renderer with viewport events and gameplay intents; no resource/health/time cheats; not hardware hand-feel"})
	print("BH_M302_VERIFY mode=%s pid=%d checks=%d failures=%d" % [_mode,OS.get_process_id(),_checks,_failures.size()])
	await _wait(0.5)
	if app.phase == app.Phase.TITLE:
		await _click_control("Interface/Screen/Title/Quit")
	else:
		app._quit()


func _write_json(name: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(output_dir.path_join(name),FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"\t",true,true)+"\n")
	file.close()


func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""


func _audio_accepted(cue: String) -> int:
	var count: int = 0
	for event: Dictionary in _audio_events:
		if event.cue == cue and event.accepted:
			count += 1
	return count
