extends "res://tests/m42_recon_flow.gd"
## Isolated normal mission, exact checkpoints, and independent journal negatives.


func _journey() -> void:
	stage = output.get_file()
	await _tap(app._home_button)
	await _tap(app._opening_picker.choices["scavenge"])
	await _tap(app._new_game_confirmation.get_ok_button())
	await _tap(app.camp_scene.hotspots[&"bus"])
	var day_two: Array[Dictionary] = app.mission_select.daily_offers
	var investigation: int = day_two.find_custom(func(action: Dictionary) -> bool: return action.has("investigation"))
	_check(app.day == 2 and investigation >= 0 and _barricade_index(day_two) < 0, "T0 day two keeps original investigation and offers")
	if investigation < 0:
		return
	var first: Expedition = await _start(investigation)
	if first == null:
		return
	await _search(first, first.search_site(&"cash"))
	await _food(first, 6)
	await _bank(first)
	await _tap(app.camp_scene.hotspots[&"bus"])
	var day_three: Array[Dictionary] = app.mission_select.daily_offers
	var supply: int = day_three.find_custom(func(action: Dictionary) -> bool: return action.type == "supply" and not action.has("rare_policy"))
	_check(app.day == 3 and supply >= 0 and _barricade_index(day_three) < 0, "T0 day three keeps ordinary supplies without barricade")
	if supply < 0:
		return
	var second: Expedition = await _start(supply)
	if second == null:
		return
	await _food(second, 10)
	await _bank(second)
	await _tap(app.camp_scene.hotspots[&"bus"])
	var camp: Dictionary = app.camp_snapshot()
	var offers: Array[Dictionary] = app.mission_select.daily_offers.duplicate(true)
	var index: int = _barricade_index(offers)
	_check(app.day == 4 and index >= 0, "T0 day four has a certified normal supply card")
	if index < 0:
		_write("missing-candidate.json", {"seed":camp.journey.seed, "offers":offers})
		return
	var action: Dictionary = offers[index]
	var offers_hash: String = RecordEncoding.fingerprint({"offers":offers})
	await _tap(app.mission_select.cancel_button)
	await _tap(app.camp_scene.hotspots[&"bus"])
	_check(RecordEncoding.fingerprint({"offers":app.mission_select.daily_offers}) == offers_hash,
		"T0 reopening cards preserves the original signed map and barricade")
	_check(action.type == "supply" and action.layout.size == "medium" and not action.has("rare_policy"),
		"T0 the signed action is ordinary medium supply")
	var old: Dictionary = camp.duplicate(true)
	old.journey.campaign.erase("barricade_policy")
	var originals: Array[Dictionary] = InvestigationActions.offers(old)
	for candidate: Dictionary in offers:
		var matching: int = originals.find_custom(func(prior: Dictionary) -> bool: return prior.slot == candidate.slot)
		var projected: Dictionary = candidate.duplicate(true)
		projected.erase("barricade")
		_check(matching >= 0 and TransactionReceipt.same(projected, originals[matching]),
			"T0 old policy keeps original action, reward and layout on slot %d" % candidate.slot)
	for key: String in ["id", "rect", "layout"]:
		var forged: Dictionary = action.duplicate(true)
		if key == "rect":
			forged.barricade.rect[0] += 16.0
		else:
			forged.barricade[key] += "-forged"
		_check(not ExplorationActions.problem(forged).is_empty(), "T0 altered barricade %s is rejected" % key)
	_write("offers.json", {"fingerprint":offers_hash, "seed":camp.journey.seed, "day":app.day, "action":action})


func _resume() -> void:
	stage = output.get_file()
	if stage == "readback":
		_barricade_readback()
		return
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	if stage in ["a-finish", "b-finish"]:
		await _resume_barricade()
		return
	var world: Expedition = await _open_barricade()
	if world == null or not await _measure_from(world):
		return
	if stage == "edges":
		await _strike_edges(world)
		return
	if stage == "a-save":
		_closed_rejections(world)
		await _barricade_shot(world, "barricade-closed", Vector2i(1024, 640))
	else:
		if not await _strike_retry(world):
			return
		await _barricade_shot(world, "barricade-open", Vector2i(1280, 720))
	var support: Dictionary = world.basic_support.snapshot()
	await _suspend(world, "checkpoint.json", {"facts":facts, "open":world.barricade_open,
		"support":support, "elapsed":world.elapsed})


