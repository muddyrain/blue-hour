extends "res://tests/m46_campaign_flow.gd"
## Identical native driver for M47 and M48. Fresh isolated ordinary journeys only.
## Field steps are accelerated; wall-clock UI measurements never advance field time.

const COMPARISON_SEED: String = "m38-wave-01"
var comparison: Dictionary = {}
var comparison_m48: bool = false


func _journey() -> void:
	_check(DisplayServer.get_name() != "headless", "comparison requires a newly launched native renderer")
	if DisplayServer.get_name() == "headless":
		return
	var seed_argument: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bh-rescue-seed="):
			seed_argument = argument.trim_prefix("--bh-rescue-seed=")
	_check(seed_argument == COMPARISON_SEED, "both comparison versions use the explicit same seed argument")
	if seed_argument != COMPARISON_SEED:
		return
	await _tap(app._home_button)
	if app._opening_picker.visible:
		await _tap(app._opening_picker.choices["scavenge"])
	await _tap(app._new_game_confirmation.get_ok_button())
	var initial_camp: Dictionary = app.camp_snapshot()
	_check(app.camp_scene.is_visible_in_tree() and not app._progress_blocked
		and initial_camp.journey.seed == COMPARISON_SEED.md5_text() and int(initial_camp.settled_sorties) == 0,
		"ordinary title confirmation creates the first genuine same-seed camp")
	if not app.camp_scene.is_visible_in_tree() or app._progress_blocked:
		return
	comparison_m48 = initial_camp.journey.campaign.get("economy") is Dictionary
	comparison = {"scope":"NORMAL_NEW_JOURNEY_COLD_PROCESS_COMPARISON", "candidate":"M48" if comparison_m48 else "M47",
		"pid":OS.get_process_id(), "engine":Engine.get_version_info(), "renderer":RenderingServer.get_current_rendering_method(),
		"viewport":[viewport.size.x,viewport.size.y], "seed_argument":seed_argument, "actual_seed":initial_camp.journey.seed,
		"profile":app.progress_path, "initial_camp":RecordEncoding.fingerprint(initial_camp),
		"strategy":"scavenge; swap starter weapons between members 1/2; first ordinary supply card; squad-covered main objective; total food >= 4; bus return",
		"input":"native viewport mouse confirmation; normal UI preview selection and original movement/search/bus intentions",
		"physical_input":"NOT_TESTED", "field_clock":"SIMULATION_ACCELERATED: fixed 1/30 second real world steps; 30 steps between rendered test frames; no fixed wall-clock multiplier",
		"timing_scope":"mouse release to native rendered feedback/completion; screenshot encoding and source inspection occur after measurement"}
	_write_comparison()
	await _shot("comparison-01-starting-camp")
	if not await _comparison_equip(initial_camp):
		return
	var menu_sample: Dictionary = await _measure_native("cards",app.camp_scene.hotspots[&"bus"],func() -> bool:
		return (app.mission_select.is_visible_in_tree() and not app.mission_select.daily_offers.is_empty()
			and app.mission_select.choices[0].is_visible_in_tree() and not app.mission_select.choices[0].disabled))
	comparison.cards = menu_sample
	var candidates: Array[Dictionary] = []
	for action: Dictionary in app.mission_select.daily_offers:
		candidates.append(_comparison_action(action))
	comparison.candidates = candidates
	_write_comparison()
	if menu_sample.is_empty():
		return
	var slot: int = _find_card(func(action: Dictionary) -> bool:
		return (action.get("type") == "supply" and not action.has("investigation") and not action.has("rare_policy")
			and not action.get("campaign",{}).get("is_finale",false)))
	_check(slot >= 0, "the same first ordinary supply-card policy has a legal candidate")
	if slot < 0:
		return
	var selected: Dictionary = app.mission_select.daily_offers[slot].duplicate(true)
	comparison.selected = _comparison_action(selected)
	_write_comparison()
	await _shot("comparison-03-cards-ready")
	var world: Expedition = await _start(slot)
	if world == null:
		return
	comparison.world = {"action":_comparison_action(world.supply.generated),"bounds":_comparison_rect(world.layout.world_bounds),
		"simulated_start":world.elapsed,"health_before":world.survivors.map(func(actor: FieldActor) -> Dictionary:
			return {"member_id":actor.member_id,"health":actor.health,"weapon":actor.weapon_instance_id})}
	await _collect(world,4)
	var main: Expedition.SearchSite = world.search_site(&"cash")
	_check(main != null and main.searched and world.living_count() == initial_camp.crew.size(),
		"actual same-strategy main objective completes with the original living squad")
	if main == null or not main.searched:
		return
	comparison.world.simulated_objective_complete = world.elapsed
	comparison.world.sites = world.sites.map(func(site: Expedition.SearchSite) -> Dictionary:
		return {"id":String(site.id),"kind":String(site.kind),"searched":site.searched,"progress":site.progress})
	comparison.world.health_after = world.survivors.map(func(actor: FieldActor) -> Dictionary:
		return {"member_id":actor.member_id,"health":actor.health})
	_write_comparison()
	_write("comparison-objective-source.json",{"scope":"NORMAL_ACQUIRED_WORLD","generated":world.supply.generated,
		"world":RecordEncoding.stringify(SortieSnapshot.capture(world)),"elapsed":world.elapsed})
	await _shot("comparison-04-real-objective")
	world.command_move(world.layout.bus_door)
	await _extract(world)
	_check(not app._pending_settlement.is_empty() and not app._progress_blocked,
		"same actual bus evacuation prepares a genuine unconfirmed result")
	if app._pending_settlement.is_empty() or app._progress_blocked:
		return
	var before_return: Dictionary = app.camp_snapshot()
	var token: Dictionary = app.progress_session.token.duplicate(true)
	var ready: Dictionary = app.progress_session._transaction.recover()
	comparison.return_source = {"before_camp":RecordEncoding.fingerprint(before_return),"ready_receipt":ready.get("hash",""),
		"report":reports.back() if not reports.is_empty() else {},"simulated_end":world.elapsed}
	await _shot("comparison-05-return-preview")
	comparison.return_confirmation = await _measure_native("return",app.get_node("Interface/Screen/Result/Continue"),func() -> bool:
		return (app.expedition == null and app.camp_scene.is_visible_in_tree() and not app._progress_blocked
			and int(app.settled_sorties) == int(before_return.settled_sorties)+1))
	_write_comparison()
	var final_camp: Dictionary = app.camp_snapshot()
	var committed: Dictionary = app.progress_session._transaction.recover()
	var repeated: Dictionary = app.progress_session._transaction.commit(token)
	_check(committed.error == OK and committed.receipt.phase == "COMMITTED" and repeated.error == OK
		and repeated.hash == committed.hash and not app._progress_dirty and not app._progress_blocked
		and int(final_camp.settled_sorties) == 1 and int(final_camp.day) == int(initial_camp.day)+1,
		"measured return durably confirms exactly one original receipt")
	comparison.final = {"camp":RecordEncoding.fingerprint(final_camp),"receipt":committed.get("hash",""),
		"day":final_camp.day,"sorties":final_camp.settled_sorties,"cash":final_camp.cash,"food":final_camp.food,"ledger":final_camp.last_day}
	_write("comparison-confirmed-source.json",{"camp":final_camp,"receipt":committed.get("receipt",{}),"receipt_hash":committed.get("hash","")})
	_write_comparison()
	await _shot("comparison-06-confirmed-camp")


