extends "res://tests/m40_workshop_flow.gd"
## Normal same-camp A/B and separate, explicitly directed fault/history cases.

const RECON_WORK: float = 6.0
const GRID: float = 96.0
var stage: String
var facts: Dictionary = {}


func _journey() -> void:
	stage = output.get_file()
	await _tap(app._home_button)
	await _tap(app._opening_picker.choices["scavenge"])
	await _tap(app._new_game_confirmation.get_ok_button())
	await _tap(app.camp_scene.hotspots[&"bus"])
	var day_two: Array[Dictionary] = app.mission_select.daily_offers
	var investigation: int = day_two.find_custom(func(action: Dictionary) -> bool: return action.has("investigation"))
	_check(app.day == 2 and investigation >= 0 and _recon_index(day_two) < 0, "T0 day two uses original offers")
	if investigation < 0:
		return
	var first: Expedition = await _start(investigation)
	if first == null:
		return
	await _search(first, first.search_site(&"cash"))
	await _food(first, 6)
	await _bank(first)
	await _facility(CampFacilities.WORKSHOP)
	await _tap(app.camp_scene.hotspots[&"bus"])
	var day_three: Array[Dictionary] = app.mission_select.daily_offers
	_check(app.day == 3 and _recon_index(day_three) < 0, "T0 day three preserves original candidates")
	var supply: int = day_three.find_custom(func(action: Dictionary) -> bool: return action.type == "supply" and not action.has("rare_policy"))
	if supply < 0:
		_check(false, "day three ordinary food offer exists")
		return
	var second: Expedition = await _start(supply)
	if second == null:
		return
	await _food(second, 10)
	await _bank(second)
	var camp: Dictionary = app.camp_snapshot()
	_check(app.day == 4 and CampFacilities.selected(camp) == CampFacilities.WORKSHOP
		and not CampaignRules.next_clue(camp.journey.campaign).is_empty(), "day four workshop camp retains a real investigation clue")
	await _tap(app.camp_scene.hotspots[&"bus"])
	var offers: Array[Dictionary] = app.mission_select.daily_offers.duplicate(true)
	var index: int = _recon_index(offers)
	_check(index >= 0, "T0 actual normal day-four card has certified recon")
	if index < 0:
		_write("missing-candidate.json", {"seed":camp.journey.seed, "offers":offers})
		return
	var expected: String = RecordEncoding.fingerprint({"offers":offers})
	await _tap(app.mission_select.cancel_button)
	await _tap(app.camp_scene.hotspots[&"bus"])
	_check(RecordEncoding.fingerprint({"offers":app.mission_select.daily_offers}) == expected, "T0 opening cards twice does not reroll")
	_protected_offers(camp, offers)
	_write("offers.json", {"fingerprint":expected, "seed":camp.journey.seed, "day":app.day, "action":offers[index]})


func _resume() -> void:
	stage = output.get_file()
	if stage == "t4-readback":
		_read_forged_journals()
		return
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	if stage in ["b-work", "b-finish", "t4-history", "t4-postdeath"]:
		await _resume_recon()
		return
	var world: Expedition = await _open_recon()
	if world == null:
		return
	if stage == "hound":
		await _hound_case(world)
	elif stage in ["a", "t4-fault"]:
		if stage == "t4-fault" and not await _source_rejections(world):
			return
		await _direct(world)
	else:
		await _recon_begin(world)


func _recon_index(offers: Array[Dictionary]) -> int:
	return offers.find_custom(func(action: Dictionary) -> bool: return ReconActionV1.enabled(action))


