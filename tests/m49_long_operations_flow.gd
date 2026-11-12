extends "res://tests/m49_recovery_flow.gd"
## Same original 100-receipt camp for native complete-operation comparisons.

const NativeProbe: Script = preload("res://tests/m49_native_probe.gd")
var operations: Dictionary = {}
var continue_active: bool = false
var continue_started: int = 0
var continue_previous: int = 0
var continue_feedback: int = -1
var continue_intervals: Array[int] = []
var continue_probes: Array[Dictionary] = []


func _capture_live_wait() -> void:
	# Startup already has its own paired default-entry measurements. This
	# comparison must also run on M48, which lacks the M49 operation clock.
	pass


func _observe_commit_paint() -> void:
	# Keep screenshot encoding outside every measured button interval.
	pass


func _resume() -> void:
	continue_started = Time.get_ticks_usec()
	continue_previous = continue_started
	continue_active = true
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	continue_active = false
	var sorted: Array[int] = continue_intervals.duplicate()
	sorted.sort()
	operations["continue"] = {"complete_ms":float(Time.get_ticks_usec()-continue_started)/1000.0,
		"feedback_ms":float(continue_feedback)/1000.0, "frame_intervals_usec":continue_intervals,
		"p95_frame_ms":float(sorted[int(ceil(sorted.size()*0.95))-1])/1000.0 if not sorted.is_empty() else 0.0,
		"max_frame_ms":float(sorted[-1])/1000.0 if not sorted.is_empty() else 0.0, "probes":continue_probes,
		"scope":"DIAGNOSTIC_DRIVER_START_THROUGH_COMPLETE_CAMP: existing actual keyboard Continue plus original hunger consent; includes all fixed helper frames, excludes PNG; not mouse-release timing"}
	var before: Dictionary = app.camp_snapshot()
	var state: Dictionary = app.progress_session.inspect()
	var minimum: int = 1 if "--long-driver-preflight" in OS.get_cmdline_user_args() else 100
	_check(state.error == OK and state.state == "CAMP" and int(state.receipt.revision) >= minimum,
		"normal Continue opens the retained authentic long camp")
	if state.error != OK or state.state != "CAMP":
		return
	operations.source = {"camp":RecordEncoding.fingerprint(before), "revision":state.receipt.revision,
		"day":before.day, "sorties":before.settled_sorties, "path":app.progress_path,
		"scope":"DRIVER_PREFLIGHT_ON_SHORT_ORIGINAL" if minimum == 1 else "NORMAL_SAME_ORIGINAL_CAMP_ONE_COLD_PROCESS_PER_VERSION_NO_DISK_CACHE_RESET"}
	var first: Dictionary = WeaponInventory.for_member(before, 1)
	var second: Dictionary = WeaponInventory.for_member(before, 2)
	_check(not first.is_empty() and not second.is_empty(), "same original two weapons support a real ownership swap")
	if first.is_empty() or second.is_empty():
		return
	app.open_loadout()
	await _hold(3)
	var armory: CampArmoryView = app.loadout_panel.armory
	armory.select_inventory(second.instance_id, 1)
	await _hold(3)
	operations["camp_save"] = await NativeProbe.measure(app, viewport, armory.confirm_equip, func() -> bool:
		return WeaponInventory.for_member(app.camp_snapshot(), 1).get("instance_id") == second.instance_id \
			and not app._progress_dirty and not app._progress_blocked and app.get("_progress_busy") != true)
	_check(app.cash == before.cash and app.food == before.food, "real ownership save changes no resource balance")
	_write("long-operations.json", operations)
	await _tap(armory.back_button)
	operations["task_cards"] = await NativeProbe.measure(app, viewport, app.camp_scene.hotspots[&"bus"], func() -> bool:
		return app.mission_select.is_visible_in_tree() and not app.mission_select.loading \
			and not app.mission_select.daily_offers.is_empty() and not app.mission_select.choices[0].disabled)
	_write("long-operations.json", operations)
	var world: Expedition = await _start(_find_card(func(action: Dictionary) -> bool:
		return action.type == "supply" and not PumpStationAction.enabled(action)))
	if world == null:
		return
	operations.action = _geometry(world.supply.generated)
	await _collect(world, 2)
	await _finish_outing(world)
	_write("long-operations.json", operations)
	await _shot("long-operations-confirmed")


func _initialize() -> void:
	super._initialize()
	RenderingServer.frame_post_draw.connect(_observe_continue)


func _observe_continue() -> void:
	if not continue_active or not is_instance_valid(app):
		return
	var now: int = Time.get_ticks_usec()
	continue_intervals.append(now-continue_previous)
	continue_previous = now
	var overlay: Variant = app.get("_operation_overlay")
	if continue_feedback < 0 and (app._hunger_confirmation.visible or app.camp_scene.is_visible_in_tree()
			or (is_instance_valid(overlay) and overlay.is_visible_in_tree())):
		continue_feedback = now-continue_started
	if continue_intervals.size() % 15 == 0:
		var event: InputEventMouseMotion = InputEventMouseMotion.new()
		event.position = Vector2(20,20)
		var sent: int = Time.get_ticks_usec()
		viewport.push_input(event,true)
		continue_probes.append({"processing_usec":Time.get_ticks_usec()-sent,"handled":viewport.is_input_handled()})


func _bank(world: Expedition) -> Dictionary:
	await _extract(world)
	var before: Dictionary = app.camp_snapshot()
	var token: Dictionary = app.progress_session.token.duplicate(true)
	var ready: Dictionary = app.progress_session._transaction.recover()
	_check(ready.error == OK and ready.receipt.phase == "RESULT_READY", "actual bus produces a fully authenticated long return")
	operations["return_confirm"] = await NativeProbe.measure(app, viewport, app.get_node("Interface/Screen/Result/Continue"), func() -> bool:
		return app.expedition == null and app.camp_scene.is_visible_in_tree() and not app._progress_blocked \
			and not app._progress_dirty and int(app.settled_sorties) == int(before.settled_sorties) + 1)
	var committed: Dictionary = app.progress_session._transaction.recover()
	var repeated: Dictionary = app.progress_session._transaction.commit(token)
	_check(committed.error == OK and repeated.error == OK and committed.hash == repeated.hash,
		"long return publishes one original settlement and remains idempotent")
	operations.return_identity = {"ready":ready.get("hash", ""), "committed":committed.get("hash", ""),
		"camp":RecordEncoding.fingerprint(app.camp_snapshot()), "pid":OS.get_process_id(), "route":"NORMAL_MAIN_SEARCH_TWO_FOOD_AND_ORIGINAL_BUS"}
	return committed
