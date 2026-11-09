extends "res://tests/campaign_flow.gd"
## Normal-entry A/B. Restore the same isolated camp bytes to the same binding path.

func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._opening_picker.choices["scavenge"])
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(NightHoundV1.campaign_enabled(app.camp_snapshot().journey.campaign), "normal new journey enables the hound policy")
	await _tap(app.camp_scene.hotspots[&"bus"])
	_check(app.mission_select.daily_offers.all(func(action: Dictionary) -> bool: return not NightHoundV1.enabled(action)), "day two has no eligible hound action")
	var index: int = app.mission_select.daily_offers.find_custom(func(action: Dictionary) -> bool: return action.has("investigation"))
	_check(index >= 0, "ordinary day-two investigation is available")
	if index < 0:
		return
	var world: Expedition = await _start(index)
	if world == null:
		return
	var main: Expedition.SearchSite = world.search_site(&"cash")
	world.request_search(main.id)
	await _until(world, func() -> bool: return main.searched)
	for site: Expedition.SearchSite in world.sites:
		if app.food + world.food_loot >= 4:
			break
		if site.kind == &"food" and not site.searched:
			world.request_search(site.id)
			await _until(world, func() -> bool: return site.searched)
	if not await _bank(world):
		return
	await _tap(app.camp_scene.hotspots[&"weapons"])
	var panel: PowerLoadoutPanel = app.loadout_panel.power_panel
	await _tap(panel.choices[SpecialPowers.FREEZE])
	await _tap(app.loadout_panel.back_button)
	var camp: Dictionary = app.camp_snapshot()
	_check(camp.day == 3 and camp.journey.build.powers.slots[0] == SpecialPowers.FREEZE,
		"confirmed day-three camp can equip the normally obtained freeze")
	_write("common.json", {"camp":camp, "receipt":app.progress_session._transaction.recover().hash})


func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var camp: Dictionary = app.camp_snapshot()
	await _tap(app.camp_scene.hotspots[&"bus"])
	var index: int = app.mission_select.daily_offers.find_custom(func(action: Dictionary) -> bool: return NightHoundV1.enabled(action))
	_check(index >= 0, "ordinary day-three industrial equipment card uses the hound policy")
	if index < 0:
		return
	var world: Expedition = await _start(index)
	if world == null:
		return
	var arrivals: Array[Dictionary] = []
	world.spawn_resolved.connect(func(event: Dictionary) -> void: arrivals.append(event.duplicate(true)))
	var main: Expedition.SearchSite = world.search_site(&"cash")
	world.request_search(main.id)
	await _until(world, func() -> bool: return main.searched)
	var recovered_at: float = world.elapsed
	var action: Dictionary = world.supply.generated
	var night: float = world.tuning.daylight_seconds
	var route: Dictionary = {"action":action.id, "map":world.layout.id, "action_seed":action.seed,
		"camp_hash":RecordEncoding.fingerprint(camp), "crew":camp.crew.map(func(member: Dictionary) -> int: return int(member.id)),
		"health_before":world.survivors.map(func(member: FieldActor) -> float: return member.health),
		"loadout":camp.loadout, "powers":camp.journey.build.powers.slots, "items":camp.journey.build.slots,
		"night":night, "main_at":recovered_at}
	if output.get_file() == "b-night":
		world.command_move(world.layout.bus_door)
		await _until(world, func() -> bool: return arrivals.any(func(event: Dictionary) -> bool:
			return event.get("enemy_type") == NightHoundV1.KIND), 12000)
		var encounter: Dictionary = arrivals.filter(func(event: Dictionary) -> bool:
			return event.get("enemy_type") == NightHoundV1.KIND).front() if arrivals.any(func(event: Dictionary) -> bool:
			return event.get("enemy_type") == NightHoundV1.KIND) else {}
		_check(not encounter.is_empty() and encounter.stage >= ThreatDirector.Stage.NIGHT and encounter.elapsed >= night and encounter.legal,
			"waiting through night uses the real spawn pipeline and sees the legal hound")
		if not encounter.is_empty():
			route.spawn = encounter
			await _approach_hound(world, int(encounter.enemy_id))
	if not await _bank(world):
		return
	var dogs: Array[Dictionary] = []
	dogs.assign(arrivals.filter(func(event: Dictionary) -> bool: return event.get("enemy_type") == NightHoundV1.KIND))
	_check(dogs.size() == (1 if output.get_file() == "b-night" else 0), "normal route has the expected number of actual hound spawns")
	if output.get_file() == "a-early":
		_check(reports.back().elapsed < night, "early route really evacuates before night")
	route.hounds = dogs
	route.hits = events.filter(func(event: Dictionary) -> bool: return event.kind == "hit")
	route.report = reports.back()
	route.camp = {"cash":app.cash, "food":app.food, "day":app.day}
	route.receipt = app.progress_session._transaction.recover().hash
	_write("route.json", route)


func _approach_hound(world: Expedition, identity: int) -> void:
	for tick: int in range(1800):
		var hound: FieldActor = world.combat._enemy(world, identity)
		if hound == null or world.is_paused:
			return
		if tick % 45 == 0:
			world.command_move(hound.position)
		if world.visible_world_rect().has_point(hound.position) and world.survivors.any(func(member: FieldActor) -> bool:
				return member.position.distance_to(hound.position) < 280.0):
			world.camera.pan_by(hound.position - world.camera.position)
			world.camera.force_update_scroll()
			await _shot("actual-hound")
			return
		world.step(1.0 / 30.0)
		if tick % 12 == 0:
			await _frame()


func _bank(world: Expedition) -> bool:
	await _extract(world)
	_check(not app._pending_settlement.is_empty() and not app._progress_blocked, "original bus reaches the validated preview")
	if app._pending_settlement.is_empty() or app._progress_blocked:
		return false
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	var committed: Dictionary = app.progress_session._transaction.recover()
	_check(committed.error == OK and committed.receipt.phase == "COMMITTED" and not reports.is_empty(),
		"original result confirms exactly one return")
	return committed.error == OK and not reports.is_empty()
