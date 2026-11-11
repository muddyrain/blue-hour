extends "res://tests/m48_campaign_flow.gd"
## Real M48 hardware work, original bus settlement, and original suspend/continue.
## Run every branch at the same bound profile path; preserve each original profile.

var _hardware_mode: String = ""


func _journey() -> void:
	_check(false, "hardware cases require the retained real common camp and --flow-resume")


func _resume() -> void:
	_hardware_mode = _argument("--flow-hardware=")
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	if _hardware_mode == "resume":
		await _hardware_resume()
		return
	_check(_hardware_mode in ["early", "partial"], "recognized independent hardware branch")
	if _hardware_mode not in ["early", "partial"]:
		return
	var common: Dictionary = _read("setup/common.json")
	var camp: Dictionary = app.camp_snapshot()
	_check(RecordEncoding.fingerprint(camp) == common.camp and camp.day == 5,
		"hardware branches start at the same real confirmed day-five common camp")
	if RecordEncoding.fingerprint(camp) != common.camp or int(camp.day) != 5:
		return
	route.assign(common.route)
	# One real ordinary supply action reaches the next periodic hardware opportunity.
	var preparation: Expedition = await _ordinary_supply()
	if preparation == null:
		return
	await _collect(preparation, 6)
	await _finish_outing(preparation)
	_check(app.day == 6 and not app._progress_blocked, "one real confirmed supply return reaches day six")
	if app.day != 6 or app._progress_blocked or not await _open_cards():
		return
	var index: int = _find_card(func(action: Dictionary) -> bool: return EconomyActions.hardware(action))
	_check(index >= 0, "normal day-six card offers the periodic hardware opportunity")
	if index < 0:
		return
	var before: Dictionary = app.camp_snapshot()
	var world: Expedition = await _start(index)
	if world == null:
		return
	var sources: Array[Dictionary] = EconomyActions.tool_sources(world.supply.generated)
	_check(sources.size() == 2 and sources[0] == {"site_id":"cash", "count":2}
		and sources[1].count == 1, "this real candidate has two main and one distinct optional unit")
	if sources.size() != 2:
		return
	var main: Expedition.SearchSite = world.search_site(StringName(sources[0].site_id))
	var optional: Expedition.SearchSite = world.search_site(StringName(sources[1].site_id))
	await _search(world, optional)
	_check(optional.searched and not main.searched and main.progress == 0.0,
		"only the real optional point is complete while the main cabinet is untouched")
	_check(EconomyActions.carried(world.supply.generated, WorldSites.facts(world)) == 1
		and EconomyBuildV1.tools(app.camp_snapshot()) == EconomyBuildV1.tools(before),
		"the carried optional unit is not confirmed camp stock")
	await _shot("hardware-optional-carried")
	if _hardware_mode == "early":
		await _food(world, 4)
		var action: Dictionary = world.supply.generated.duplicate(true)
		await _finish_outing(world)
		_assert_hardware_return(before, action, 1, false)
		_write("hardware-early.json", {"scope":"NORMAL_VIEWPORT_INTENTIONS_ACCELERATED_SIMULATION",
			"before":before, "after":app.camp_snapshot(), "action":action, "route":route,
			"report":reports.back(), "pid":OS.get_process_id()})
		return
	world.command_move(main.door)
	await _until(world, func() -> bool:
		return world.survivors.all(func(member: FieldActor) -> bool:
			return member.health <= 0 or member.position.distance_to(main.door) < 80.0))
	world.request_search(main.id)
	await _until(world, func() -> bool: return main.progress > 0.2)
	_check(not main.searched and main.progress < main.seconds, "main cabinet has real unfinished work before suspend")
	var proof: Dictionary = {"scope":"NORMAL_PARTIAL_HARDWARE_WORK", "before":before,
		"tools_before":EconomyBuildV1.tools(before), "action_id":world.supply.generated.id,
		"main_id":String(main.id), "optional_id":String(optional.id), "main_progress":main.progress,
		"optional_progress":optional.progress, "carried_tools":EconomyActions.carried(world.supply.generated, WorldSites.facts(world)),
		"route":route}
	await _suspend(world, "hardware-checkpoint.json", proof)


