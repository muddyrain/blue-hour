class_name MigrationPlaytest
extends BattlePlaytest
## Real main/viewport workflow, with one world step per rendered movie frame.

var _migration_case: String = "import"
var _choice: String = "MAIN"
var _expected: String = ""
var _handshake: bool = false


func _run() -> void:
	if not output_dir.is_absolute_path() or "/.local/" not in output_dir.replace("\\", "/").to_lower() or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--migration-case="):
			_migration_case = arg.trim_prefix("--migration-case=")
		if arg == "--migration-choice=BACKUP":
			_choice = "BACKUP"
		if arg == "--migration-map=market":
			_map = 1
		if arg.begins_with("--migration-expected="):
			_expected = arg.trim_prefix("--migration-expected=")
		if arg.begins_with("--migration-fail="):
			_fault_point = arg.trim_prefix("--migration-fail=")
		if arg.begins_with("--p0d-barrier="):
			_barrier = arg.trim_prefix("--p0d-barrier=")
		if arg == "--migration-handshake":
			_handshake = true
	app.progress_session.fault_hook = _fault
	await _settle()
	match _migration_case:
		"import", "retry":
			await _migration_ui()
			if not app._progress_blocked:
				await _normal_sortie()
		"reopen":
			await _enter()
			_initial = app.camp_snapshot()
			if not _expected.is_empty():
				_expect(TransactionReceipt.same(_initial, JSON.parse_string(FileAccess.get_file_as_string(_expected))), "fresh process restores every saved field without reading old source")
			await _capture("continue-camp.png")
			await _normal_sortie()
		"continue":
			await _enter()
			_initial = app.camp_snapshot()
			await _capture("continue-camp.png")
		"repeat":
			await _enter()
			var before: Dictionary = app.camp_snapshot()
			var bytes: String = _digest()
			await _tap(app._home_return)
			await _tap(app._migration_entry)
			_expect(not app.migration_panel.confirm_button.disabled and app.migration_panel.confirm_button.text == "继续已转换旅程", "completed-source preview offers current journey instead of importing again")
			await _tap(app.migration_panel.confirm_button)
			_expect(TransactionReceipt.same(before, app.camp_snapshot()) and bytes == _digest(), "repeat after two sorties keeps every current field and target byte")
		"ready":
			await _enter()
			await _normal_sortie()
		"commit": await _enter()
		"locked-continue":
			await _tap(app._continue_button)
			_expect(app._progress_blocked and app._progress_dirty, "real locked commit keeps the frozen result available for retry")
			await _capture("commit-locked.png")
		"battle-first", "death-pending":
			_case = "first"
			if _migration_case == "death-pending":
				_stop = "death"
			await _play()
		"battle-single":
			_case = "single"
			await _play()
		"battle-ended":
			await _enter()
			_expect(app._battle_meta.state == "FAILED" and app.phase == app.Phase.RESULT, "schema102 migrated final death remains a terminal journey after restart")
			if not app._migration_source.is_empty():
				var bytes: String = _digest()
				var preview: Dictionary = app.progress_session.preview_migration(app._migration_source, "MAIN")
				var repeated: Dictionary = app.progress_session.migrate(app._migration_source, preview.get("intent", {}))
				_expect(repeated.error == OK and repeated.state == "ENDED" and bytes == _digest(), "original migration authorization cannot revive or replace a FAILED journey")
			await _capture("terminal-reopened.png")
		"hold":
			_write(output_dir.path_join("barrier.json"), {"pid":OS.get_process_id(),"point":"hold"})
			while not FileAccess.file_exists(output_dir.path_join("release")):
				await get_tree().create_timer(0.03).timeout
		"source-changed":
			await _tap(app._migration_entry)
			_write(output_dir.path_join("barrier.json"), {"pid":OS.get_process_id(),"point":"preview"})
			while not FileAccess.file_exists(output_dir.path_join("release")):
				await get_tree().create_timer(0.03).timeout
			await _tap(app.migration_panel.confirm_button)
			_expect(app._progress_blocked and app.migration_panel.visible and not FileAccess.file_exists(app.progress_path), "external byte change invalidates UI preview before target creation")
			await _capture("source-changed-blocked.png")
		"locked-migration":
			await _tap(app._migration_entry)
			await _tap(app.migration_panel.confirm_button)
			_expect(app._progress_blocked and app.migration_panel.visible and not app._camp_open and not FileAccess.file_exists(app.progress_path + ".migration/seal.json"), "real Windows rename refusal keeps migration unsealed and inactive")
			await _capture("migration-locked.png")
		"observe":
			_expect(app._progress_blocked and not app._requires_continue, "incomplete/lost binding blocks before applying camp; no v5 fallback")
			var original: String = _digest()
			app.open_expedition()
			_expect(app.expedition == null and _digest() == original, "blocked target cannot start a sortie or restore old source")
			await _capture("recovery-blocked.png")
		"preview-blocked":
			var original: String = _digest()
			await _tap(app._migration_entry)
			if _choice == "BACKUP":
				await _tap(app.migration_panel.backup_button)
			_expect(app.migration_panel.confirm_button.disabled and _digest() == original, "unsafe source/target has explicit disabled confirmation without writes")
			await _capture("migration-blocked.png")
		"migrate-only": await _migration_ui()
		_:
			_expect(false, "known migration proof case")
	await _hold(30)
	var state: Dictionary = app.progress_session.inspect()
	_write(output_dir.path_join("report.json"), {"pid":OS.get_process_id(),"checks":_checks,"failures":_failures,
		"case":_migration_case,"display":DisplayServer.get_name(),"window_size":DisplayServer.window_get_size(),
		"camp":app.camp_snapshot(),"initial":_initial,"state":state.get("state"),"reason":state.get("reason", ""),
		"reports":_reports,"combat_events":_events,"confirmed_deaths":state.get("confirmed_deaths", []),"frame":Engine.get_frames_drawn(),"input_layer":"native viewport mouse/keyboard and gameplay intentions, not OS input"})
	print("BH_MIGRATION_UI case=%s checks=%d failures=%d" % [_migration_case, _checks.size(), _failures])
	app.audio.shutdown()
	OS.delay_msec(150)
	get_tree().quit(0 if _failures == 0 else 1)