func _protected_offers(camp: Dictionary, offers: Array[Dictionary]) -> void:
	var old: Dictionary = camp.duplicate(true)
	old.journey.campaign.erase("recon_policy")
	var old_offers: Array[Dictionary] = InvestigationActions.offers(old)
	_check(old_offers.size() == offers.size() and _recon_index(old_offers) < 0, "T0 old camp has no recon even on same eligible day")
	for action: Dictionary in offers:
		var index: int = old_offers.find_custom(func(original: Dictionary) -> bool: return original.slot == action.slot)
		_check(index >= 0, "T0 source slot retained")
		if index < 0:
			continue
		var projected: Dictionary = action.duplicate(true)
		projected.erase("recon")
		_check(RecordEncoding.fingerprint(projected) == RecordEncoding.fingerprint(old_offers[index]), "T0 recon keeps original signed layout, sites and budget on slot %d" % action.slot)
	for label: String in ["commercial", "rescue", "event", "rare"]:
		var sample: String = {"commercial":"m42-recon-02","rescue":"m42-protect-00","event":"m42-protect-03","rare":"m42-protect-01"}[label]
		var directed: Dictionary = camp.duplicate(true)
		directed.journey.seed = sample.md5_text()
		var current: Array[Dictionary] = InvestigationActions.offers(directed)
		directed.journey.campaign.erase("recon_policy")
		var protected: Array[Dictionary] = InvestigationActions.offers(directed)
		var slot: Dictionary = {}
		for action: Dictionary in current:
			if action.slot == SortieRiskV1.SLOT:
				slot = action
				break
		var expected: bool = false
		match label:
			"commercial": expected = slot.get("type") == "airdrop" and slot.layout.topology == "commercial"
			"rescue": expected = slot.get("type") == "rescue"
			"event": expected = slot.has("event_sortie")
			"rare": expected = slot.has("rare_policy")
		_check(expected and _recon_index(current) < 0
			and RecordEncoding.fingerprint({"offers":current}) == RecordEncoding.fingerprint({"offers":protected}),
			"T0 directed protected slot retains original " + label)
	var source: Dictionary = old_offers[_recon_index(offers)].duplicate(true)
	# The source remains an ordinary gear descriptor. An outdoor primary in the
	# initially visible bus cell cannot satisfy the frozen reconnaissance rules.
	for site: Dictionary in source.sites:
		if site.id == ReconActionV1.PRIMARY_ID:
			site.point = source.layout.bus.door.duplicate()
	var before: String = RecordEncoding.fingerprint(source)
	var fallback: Dictionary = ReconActionV1.freeze(source, ReconActionV1.SOURCE_VERSION)
	_check(not fallback.has("recon") and before == RecordEncoding.fingerprint(fallback),
		"T0 directed map with no legal recon anchor retains its source")


func _open_recon() -> Expedition:
	await _tap(app.camp_scene.hotspots[&"bus"])
	var offers: Array[Dictionary] = app.mission_select.daily_offers
	var index: int = _recon_index(offers)
	_check(index >= 0, "T0 recon normal card remains available after restart")
	if index < 0:
		return null
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("setup/offers.json")))
	_check(expected.fingerprint == RecordEncoding.fingerprint({"offers":offers}), "T0 another process gets same full candidates and point")
	var text: String = app.mission_select._descriptions[index].text
	_check("可侦察" in text and "1 处" in text, "T0 original card shows recon and one optional building")
	var world: Expedition = await _start(index)
	if world != null:
		_init_facts(world)
	return world


func _init_facts(world: Expedition) -> void:
	var action: Dictionary = world.supply.generated
	var marker: Dictionary = action.recon
	var primary: Expedition.SearchSite = world.search_site(StringName(marker.primary_id))
	var optional: Expedition.SearchSite = world.search_site(StringName(marker.optional_id))
	var bus: Vector2 = world.layout.bus_door
	var station: Vector2 = ReconActionV1.point(action)
	var direct: float = ExplorationLayout._length(world.navigation.path_between(bus, primary.door))
	var via: float = ExplorationLayout._length(world.navigation.path_between(bus, station)) \
		+ ExplorationLayout._length(world.navigation.path_between(station, primary.door))
	_check(via - direct >= 300.0 and is_equal_approx(direct, float(marker.direct)) and is_equal_approx(via, float(marker.via_recon)),
		"T0 runtime navigation agrees with signed direct/detour lengths and >=300 added units")
	facts = {"seed":_before.journey.seed, "day":_before.day, "camp":RecordEncoding.fingerprint(_before),
		"action":action.id, "map":world.layout.id, "recon_point":[station.x,station.y], "primary":String(primary.id),
		"optional":String(optional.id), "toolbox":WorkshopSiteV1.site_id(action), "direct":direct, "via":via,
		"extra":via-direct, "viewport":[viewport.size.x,viewport.size.y], "departed_members":world.living_count()}


func _knowledge(world: Expedition) -> Dictionary:
	return world.recon_knowledge.snapshot(world.recon_site.progress)


