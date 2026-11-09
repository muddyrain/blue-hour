extends "res://tests/m40_workshop_flow.gd"
## M41 path-bound same-camp branches. Steps simulation on the real world; UI controls use viewport input.

var _phase_name: String
var _baseline_spawns: int
var _baseline_requests: int
var _first_work: float = -1.0
var _work_seconds: float = 0.0


func _journey() -> void:
	_phase_name = output.get_file()
	if _phase_name == "tool-first":
		await super._journey()
		await _facility(CampFacilities.WORKSHOP)
		await _tool_route(true)
		return
	await _tap(app._home_button)
	await _tap(app._opening_picker.choices["scavenge"])
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(app.day == 2 and app.camp_scene.visible, "normal new journey starts at day two")
	await _tap(app.camp_scene.hotspots[&"bus"])
	var day_two: Array[Dictionary] = app.mission_select.daily_offers
	_check(day_two.size() == 3 and _event_index(day_two) == -1, "T0 day two preserves all ordinary slots")
	var investigation: int = day_two.find_custom(func(action: Dictionary) -> bool: return action.has("investigation"))
	_check(investigation >= 0, "day two original investigation available")
	if investigation < 0:
		return
	var world: Expedition = await _start(investigation)
	if world == null:
		return
	await _search(world, world.search_site(&"cash"))
	await _food(world, 6)
	await _bank(world)
	_check(app.day == 3, "one original confirmed return reaches day three")
	await _tap(app.camp_scene.hotspots[&"bus"])
	var first: Array[Dictionary] = app.mission_select.daily_offers.duplicate(true)
	_check(_event_index(first) >= 0, "T0 real normal day-three offer contains the emergency station")
	await _tap(app.mission_select.cancel_button)
	await _tap(app.camp_scene.hotspots[&"bus"])
	_check(TransactionReceipt.same({"offers":first}, {"offers":app.mission_select.daily_offers}), "T0 opening and closing cards cannot reroll")
	_write("offers.json", {"offers":first, "fingerprint":RecordEncoding.fingerprint({"offers":first}), "seed":app.camp_snapshot().journey.seed, "day":app.day})
	if _event_index(first) >= 0:
		_protected_slots(app.camp_snapshot(), first)


func _resume() -> void:
	_phase_name = output.get_file()
	if _phase_name == "tool-resume":
		await super._resume()
		return
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	if _phase_name in ["b-resume", "b-unstarted-resume"]:
		await _resume_branch()
		return
	var world: Expedition = await _open_event()
	if world == null:
		return
	if _phase_name == "early":
		await _return(world, "", 0, 0)
		return
	var branch: String = EventSortieV1.QUIET if _phase_name in ["a", "failed"] else EventSortieV1.FORCE
	var site: Expedition.SearchSite = world.search_site(StringName(EventSortieV1.site_id(world.supply.generated)))
	await _choose(world, site, branch)
	if _phase_name == "b-unstarted":
		_check(site.progress == 0.0 and not world.task_event.started, "T3 saved locked B before any actual work")
		await _event_suspend(world, site)
		return
	if _phase_name == "b-capacity":
		await _capacity_case(world, site)
		return
	if _phase_name == "b-first":
		await _timed_work(world, site, func() -> bool: return site.progress >= 2.0)
		_check(not site.searched and world.task_event.started, "T3 B alarm and real partial work exist before safety suspend")
		_event_negatives(world, site)
		await _event_suspend(world, site)
		return
	await _timed_work(world, site, func() -> bool: return site.searched)
	if _phase_name == "failed":
		await _fail_evacuation(world)
		return
	await _return(world, branch, 0, 3)


func _event_index(offers: Array[Dictionary]) -> int:
	return offers.find_custom(func(action: Dictionary) -> bool: return action.has("event_sortie"))