func _migration_ui() -> void:
	var source_hashes: Dictionary = _source_hashes()
	_expect(app.survival_mode and not app._camp_open, "explicit schema102 migration starts unloaded")
	await _tap(app._migration_entry)
	if _choice == "BACKUP":
		_expect(app.migration_panel.confirm_button.disabled, "bad main does not silently select backup")
		await _capture("bad-main-blocked.png")
		await _tap(app.migration_panel.backup_button)
	if app._migration_preview.is_empty():
		_expect(false, "valid explicit source is previewed")
		return
	var preview: Dictionary = app._migration_preview.duplicate(true)
	_write(output_dir.path_join("preview.json"), preview)
	var first: bool = not DirAccess.dir_exists_absolute(app.progress_path + ".migration")
	_initial = SurvivalState.legacy(preview.initial)
	await _capture("migration-preview.png")
	await _hold(45)
	if first:
		await _tap(app.migration_panel.cancel_button)
		_expect(not FileAccess.file_exists(app.progress_path) and not DirAccess.dir_exists_absolute(app.progress_path + ".migration") and _source_hashes() == source_hashes, "Cancel creates no target/receipt and preserves source pair")
		await _tap(app._migration_entry)
		await _key_battle(KEY_ESCAPE)
		_expect(not app.migration_panel.visible and not FileAccess.file_exists(app.progress_path), "Esc leaves the legal page without target creation")
		await _tap(app._migration_entry)
		if _choice == "BACKUP":
			await _tap(app.migration_panel.backup_button)
		preview = app._migration_preview.duplicate(true)
	await _tap(app.migration_panel.confirm_button)
	if not _fault_point.is_empty():
		_expect(app._progress_blocked and app.migration_panel.visible and not app._camp_open, "write fault does not publish an active migrated camp")
		await _capture("migration-write-blocked.png")
		await _hold(45)
		_fault_point = ""
		await _tap(app.migration_panel.confirm_button)
	_expect(not app._progress_blocked and app._camp_open and not app.migration_panel.visible, "real confirmation reaches saved/registered/sealed camp")
	if app._progress_blocked:
		return
	var camp: Dictionary = app.camp_snapshot()
	_expect(SurvivalState.problem(camp).is_empty() and TransactionReceipt.same(SurvivalState.legacy(camp), _initial), "complete source snapshot preserved in actual main, no life/food/day/history change")
	_expect(camp.origin.migration_id == preview.initial.origin.migration_id and _source_hashes() == source_hashes, "one confirmed migration identity and both original byte hashes retained")
	app._confirm_migration()
	_expect(TransactionReceipt.same(camp, app.camp_snapshot()), "duplicate same confirmation callback cannot create another run")
	await _capture("migration-camp.png")
	await _hold(45)