func _world_click(world: Expedition, point: Vector2) -> void:
	world.camera.pan_by(point - world.camera.position)
	await _hold(2)
	var screen: Vector2 = world.get_global_transform_with_canvas() * point
	_check(viewport.get_visible_rect().has_point(screen), "world target falls inside the viewport")
	for down: bool in [true,false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = screen
		click.global_position = screen
		click.pressed = down
		viewport.push_input(click, true)
		await _frame()


func _shot_state(world: Expedition, label: String) -> void:
	await _shot(label)
	_write(label + ".json", {"viewport":[viewport.size.x, viewport.size.y], "zoom":world.camera.zoom.x,
		"progress":world.recon_site.progress, "complete":world.recon_site.searched, "elapsed":world.elapsed,
		"primary_exact":world.site_discovered(world.search_site(StringName(facts.primary))),
		"optional_exact":world.site_discovered(world.search_site(StringName(facts.optional)))})


func _direct(world: Expedition) -> void:
	var primary: Expedition.SearchSite = world.search_site(StringName(facts.primary))
	var optional: Expedition.SearchSite = world.search_site(StringName(facts.optional))
	_check(not world.site_discovered(primary) and not world.site_discovered(optional), "T1 departure has no precise primary or optional point")
	var initial: String = _knowledge(world).bits
	world.request_search(primary.id)
	world.request_search(optional.id)
	_check(world.search_assignments.member_for(String(primary.id)) == 0 and world.search_assignments.member_for(String(optional.id)) == 0,
		"T1 known site IDs cannot assign an undiscovered target")
	world.locate_objective("primary")
	var rough: Vector2 = world.recon_region().get_center()
	_check(rough.distance_to(primary.door) > 8.0 and world.recon_region().has_point(primary.door),
		"T1 primary locate uses a coarse camera area containing the target")
	if stage == "a":
		viewport.size = Vector2i(1024, 640)
		await _hold(3)
		world.locate_objective("primary")
		await _shot_state(world, "recon-before")
		viewport.size = Vector2i(1280, 720)
		await _hold(3)
	world.camera.pan_by(Vector2(205, -96))
	var initial_zoom: Vector2 = world.camera.zoom
	world.camera.zoom_at(Vector2(viewport.size) / 2.0, 1.1)
	world.toggle_pause()
	for _step: int in range(12):
		world.step(STEP)
	world.toggle_pause()
	_check(_knowledge(world).bits == initial and not world.site_discovered(primary), "T1 locate, pan, zoom and paused ticks reveal nothing")
	world.camera.zoom = initial_zoom
	world.camera.force_update_scroll()
	await _world_click(world, optional.door)
	_check(world.search_assignments.member_for(String(optional.id)) == 0, "T1 clicking on hidden geometry produces no optional work")
	await _explore_area(world, primary, rough)
	var discovered: bool = world.site_discovered(primary) and world.recon_knowledge.explored(primary.door)
	_check(discovered, "T1 authentic nearby outdoor discovery exposes the actual target")
	if not discovered:
		_write("exploration-failure.json", {"elapsed":world.elapsed, "region":[rough.x,rough.y],
			"positions":world.survivors.map(func(actor: FieldActor) -> Array: return [actor.position.x,actor.position.y])})
		return
	facts.first_exact = world.elapsed
	await _primary(world, primary)
	_check(world.recon_site.progress == 0.0 and not world.recon_site.searched, "T1 no recon progress on direct route")
	await _return_recon(world, false)


func _explore_area(world: Expedition, site: Expedition.SearchSite, _rough: Vector2) -> void:
	# Explore visible street space within the coarse sector, using the real
	# formation destination and its route length rather than a hidden site point.
	var area: Rect2 = world.recon_region()
	var waypoints: Array[Vector2] = []
	for y: int in range(ceili(area.size.y / GRID)):
		for x: int in range(ceili(area.size.x / GRID)):
			var point: Vector2 = area.position + (Vector2(x, y) + Vector2.ONE * 0.5) * GRID
			if area.has_point(point) and world.navigation.is_clear(point):
				waypoints.append(point)
	world.locate_objective("primary")
	while not waypoints.is_empty() and not world.site_discovered(site):
		var leader: FieldActor
		for actor: FieldActor in world.survivors:
			if actor.health > 0.0:
				leader = actor
				break
		if leader == null:
			return
		var best: Vector2 = Vector2.INF
		var shortest: float = INF
		var planned: PackedVector2Array
		for point: Vector2 in waypoints:
			if world.recon_knowledge.explored(point):
				continue
			var path: PackedVector2Array = world.navigation.path_between(leader.position, point + world._group_offset(leader))
			if path.is_empty() or path[-1].distance_to(point) > GRID:
				continue
			var length: float = ExplorationLayout._length(path)
			if length < shortest:
				best = point
				shortest = length
				planned = path
		if not best.is_finite():
			return
		waypoints.erase(best)
		world.command_move(best)
		var limit: int = ceili((shortest / 90.0 + 5.0) / STEP)
		for index: int in range(limit):
			if world.site_discovered(site) or world.phase == Expedition.Phase.FINISHED or world.is_paused:
				return
			if leader.health <= 0.0 or leader.position.distance_to(planned[-1]) < 14.0:
				break
			world.step(STEP)
			if index % 30 == 0:
				await _frame()


func _primary(world: Expedition, site: Expedition.SearchSite) -> void:
	await _world_click(world, site.door)
	await _until(world, func() -> bool: return site.progress > 0.0)
	facts.primary_started = world.elapsed
	await _until(world, func() -> bool: return site.searched)
	facts.primary_completed = world.elapsed


func _recon_begin(world: Expedition) -> void:
	var station: Expedition.SearchSite = world.recon_site
	await _world_click(world, station.door)
	var worker: int = world.search_assignments.member_for(String(station.id))
	_check(worker > 0 and world.search_assignments.phase_for(worker) == "approach" and station.progress == 0.0,
		"T2 actual click assigns one worker and approach has no progress")
	await _until(world, func() -> bool: return station.progress > 0.0)
	facts.recon_arrival = world.elapsed - STEP
	facts.worker = worker
	var partial: float = station.progress
	world.toggle_pause()
	for _step: int in range(12):
		world.step(STEP)
	world.toggle_pause()
	_check(station.progress == partial, "T2 pause has no work time")
	world.request_search(station.id)
	_check(world.search_assignments.member_for(String(station.id)) == 0 and station.progress == partial, "T2 cancel preserves partial progress")
	world.request_search(station.id)
	_check(world.search_assignments.member_for(String(station.id)) > 0, "T2 reassignment remains exclusive")
	await _until(world, func() -> bool: return station.progress >= 2.0)
	_check(not station.searched, "T3 first save is genuinely partway through recon")
	await _save_recon(world, "partial")


func _save_recon(world: Expedition, state: String) -> void:
	var proof: Dictionary = {"route":facts,"state":state, "progress":world.recon_site.progress,
		"worker":world.search_assignments.member_for(String(world.recon_site.id)), "elapsed":world.elapsed,
		"knowledge":RecordEncoding.fingerprint(_knowledge(world))}
	await _suspend(world, "recon-checkpoint.json", proof)


func _resume_recon() -> void:
	var world: Expedition = app.expedition
	var source: String = "b-work" if stage == "b-finish" else "t4-history" if stage == "t4-postdeath" else "b-first"
	var prior: Dictionary = _checkpoint(world, source + "/recon-checkpoint.json")
	if prior.is_empty():
		return
	facts = prior.route.duplicate(true)
	_before = app.camp_snapshot()
	var station: Expedition.SearchSite = world.recon_site
	_check(RecordEncoding.fingerprint(_knowledge(world)) == prior.knowledge and is_equal_approx(station.progress, float(prior.progress))
		and world.search_assignments.member_for(String(station.id)) == int(prior.worker), "T3 restored map, partial/full work and assigned worker exactly")
	_write("recon-restored.json", {"source_pid":prior.pid, "resume_pid":OS.get_process_id(),
		"fingerprint":RecordEncoding.fingerprint(SortieSnapshot.capture(world)), "progress":station.progress, "worker":int(prior.worker),
		"elapsed":world.elapsed, "knowledge":RecordEncoding.fingerprint(_knowledge(world))})
	if stage == "t4-history":
		await _history(world)
		return
	if stage == "t4-postdeath":
		_check(world.living_count() == 1 and station.progress >= 2.0, "T4 legitimate post-death checkpoint restores the survivor and original recon")
		return
	await _unpause(world)
	var primary: Expedition.SearchSite = world.search_site(StringName(facts.primary))
	var optional: Expedition.SearchSite = world.search_site(StringName(facts.optional))
	if stage == "b-work":
		var cash: int = world.loot
		var food: int = world.food_loot
		var gear: int = world.weapon_loot.size()
		var xp_before: int = world.xp_inputs.snapshot(world).events.size()
		var phase_before: String = RecordEncoding.fingerprint(world.trait_inputs.snapshot(world))
		var ambient: Array[Dictionary] = []
		world.spawn_resolved.connect(func(event: Dictionary) -> void: ambient.append(event.duplicate(true)))
		await _until(world, func() -> bool: return station.searched)
		_check(station.progress == RECON_WORK and world.loot == cash and world.food_loot == food and world.weapon_loot.size() == gear
			and not primary.searched, "T2 recon completes at six effective seconds and generates no resources, weapons or primary completion")
		_check(ambient.all(func(row: Dictionary) -> bool: return row.source != "recon")
			and RecordEncoding.fingerprint(world.trait_inputs.snapshot(world)) == phase_before,
			"T2 recon adds no spawn requests or search XP/trait event")
		facts.merge({"first_exact":world.elapsed, "recon_complete":world.elapsed, "recon_effective":station.progress,
			"natural_attempts_while_completing":ambient.size(), "xp_before":xp_before, "xp_after":world.xp_inputs.snapshot(world).events.size(),
			"recon_work_wall_sim":world.elapsed - float(facts.recon_arrival)})
		_check(world.site_discovered(primary) and world.site_discovered(optional)
			and not world.recon_knowledge.explored(primary.door) and not world.recon_knowledge.explored(optional.door),
			"T2 two real remote locations unlock while their terrain remains unexplored")
		world.locate_objective("primary")
		await _shot_state(world, "recon-after")
		await _save_recon(world, "complete")
		return
	_check(station.searched and station.progress == RECON_WORK and world.site_discovered(primary) and world.site_discovered(optional),
		"T3 completed restore immediately keeps both genuine pins")
	world.request_search(station.id)
	_check(world.search_assignments.member_for(String(station.id)) == 0 and station.progress == RECON_WORK,
		"T3 completed station cannot repeat or create new work")
	await _world_click(world, optional.door)
	await _until(world, func() -> bool: return optional.searched)
	facts.optional_completed = world.elapsed
	facts.optional_reward = {"kind":String(optional.kind), "amount":optional.reward}
	await _primary(world, primary)
	var toolbox: Expedition.SearchSite = world.search_site(StringName(facts.toolbox))
	_check(toolbox != null and NightHoundV1.enabled(world.supply.generated), "T6 recon preserves original workshop and night hound eligibility")
	if toolbox != null and not toolbox.searched:
		if not world.site_discovered(toolbox):
			# The original toolbox badge is naturally discovered by movement near
			# its building rather than by a forged reveal or duplicated loot path.
			world.command_move(toolbox.door)
			await _until(world, func() -> bool: return world.site_discovered(toolbox))
		await _search(world, toolbox)
	await _return_recon(world, true)


func _return_recon(world: Expedition, used_recon: bool) -> void:
	var carry: Dictionary = {"cash":world.loot, "food":world.food_loot, "weapons":world.weapon_loot.duplicate(true)}
	var banked_before: int = WorkshopV1.tools(_before)
	var bus: Button = world._hud.view._bus_button
	await _until(world, func() -> bool: return world.elapsed >= world.tuning.bus_ready_seconds and not bus.disabled)
	await _tap(bus)
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.BOARDING)
	await _tap(bus)
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED)
	_check(app.phase == app.Phase.RESULT and world.boarding_status().arrived == world.living_count(),
		"actual bus control gathers living crew through original return")
	for index: int in range(300):
		if not world.bus_view.running():
			break
		world.step(STEP)
	await _hold(3)
	if reports.is_empty() or app._pending_settlement.is_empty():
		_check(false, "successful actual sortie prepares one result receipt")
		return
	var report: Dictionary = reports.back()
	_check(report.evacuated and report.loot == carry.cash and report.food == carry.food
		and TransactionReceipt.same({"weapons":report.weapons}, {"weapons":carry.weapons}), "original result exactly matches actual collected loot")
	var elapsed: float = world.elapsed
	var recon_progress: float = world.recon_site.progress
	var living: int = world.living_count()
	var token: Dictionary = app.progress_session.token.duplicate(true)
	var transaction: RunTransaction = app.progress_session._transaction
	var confirm: Button = app.get_node("Interface/Screen/Result/Continue")
	if stage == "t4-fault":
		var ready: Dictionary = transaction.recover()
		var disk_before: PackedByteArray = FileAccess.get_file_as_bytes(app.progress_path)
		var injection: Dictionary = {"hits":0}
		app.progress_session.fault_hook = func(point: String) -> Error:
			if point != "before_camp_write":
				return OK
			injection.hits += 1
			return ERR_CANT_CREATE
		await _tap(confirm)
		var interrupted: Dictionary = transaction.recover()
		var disk_after: PackedByteArray = FileAccess.get_file_as_bytes(app.progress_path)
		var untouched: bool = not disk_before.is_empty() and disk_before == disk_after
		_check(injection.hits == 1 and app._progress_blocked and interrupted.error == OK
			and interrupted.receipt.phase == "RESULT_READY" and interrupted.hash == ready.hash and untouched,
			"T4 simulated failure before camp write leaves exact disk camp and one retryable frozen result")
		_write("fault-before-camp.json", {"hits":injection.hits,"unchanged":untouched,"head_before":ready.get("hash"),
			"head_after":interrupted.get("hash"),"state":interrupted.get("state"),"message":app._progress_message})
		app.progress_session.fault_hook = Callable()
	await _tap(confirm)
	var after: Dictionary = app.camp_snapshot()
	var committed: Dictionary = transaction.recover()
	var repeated: Dictionary = transaction.commit(token)
	_check(committed.error == OK and repeated.error == OK and committed.hash == repeated.hash,
		"original repeated confirmation returns the same final receipt")
	_check(after.cash - _before.cash == carry.cash and after.last_day.food_found == carry.food and not app._progress_blocked,
		"actual camp credit keeps the existing rewards, stock and ration settlement")
	if used_recon:
		_check(WorkshopV1.tools(after) == banked_before + 1 and WorkshopV1.tools(app.camp_snapshot()) == banked_before + 1,
			"T6 one original toolbox is acquired and re-confirming cannot add a second")
	facts.merge({"return_seconds":elapsed, "survivors":living, "deaths":int(facts.departed_members) - living,
		"carried":carry, "banked":{"cash":after.last_day.cash_gained,"food":after.last_day.food_stored, "tools":WorkshopV1.tools(after) - banked_before},
		"recon_progress":recon_progress,"ration":after.last_day.food_consumed,"cash_delta":after.cash - _before.cash,
		"food_delta":after.food - _before.food,"receipt":committed.get("hash", ""), "pid":OS.get_process_id()})
	_write("route-result.json", facts)