func _comparison_equip(before: Dictionary) -> bool:
	var first: Dictionary = WeaponInventory.for_member(before,1)
	var second: Dictionary = WeaponInventory.for_member(before,2)
	_check(not first.is_empty() and not second.is_empty() and first.instance_id != second.instance_id,
		"ordinary starters provide two real unique instances for the shared swap operation")
	if first.is_empty() or second.is_empty():
		return false
	await _tap(app.camp_scene.hotspots[&"weapons"])
	var armory: CampArmoryView = app.loadout_panel.armory
	armory.select_inventory(second.instance_id,1)
	await _hold(3)
	_check(armory.matches_equip(before,1,second.instance_id) and not armory.confirm_equip.disabled,
		"shared read-only armory preview proposes the exact legal two-owner swap")
	await _shot("comparison-02-swap-preview")
	comparison.camp_confirmation = await _measure_native("camp",armory.confirm_equip,func() -> bool:
		return (WeaponInventory.for_member(app.camp_snapshot(),1).get("instance_id") == second.instance_id
			and WeaponInventory.for_member(app.camp_snapshot(),2).get("instance_id") == first.instance_id
			and not app._progress_dirty and not app._progress_blocked))
	_write_comparison()
	var after: Dictionary = app.camp_snapshot()
	_check(after.cash == before.cash and after.food == before.food and TransactionReceipt.same({"weapons":after.weapons},{"weapons":before.weapons}),
		"real swap changes ownership without granting or consuming resources or instances")
	comparison.camp_source = {"before":RecordEncoding.fingerprint(before),"after":RecordEncoding.fingerprint(after),
		"request":{"kind":"equip","member_id":1,"value":second.instance_id},"preview_selection":"shared public read-only select_inventory helper",
		"receipt":app.progress_session._transaction.recover().get("hash","")}
	_write_comparison()
	await _shot("comparison-02b-swap-confirmed")
	await _tap(armory.back_button)
	return not comparison.camp_confirmation.is_empty() and app.camp_scene.is_visible_in_tree()