func _protected_slots(camp: Dictionary, current: Array[Dictionary]) -> void:
	var legacy: Dictionary = camp.duplicate(true)
	legacy.journey.campaign.erase("event_sortie_policy")
	var prior: Array[Dictionary] = InvestigationActions.offers(legacy)
	_check(prior.size() == current.size() and _event_index(prior) == -1, "T0 policy-free camp preserves original M40 candidate")
	for offer: Dictionary in current:
		if not offer.has("event_sortie"):
			_check(prior.any(func(old: Dictionary) -> bool: return TransactionReceipt.same(offer, old)), "T0 protected non-event slot unchanged: %s" % offer.slot)
	var original: Dictionary = {}
	for offer: Dictionary in prior:
		if offer.slot == SortieRiskV1.SLOT:
			original = offer
			break
	_check(not original.is_empty() and original.type == "airdrop" and not original.has("rare_policy"), "T0 the replaced offer was original ordinary equipment")
	if not original.is_empty():
		var invalid_route: Dictionary = original.duplicate(true)
		var blocked: Vector2 = WorldLayout.rect(invalid_route.layout.entities[0].rect).get_center()
		for site: Dictionary in invalid_route.sites:
			if site.id == EventSortieV1.SITE:
				site.point = [blocked.x, blocked.y]
		_check(EventSortieV1.freeze(invalid_route).is_empty() and EventSortieV1.freeze(original).has("event_sortie"),
			"T0 a real obstruction fails route certification while the original candidate remains legal")
	for sample: String in ["m41-protected-03", "m41-protected-34"]:
		var directed: Dictionary = camp.duplicate(true)
		directed.journey.seed = sample.md5_text()
		var protected_offers: Array[Dictionary] = InvestigationActions.offers(directed)
		directed.journey.campaign.erase("event_sortie_policy")
		var without_policy: Array[Dictionary] = InvestigationActions.offers(directed)
		var protected_type: bool = protected_offers.any(func(offer: Dictionary) -> bool:
			return offer.type == "rescue" if sample.ends_with("03") else offer.has("rare_policy"))
		_check(EventSortieV1.selected(directed.journey.seed, int(directed.day), SortieRiskV1.SLOT)
			and protected_type and TransactionReceipt.same({"offers":protected_offers}, {"offers":without_policy}),
			"T0 a winning roll cannot displace original " + ("rescue" if sample.ends_with("03") else "rare sortie"))
	var resolved: Dictionary = camp.duplicate(true)
	var second_clue: Dictionary = current.filter(func(action: Dictionary) -> bool: return action.has("investigation"))[0]
	resolved.journey.campaign.clues.append({"id":CampaignRules.CLUE_IDS.back(), "site_id":"cash",
		"action_id":second_clue.id, "transaction_id":"%s:2" % resolved.profile_id})
	resolved.settled_sorties = 2
	resolved.day = 4
	var finale: Array[Dictionary] = InvestigationActions.offers(resolved)
	resolved.journey.campaign.erase("event_sortie_policy")
	var old_finale: Array[Dictionary] = InvestigationActions.offers(resolved)
	_check(_event_index(finale) < 0 and finale.any(func(action: Dictionary) -> bool: return action.get("campaign", {}).get("is_finale", false))
		and TransactionReceipt.same({"offers":finale}, {"offers":old_finale}), "T0 investigation with all clues retains finale and no event")


func _open_event() -> Expedition:
	await _tap(app.camp_scene.hotspots[&"bus"])
	var offers: Array[Dictionary] = app.mission_select.daily_offers
	var index: int = _event_index(offers)
	_check(index >= 0, "T0 event appears in normal camp after process restart")
	if index < 0:
		return null
	var initial_offers: Variant = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("setup/offers.json")))
	_check(initial_offers is Dictionary and RecordEncoding.fingerprint({"offers":offers}) == initial_offers.fingerprint,
		"T0 fresh process offers identical action, site and map")
	var title: Label = app.mission_select._titles[index]
	var description: Label = app.mission_select._descriptions[index]
	_check("应急补给站" in title.text and "3 粮" in description.text and "6 币" in description.text and "12 秒" in description.text
		and "额外增援" in description.text, "T1 actual card shows both rewards, work and reinforcement risk")
	if _phase_name == "a":
		await _shot("task-card")
	var world: Expedition = await _start(index)
	if world != null:
		_baseline_spawns = world._spawn_count
		_baseline_requests = world._spawn_attempts
	return world


func _click_station(world: Expedition, site: Expedition.SearchSite) -> void:
	world.camera.pan_by(site.door - world.camera.position)
	world.camera.force_update_scroll()
	await _hold(2)
	var screen: Vector2 = world.get_global_transform_with_canvas() * site.door
	_check(viewport.get_visible_rect().has_point(screen), "actual station is in the viewport")
	for down: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = screen
		click.global_position = screen
		click.pressed = down
		viewport.push_input(click, true)
		await _frame()