func _barricade_index(offers: Array[Dictionary]) -> int:
	return offers.find_custom(func(action: Dictionary) -> bool: return BarricadeV1.enabled(action))


func _open_barricade() -> Expedition:
	await _tap(app.camp_scene.hotspots[&"bus"])
	var offers: Array[Dictionary] = app.mission_select.daily_offers
	var index: int = _barricade_index(offers)
	_check(index >= 0, "T0 certified card remains available in a new process")
	if index < 0:
		return null
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("setup/offers.json")))
	_check(expected.fingerprint == RecordEncoding.fingerprint({"offers":offers}),
		"T0 restart keeps identical signed action and measurement geometry")
	_check("路障" in app.mission_select._descriptions[index].text, "T0 actual selected card announces the barricade")
	FreezeProfile.enabled = true
	FreezeProfile.start({"sample":"cold field navigation preparation", "phase":stage})
	var world: Expedition = await _start(index)
	FreezeProfile.finish()
	FreezeProfile.enabled = false
	var preparation: Dictionary = FreezeProfile.latest.stages.get("barricade.navigation_prepare", {})
	_write("field-navigation-timing.json", {"metadata":FreezeProfile.latest.metadata, "prepare":preparation})
	if world == null:
		return null
	var action: Dictionary = world.supply.generated
	var marker: Dictionary = action.barricade
	var site: Expedition.SearchSite = world.search_site(StringName(marker.site_id))
	_check(not world.barricade_open and site != null and world.basic_support.ready("airstrike"),
		"T0 real action starts with its original target, closed vehicle and ready E")
	if site == null:
		return null
	var near: Vector2 = WorldLayout.point(marker.near)
	var open_nav: FieldNavigation = BarricadeV1.navigation(action, true)
	var closed_length: float = ExplorationLayout._length(world.navigation.path_between(near, site.door))
	var open_length: float = ExplorationLayout._length(open_nav.path_between(near, site.door))
	_check(closed_length - open_length >= 320.0 and is_equal_approx(closed_length, float(marker.closed_length))
		and is_equal_approx(open_length, float(marker.open_length)), "T0 actual runtime navigation agrees with signed route savings")
	facts = {"seed":_before.journey.seed, "day":_before.day, "camp":RecordEncoding.fingerprint(_before),
		"action":action.id, "action_fingerprint":RecordEncoding.fingerprint(action), "map":String(world.layout.id),
		"map_fingerprint":RecordEncoding.fingerprint(action.layout), "marker":marker,
		"site":String(site.id), "site_point":[site.door.x, site.door.y], "departed_members":world.living_count(),
		"closed_length":closed_length, "open_length":open_length}
	return world


func _measure_from(world: Expedition) -> bool:
	var leader: FieldActor = world.survivors[0]
	var near: Vector2 = WorldLayout.point(facts.marker.near)
	var destination: Vector2 = near - world._group_offset(leader)
	await _world_click(world, destination)
	_check(world.goal.distance_to(destination) < 1.0 and not leader.path.is_empty(),
		"T1/T2 actual viewport click orders the crew to the common measurement point")
	await _until(world, func() -> bool: return world.survivors.all(func(actor: FieldActor) -> bool:
		return actor.activity != FieldActor.Activity.MOVING))
	var arrived: bool = leader.health > 0.0 and leader.position.distance_to(near) <= 14.0
	_check(arrived and world.basic_support.ready("airstrike") and not world.barricade_open,
		"T1/T2 living crew arrives at the common point while E and the closed route are available")
	facts.measurement = {"position":[leader.position.x,leader.position.y], "elapsed":world.elapsed,
		"positions":world.survivors.map(func(actor: FieldActor) -> Array: return [actor.position.x,actor.position.y])}
	return arrived