func _measure_native(operation: String, button: BaseButton, complete: Callable) -> Dictionary:
	_check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled,
		"measured %s operation starts at an enabled actual UI control" % operation)
	if not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled:
		return {}
	viewport.gui_release_focus()
	await RenderingServer.frame_post_draw
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.position = button.get_global_rect().get_center()
	mouse.global_position = mouse.position
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	viewport.push_input(mouse,true)
	await RenderingServer.frame_post_draw
	FreezeProfile.enabled = true
	FreezeProfile.start({"operation":operation,"comparison":true,"pid":OS.get_process_id()})
	var began: int = Time.get_ticks_usec()
	mouse = mouse.duplicate()
	mouse.pressed = false
	viewport.push_input(mouse,true)
	var dispatch_return: int = Time.get_ticks_usec()-began
	var previous: int = began
	var largest: int = 0
	var first_paint: int = -1
	var first_feedback: int = -1
	var first_state: String = ""
	var rendered_frames: int = 0
	var waiting_return: bool = false
	var wait_observed: bool = false
	while Time.get_ticks_usec()-began < 90000000:
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		largest = maxi(largest,now-previous)
		previous = now
		rendered_frames += 1
		if first_paint < 0:
			first_paint = now-began
		var done: bool = complete.call()
		var visible_state: String = "CONFIRMED" if done else ""
		if operation == "cards" and app.mission_select.is_visible_in_tree():
			visible_state = "CARDS_READY" if done else "WAITING"
			waiting_return = waiting_return or (not done and app.mission_select.cancel_button.is_visible_in_tree() and not app.mission_select.cancel_button.disabled)
		elif operation == "return" and comparison_m48 and app.get("_camp_commit_busy") == true and button.text.contains("正在确认归航"):
			visible_state = "WAITING"
		elif operation == "camp" and app.loadout_panel.is_visible_in_tree() and app.loadout_panel.armory.message.text.contains("正在保存"):
			visible_state = "WAITING"
		wait_observed = wait_observed or visible_state == "WAITING"
		if first_feedback < 0 and not visible_state.is_empty():
			first_feedback = now-began
			first_state = visible_state
		if done:
			if FreezeProfile.active:
				FreezeProfile.finish()
			var result: Dictionary = {"operation":operation,"release_monotonic_usec":began,"completed_monotonic_usec":now,
				"input_dispatch_return_usec":dispatch_return,"first_rendered_frame_usec":first_paint,
				"first_visible_feedback_usec":first_feedback,"first_visible_state":first_state,"completed_paint_usec":now-began,
				"first_visible_feedback_ms":first_feedback/1000.0,"confirmation_ms":(now-began)/1000.0,"max_frame_ms":largest/1000.0,
				"max_frame_interval_usec":largest,"rendered_frames":rendered_frames,"wait_state_observed":wait_observed,
				"waiting_return_visible":waiting_return,"profile":FreezeProfile.latest.duplicate(true),
				"profile_scope":"operation wall time includes native frame waits; nested stages measure main-thread spans; not pure synchronous callback duration",
				"screenshots_during_measurement":false}
			_check(first_feedback >= 0,"measured %s confirmation has an actual rendered feedback state" % operation)
			return result
	if FreezeProfile.active:
		FreezeProfile.finish()
	_check(false,"measured %s operation completes within ninety wall-clock seconds" % operation)
	_write("comparison-timeout-%s.json" % operation,{"elapsed_usec":Time.get_ticks_usec()-began,"first_feedback_usec":first_feedback,
		"max_frame_interval_usec":largest,"profile":FreezeProfile.latest})
	return {}


func _search(world: Expedition, site: Expedition.SearchSite) -> void:
	# Identical original intentions in both candidates, so the worker stays covered.
	world.command_move(site.door)
	await _until(world,func() -> bool:
		return world.survivors.all(func(actor: FieldActor) -> bool: return actor.health <= 0.0 or actor.position.distance_to(site.door) < 80.0))
	world.request_search(site.id)
	await _until(world,func() -> bool: return site.searched)


func _comparison_action(action: Dictionary) -> Dictionary:
	var map: Dictionary = action.get("layout",{})
	return {"id":action.get("id",""),"slot":action.get("slot",-1),"type":action.get("type",""),
		"size":map.get("size",""),"theme":map.get("topology",""),"map_id":map.get("id",""),
		"layout_fingerprint":RecordEncoding.fingerprint(map),"generated_fingerprint":RecordEncoding.fingerprint(action)}


func _comparison_rect(rect: Rect2) -> Array:
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]


func _write_comparison() -> void:
	_write("comparison.json",comparison)


func flow_input_description() -> String:
	return "Native viewport mouse for measured UI confirmations; original squad movement/search/bus intentions. Field simulation accelerated at fixed 1/30s steps, 30 steps per rendered test frame; no HP/resource mutation."