func _choose(world: Expedition, site: Expedition.SearchSite, branch: String) -> void:
	_check(site != null and not site.weapon and site.seconds == EventSortieV1.SECONDS, "real event site has frozen work and no equipment reward")
	if site == null:
		return
	_check(not world.confirm_event_choice(branch) and not world.event_sortie_panel.visible and world.task_event.branch == "",
		"T1 direct early confirmation is rejected before reaching the station")
	await _click_station(world, site)
	await _until(world, func() -> bool: return world.event_sortie_panel.visible)
	_check(world.task_event.branch == "" and world.task_event.resolutions.is_empty() and site.progress == 0.0,
		"T1 arriving and opening the panel never commits branch, work or reinforcement")
	_check(not world.confirm_event_choice("forged"), "T5 invalid live branch is rejected in range")
	if _phase_name == "a":
		await _shot("station-choice")
		await _tap(world.event_sortie_panel.cancel_button)
		_check(not world.event_sortie_panel.visible and world.task_event.branch == "", "T1 cancelling the choice keeps the station unselected")
		await _click_station(world, site)
		await _until(world, func() -> bool: return world.event_sortie_panel.visible)
	var choice: Button = world.event_sortie_panel.quiet_button if branch == EventSortieV1.QUIET else world.event_sortie_panel.force_button
	await _tap(choice)
	_check(world.task_event.branch == branch and not world.task_event.started and site.progress == 0.0, "T1 confirmation locks one branch without work or alarm")
	var other: String = EventSortieV1.FORCE if branch == EventSortieV1.QUIET else EventSortieV1.QUIET
	_check(not world.confirm_event_choice(other) and not world.confirm_event_choice(branch), "T1/T5 switching or repeat confirmation rejected")


func _timed_work(world: Expedition, site: Expedition.SearchSite, done: Callable) -> void:
	for index: int in range(12000):
		if done.call() or world.phase == Expedition.Phase.FINISHED or world.is_paused:
			break
		var previous: float = site.progress
		world.step(STEP)
		if site.progress > previous:
			if _first_work < 0.0:
				_first_work = world.elapsed
			_work_seconds += STEP
		if index % 30 == 0:
			await _frame()
	_check(done.call(), "real work reaches checkpoint at %.2f seconds" % world.elapsed)


func _event_suspend(world: Expedition, site: Expedition.SearchSite) -> void:
	await _suspend(world, "event-checkpoint.json", {
		"action":world.supply.generated.id, "map":world.layout.id, "site":String(site.id),
		"branch":world.task_event.branch, "event":world.task_event.duplicate(true),
		"event_fingerprint":RecordEncoding.fingerprint(world.task_event), "progress":site.progress, "elapsed":world.elapsed,
		"base_spawns":_baseline_spawns, "base_requests":_baseline_requests, "first_work":_first_work, "work_seconds":_work_seconds
	})


func _resume_branch() -> void:
	var world: Expedition = app.expedition
	var source: String = "b-first" if _phase_name == "b-resume" else "b-unstarted"
	var prior: Dictionary = _checkpoint(world, source + "/event-checkpoint.json")
	if prior.is_empty():
		return
	var site: Expedition.SearchSite = world.search_site(StringName(EventSortieV1.site_id(world.supply.generated)))
	var resumed_event: String = RecordEncoding.fingerprint(world.task_event)
	_check(site != null and String(site.id) == prior.site and world.layout.id == prior.map and world.supply.generated.id == prior.action
		and is_equal_approx(site.progress, float(prior.progress)) and world.task_event.branch == prior.branch
		and prior.get("event_fingerprint", resumed_event) == resumed_event
		and not world.event_sortie_panel.visible, "T3 restore preserves event facts, real site, progress and closed choice UI")
	if site == null:
		return
	_before = app.camp_snapshot()
	_baseline_spawns = int(prior.base_spawns)
	_baseline_requests = int(prior.base_requests)
	_first_work = float(prior.first_work)
	_work_seconds = float(prior.work_seconds)
	await _unpause(world)
	if _phase_name == "b-resume":
		_check(world.task_event.started and world.task_event.resolutions.size() == EventSortieV1.REQUESTS, "T3 completed alarm with request facts remains durable")
		world.request_search(site.id)
		_check(world.search_assignments.member_for(String(site.id)) == 0, "T3 original cancel stops the current B work assignment")
		world.request_search(site.id)
		_check(world.search_assignments.member_for(String(site.id)) > 0, "T3 can reassign only the locked B branch")
	else:
		_check(not world.task_event.started and world.task_event.resolutions.is_empty(), "T3 locked unstarted B returns without an alarm")
		await _timed_work(world, site, func() -> bool: return site.progress > 0.0)
		_check(world.task_event.started and world.task_event.resolutions.size() == EventSortieV1.REQUESTS,
			"T3 first real work after restore triggers the alarm exactly once")
	await _timed_work(world, site, func() -> bool: return site.searched)
	if _phase_name == "b-resume":
		_check(RecordEncoding.fingerprint(world.task_event) == resumed_event, "T3 cancel, reassign and finish leave original alarm and enemy IDs identical")
	await _return(world, EventSortieV1.FORCE, 6, 0)