func _source_rejections(world: Expedition) -> bool:
	var transaction: RunTransaction = app.progress_session._transaction
	var token: Dictionary = app.progress_session.token.duplicate(true)
	var evidence: Dictionary = {}
	for variant: String in ["all-explored-at-departure", "unworked-completion"]:
		if variant == "unworked-completion":
			await _until(world, func() -> bool: return world.elapsed >= 12.36)
		app.open_pause_menu()
		var valid: Dictionary = SortieSnapshot.capture(world)
		var head: Dictionary = transaction.recover()
		var genuine: bool = not valid.is_empty() and valid.recon.progress == 0.0 and valid.recon.work.is_empty()
		if variant == "all-explored-at-departure":
			genuine = genuine and world.elapsed == 0.0
		else:
			genuine = genuine and world.elapsed >= RECON_WORK and world.survivors.all(
				func(actor: FieldActor) -> bool:
					return actor.position.distance_to(world.recon_site.door) > ReconActionV1.WORK_RANGE)
		_check(genuine and SortieSnapshot.problem(valid, head.receipt).is_empty(),
			"T4 genuine idle snapshot provides an exact source for " + variant)
		if not genuine:
			return false
		var forged: Dictionary = valid.duplicate(true)
		var reason: String = "RECON_WORK_SOURCE"
		if variant == "all-explored-at-departure":
			var bitmap: PackedByteArray = String(forged.recon.bits).hex_decode()
			bitmap.fill(0xff)
			var tail: int = (world.recon_knowledge.columns * world.recon_knowledge.rows) % 8
			if tail > 0:
				bitmap[-1] = (1 << tail) - 1
			forged.recon.bits = bitmap.hex_encode()
			reason = "RECON_BITS_SOURCE"
		else:
			forged.recon.progress = RECON_WORK
			forged.recon.completed = true
		var preview: Dictionary = transaction.preview_suspend(token, forged)
		var write: Dictionary = transaction.suspend(token, forged)
		var unchanged: bool = transaction.recover().hash == head.hash
		_check(preview.error != OK and write.error != OK and preview.get("reason") == reason
			and write.get("reason") == reason and unchanged,
			"T4 preview and writer reject " + variant + " with unchanged live head")
		if not unchanged:
			return false
		var destination: String = output.path_join("forged-" + variant)
		_copy_forged_record(transaction._journal.directory, destination, _forged_receipt(head, token, forged))
		var replay: Dictionary = ReceiptJournal.new(destination).read_all()
		_check(replay.error != OK and replay.get("reason") == reason,
			"T4 readback of exact forged record rejects " + variant)
		evidence[variant] = {"elapsed":world.elapsed, "actual_progress":valid.recon.progress,
			"preview":preview.get("reason", ""), "write":write.get("reason", ""), "readback":replay.get("reason", "")}
		await _unpause(world)
	_write("recon-source-rejections.json", evidence)
	return true


