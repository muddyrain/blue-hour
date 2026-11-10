extends "res://tests/m40_workshop_flow.gd"
## Run with both exact M45 source and the M46 candidate against the same test binding.


func _initialize() -> void:
	if "exercise_departure_review" in self:
		set("exercise_departure_review", true)
	super()


func _journey() -> void:
	await _tap(app._home_button)
	if app._opening_picker.visible:
		await _tap(app._opening_picker.choices["scavenge"])
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(app.camp_snapshot().journey.campaign.midgame.version == 1, "exact M45 creates its original facility-policy camp")
	if not await _open_cards():
		return
	var index: int = app.mission_select.daily_offers.find_custom(func(action: Dictionary) -> bool: return action.type == "supply")
	var world: Expedition = await _start(index)
	if world == null:
		return
	var site: Expedition.SearchSite = world.search_site(StringName(world.supply.generated.objective.site_ids[0]))
	await _search(world, site)
	await _food(world, 5)
	await _return(world)
	_write("old-camp.json", {"fingerprint":RecordEncoding.fingerprint(app.camp_snapshot()), "pid":OS.get_process_id()})


func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	match output.get_file():
		"m45-field", "m46-camp":
			await _continue_camp(output.get_file() == "m45-field")
		"m45-finish", "m46-finish":
			await _continue_field()


func _continue_camp(start_field: bool) -> void:
	var original: Dictionary = _read("m45-camp/old-camp.json")
	var camp: Dictionary = app.camp_snapshot()
	_check(original.pid != OS.get_process_id() and original.fingerprint == RecordEncoding.fingerprint(camp)
		and camp.journey.campaign.midgame.version == 1 and app.camp_scene.is_visible_in_tree(),
		"fresh process continues exact original camp with legacy facility policy")
	if not start_field and "exercise_departure_review" in self:
		await _tap(app.camp_scene.hotspots[&"bus"])
		var menu: MissionSelect = app.mission_select
		_check(menu.visible and menu.get("loading") == true and not menu.cancel_button.disabled,
			"actual cold wait is visible and its return control is active")
		await _tap(menu.cancel_button)
		_check(app.camp_scene.is_visible_in_tree() and not menu.visible and TransactionReceipt.same(camp, app.camp_snapshot()),
			"return cancels pending selection without changing the old camp")
	if not await _open_cards():
		return
	_write("offers.json", _offers())
	if not start_field:
		await _tap(app.mission_select.cancel_button)
		_check(app.camp_scene.is_visible_in_tree(), "new menu returns to the original camp")
		return
	var index: int = app.mission_select.daily_offers.find_custom(func(action: Dictionary) -> bool: return BillboardActionV1.enabled(action))
	for attempt: int in range(3):
		if index >= 0:
			break
		var ordinary: int = app.mission_select.daily_offers.find_custom(func(action: Dictionary) -> bool: return action.type == "supply" and action.slot == 0)
		var preliminary: Expedition = await _start(ordinary)
		if preliminary == null:
			return
		var main_site: Expedition.SearchSite = preliminary.search_site(StringName(preliminary.supply.generated.objective.site_ids[0]))
		await _search(preliminary, main_site)
		await _return(preliminary)
		if not await _open_cards():
			return
		index = app.mission_select.daily_offers.find_custom(func(action: Dictionary) -> bool: return BillboardActionV1.enabled(action))
	_check(index >= 0, "ordinary M45 card exposes the existing certified roadside billboard")
	var departure_camp: String = RecordEncoding.fingerprint(app.camp_snapshot())
	var world: Expedition = await _start(index)
	if world == null:
		return
	var board: Expedition.SearchSite = world.search_site(StringName(BillboardActionV1.SITE_ID))
	_check(board != null, "billboard is an actual in-world work point")
	if board == null:
		return
	await _search(world, board)
	await _food(world, 5)
	await _suspend(world, "checkpoint.json", {"action":RecordEncoding.fingerprint(world.supply.generated),
		"layout":RecordEncoding.fingerprint(world.layout.world_data), "camp":departure_camp})


func _continue_field() -> void:
	var world: Expedition = app.expedition
	var prior: Dictionary = _checkpoint(world, "m45-field/checkpoint.json")
	if prior.is_empty():
		return
	_check(RecordEncoding.fingerprint(world.supply.generated) == prior.action
		and RecordEncoding.fingerprint(world.layout.world_data) == prior.layout
		and RecordEncoding.fingerprint(app.camp_snapshot()) == prior.camp,
		"legacy field restores its exact action signature, layout and unmodified camp")
	await _unpause(world)
	await _return(world)
	var camp: Dictionary = app.camp_snapshot()
	var intel: Dictionary = BillboardIntelV1.opportunity(camp)
	_check(not intel.is_empty() and intel.day == camp.day and camp.journey.campaign.midgame.version == 1,
		"successful original return banks one real next-day M44 opportunity under the old economy")
	if not await _open_cards():
		return
	var offers: Dictionary = _offers()
	_check(offers.candidates.any(func(row: Dictionary) -> bool: return row.slot == 2 and not row.intel.is_empty()),
		"real next-day menu places billboard intelligence in the authenticated slot")
	_write("next-day.json", offers.merged({"intel":intel, "source_layout":prior.layout}))


func _offers() -> Dictionary:
	var records: Array[Dictionary] = []
	for action: Dictionary in app.mission_select.daily_offers:
		records.append({"id":action.id, "slot":action.slot, "type":action.type,
			"intel":action.get("billboard_target", {}), "signature":RecordEncoding.fingerprint(action),
			"layout":RecordEncoding.fingerprint(action.layout)})
	return {"candidates":records}


func _open_cards() -> bool:
	await _tap(app.camp_scene.hotspots[&"bus"])
	var deadline: int = Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		if app.mission_select.visible and not app.mission_select.daily_offers.is_empty() and not app.mission_select.choices[0].disabled:
			return true
		await _frame()
	_check(false, "normal card menu is ready")
	return false


func _start(slot: int) -> Expedition:
	_check(slot >= 0, "available original candidate")
	if slot < 0:
		return null
	await _tap(app.mission_select.choices[slot])
	if app.expedition == null and "depart_button" in app.mission_select:
		await _tap(app.mission_select.get("depart_button"))
	var world: Expedition = app.expedition
	_check(world != null and not app._progress_blocked, "real original departure starts")
	if world != null:
		world.set_physics_process(false)
		world.set_process(false)
		await _until(world, func() -> bool: return not world.bus_view.running())
	return world


func _return(world: Expedition) -> void:
	world.command_move(world.layout.bus_door)
	await _bank(world)


func _extract(world: Expedition) -> void:
	await _until(world, func() -> bool: return world.elapsed >= world.tuning.bus_ready_seconds)
	world.request_bus_action()
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.BOARDING)
	world.request_bus_gather()
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED)
	for tick: int in range(1500):
		if not world.bus_view.running():
			break
		world.step(STEP)
		if tick % 30 == 0:
			await _frame()
	_check(app.phase == app.Phase.RESULT, "real bus completes departure before original result")
	await _hold(3)


func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(path)))
