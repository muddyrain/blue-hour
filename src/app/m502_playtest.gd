class_name M502Playtest
extends M501Playtest
## Native ordinary sorties plus explicitly labelled short-profile rehearsal.

var _pressure_mode: String = ""
var _spawns: Array[Dictionary] = []
var _threats: Array[Dictionary] = []
var _pressure_trace: Array[Dictionary] = []
var _sample_clock: float = 0.0
var _peak_enemies: int = 0
var _peak_corpses: int = 0
var _peak_process_ms: float = 0.0
var _peak_simulation_ms: float = 0.0
var _pause_done: bool = false
var _hud_checked: Dictionary[String, bool] = {}
var _pause_observations: Array[Dictionary] = []


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_instance_valid(app.expedition) or app.phase != app.Phase.EXPEDITION:
		return
	var sortie: Expedition = app.expedition
	_peak_enemies = maxi(_peak_enemies, sortie.enemies.size())
	_peak_corpses = maxi(_peak_corpses, sortie._corpses.size())
	_peak_process_ms = maxf(_peak_process_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_peak_simulation_ms = maxf(_peak_simulation_ms, float(sortie.last_simulation_usec) / 1000.0)
	_sample_clock += delta
	if _sample_clock >= 0.5:
		_sample_clock = 0.0
		var sample: Dictionary = sortie.threat_status()
		sample["movie_frame"] = Engine.get_frames_drawn()
		_pressure_trace.append(sample)


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--m402-mode="):
			_pressure_mode = argument.trim_prefix("--m402-mode=")
	app.get_node("World").child_entered_tree.connect(_connect_pressure)
	if not _pressure_mode.begins_with("night-") and not _pressure_mode.begins_with("short-") and _pressure_mode != "abort-night":
		await super._run()
		return
	_sequence = _pressure_mode
	_identity_mode = _pressure_mode
	_mode = _pressure_mode
	_has_food = _pressure_mode.ends_with("market")
	DirAccess.make_dir_recursive_absolute(output_dir)
	_initial_save_hash = _hash(app.run_save.path)
	_initial_backup_hash = _hash(app.run_save.path + ".bak")
	app.get_node("World").child_entered_tree.connect(_connect_feedback)
	app.audio_requested.connect(func(cue: StringName, world: bool, accepted: bool) -> void:
		_audio_events.append({"cue":String(cue), "world":world, "accepted":accepted, "frame":Engine.get_frames_drawn()}))
	await _capture("m502-001-home")
	if app._requires_continue:
		_expected = app._pending_save.duplicate(true)
		await _click_screen(app._continue_button.get_global_rect().get_center())
		_expect(app.camp_snapshot() == _expected and _hash(app.run_save.path) == _initial_save_hash, "continued pressure process restores exact previous camp without saving")
	else:
		await _click_screen(app._home_button.get_global_rect().get_center())
	_before = app.camp_snapshot()
	await _profiles()
	await _key(KEY_ESCAPE)
	await _enter_task()
	var sortie: Expedition = app.expedition
	_tracing = true
	sortie.finished.connect(func(report: Dictionary) -> void: _sortie_reports.append(report.duplicate(true)))
	_expect(not sortie.is_practice and sortie.threat_status().enabled, "normal mission uses real ThreatDirector and existing enemy system")
	var short: bool = _pressure_mode.begins_with("short-")
	_expect(sortie.threat_rehearsal == short and sortie.tuning.daylight_seconds == (21.0 if short else 105.0), "explicit profile is reported; ordinary sortie retains 105-second baseline")
	if _pressure_mode == "abort-night":
		await _until_time(sortie, 107.0)
		await _key(KEY_SPACE)
		await _capture("m502-abort-at-night")
		_expect(app.camp_snapshot() == _before and _hash(app.run_save.path) == _initial_save_hash, "aborting a live night sortie never banks rewards, injury or pressure state")
		await _finish_proof()
		return
	await _capture("m502-002-early-window")
	if short:
		await _until_time(sortie, 12.6)
		await _pause_cycle(sortie)
	await _collect_early(sortie)
	if not _pause_done:
		await _until_time(sortie, 68.5)
		await _pause_cycle(sortie)
	await _frame_at(sortie, sortie.layout.bus_door)
	await _click_world(sortie, sortie.layout.bus_door + Vector2(144,-48))
	await _until_time(sortie, 34.0 if short else 146.0)
	await _frame_at(sortie, (sortie.survivors[0].position + sortie.survivors[1].position) * 0.5)
	await _capture("m502-003-pressure-increased")
	if not short:
		var early: int = _spawn_window(0.5, 28.5)
		var late: int = _spawn_window(105.5, 133.5)
		_expect(early > 0 and late > early, "equal natural 28-second windows have more actual spawns at night than early")
	_expect(_threats.size() >= 2 and sortie.threat.stage >= ThreatDirector.Stage.NIGHT and sortie.phase == Expedition.Phase.ACTIVE, "natural stage warnings accompany actual generation, zero time causes no forced result")
	# Screen-safe enemies must walk from the map edge; short stage thresholds do not teleport them.
	if short:
		var contact_wait: int = 0
		while sortie.kills == 0 and contact_wait < 600:
			await _wait(0.1)
			contact_wait += 1
	_expect(sortie.living_count() == 2 and _audio_accepted("fire") > 0 and sortie.kills > 0, "two real characters fight with real sound and unchanged enemy stats through pressure")
	await _leave_under_pressure(sortie)
	var saved: Dictionary = app.camp_snapshot()
	var bytes: String = _hash(app.run_save.path)
	await _enter_task()
	await _key(KEY_SPACE)
	_expect(app.camp_snapshot() == saved and _hash(app.run_save.path) == bytes, "second sortie cannot replay settlement or change saved camp")
	await _capture("m502-008-fresh-sortie")
	await _finish_proof()


func _enter_task() -> void:
	await super._enter_task()
	if not app.expedition.is_practice:
		_expect(app.expedition.threat.stage == ThreatDirector.Stage.CALM and app.expedition.threat.transitions == 0 and app.expedition._spawn_count == 0, "new normal sortie resets threat stage, transition and spawn counts")


func _frame_at(sortie: Expedition, point: Vector2) -> void:
	# At wide zoom the bottom map edge projects behind C's existing action panel.
	# Frame the real ground before clicking it; never treat a swallowed click as movement.
	if point.distance_to(sortie.layout.bus_door) < 200.0:
		sortie.camera.zoom_at(get_viewport().get_visible_rect().size * 0.5, 1.1 / sortie.camera.zoom.x)
	await super._frame_at(sortie,point)


func _click_world(sortie: Expedition, point: Vector2) -> void:
	if point.distance_to(sortie.layout.bus_door) < 200.0:
		var screen: Vector2 = sortie.get_global_transform_with_canvas() * point
		_expect(not sortie._hud.view.get_node("ActionsPanel").get_global_rect().has_point(screen), "real bus ground command is framed outside opaque HUD")
	await super._click_world(sortie,point)
	if point.distance_to(sortie.layout.bus_door) < 200.0:
		_expect(sortie.goal.distance_to(point) < 1.0, "actual ground click reaches existing movement intent before evacuation is awaited")


func _capture(file_name: String) -> void:
	await super._capture(file_name)
	if not is_instance_valid(app.expedition) or app.phase != app.Phase.EXPEDITION:
		return
	var view: C1ExpeditionHud = app.expedition._hud.view
	var key: String = str(app.expedition.threat.stage) + str(get_viewport().get_visible_rect().size)
	if _hud_checked.has(key):
		return
	_hud_checked[key] = true
	var screen: Rect2 = get_viewport().get_visible_rect()
	for panel: Control in [view.get_node("MissionPanel"),view.get_node("ActionsPanel")]:
		_expect(screen.encloses(panel.get_global_rect()), "existing HUD panels stay inside actual viewport at current pressure stage")
	for label: Label in [view._time_label,view._time_text,view._time_hint]:
		if label.visible:
			var width: float = label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x
			_expect(width <= label.size.x + 0.5 and screen.encloses(label.get_global_rect()), "pressure time and warning text fit without clipping")
	_expect(view._time_hint.mouse_filter == Control.MOUSE_FILTER_IGNORE, "new pressure hint adds no world-input blocker")


func _connect_pressure(node: Node) -> void:
	if node is Expedition:
		var sortie: Expedition = node
		sortie.spawn_resolved.connect(func(event: Dictionary) -> void:
			var sample: Dictionary = event.duplicate(true)
			sample["movie_frame"] = Engine.get_frames_drawn()
			_spawns.append(sample))
		sortie.threat_changed.connect(func(state: Dictionary) -> void:
			var sample: Dictionary = state.duplicate(true)
			sample["movie_frame"] = Engine.get_frames_drawn()
			_threats.append(sample)
			_instant_capture.call_deferred("m502-stage-%d" % state.stage))


func _until_time(sortie: Expedition, target: float) -> void:
	var attempts: int = 0
	while sortie.elapsed < target and sortie.phase != Expedition.Phase.FINISHED and attempts < 2400:
		await _wait(0.1)
		attempts += 1
	_expect(sortie.elapsed >= target and sortie.phase != Expedition.Phase.FINISHED, "real simulation naturally reaches time %.1f without clock/health/reward injection" % target)


func _pause_cycle(sortie: Expedition) -> void:
	_pause_done = true
	await _key(KEY_SPACE)
	var before: Dictionary = _pressure_state(sortie)
	var frame_before: int = Engine.get_frames_drawn()
	await _capture("m502-pause-before")
	await _wait(8.0)
	var after: Dictionary = _pressure_state(sortie)
	var frame_after: int = Engine.get_frames_drawn()
	_expect(sortie.is_paused and _pressure_state(sortie) == before and app.audio._world_paused, "pause longer than full spawn cycle freezes time/threat/spawns/actors/cooldown/search/engine")
	await _capture("m502-pause-after-eight-seconds")
	await _key(KEY_SPACE)
	var resumed: Dictionary = _pressure_state(sortie)
	_expect(sortie._spawn_count == int(before.threat.spawned) and sortie._spawn_attempts == int(before.threat.attempts), "resume has no queued wall-clock catch-up spawn")
	var remaining: float = sortie._spawn_clock
	var count: int = sortie._spawn_count
	await _wait(remaining + 0.12)
	_expect(sortie._spawn_count == count + 1, "next simulation deadline produces exactly one normal enemy after resume")
	_pause_observations.append({"before":before,"after":after,"resumed":resumed,"after_next":_pressure_state(sortie),
		"movie_frame_before":frame_before,"movie_frame_after":frame_after})
	await _capture("m502-resumed-single-spawn")


func _pressure_state(sortie: Expedition) -> Dictionary:
	var actors: Array[Dictionary] = []
	for actor: FieldActor in sortie.survivors + sortie.enemies:
		actors.append({"id":actor.actor_id, "enemy":actor.is_enemy, "position":actor.position,
			"health":actor.health, "cooldown":actor.cooldown, "activity":actor.activity})
	return {"threat":sortie.threat_status(), "actors":actors, "engine":sortie._engine_clock,
		"phase":sortie.phase, "search":[sortie._cash_site.progress,sortie._food_site.progress], "corpses":sortie._corpse_times.duplicate()}


func _spawn_window(start: float, end: float) -> int:
	return _spawns.filter(func(event: Dictionary) -> bool:
		return event.reason == "spawned" and float(event.elapsed) >= start and float(event.elapsed) < end).size()


func _collect_early(sortie: Expedition) -> void:
	var kinds: Array[StringName] = [&"cash"]
	if _has_food:
		kinds.assign([&"food", &"cash"])
	for kind: StringName in kinds:
		var site: Expedition.SearchSite = sortie.search_site(kind)
		var block: Rect2 = sortie.layout.food_block if kind == &"food" else sortie.layout.cash_block
		await _frame_at(sortie, site.door)
		sortie.command_move(site.door + Vector2(112, 96))
		await _click_world(sortie, Vector2(block.get_center().x, block.end.y - 30))
		await _until_inside(sortie)
		var limit: int = 0
		while not site.searched and sortie.phase != Expedition.Phase.FINISHED and limit < 450:
			await _wait(0.1)
			if not _pause_done and sortie.elapsed >= 68.5:
				await _pause_cycle(sortie)
			limit += 1
		_expect(site.searched and app.camp_snapshot() == _before, "actual early search pays once into carried resources while camp stays unchanged")
		await _capture("m502-004-" + String(kind) + "-collected")


func _leave_under_pressure(sortie: Expedition) -> void:
	await _click_screen(sortie._hud.view._bus_button.get_global_rect().get_center())
	_expect(sortie.phase == Expedition.Phase.ENGINE and sortie.threat.stage >= ThreatDirector.Stage.NIGHT, "actual night bus starts with ordinary engine countdown and no forced result")
	await _frame_at(sortie, sortie.layout.bus_door)
	await _click_world(sortie, sortie.layout.bus_door)
	await _capture("m502-005-gathering-under-pressure")
	var limit: int = 0
	while app.phase != app.Phase.RESULT and limit < 500:
		await _wait(0.1)
		limit += 1
	_tracing = false
	_expect(app.phase == app.Phase.RESULT and _sortie_reports.size() == 1 and _sortie_reports[0].evacuated, "night gathering reaches one ordinary successful result")
	var proposal: Dictionary = app._pending_settlement.duplicate(true)
	var callback: Callable = app._finish_callback
	callback.call({})
	_expect(app.camp_snapshot() == _before and app._pending_settlement == proposal, "result duplicate cannot bank night rewards early")
	await _capture("m502-006-result")
	await _check_finished(sortie)
	await _click_control("Interface/Screen/Result/Continue")
	callback.call({})
	_expect(app.camp_snapshot() == proposal and app.run_save.load_save() == OK and app.run_save.snapshot == proposal, "return commits exactly one existing v4 transaction; no threat save fields")
	_expect(app.day == int(_before.day) + 1 and app.cash == int(_before.cash) + 4 and app.weapons.size() == _before.weapons.size() + 1 and app.loadout == _before.loadout, "night preserves food/weapon/source/equipment/date settlement boundaries")
	await _capture("m502-007-saved-camp")


func _finish_proof() -> void:
	_expect(_peak_enemies <= ThreatRules.ENEMY_CAP, "observed active enemy count remains within configured cap")
	_expect(_spawns.all(func(event: Dictionary) -> bool: return event.reason != "spawned" or event.legal), "all actual generated enemies occupy legal navigation ground")
	_write_json("night-pressure-report.json", {"mode":_pressure_mode, "spawns":_spawns, "threats":_threats,
		"pause_observations":_pause_observations,
		"trace":_pressure_trace, "early_28_seconds":_spawn_window(0.5,28.5), "night_28_seconds":_spawn_window(105.5,133.5),
		"peak_enemies":_peak_enemies, "peak_corpses":_peak_corpses, "observed_process_ms_max":_peak_process_ms,
		"observed_simulation_ms_max":_peak_simulation_ms,
		"scope":"Real engine/window events. Ordinary modes never modify clock/stats/rewards. short-* explicitly configures 21-second daylight before scene entry; same director and real bus/search/settlement. MovieWriter timing is not hardware FPS."})
	await super._finish_proof()
