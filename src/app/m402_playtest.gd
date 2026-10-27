class_name M402Playtest
extends M304Playtest
## Native dual-layout proof. Normal viewport controls/intents, no gameplay-value edits.

var _has_food: bool = false
var _map_trace: Array[Dictionary] = []
var _tracing: bool = false
var _trace_clock: float = 0.0
var _capture_names: Dictionary[String, int] = {}


func _physics_process(delta: float) -> void:
	if not _tracing or app.expedition == null:
		return
	_trace_clock += delta
	if _trace_clock < 0.2:
		return
	_trace_clock = 0.0
	var sortie: Expedition = app.expedition
	for actor: FieldActor in sortie.survivors:
		_map_trace.append({"elapsed":sortie.elapsed,"id":actor.actor_id + 1,"position":[actor.position.x, actor.position.y],
			"visible":actor.visible,"activity":actor.activity,"clear":sortie.navigation.is_clear(actor.position)})


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--m402-mode="):
			_sequence = argument.trim_prefix("--m402-mode=")
		if argument.begins_with("--m402-expected="):
			var previous: RunSave = RunSave.new(argument.trim_prefix("--m402-expected="))
			_expect(previous.load_save() == OK, "preceding process snapshot validates")
			_expected = previous.snapshot
	_has_food = _sequence in ["market", "reopen-market"]
	_mode = "day1" if _sequence == "scavenge" else "second"
	_initial_save_hash = _hash(app.run_save.path)
	_initial_backup_hash = _hash(app.run_save.path + ".bak")
	app.get_node("World").child_entered_tree.connect(_connect_feedback)
	app.audio_requested.connect(func(cue: StringName, world: bool, accepted: bool) -> void:
		_audio_events.append({"cue":String(cue),"world":world,"accepted":accepted,"frame":Engine.get_frames_drawn()}))
	await _capture("m402-001-home")
	if _sequence == "scavenge" and not app._requires_continue:
		await _click_screen(app._home_button.get_global_rect().get_center())
		await _rename(1, "Azure")
		await _rename(2, "Amber")
	else:
		_expect(app._requires_continue and app._pending_save == _expected, "new Windows process offers exact complete saved camp")
		await _click_screen(app._continue_button.get_global_rect().get_center())
		_expect(app.camp_snapshot() == _expected and _hash(app.run_save.path) == _initial_save_hash, "Continue restores resources, instances, names, health and service without writes")
	_before = app.camp_snapshot()
	await _capture("m402-002-camp")
	await _check_audio_preferences()
	await _click_screen(app._roster_button.get_global_rect().get_center())
	await _click_screen(app.roster_panel.member_buttons[1].get_global_rect().get_center())
	_expect((app.roster_panel._portrait.texture as AtlasTexture).atlas == CrewAppearance.AMBER_FULL, "Amber profile matches independent field character")
	await _capture("m402-003-amber-profile")
	await _click_screen(app.roster_panel.equipment_button.get_global_rect().get_center())
	await _capture("m402-004-equipment")
	await _key(KEY_ESCAPE)
	_expect(app.roster_panel.selected_member_id == 2, "equipment returns to Amber profile")
	await _key(KEY_ESCAPE)
	if _sequence.begins_with("reopen"):
		await _enter_task()
		await _key(KEY_SPACE)
		await _capture("m402-020-independent-reentry")
		_expect(app.camp_snapshot() == _expected and _hash(app.run_save.path) == _initial_save_hash, "independent reentry cannot reset or bank campaign")
	else:
		await _play_task()
		if _sequence == "scavenge":
			_carried_id = WeaponInventory.reward("%s:%d" % [app.profile_id, app.settled_sorties]).instance_id
			await _click_screen(app._loadout_button.get_global_rect().get_center())
			await _configure_weapons()
			await _key(KEY_ESCAPE)
		else:
			var equipped: String = WeaponInventory.for_member(_before, 1).instance_id
			_expect(_feedback.any(func(event: Dictionary) -> bool: return event.get("kind") == "shot" and event.get("instance_id") == equipped), "carried repaired loot actually fires after process restart on the other map")
		var saved: Dictionary = app.camp_snapshot()
		await _click_screen(app._roster_button.get_global_rect().get_center())
		await _capture("m402-018-saved-service")
		await _key(KEY_ESCAPE)
		var bytes: String = _hash(app.run_save.path)
		await _enter_task()
		await _key(KEY_SPACE)
		await _capture("m402-019-same-task-again")
		_expect(app.camp_snapshot() == saved and _hash(app.run_save.path) == bytes and not app.expedition.searched, "same task can be entered again with equipped saved party and clean local search state")
	_write_json("topology-trace.json", {"layout":String(app.expedition.layout.id),"samples":_map_trace})
	_mode = _sequence
	await _finish_proof()