func _enter() -> void:
	if _migration_case in ["battle-first", "death-pending"] and not app._camp_open and not app._requires_continue:
		await _migration_ui()
	else:
		await super._enter()


func _normal_sortie() -> void:
	var before: Dictionary = app.camp_snapshot()
	await _open_map(_map)
	if app.expedition == null:
		return
	var sortie: Expedition = app.expedition
	if app.survival_pilot:
		_expect(not sortie.battle_drill and sortie.drill_panel.buttons.is_empty(), "normal pilot uses only original safe spawns, without near-enemy buttons")
	sortie.finished.connect(func(report: Dictionary) -> void: _reports.append(report.duplicate(true)))
	sortie.combat_feedback.connect(func(event: Dictionary) -> void:
		var copy: Dictionary = event.duplicate(true)
		copy.frame = Engine.get_frames_drawn()
		_events.append(copy))
	await _ui_checks(sortie)
	sortie.request_search(&"cash")
	for frame: int in range(3600):
		if sortie.searched and sortie.kills > 0:
			break
		await _step(sortie)
	_expect(sortie.searched and sortie.kills > 0, "migrated actors really search, navigate, fire and defeat original safe-spawn enemies")
	if _map == 1:
		sortie.request_search(&"food")
		var hidden: bool = false
		for frame: int in range(3600):
			if sortie.search_actor != null and sortie.search_actor.activity == FieldActor.Activity.SEARCHING:
				hidden = hidden or not sortie.search_actor.visible
			if sortie.search_site(&"food").searched:
				break
			await _step(sortie)
		_expect(hidden and sortie.search_site(&"food").searched, "actual worker hides and completes food collection")
	await _capture("real-search-combat.png")
	await _tap(sortie._hud.view._bus_button)
	_expect(sortie.phase == Expedition.Phase.ENGINE and not sortie.boarding_status().ordered, "engine does not silently recall the migrated crew")
	for frame: int in range(180):
		if sortie.phase == Expedition.Phase.BOARDING:
			break
		await _step(sortie)
	await _key_battle(KEY_SPACE)
	var clock: float = sortie.elapsed
	sortie._hud.view._bus_button.grab_focus()
	await _key_battle(KEY_ENTER)
	_expect(sortie.is_paused and sortie.elapsed == clock and sortie.boarding_status().ordered, "paused keyboard gather keeps the original clock")
	sortie._hud.view._bus_button.release_focus()
	await _key_battle(KEY_SPACE)
	for frame: int in range(3600):
		if sortie.phase == Expedition.Phase.FINISHED:
			break
		await _step(sortie)
	_expect(_reports.size() == 1 and _reports[0].evacuated and not app._pending_settlement.is_empty(), "actual evacuation freezes one complete migrated result")
	if app._pending_settlement.is_empty():
		return
	_expect(FrozenSettlement.validate(app.progress_session.packet).is_empty(), "same original frozen-result validator accepts the full102 packet")
	await _capture("migration-result.png")
	await _hold(45)
	if _migration_case == "ready":
		return
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_expect(not app._progress_blocked and app.day == before.day + 1 and app.settled_sorties == before.settled_sorties + 1, "normal return commits the next original transaction only once")
	await _capture("returned-camp.png")
	await _hold(45)


func _source_hashes() -> Dictionary:
	return {"main":FileAccess.get_sha256(app._migration_source),"backup":FileAccess.get_sha256(app._migration_source + ".bak")}


func _fault(point: String) -> Error:
	if _handshake and point == _barrier:
		_write(output_dir.path_join("barrier.json"), {"pid":OS.get_process_id(),"point":point})
		var deadline: int = Time.get_ticks_msec() + 45000
		while not FileAccess.file_exists(output_dir.path_join("release")) and Time.get_ticks_msec() < deadline:
			OS.delay_msec(10)
		return OK
	return super._fault(point)