func _key(code: Key) -> void:
	for down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		viewport.push_input(event, true)
		await _frame()


func _strike_retry(world: Expedition) -> bool:
	var landing: Vector2 = WorldLayout.point(facts.marker.landing)
	var closed_nav: FieldNavigation = world.navigation
	var closed_rect: Rect2 = BarricadeV1.rect(world.supply.generated)
	var support_before: Dictionary = world.basic_support.snapshot()
	var transaction: RunTransaction = app.progress_session._transaction
	var head: Dictionary = transaction.recover()
	var preview: Dictionary = world.support_plan_airstrike(landing)
	var before: Dictionary = world.support_world()
	_check(not preview.is_empty() and TransactionReceipt.same(preview, BuildAuthority.plan_airstrike(before, landing)),
		"T2 original preview agrees with authenticated closed-state airstrike planning")
	if preview.is_empty():
		return false
	var injected: Dictionary = {"count":0}
	app.progress_session.fault_hook = func(point: String) -> Error:
		if point == "before_record_write" and injected.count == 0:
			injected.count += 1
			return ERR_CANT_CREATE
		return OK
	await _key(KEY_E)
	await _world_click(world, landing)
	var pending: Dictionary = world.pending_support.duplicate(true)
	_check(injected.count == 1 and world.is_paused and not pending.is_empty() and not world.barricade_open
		and world.navigation == closed_nav and TransactionReceipt.same(world.basic_support.snapshot(), support_before)
		and world.support_aim._impact_remaining == 0.0 and "支援尚未确认" in world._notice_text
		and transaction.recover().hash == head.hash,
		"T5 fault leaves original closed geometry, cooldown, impact, and live receipt unchanged")
	app.progress_session.fault_hook = Callable()
	if pending.is_empty():
		return false
	FreezeProfile.enabled = true
	FreezeProfile.start({"sample":"durable retry and first opening"})
	world.toggle_pause()
	FreezeProfile.finish()
	var durable_timing: Dictionary = FreezeProfile.latest.duplicate(true)
	var accepted: Dictionary = world.basic_support.snapshot()
	var durable: Dictionary = transaction.recover()
	var accepted_once: bool = accepted.accepted.size() == 1 and accepted.accepted[0].id == pending.request.id
	_check(world.barricade_open and not world.is_paused and world.pending_support.is_empty() and accepted_once
		and world.basic_support.remaining("airstrike") == 20.0 and durable.receipt.support.size() == 1
		and int(durable.receipt.revision) == int(head.receipt.revision) + 2,
		"T5 normal retry publishes and opens exactly once with a single 20 second cooldown")
	_check(not closed_nav.is_clear(closed_rect.get_center()) and world.navigation.is_clear(closed_rect.get_center())
		and world.navigation != closed_nav, "T2/T6 open and closed navigation are independent in the same process")
	if not accepted_once or not world.barricade_open:
		return false
	var after: Dictionary = world.support_world()
	_check(TransactionReceipt.same(BuildAuthority.propose(pending.before, pending.request), after)
		and after.sites == pending.before.sites and after.sim.loot == pending.before.sim.loot
		and after.sim.food_loot == pending.before.sim.food_loot and after.weapons == pending.before.weapons
		and after.sim._spawn_count == pending.before.sim._spawn_count and after.sim._spawn_attempts == pending.before.sim._spawn_attempts,
		"T2 original support replay owns damage while opening produces no supplies")
	facts.strike = {"request":pending.request, "accepted":accepted.accepted[0],
		"cooldown_after":world.basic_support.remaining("airstrike"), "revision_before":head.receipt.revision,
		"revision_after":durable.receipt.revision, "failure_attempts":injected.count,
		"fault_point":"before_record_write",
		"impact_seconds":world.support_aim._impact_remaining}
	var samples: Array[Dictionary] = [durable_timing]
	for index: int in range(3):
		FreezeProfile.start({"sample":"warm proposal and projection only", "index":index + 1})
		var plan: Dictionary = BuildAuthority.plan_airstrike(pending.before, SortieSnapshot._vec(pending.request.payload.point))
		var proof_stamp: int = FreezeProfile.enter("support.proposal_only")
		var replay: Dictionary = BuildAuthority.propose(pending.before, pending.request)
		FreezeProfile.leave("support.proposal_only", proof_stamp)
		world.apply_barricade_history(pending.before.support.accepted)
		var apply_stamp: int = FreezeProfile.enter("support.projection_only")
		world.apply_barricade_history(replay.support.accepted)
		FreezeProfile.leave("support.projection_only", apply_stamp)
		FreezeProfile.finish()
		_check(TransactionReceipt.same(plan, pending.request.payload) and TransactionReceipt.same(replay, after)
			and world.barricade_open, "T7 warm projection repeats the exact genuine opening proof")
		samples.append(FreezeProfile.latest.duplicate(true))
	FreezeProfile.enabled = false
	_write("opening-timing.json", {"samples":samples})
	return true


