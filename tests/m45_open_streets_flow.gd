extends "res://tests/playable_flow.gd"
## Normal candidate, original intents, and a disposable cross-process checkpoint.

func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(app.camp_snapshot().journey.campaign.get("open_streets_policy") == OpenStreetsV1.VERSION,
		"isolated normal new journey opts into the prototype")
	await _tap(app.camp_scene.hotspots[&"bus"])
	var selected: int = -1
	for index: int in range(app.mission_select.daily_offers.size()):
		var action: Dictionary = app.mission_select.daily_offers[index]
		if action.layout.has("open_streets"):
			selected = index
			_check(action.layout.open_streets == OpenStreetsV1.VERSION,
				"every open-street offer uses the new journey's geometry revision")
			_check(DailyActions.problem(action).is_empty(), "frozen M45 action authenticates")
		elif action.layout["size"] != "large":
			_check(action.layout.bounds == ExplorationLayout.SIZES[action.layout["size"]].bounds, "original small/medium dimensions")
	_check(selected >= 0, "normal mission menu offers an open-street candidate")
	if selected < 0:
		return
	await _tap(app.mission_select.choices[selected])
	var world: Expedition = app.expedition
	_check(world != null and not app._progress_blocked, "original departure transaction accepts the layout")
	if world == null:
		return
	world.set_physics_process(false)
	world.set_process(false)
	var layout: Dictionary = world.layout.world_data
	var road_stats: Dictionary = WorldgenStructure.metrics(layout)
	_write("geometry.json", {"theme":layout.topology, "task":world.supply.generated.type,
		"seed":layout.seed, "layout_id":layout.id, "bounds":layout.bounds, "buildings":layout.entities.size(),
		"blocks":layout.parcels.size(), "loops":road_stats.loops, "bus":layout.bus})
	_check(layout.bounds == OpenStreetsV1.BOUNDS and OpenStreetsV1.certify(layout, world.layout.blockers()),
		"frozen continuous arterial, parking lane, clear turn and doorway")
	await _advance(world, func() -> bool: return world.bus_view.stage == "disembarking", 1200)
	_check(world._bus_sprite.position == WorldLayout.point(layout.bus.stop), "bus drives to the in-lane stop")
	await _advance(world, func() -> bool: return not world.bus_view.running(), 180)
	_check(world.survivors.all(func(actor: FieldActor) -> bool: return actor.visible), "actual disembarking reveals the crew")
	await _photo("01-in-lane")
	var action: Dictionary = world.supply.generated
	var site_id: StringName = StringName(action.objective.site_ids[0]) if not action.objective.site_ids.is_empty() else &"cash"
	var site: Expedition.SearchSite = world.search_site(site_id)
	_check(site != null, "real work target")
	if site == null:
		return
	world.request_search(site_id)
	await _advance(world, func() -> bool: return site.progress >= 1.0 or world.phase == Expedition.Phase.FINISHED, 4200)
	_check(site.progress >= 1.0, "a crew member walked to and worked the original target")
	if site.progress < 1.0:
		return
	if "--flow-m45-suspend" in OS.get_cmdline_user_args():
		app.open_pause_menu()
		await _hold(2)
		var checkpoint: Dictionary = SortieSnapshot.capture(world)
		_write("checkpoint.json", {"fingerprint":RecordEncoding.fingerprint(checkpoint),
			"layout":RecordEncoding.fingerprint(layout), "pid":OS.get_process_id(), "site_id":String(site_id)})
		app.suspend_sortie()
		await _hold(3)
		_check(app.expedition == null and app._requires_continue, "durable normal suspension")
		return
	await _finish_open_sortie(world, site)


func _resume() -> void:
	var prior: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/checkpoint.json")))
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var world: Expedition = app.expedition
	_check(world != null, "normal Continue restores the suspended outing")
	if world == null:
		return
	world.set_physics_process(false)
	world.set_process(false)
	_check(int(prior.pid) != OS.get_process_id() and prior.layout == RecordEncoding.fingerprint(world.layout.world_data)
		and prior.fingerprint == RecordEncoding.fingerprint(SortieSnapshot.capture(world)), "new process restores exact layout and world fingerprints")
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:
		world.toggle_pause()
	await _finish_open_sortie(world, world.search_site(StringName(prior.site_id)))