func _capture(file_name: String) -> void:
	var occurrence: int = _capture_names.get(file_name, 0)
	_capture_names[file_name] = occurrence + 1
	if occurrence > 0:
		file_name += "-%02d" % (occurrence + 1)
	await _wait(0.35)
	await super._capture(file_name)
	if file_name in ["m402-001-home", "m402-003-amber-profile", "m402-004-equipment", "m402-005-missions", "m402-015-result", "m402-018-saved-service"]:
		await _wait(1.4)


func _enter_task() -> void:
	var before: Dictionary = app.camp_snapshot()
	await _click_control("Interface/Screen/Title/Start")
	await _capture("m402-005-missions")
	await _click_screen(app.mission_select.choices[1 if _has_food else 0].get_global_rect().get_center())
	var sortie: Expedition = app.expedition
	_expect(sortie.layout.id == (&"market_loop" if _has_food else &"repair_lane"), "selected task creates the corresponding physical map")
	_expect(sortie.navigation.obstacles == sortie.layout.blockers() and sortie._food_site.prop.searchable == _has_food, "actual navigation and usable sources follow map selection")
	for actor: FieldActor in sortie.survivors:
		var member: Dictionary = SurvivorRoster.member(before.crew, actor.actor_id + 1)
		var item: Dictionary = WeaponInventory.for_member(before, actor.actor_id + 1)
		_expect(actor.health == float(member.health) and actor.call_sign == member.call_sign and actor.weapon_instance_id == item.instance_id, "actual field actor retains saved identity, health and exact weapon ownership")
	_check_arrival_visibility(sortie)
	sortie.camera.zoom_at(Vector2(640, 360), 0.70 / sortie.camera.zoom.x)
	_check_arrival_visibility(sortie)
	await _capture("m402-006-arrival-wide")


func _check_arrival_visibility(sortie: Expedition) -> void:
	var view: C1ExpeditionHud = sortie._hud.view
	for actor: FieldActor in sortie.survivors:
		var point: Vector2 = sortie.get_global_transform_with_canvas() * actor.position
		var body: Rect2 = Rect2(point - Vector2(38, 80) * sortie.camera.zoom.x, Vector2(76, 84) * sortie.camera.zoom.x)
		var visible_body: bool = Rect2(0, 0, 1280, 720).encloses(body)
		for panel: Control in [view.get_node("MissionPanel"), view.get_node("ActionsPanel"), view._help_button]:
			visible_body = visible_body and not body.intersects(panel.get_global_rect())
		_expect(visible_body, "both arrival silhouettes remain outside opaque HUD at normal and wide zoom")


func _frame_at(sortie: Expedition, point: Vector2) -> void:
	sortie.camera.pan_by(point - Vector2(0, 100) - sortie.camera.position)
	await _wait(0.1)