func _history(world: Expedition) -> void:
	var station: Expedition.SearchSite = world.recon_site
	var transaction: RunTransaction = app.progress_session._transaction
	var token: Dictionary = app.progress_session.token.duplicate(true)
	var valid: Dictionary = SortieSnapshot.capture(world)
	var head: Dictionary = transaction.recover()
	_check(SortieSnapshot.problem(valid, head.receipt).is_empty(), "T4 exact source snapshot is authenticated")
	var rejected: Dictionary = {}
	for variant: String in ["point", "oversize-bits", "nonhex-bits", "premature-complete", "extra-target"]:
		var forged: Dictionary = valid.duplicate(true)
		match variant:
			"point": forged.generated.recon.point = [-500.0, -500.0]
			"oversize-bits": forged.recon.bits += "ff"
			"nonhex-bits": forged.recon.bits = "xx" + forged.recon.bits.substr(2)
			"premature-complete": forged.recon.completed = true
			"extra-target": forged.recon.extra = [String(world.recon_site.id)]
		var issue: String = SortieSnapshot.problem(forged, head.receipt)
		var preview: Dictionary = transaction.preview_suspend(token, forged)
		_check(not issue.is_empty() and preview.error != OK and transaction.recover().hash == head.hash, "T4 preflight rejects " + variant)
		rejected[variant] = preview.get("reason","")
	var columns: int = ceili(world.layout.world_bounds.size.x / GRID)
	var rows_count: int = ceili(world.layout.world_bounds.size.y / GRID)
	if (columns * rows_count) % 8 != 0:
		var padding: Dictionary = valid.duplicate(true)
		padding.recon.bits = padding.recon.bits.left(-2) + "ff"
		var outside: Dictionary = transaction.preview_suspend(token, padding)
		_check(outside.error != OK and transaction.recover().hash == head.hash, "T4 nonzero out-of-grid padding is rejected")
		rejected["padding"] = outside.get("reason","")

	await _unpause(world)
	var worker: int = world.search_assignments.member_for(String(station.id))
	var victim: FieldActor
	for actor: FieldActor in world.survivors:
		if actor.member_id != worker and actor.health > 0.0:
			victim = actor
			break
	_check(worker > 0 and victim != null, "T4 restored worker and second member are alive")
	if victim == null:
		return
	victim.clear_order()
	var accepted: bool = victim.take_damage(victim.health)
	var death: Dictionary = transaction.recover()
	_check(accepted and victim.permanent_death and death.error == OK and death.receipt.phase == "DEATH_CONFIRMED"
		and death.receipt.envelope.is_empty(), "T4 original damage gate records one death without a replacement world")
	app.open_pause_menu()
	valid = SortieSnapshot.capture(world)
	_check(app.progress_session.preview_suspend(valid).error == OK, "T4 exact post-death recon remains safely suspendable")
	var copied: Array[Dictionary] = []
	for variant: String in ["bits", "progress"]:
		var forged: Dictionary = valid.duplicate(true)
		var expected: String = "RECON_BITS_SOURCE" if variant == "bits" else "RECON_HISTORY_PROGRESS"
		if variant == "bits":
			forged.recon.bits = "0".repeat(String(forged.recon.bits).length())
			_check(SortieSnapshot.problem(forged, death.receipt) == expected,
				"T4 forged bitmap rollback disagrees with the recorded reveal sources")
		else:
			# Keep the same worker and ending time so the truncated work still
			# agrees with the snapshot on its own. Receipt history must reject it.
			var last_work: Array = forged.recon.work.back()
			var removed: float = (float(last_work[2]) - float(last_work[1])) * 0.5
			last_work[1] += removed
			forged.recon.progress -= removed
			_check(SortieSnapshot.problem(forged, death.receipt).is_empty(),
				"T4 truncated work is locally valid before comparing claimed history")
		var preview: Dictionary = transaction.preview_suspend(token, forged)
		var write: Dictionary = transaction.suspend(token, forged)
		_check(preview.error != OK and write.error != OK and preview.get("reason") == expected
			and write.get("reason") == expected and transaction.recover().hash == death.hash,
			"T4 real preflight and writer reject " + variant + " rollback without modifying the live head")
		var next: Dictionary = _forged_receipt(death, token, forged)
		var published: Dictionary = transaction._journal.append(next, death.hash)
		_check(published.error != OK and published.get("reason") == expected and transaction.recover().hash == death.hash,
			"T4 journal writer rejects " + variant + " rollback")
		var destination: String = output.path_join("forged-" + variant)
		_copy_forged_record(transaction._journal.directory, destination, next)
		copied.append({"directory":destination,"reason":expected})
	_write("history.json", {"pid":OS.get_process_id(),"death_head":death.hash,"rejections":rejected,"forged":copied})
	await _save_recon(world, "post-death")