func _capacity_case(world: Expedition, site: Expedition.SearchSite) -> void:
	var previous_cap: int = world.threat.rules.enemy_cap
	world.threat.rules.enemy_cap = world.enemies.size()
	await _timed_work(world, site, func() -> bool: return site.progress > 0.0)
	world.threat.rules.enemy_cap = previous_cap
	_check(world.task_event.resolutions == [{"reason":"capacity", "enemy_id":-1}, {"reason":"capacity", "enemy_id":-1}],
		"T4 directed capacity limit consumes both event requests without spawning")
	var original: Dictionary = world.task_event.duplicate(true)
	world.request_search(site.id)
	world.request_search(site.id)
	await _timed_work(world, site, func() -> bool: return site.searched)
	_check(world.task_event == original, "T4 freed capacity never replenishes event pressure")
	await _return(world, EventSortieV1.FORCE, 6, 0)


func _fail_evacuation(world: Expedition) -> void:
	# Directed encounter: suppress firing, then let original enemy hits and death receipts resolve.
	for actor: FieldActor in world.survivors:
		actor.cooldown = 1000000.0
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED, 18000)
	_check(not reports.is_empty() and not reports.back().evacuated and world.living_count() == 0, "T4 actual enemy deaths cause failed evacuation")
	if reports.is_empty():
		return
	var after: Dictionary = app.camp_snapshot()
	_check(reports.back().loot == 0 and reports.back().food == 0 and after.cash == _before.cash
		and after.last_day.task.get("event_cash", -1) == 0 and after.last_day.task.get("event_food", -1) == 0,
		"T4 actual failure banks zero despite completing the event")
	_write("failed-route.json", {"carried":world.food_loot,"report":reports.back(),"camp_before":_before,"camp_after":after})


func _event_negatives(world: Expedition, site: Expedition.SearchSite) -> void:
	app.open_pause_menu()
	var saved: Dictionary = SortieSnapshot.capture(world)
	_check(saved.has("task_event") and app.progress_session.preview_suspend(saved).error == OK, "real paused B world passes original safety preview")
	if not saved.has("task_event"):
		return
	var receipt: Dictionary = app.progress_session._transaction.recover().receipt
	for field: String in ["bad-branch", "unselected-work", "quiet-alarm", "missing-alarm", "duplicate-id", "future-id", "early-complete"]:
		var forged: Dictionary = saved.duplicate(true)
		match field:
			"bad-branch": forged.task_event.branch = "both"
			"unselected-work": forged.task_event.branch = ""
			"quiet-alarm": forged.task_event.branch = EventSortieV1.QUIET
			"missing-alarm":
				forged.task_event.started = false
				forged.task_event.resolutions = []
			"duplicate-id":
				forged.task_event.resolutions = [{"reason":"spawned","enemy_id":0},{"reason":"spawned","enemy_id":0}]
			"future-id": forged.task_event.resolutions[0] = {"reason":"spawned","enemy_id":2147483647}
			"early-complete": forged.sites[String(site.id)].searched = true
		_check(not SortieSnapshot.problem(forged, receipt).is_empty() and app.progress_session.preview_suspend(forged).error != OK,
			"T5 world and safety preview reject " + field)


