extends "res://tests/task_flow.gd"
## A verified unpublished stage cannot become a reward or departure before retry/ACK.

func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	await _menu()
	await _start("equipment")
	var world: Expedition = app.expedition
	var target: StringName = &"food" if world.supply.food_reward > 0 else &"cash"
	world.request_search(target)
	await _advance(world, func() -> bool: return world.search_site(target).searched)
	var expected: Dictionary = WorldSites.carry(_selected.sites,WorldSites.facts(world),world.sortie_id,true)
	app.progress_session.fault_hook = func(point: String) -> Error:
		return ERR_CANT_CREATE if point == "after_record_flush" else OK
	world.request_bus_action()
	await _advance(world, func() -> bool: return world.phase == Expedition.Phase.BOARDING)
	world.request_bus_gather()
	await _advance(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED)
	_check(app._progress_blocked and TransactionReceipt.same(_before,app.camp_snapshot()), "failed preview publication never banks")
	_check(world.bus_view.stage == "exploring", "unpublished verified bytes never permit boarding/departure")
	app.return_to_title() # Original failure route exposes its explicit retry confirmation.
	app.open_mission_select()
	_check(not app.mission_select.visible, "publication failure blocks a new sortie")
	app.progress_session.fault_hook = Callable()
	await _tap(app._retry_button)
	var frozen: Dictionary = app.progress_session._transaction.recover()
	_check(frozen.error == OK and frozen.receipt.phase == "COMMITTED", "original retry confirmation commits the same frozen packet")
	_check(frozen.receipt.envelope.result.battle.loot == expected.loot and frozen.receipt.envelope.result.battle.food == expected.food, "retry keeps actual partial carry")
	var camp: Dictionary = app.camp_snapshot()
	_check(camp.day == _before.day+1 and camp.cash == _before.cash+expected.loot and camp.last_day.food_found == expected.food, "one ACK banks the retried partial result")
	var hash: String = FileAccess.get_sha256(app.progress_path)
	app.return_to_title()
	_check(hash == FileAccess.get_sha256(app.progress_path), "duplicate ACK never pays twice")