func _barricade_shot(world: Expedition, name: String, size: Vector2i) -> void:
	var marker: Dictionary = world.supply.generated.barricade
	var anchor: Vector2 = WorldLayout.point(marker.anchor)
	viewport.size = size
	world.camera.pan_by(anchor - world.camera.position)
	await _shot(name)
	_write(name + ".json", {"viewport":[viewport.size.x, viewport.size.y], "zoom":world.camera.zoom.x,
		"open":world.barricade_open, "elapsed":world.elapsed, "cooldown":world.basic_support.remaining("airstrike"),
		"anchor":marker.anchor, "notice":world._notice_text})
	viewport.size = Vector2i(1280, 720)
	await _hold(3)


func _resume_barricade() -> void:
	var world: Expedition = app.expedition
	var source: String = stage.trim_suffix("-finish") + "-save"
	var prior: Dictionary = _checkpoint(world, source + "/checkpoint.json")
	if prior.is_empty():
		return
	facts = prior.facts.duplicate(true)
	_before = app.camp_snapshot()
	var support: Dictionary = world.basic_support.snapshot()
	var digest: String = RecordEncoding.fingerprint(SortieSnapshot.capture(world))
	_check(digest == prior.fingerprint and world.barricade_open == prior.open
		and world.search_site(StringName(facts.site)) != null,
		"T4 new process preserves route, original target, exact accepted history and cooldown")
	_write("restored.json", {"pid":OS.get_process_id(), "source_pid":prior.pid, "open":world.barricade_open,
		"fingerprint":digest, "support":support, "elapsed":world.elapsed})
	await _unpause(world)
	await _trace_supply(world)


func _trace_supply(world: Expedition) -> void:
	var site: Expedition.SearchSite = world.search_site(StringName(facts.site))
	await _world_click(world, site.door)
	var worker: int = world.search_assignments.member_for(String(site.id))
	_check(worker > 0, "T1/T2 actual click assigns one worker at the same original supply point")
	if worker <= 0:
		return
	var actor: FieldActor = world.search_member(worker)
	var start: Vector2 = actor.position
	var previous: Vector2 = start
	var elapsed: float = world.elapsed
	var walked: float = 0.0
	var crossed: bool = false
	var rect: Rect2 = BarricadeV1.rect(world.supply.generated)
	var path: PackedVector2Array = actor.path.duplicate()
	for tick: int in range(5400):
		if site.progress > 0.0 or actor.health <= 0.0 or world.is_paused:
			break
		world.step(STEP)
		walked += previous.distance_to(actor.position)
		crossed = crossed or rect.has_point(actor.position)
		previous = actor.position
		if tick % 30 == 0:
			await _frame()
	_check(site.progress > 0.0 and crossed == world.barricade_open and actor.position.distance_to(site.door) <= 14.0,
		"T1/T2 real worker reaches the supply point; only the open route crosses the original vehicle footprint")
	if site.progress <= 0.0:
		return
	facts.trace = {"worker":worker, "start":[start.x,start.y], "distance":walked, "crossed":crossed,
		"seconds":world.elapsed - elapsed, "planned_length":ExplorationLayout._length(path)}
	await _until(world, func() -> bool: return site.searched)
	var opened: bool = world.barricade_open
	var before: Dictionary = {"cash":world.loot, "food":world.food_loot, "weapons":world.weapon_loot.duplicate(true)}
	var committed: Dictionary = await _bank(world)
	if committed.is_empty() or reports.is_empty():
		return
	var after: Dictionary = app.camp_snapshot()
	var report: Dictionary = reports.back()
	var living: int = report.health.filter(func(health: float) -> bool: return health > 0.0).size()
	_check(report.evacuated and report.loot == before.cash and report.food == before.food
		and after.cash - _before.cash == before.cash and after.last_day.food_found == before.food,
		"T1/T2 original search and settlement preserve the actual carried rewards")
	facts.merge({"route_open":opened, "carried":before, "return_seconds":float(report.elapsed),
		"banked":{"cash":after.last_day.cash_gained, "food":after.last_day.food_stored, "rations":after.last_day.food_consumed},
		"survivors":living, "deaths":int(facts.departed_members) - living, "receipt":committed.hash,
		"support":report.get("support", {}), "pid":OS.get_process_id()})
	_write("route-result.json", facts)