func _hardware_resume() -> void:
	var path: String = _argument("--flow-hardware-checkpoint=")
	_check(path.is_absolute_path() and "/.local/" in path and ".." not in path,
		"hardware continuation reads only the explicitly retained isolated checkpoint")
	if not path.is_absolute_path() or "/.local/" not in path or ".." in path:
		return
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(decoded is Dictionary, "the retained hardware checkpoint decodes")
	if not decoded is Dictionary:
		return
	var proof: Dictionary = decoded
	var world: Expedition = app.expedition
	_check(world != null and int(proof.pid) != OS.get_process_id(), "a separate PID restores the original hardware action")
	if world == null:
		return
	world.set_physics_process(false)
	world.set_process(false)
	world.finished.connect(func(report: Dictionary) -> void: reports.append(report.duplicate(true)))
	world.combat_feedback.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
	var snapshot: Dictionary = SortieSnapshot.capture(world)
	_check(RecordEncoding.fingerprint(snapshot) == proof.fingerprint
		and world.supply.generated.id == proof.action_id,
		"independent continuation preserves the complete original snapshot fingerprint and action")
	var main: Expedition.SearchSite = world.search_site(StringName(proof.main_id))
	var optional: Expedition.SearchSite = world.search_site(StringName(proof.optional_id))
	_check(main != null and optional != null and optional.searched and not main.searched
		and is_equal_approx(main.progress, float(proof.main_progress))
		and is_equal_approx(optional.progress, float(proof.optional_progress)),
		"searched optional point and unfinished main progress retain their exact original state")
	_check(EconomyBuildV1.tools(app.camp_snapshot()) == int(proof.tools_before)
		and EconomyActions.carried(world.supply.generated, WorldSites.facts(world)) == int(proof.carried_tools)
		and int(proof.carried_tools) == 1, "restarting does not prematurely bank or reissue the optional tool")
	if main == null or optional == null:
		return
	route.assign(proof.route)
	await _unpause(world)
	await _until(world, func() -> bool: return main.searched)
	_check(EconomyActions.carried(world.supply.generated, WorldSites.facts(world)) == 3,
		"finishing the original main work adds exactly its two carried units")
	await _food(world, 4)
	var action: Dictionary = world.supply.generated.duplicate(true)
	await _finish_outing(world)
	_assert_hardware_return(proof.before, action, 3, true)
	_write("hardware-restored.json", {"scope":"NORMAL_SEPARATE_PID_RESUME", "pid":OS.get_process_id(),
		"prior_pid":proof.pid, "checkpoint_fingerprint":proof.fingerprint, "restored_fingerprint":RecordEncoding.fingerprint(snapshot),
		"before":proof.before, "after":app.camp_snapshot(), "route":route, "report":reports.back()})
	await _shot("hardware-resumed-confirmed")


func _assert_hardware_return(before: Dictionary, action: Dictionary, expected_units: int, main_complete: bool) -> void:
	var after: Dictionary = app.camp_snapshot()
	var transaction: String = after.last_settlement_id
	var units: Array = EconomyBuildV1.state(after).tools.filter(func(unit: Dictionary) -> bool: return unit.transaction_id == transaction)
	var report: Dictionary = reports.back()
	_check(not app._progress_blocked and after.last_day.evacuated
		and EconomyBuildV1.tools(after) == EconomyBuildV1.tools(before) + expected_units
		and units.size() == expected_units, "normal original bus confirmation banks only the actually completed hardware units")
	var main_units: Array = units.filter(func(unit: Dictionary) -> bool: return unit.site_id == "cash")
	_check(main_units.size() == (2 if main_complete else 0)
		and report.site_facts.cash.searched == main_complete,
		"unfinished main cabinet cannot contribute either numbered main source")
	var identities: Array[String] = []
	for unit: Dictionary in units:
		_check(unit.id not in identities and unit.action_id == action.id, "every banked hardware unit retains one distinct actual action/site ordinal")
		identities.append(unit.id)
	_check(after.last_day.task.status == ("COMPLETED" if main_complete else "EARLY"),
		"hardware task outcome follows only the main cabinet completion")
	var committed: Dictionary = app.progress_session._transaction.recover()
	var repeated: Dictionary = app.progress_session._transaction.commit(RunTransaction.token_for(committed.receipt))
	_check(repeated.get("error") == OK and repeated.get("hash") == committed.get("hash")
		and RecordEncoding.fingerprint(after) == RecordEncoding.fingerprint(app.camp_snapshot()),
		"repeating the same return receipt does not add any hardware tool")
