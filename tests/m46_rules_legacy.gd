extends "res://tests/playable_flow.gd"
## Produce real M45 profiles on the pinned baseline and continue them on M46.


func _journey() -> void:
	_check(output.get_file() == "make-camp", "baseline starts with a fresh isolated profile")
	await _tap(app._home_button)
	if app._opening_picker.visible:
		await _tap(app._opening_picker.choices["scavenge"])
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(app.camp_scene.is_visible_in_tree() and not app._progress_blocked, "M45 creates the camp through normal startup")
	_capture_camp()


func _resume() -> void:
	_check(app._requires_continue and not app._camp_open, "normal startup offers Continue")
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	match output.get_file():
		"resume-camp":
			var previous: Dictionary = _read_previous("make-camp", "camp.json")
			var current: Dictionary = _capture_camp()
			_check(current.pid != previous.pid and current.camp == previous.camp and current.receipt == previous.receipt,
				"fresh process continues exact M45 camp and original receipt")
			_check(app.camp_scene.is_visible_in_tree() and not app._progress_blocked,
				"new runtime returns to usable camp UI")
		"make-sortie":
			await _make_sortie()
		"resume-sortie":
			_verify_sortie()
		_:
			_check(false, "known compatibility phase")


func _capture_camp() -> Dictionary:
	var camp: Dictionary = app.camp_snapshot()
	var status: Dictionary = app.progress_session.inspect()
	var marker: Dictionary = camp.get("journey", {}).get("campaign", {}).get("midgame", {})
	_check(marker.get("version") == 1 and not marker.has("upgraded_day") and status.error == OK,
		"camp stays on original M45 facility policy")
	var result: Dictionary = {"camp": RecordEncoding.fingerprint(camp), "receipt": status.get("hash", ""), "pid": OS.get_process_id()}
	_write("camp.json", result)
	return result


func _make_sortie() -> void:
	await _tap(app.camp_scene.hotspots[&"bus"])
	_check(not app.mission_select.daily_offers.is_empty(), "M45 opens ordinary action choices")
	if app.mission_select.daily_offers.is_empty():
		return
	await _tap(app.mission_select.choices[0])
	var world: Expedition = app.expedition
	_check(world != null, "M45 starts an original signed expedition")
	if world == null:
		return
	world.set_physics_process(false)
	world.set_process(false)
	if world.bus_view != null:
		await _advance(world, func() -> bool: return not world.bus_view.running(), 1800)
	app.open_pause_menu()
	await _hold(2)
	var captured: Dictionary = SortieSnapshot.capture(world)
	_check(not captured.is_empty(), "M45 captures the original live world")
	var result: Dictionary = _sortie_proof(world, captured)
	app.suspend_sortie()
	await _hold(4)
	var saved: Dictionary = app.progress_session.inspect()
	_check(app.expedition == null and app._requires_continue and saved.get("receipt", {}).get("phase") == "SUSPEND_READY",
		"M45 durably suspends through the normal gameplay entry")
	result.receipt = saved.get("hash", "")
	_write("sortie.json", result)


func _verify_sortie() -> void:
	var previous: Dictionary = _read_previous("make-sortie", "sortie.json")
	var world: Expedition = app.expedition
	_check(world != null and not app._progress_blocked, "M46 Continue restores the original M45 in-flight world")
	if world == null:
		return
	world.set_physics_process(false)
	world.set_process(false)
	var current: Dictionary = _sortie_proof(world, SortieSnapshot.capture(world))
	_check(current.pid != previous.pid and current.world == previous.world and current.action == previous.action
		and current.layout == previous.layout and current.instances == previous.instances and current.facility_version == 1,
		"different process restores the exact M45 world, signed action, map, and magazine instances")
	_write("sortie.json", current)


func _sortie_proof(world: Expedition, snapshot: Dictionary) -> Dictionary:
	var instances: Array[String] = []
	for actor: FieldActor in world.survivors:
		instances.append(actor.weapon_instance_id)
	return {"world": RecordEncoding.fingerprint(snapshot), "action": RecordEncoding.fingerprint(world.supply.generated),
		"layout": RecordEncoding.fingerprint(world.layout.world_data), "instances": instances,
		"facility_version": world.field_departure.get("journey", {}).get("campaign", {}).get("midgame", {}).get("version"),
		"pid": OS.get_process_id()}


func _read_previous(phase: String, file_name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(phase).path_join(file_name)))