func _forged_receipt(head: Dictionary, token: Dictionary, world: Dictionary) -> Dictionary:
	var next: Dictionary = head.receipt.duplicate(true)
	next.phase = "SUSPEND_READY"
	next.revision += 1
	next.previous_hash = head.hash
	next.envelope = SuspendRecord.make(world, token, head.hash)
	return next


func _copy_forged_record(source: String, destination: String, next: Dictionary) -> void:
	for folder: String in DirAccess.get_directories_at(source):
		if not folder.is_valid_int():
			continue
		DirAccess.make_dir_recursive_absolute(destination.path_join(folder))
		var path: String = folder.path_join("record.json")
		_check(DirAccess.copy_absolute(source.path_join(path), destination.path_join(path)) == OK,
			"T4 copies one existing receipt byte-for-byte to isolated readback folder")
	var generation: String = destination.path_join("%08d" % int(next.revision))
	DirAccess.make_dir_recursive_absolute(generation)
	var file: FileAccess = FileAccess.open(generation.path_join("record.json"), FileAccess.WRITE)
	_check(file != null, "T4 can place exact forged generation in the independent copy only")
	if file != null:
		file.store_string(RecordEncoding.stringify(next))
		file.close()


func _read_forged_journals() -> void:
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("t4-history/history.json")))
	var results: Dictionary = {}
	_check(int(evidence.pid) != OS.get_process_id(), "T4 independent readback uses another process")
	for row: Dictionary in evidence.forged:
		var result: Dictionary = ReceiptJournal.new(row.directory).read_all()
		_check(result.error != OK and result.get("reason") == row.reason, "T4 standalone journal replay rejects " + row.reason)
		results[row.reason] = result.get("reason","")
	_write("independent-readback.json", {"pid":OS.get_process_id(),"rejections":results})