func _closed_rejections(world: Expedition) -> void:
	var transaction: RunTransaction = app.progress_session._transaction
	var token: Dictionary = app.progress_session.token.duplicate(true)
	var head: Dictionary = transaction.recover()
	var valid: Dictionary = world.support_world()
	var checkpoint: Dictionary = head.receipt.duplicate(true)
	checkpoint.health = valid.survivors.map(func(row: Dictionary) -> Dictionary:
		return {"id":row.state.member_id, "health":row.state.health})
	_check(SortieSnapshot.problem(valid, checkpoint).is_empty(), "T4 genuine closed snapshot validates before negative fixtures")
	var landing: Vector2 = WorldLayout.point(facts.marker.landing)
	var plan: Dictionary = BuildAuthority.plan_airstrike(valid, landing)
	var forged_history: Dictionary = BuildAuthority.propose(valid, world.basic_support.request("airstrike", plan))
	_check(not forged_history.is_empty(), "T4 directed sample can propose a strike but has no confirmed receipt")
	var rejections: Array[Dictionary] = []
	for variant: String in ["closed-position", "closed-path", "undurable-opening"]:
		var forged: Dictionary = valid.duplicate(true)
		var actor: Dictionary = forged.survivors[0].state
		if variant == "closed-position":
			actor.position = facts.marker.anchor.duplicate()
		elif variant == "closed-path":
			actor.path = [actor.position.duplicate(), facts.marker.anchor.duplicate(), facts.marker.far.duplicate()]
			actor.activity = FieldActor.Activity.MOVING
			actor._path_index = 1
		elif not forged_history.is_empty():
			forged = forged_history
		else:
			continue
		var preview: Dictionary = transaction.preview_suspend(token, forged)
		var reason: String = "SUPPORT_NOT_DURABLE" if variant == "undurable-opening" else "WORLD_BARRICADE_SURVIVOR"
		_check(preview.error != OK and preview.get("reason") == reason, "T4 preflight rejects " + variant)
		if preview.error == OK:
			continue
		var written: Dictionary = transaction.suspend(token, forged)
		var untouched: bool = transaction.recover().hash == head.hash
		_check(written.error != OK and written.get("reason") == preview.get("reason") and untouched,
			"T4 writer rejects " + variant + " and preserves the live head")
		if not untouched:
			break
		var destination: String = output.path_join("forged-" + variant)
		var next: Dictionary = _forged_receipt(head, token, forged)
		next.health = checkpoint.health.duplicate(true)
		_copy_forged_record(transaction._journal.directory, destination, next)
		rejections.append({"variant":variant, "directory":destination, "reason":preview.get("reason", ""),
			"write":written.get("reason", ""), "live_head_preserved":untouched})
	_write("forgeries.json", {"pid":OS.get_process_id(), "rejections":rejections})


