extends "res://tests/m40_workshop_flow.gd"
## The same driver runs on the original source and on M47 with one isolated binding.


func _initialize() -> void:
	if "exercise_departure_review" in self:
		set("exercise_departure_review", true)
	super()


func _journey() -> void:
	var pilot: bool = "--bh-open-streets" in OS.get_cmdline_user_args()
	await _tap(app._home_button)
	await _tap(app._opening_picker.choices["scavenge"])
	await _tap(app._new_game_confirmation.get_ok_button())
	var camp: Dictionary = app.camp_snapshot()
	_check(app.camp_scene.is_visible_in_tree() and not app._progress_blocked, "original title creates an isolated camp")
	if not app.camp_scene.is_visible_in_tree() or app._progress_blocked:
		return
	var marker: Dictionary = camp.journey.build.opening
	var policy: int = int(camp.journey.campaign.get("open_streets_policy", 0))
	_check(marker.version == 1 and not marker.has("specialty") and (policy == OpenStreetsV1.VERSION if pilot else policy == 0),
		"original registration freezes only its historical map and opening rules")
	if not await _open_original_cards():
		return
	var index: int = app.mission_select.daily_offers.find_custom(func(action: Dictionary) -> bool:
		return action.type == "supply" and action.layout.has("open_streets") == pilot)
	_check(index >= 0, "old normal cards expose a supply action with the intended map strategy")
	if index < 0:
		return
	var expected: Dictionary = app.mission_select.daily_offers[index]
	var world: Expedition = await _start_original(index)
	if world == null:
		return
	_check(TransactionReceipt.same(expected, world.supply.generated), "old field enters the selected signed action")
	var site: Expedition.SearchSite = world.search_site(StringName(expected.objective.site_ids[0]))
	_check(site != null, "original primary food work is available")
	if site == null:
		return
	await _search(world, site)
	await _food(world, 5)
	_check(site.searched and world.food_loot > 0, "actual work adds food to the field carry ledger")
	await _suspend(world, "checkpoint.json", _field_facts(world).merged({
		"camp":RecordEncoding.fingerprint(camp), "policy":policy, "pilot":pilot,
		"seed":camp.journey.seed, "site":String(site.id), "opening":marker,
	}))
	var saved: Dictionary = app.progress_session.inspect()
	var receipt: Dictionary = saved.get("receipt", {})
	_check(saved.error == OK and saved.get("state") == "SUSPENDED" and receipt.get("phase") == "SUSPEND_READY"
		and TransactionReceipt.problem(receipt).is_empty(), "the original source durably seals a valid suspension receipt")
	_write("suspended.json", {"hash":saved.get("hash", ""), "phase":receipt.get("phase", ""),
		"transaction_id":receipt.get("transaction_id", ""), "pid":OS.get_process_id()})


func _resume() -> void:
	_check("--bh-open-streets" not in OS.get_cmdline_user_args(), "M47 uses only the saved map policy for old continuation")
	var source: Dictionary = _read_original("original/suspended.json")
	var suspended: Dictionary = app.progress_session.inspect()
	_check(not source.is_empty() and suspended.error == OK and suspended.get("hash") == source.get("hash"),
		"candidate opens the byte-authenticated suspension receipt at its original binding")
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var world: Expedition = app.expedition
	var checkpoint: Dictionary = _checkpoint(world, "original/checkpoint.json")
	if checkpoint.is_empty():
		return
	var camp: Dictionary = app.camp_snapshot()
	var field: Dictionary = _field_facts(world)
	for key: String in field:
		_check(field[key] == checkpoint.get(key), "cross-process field state matches original " + key)
	_check(RecordEncoding.fingerprint(camp) == checkpoint.camp and camp.journey.build.opening.version == 1
		and int(camp.journey.campaign.get("open_streets_policy", 0)) == int(checkpoint.policy),
		"the exact departure camp keeps its old opening and map policies")
	var before: Dictionary = _catalog_projection()
	_check(_no_specialty_credit(before), "M47 loads the old journey without generating specialty eligibility or XP")
	await _unpause(world)
	world.command_move(world.layout.bus_door)
	var committed: Dictionary = await _bank(world)
	var receipt: Dictionary = committed.get("receipt", {})
	var returned: Dictionary = app.camp_snapshot()
	_check(not committed.is_empty() and receipt.get("transaction_id") == source.get("transaction_id")
		and TransactionReceipt.problem(receipt).is_empty() and returned.last_day.get("evacuated") == true
		and int(returned.settled_sorties) == int(camp.settled_sorties) + 1,
		"actual bus return confirms one legal receipt for the original transaction")
	var after: Dictionary = _catalog_projection()
	_check(_no_specialty_credit(after) and after == before, "old return does not alter the M47 specialty projection")
	_write("resumed.json", {"source":source, "field":field, "policy":checkpoint.policy, "seed":checkpoint.seed,
		"snapshot":checkpoint.fingerprint, "return_hash":committed.get("hash", ""), "return_ledger":returned.last_day,
		"specialty_before":before, "specialty_after":after, "pid":OS.get_process_id()})


func _open_original_cards() -> bool:
	await _tap(app.camp_scene.hotspots[&"bus"])
	var menu: MissionSelect = app.mission_select
	var deadline: int = Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		if menu.visible and not menu.daily_offers.is_empty() and not menu.choices[0].disabled:
			return true
		await _frame()
	_check(false, "normal card menu becomes operable")
	return false


func _start_original(index: int) -> Expedition:
	await _tap(app.mission_select.choices[index])
	if app.expedition == null and "depart_button" in app.mission_select:
		await _tap(app.mission_select.get("depart_button"))
	var world: Expedition = app.expedition
	_check(world != null and not app._progress_blocked, "the old confirmed card starts an original outing")
	if world != null:
		world.set_physics_process(false)
		world.set_process(false)
		await _until(world, func() -> bool: return not world.bus_view.running())
	return world


func _field_facts(world: Expedition) -> Dictionary:
	var layout: Dictionary = world.layout.world_data
	return {"action_id":world.supply.generated.id, "action":RecordEncoding.fingerprint(world.supply.generated),
		"layout":RecordEncoding.fingerprint(layout), "route":RecordEncoding.fingerprint(layout.bus),
		"size":layout["size"], "theme":layout.topology, "revision":layout.get("open_streets", 0),
		"food":world.food_loot, "cash":world.loot, "weapons":RecordEncoding.fingerprint({"items":world.weapon_loot})}


func _catalog_projection() -> Dictionary:
	var state: Dictionary = app.progress_session.catalog_state()
	return {"error":state.get("error"), "xp":state.get("specialties", {}),
		"result":state.get("specialization_result", {}), "m47_run_id":state.get("m47_run_id", "")}


func _no_specialty_credit(value: Dictionary) -> bool:
	return value.error == OK and value.xp == {"scavenge":0, "firepower":0, "support":0} \
		and value.result.is_empty() and value.m47_run_id.is_empty()


func _read_original(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(path)))
	return value if value is Dictionary else {}