func _hound_case(world: Expedition) -> void:
	_check(ReconActionV1.enabled(world.supply.generated) and NightHoundV1.enabled(world.supply.generated),
		"T6 same signed action enables original night hound gate with recon")
	var observed: Array[Dictionary] = []
	world.spawn_resolved.connect(func(row: Dictionary) -> void: observed.append(row.duplicate(true)))
	world._spawn_enemy()
	world.elapsed = world.tuning.daylight_seconds * world.threat.rules.late_fraction + 0.125
	world.threat.update(world.elapsed, world.tuning.daylight_seconds, world.tuning.spawn_seconds)
	world._spawn_enemy()
	var daytime: bool = observed.all(func(row: Dictionary) -> bool:
		return row.reason == "spawned" and row.get("enemy_type") != NightHoundV1.KIND)
	_check(observed.size() == 2 and daytime, "T6 original daytime and dusk legal spawns exclude night hounds")
	world.elapsed = world.tuning.daylight_seconds + 0.125
	world.threat.update(world.elapsed, world.tuning.daylight_seconds, world.tuning.spawn_seconds)
	var hound: Dictionary = {}
	for _index: int in range(world.threat.rules.enemy_cap - world.enemies.size()):
		var attempt: Dictionary = world._spawn_enemy()
		if attempt.reason == "spawned" and observed.back().get("enemy_type") == NightHoundV1.KIND:
			hound = observed.back()
			break
	_check(not hound.is_empty() and hound.stage == ThreatDirector.Stage.NIGHT and hound.legal
		and CombatEnemyRules.pick(world.sortie_id, int(hound.enemy_id), ThreatDirector.Stage.NIGHT) == EnemyRules.NORMAL,
		"T6 first legal ordinary night spawn is still replaced by one hound")
	_write("hound-proof.json", {"action":world.supply.generated.id,"map":world.layout.id,"spawns":observed,"hound":hound})