func _barricade_readback() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("a-save/forgeries.json")))
	_check(source.pid != OS.get_process_id() and source.rejections.size() == 3,
		"T4 three forged journal copies use an independent process")
	var reasons: Dictionary = {}
	for item: Dictionary in source.rejections:
		var replay: Dictionary = ReceiptJournal.new(item.directory).read_all()
		_check(replay.error != OK and replay.get("reason") == item.reason, "T4 exact independent readback rejects " + item.variant)
		reasons[item.variant] = replay.get("reason", "")
	_write("readback.json", {"pid":OS.get_process_id(), "reasons":reasons})


func _strike_edges(world: Expedition) -> void:
	var action: Dictionary = world.supply.generated
	var landing: Vector2 = WorldLayout.point(action.barricade.landing)
	var anchor: Vector2 = WorldLayout.point(action.barricade.anchor)
	await _key(KEY_E)
	_check(world.support_aiming, "T3 E enters original aim mode")
	await _key(KEY_ESCAPE)
	_check(not world.support_aiming and world.basic_support.ready("airstrike") and not world.barricade_open,
		"T3 cancelling aim changes no cooldown or geometry")
	var points: Dictionary = _edge_points(world, anchor)
	_check(points.has_all(["range", "wall", "miss"]), "T3 original generated map provides range, wall and valid off-center targets")
	if not points.has_all(["range", "wall", "miss"]):
		return
	await _key(KEY_E)
	for point: Vector2 in [anchor, points.range, points.wall]:
		_check(world.support_plan_airstrike(point).is_empty(), "T3 original legal-ground and caller gate rejects directed point")
		await _world_click(world, point)
		_check(world.support_aiming and world.basic_support.snapshot().sequence == 0 and not world.barricade_open,
			"T3 illegal actual click leaves aim, cooldown and route intact")
	await _world_click(world, points.miss)
	_check(not world.barricade_open and world.basic_support.snapshot().sequence == 1
		and world.basic_support.remaining("airstrike") == 20.0, "T3 legal miss consumes original cooldown without opening")
	await _until(world, func() -> bool: return world.basic_support.ready("airstrike"), 610)
	await _key(KEY_E)
	await _world_click(world, landing)
	_check(world.barricade_open and world.basic_support.snapshot().sequence == 2,
		"T3 legal hit after a miss opens through one later original acceptance")
	if not world.barricade_open:
		return
	var open_nav: FieldNavigation = world.navigation
	await _until(world, func() -> bool: return world.basic_support.ready("airstrike"), 610)
	await _key(KEY_E)
	await _world_click(world, landing)
	var support: Dictionary = world.basic_support.snapshot()
	_check(world.barricade_open and world.navigation == open_nav and support.sequence == 3
		and "路障已清除" not in world._notice_text, "T3 later ordinary airstrike keeps the open route without repeating the opening notice")
	_write("edges.json", {"points":points, "support":support, "open":world.barricade_open})


func _edge_points(world: Expedition, anchor: Vector2) -> Dictionary:
	var found: Dictionary = {}
	var center: Vector2 = world.survivors[0].position
	var blast: float = BasicSupport.POLICY.airstrike_radius * BuildItems.frozen_factors(world.supply.generated.build).blast
	for y: int in range(-24, 25):
		for x: int in range(-24, 25):
			var point: Vector2 = center + Vector2(x,y) * 16.0
			if not world.navigation.is_clear(point):
				continue
			var in_range: Array[FieldActor] = world.survivors.filter(func(actor: FieldActor) -> bool:
				return actor.health > 0.0 and actor.visible and actor.position.distance_to(point) <= BasicSupport.POLICY.airstrike_range)
			if in_range.is_empty():
				if not found.has("range"):
					found.range = point
				continue
			var visible: bool = in_range.any(func(actor: FieldActor) -> bool:
				return ToxicV1.line_clear(actor.position, point, world.shot_obstacles))
			if not visible and not found.has("wall"):
				found.wall = point
			elif visible and not found.has("miss") and point.distance_to(anchor) > blast and not world.support_plan_airstrike(point).is_empty():
				found.miss = point
			if found.has_all(["range", "wall", "miss"]):
				return found
	return found