func _return(world: Expedition, branch: String, cash: int, food: int) -> void:
	var action: Dictionary = world.supply.generated
	var site: Expedition.SearchSite = world.search_site(StringName(EventSortieV1.site_id(action)))
	if _phase_name == "early":
		# Take a distinct authentic food site before skipping the event.
		for other: Expedition.SearchSite in world.sites:
			if other.id != site.id and other.kind == &"food" and other.reward > 0:
				await _search(world, other)
				break
	var before: Dictionary = _before.duplicate(true)
	var carried_cash: int = world.loot
	var carried_food: int = world.food_loot
	_check(not site.searched if branch.is_empty() else site.searched and carried_cash == cash and carried_food == food,
		"T2/T4 actual carried totals contain only the completed branch reward on event-only routes")
	var bus: Button = world._hud.view._bus_button
	await _until(world, func() -> bool: return world.elapsed >= world.tuning.bus_ready_seconds and not bus.disabled)
	await _tap(bus)
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.BOARDING)
	await _tap(bus)
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED)
	_check(app.phase == app.Phase.RESULT and world.boarding_status().arrived == world.living_count(),
		"T2 actual bus button and gathering bring living crew to the original result")
	for index: int in range(300):
		if not world.bus_view.running():
			break
		world.step(STEP)
	await _hold(3)
	var pending: Dictionary = app._pending_settlement
	_check(not pending.is_empty() and not app._progress_blocked and not reports.is_empty(), "valid original result preview prepares transaction")
	if pending.is_empty() or reports.is_empty():
		return
	var body: Label = app.get_node("Interface/Screen/Result/Scroll/Body")
	_check("本次事件收益" in body.text and (("3 粮" in body.text) if food > 0 else ("6 币" in body.text) if cash > 0 else ("0" in body.text)),
		"T7 result separately shows the actual event gain")
	if _phase_name == "a":
		await _shot("return-result")
	var report: Dictionary = reports.back()
	_check(report.loot == carried_cash and report.food == carried_food and report.weapons.is_empty(), "T2/T4 successful return credits actual carry, without equipment")
	var event_facts: Dictionary = world.task_event.duplicate(true)
	var spawned: int = event_facts.resolutions.filter(func(row: Dictionary) -> bool: return row.reason == "spawned").size()
	var expected_requests: int = EventSortieV1.REQUESTS if branch == EventSortieV1.FORCE else 0
	_check(event_facts.resolutions.size() == expected_requests and spawned <= expected_requests,
		"T2 event-only request and successful spawn counts follow the chosen route")
	if _phase_name in ["a", "early"]:
		_result_negatives()
	var result: Dictionary = {"branch":branch,"seed":before.journey.seed,"day":before.day,"camp_fingerprint":RecordEncoding.fingerprint(before),
		"action":action.id,"map":world.layout.id,"site":String(site.id),"point":[site.door.x,site.door.y],
		"event_cash":cash,"event_food":food,"carried_cash":carried_cash,"carried_food":carried_food,
		"other_cash":carried_cash - cash,"other_food":carried_food - food,
		"event_requests":event_facts.resolutions.size(),"event_spawned":spawned,"event_facts":event_facts,
		"natural_spawns":world._spawn_count - _baseline_spawns - spawned,
		"natural_requests":world._spawn_attempts - _baseline_requests - event_facts.resolutions.size(),
		"work_started":_first_work,"work_seconds":_work_seconds,"return_seconds":world.elapsed,"pid":OS.get_process_id()}
	var token: Dictionary = app.progress_session.token.duplicate(true)
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	var after: Dictionary = app.camp_snapshot()
	var committed: Dictionary = app.progress_session._transaction.recover()
	var duplicate: Dictionary = app.progress_session._transaction.commit(token)
	_check(committed.error == OK and duplicate.error == OK and committed.hash == duplicate.hash
		and TransactionReceipt.same(after, app.camp_snapshot()), "T4 repeated confirmation reads one committed receipt")
	_check(not app._progress_blocked and after.cash == before.cash + carried_cash
		and after.last_day.cash_gained == carried_cash and after.last_day.food_found == carried_food
		and after.last_day.task.event_cash == cash and after.last_day.task.event_food == food, "T2/T4 confirmed camp balances use original settlement")
	result.merge({"receipt":committed.get("hash",""), "banked_cash":int(after.last_day.cash_gained), "banked_food":int(after.last_day.food_stored),
		"cash_before":before.cash,"cash_after":after.cash,"food_before":before.food,"food_after":after.food,
		"cash_delta":int(after.cash) - int(before.cash),"food_delta":int(after.food) - int(before.food),
		"ration_consumed":after.last_day.get("food_consumed", -1),"ration_ledger":after.last_day,"task_summary":after.last_day.task})
	_write("event-result.json", result)


func _result_negatives() -> void:
	var original: Dictionary = app.progress_session.packet.input
	var forged: Dictionary = original.duplicate(true)
	forged.report.loot += 6
	forged.report.food += 3
	forged.carried.loot += 6
	forged.carried.food += 3
	_check(not FrozenSettlement.compute(forged).error.is_empty(), "T5 authentic settlement recomputation rejects excess/dual event rewards")
	forged = original.duplicate(true)
	forged.report.task_event.branch = "both"
	_check(not FrozenSettlement.compute(forged).error.is_empty(), "T5 settlement rejects illegal branch with otherwise authentic report")



func _shot(label: String) -> void:
	if _phase_name == "a":
		await super._shot(label)