func _play_task() -> void:
	await _enter_task()
	var sortie: Expedition = app.expedition
	_tracing = true
	sortie.finished.connect(func(report: Dictionary) -> void: _sortie_reports.append(report.duplicate(true)))
	await _hud_inputs(sortie)
	# A real legal route behind the cash building verifies selective roof transparency.
	var rear: Vector2 = Vector2(sortie.layout.cash_block.get_center().x, sortie.layout.cash_block.position.y - 80)
	await _frame_at(sortie, rear)
	await _click_world(sortie, rear)
	var limit: int = 0
	while not sortie._shop._roof.modulate.a < 1.0 and limit < 300:
		await _wait(0.1)
		limit += 1
	_expect(sortie._shop._roof.modulate.a < 1.0 and sortie._shop._wall.modulate.a == 1.0, "normal walk behind a building reveals party through roof while preserving front wall")
	await _capture("m402-007-roof-reveals-party")
	var kinds: Array[StringName] = [&"cash"]
	if _has_food:
		kinds.assign([&"food", &"cash"])
	var collects: int = _audio_count("collect_complete")
	for kind: StringName in kinds:
		var site: Expedition.SearchSite = sortie.search_site(kind)
		var block: Rect2 = sortie.layout.food_block if kind == &"food" else sortie.layout.cash_block
		await _frame_at(sortie, site.door)
		# Guard moves to the entrance via the same visible paths as the searcher.
		sortie.command_move(site.door + Vector2(112, 96))
		await _click_world(sortie, Vector2(block.get_center().x, block.end.y - 30))
		_expect(sortie.search_actor != null and sortie._active_site == site, "real map click assigns the selected " + String(kind) + " entrance")
		await _until_inside(sortie)
		await _wait(0.6)
		await _key(KEY_SPACE)
		var progress: float = site.progress
		await _click_world(sortie, Vector2(block.get_center().x, block.end.y - 30))
		_expect(sortie.search_actor == null and site.progress == progress and not site.searched, "pause cancel preserves unfinished work with no payout")
		await _click_world(sortie, Vector2(block.get_center().x, block.end.y - 30))
		await _key(KEY_SPACE)
		await _until_inside(sortie)
		await _capture("m402-008-" + String(kind) + "-search")
		if kind == kinds[-1]:
			while sortie.elapsed < sortie.tuning.bus_ready_seconds:
				await _wait(0.1)
			await _click_screen(sortie._hud.view._bus_button.get_global_rect().get_center())
			_expect(sortie.phase == Expedition.Phase.ENGINE and sortie.search_actor != null, "normal bus engine starts during search")
			await _key(KEY_SPACE)
			var clock: float = sortie.elapsed
			await _wait(0.5)
			_expect(sortie.elapsed == clock and app.audio._world_paused, "pause freezes search/engine/clock and world audio")
			await _capture("m402-009-engine-paused")
			await _key(KEY_SPACE)
		limit = 0
		while not site.searched and limit < 450:
			await _wait(0.1)
			limit += 1
		_expect(site.searched and app.camp_snapshot() == _before, "actual search pays once into carried resources, not camp")
		var completed: int = _audio_count("collect_complete")
		sortie.request_search(kind)
		_expect(_audio_count("collect_complete") == completed, "completed point cannot replay reward or sound")
		await _capture("m402-010-" + String(kind) + "-collected")
	_expect(sortie.loot == 4 and sortie.food_loot == (3 if _has_food else 0) and sortie.weapon_loot.size() == 1, "layout changes preserve exact existing mission reward contract")
	_expect(_audio_count("collect_complete") - collects == kinds.size() and _audio_accepted("fire") > 0 and sortie.kills > 0, "normal exploration includes real combat and exactly one collect cue per target")
	_expect(sortie._shop._roof.modulate.a == 1.0, "roof restores normally at front entrance")
	await _frame_at(sortie, sortie.layout.bus_door)
	await _click_world(sortie, sortie.layout.bus_door)
	limit = 0
	while app.phase != app.Phase.RESULT and limit < 400:
		await _wait(0.1)
		limit += 1
	_tracing = false
	_expect(app.phase == app.Phase.RESULT and _sortie_reports.size() == 1 and _sortie_reports[0].evacuated, "normal navigated gathering and bus evacuation produce exactly one result")
	var proposal: Dictionary = app._pending_settlement.duplicate(true)
	var callback: Callable = app._finish_callback
	callback.call({})
	_expect(app.camp_snapshot() == _before and app._pending_settlement == proposal, "result repeat never banks or consumes before camp")
	await _capture("m402-015-result")
	await _check_finished(sortie)
	await _click_control("Interface/Screen/Result/Continue")
	callback.call({})
	_expect(app.camp_snapshot() == proposal and app.run_save.load_save() == OK and app.run_save.snapshot == proposal and not app._progress_dirty, "return banks one exact v4 transaction, duplicate finish cannot repeat it")
	_expect(app.cash == int(_before.cash) + 4 and app.weapons.size() == _before.weapons.size() + 1 and app.day == int(_before.day) + 1, "normal extraction banks one weapon and unchanged cash/date behavior")
	var recorded_kills: int = 0
	for member: Dictionary in app.crew:
		var old: Dictionary = SurvivorRoster.member(_before.crew, int(member.id))
		recorded_kills += int(member.service.kills) - int(old.service.kills)
		_expect(member.service.sorties == int(old.service.sorties) + 1 and is_equal_approx(member.service.damage_received - old.service.damage_received, old.health - member.health), "real member service and health match actual outing")
	_expect(recorded_kills == int(_sortie_reports[0].kills) and app.loadout == _before.loadout, "personal kills sum correctly; sortie preserves unique weapon ownership")
	_expect(_map_trace.all(func(sample: Dictionary) -> bool: return sample.clear), "every sampled actual actor foot stays outside all buildings and fences")
	_expect(_audio_count("bus_start") == 1 and _audio_accepted("collect_complete") == kinds.size(), "sound accepts one bus and each successful collection")
	await _capture("m402-016-saved-camp")
