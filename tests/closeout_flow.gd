extends "res://tests/neighborhood_flow.gd"
## Reuse actual medium suspend setup, then comparable large extractions in new PIDs.

func _journey() -> void:
	FreezeProfile.enabled = true
	await super._journey()


func _resume() -> void:
	FreezeProfile.enabled = true
	var phase_name: String = output.get_file()
	if phase_name in ["restore", "large"]:
		await super._resume()
	else:
		var previous: String = "large" if phase_name == "large2" else "large2"
		var prior: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(previous + "/report.json")))
		await _tap(app._continue_button)
		if app._hunger_confirmation.visible:
			await _tap(app._hunger_confirmation.get_ok_button())
		_check(int(prior.pid) != OS.get_process_id(), "independent large sample process")
		_check(TransactionReceipt.same(prior.camp, app.camp_snapshot()), "large sample uses actual prior camp/history")
		await _menu()
		await _start("large")
		var world: Expedition = app.expedition
		var target: StringName = &"food" if world.supply.food_reward > 0 else &"cash"
		world.request_search(target)
		await _advance(world, func() -> bool: return world.search_site(target).searched)
		await _finish(world, phase_name == "large2")
		_write("daily-state.json", {"menu_history":menu_history,"reports":journey_reports})
	if not FreezeProfile.latest.is_empty():
		if not freeze_usec.is_empty():
			FreezeProfile.latest.longest_main_thread_block_usec = freeze_usec.max()
			FreezeProfile.latest.full_simulation_step_usec = freeze_usec.duplicate()
		_write("freeze-profile.json", FreezeProfile.latest)
		print("CLOSEOUT_FREEZE usec=", FreezeProfile.latest.total_usec,
			" target_500ms=", FreezeProfile.latest.total_usec <= 500000)