func _finish_open_sortie(world: Expedition, site: Expedition.SearchSite) -> void:
	await _advance(world, func() -> bool: return site.searched or world.phase == Expedition.Phase.FINISHED, 4200)
	_check(site.searched, "original work completes and carries loot")
	var ready_at: float = world.elapsed
	await _advance(world, func() -> bool: return world.elapsed >= world.tuning.bus_ready_seconds, 1800)
	world.request_bus_action()
	await _advance(world, func() -> bool: return world.phase == Expedition.Phase.BOARDING or world.phase == Expedition.Phase.FINISHED, 1800)
	if world.phase == Expedition.Phase.BOARDING:
		world.request_bus_gather()
		await _advance(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED, 5400)
	var bus: BusJourney = world.bus_view
	var ready: Dictionary = app.progress_session.inspect()
	_check(ready.get("receipt", {}).get("phase") == "RESULT_READY" and bus.stage == "embarking",
		"durable successful result precedes the boarding animation")
	if bus.stage != "embarking":
		return
	_check(app.phase == app.Phase.EXPEDITION and not app._screen.visible, "result panel stays hidden")
	var parked: Vector2 = world._bus_sprite.position
	bus.skip()
	_check(bus.stage == "embarking" and world._bus_sprite.position == parked, "boarding cannot skip to the result")
	var shown: int = bus._boarding_actors.size()
	for actor: FieldActor in bus._boarding_actors:
		_check(actor.visible, "each living actor visible before entering the door")
	await _advance(world, func() -> bool: return bus._boarding_index >= 1, 200)
	_check(bus._boarding_index == 1 and shown > 1 and not bus._boarding_actors[0].visible
		and bus._boarding_actors[1].visible and world._bus_sprite.position == parked,
		"one actor hidden at the door while the next still waits and the bus remains stopped")
	await _photo("02-boarding")
	await _advance(world, func() -> bool: return bus.stage == "departing", 500)
	_check(not bus._open_body.door_open and bus._boarding_index == shown, "all living passengers aboard before forward movement")
	bus.skip()
	_check(bus.stage == "departing", "exit cannot skip to the result")
	var route_heading: Vector2 = (WorldLayout.point(bus.route.out_path[1]) - parked).normalized()
	var initial_rotation: float = world._bus_sprite.rotation
	world.step(0.15)
	var forward: Vector2 = world._bus_sprite.position - parked
	_check(forward.dot(route_heading) > 0.0 and absf(forward.cross(route_heading)) < 0.1,
		"bus starts forward along the ordinary lane")
	var observed_turn: bool = false
	var observed_partial_exit: bool = false
	var move_seconds: float = 0.15
	for tick: int in range(1500):
		if bus.stage == "done":
			break
		world.step(1.0/30.0)
		move_seconds += 1.0/30.0
		if not observed_turn and absf(angle_difference(initial_rotation, world._bus_sprite.rotation)) > 0.35:
			observed_turn = true
			await _photo("03-turn")
		if not observed_partial_exit and not world.layout.world_bounds.has_point(world._bus_sprite.position) and not bus._entire_bus_outside():
			observed_partial_exit = true
			_check(app.phase == app.Phase.EXPEDITION and not app._screen.visible, "result remains hidden with tail inside")
			await _photo("04-edge")
		if tick % 24 == 0:
			await _frame()
	_check(observed_turn == (world.layout.world_data.topology != "commercial") and observed_partial_exit,
		"certified straight or curved route and intermediate boundary state both observed")
	_check(bus.stage == "done" and bus._entire_bus_outside() and app.phase == app.Phase.RESULT and app._screen.visible,
		"normal result opens after the entire bus leaves")
	_check(app.progress_session.inspect().hash == ready.hash, "the drive does not modify the durable receipt")
	_write("evacuation.json", {"member_count":shown, "site":String(site.id), "site_complete_at":ready_at,
		"evacuated_at":world.elapsed, "drive_seconds":move_seconds, "turn":observed_turn, "tail_gate":observed_partial_exit})
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	var banked: Dictionary = app.camp_snapshot()
	app.return_to_title()
	_check(not app._progress_blocked and banked.settled_sorties == 1
		and TransactionReceipt.same(banked, app.camp_snapshot()), "one original confirmation banks the outing")


func _photo(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _hold(2)
	RenderingServer.force_draw()
	var error: Error = viewport.get_texture().get_image().save_png(output.path_join(name + ".png"))
	_check(error == OK, "offscreen rendered " + name)
