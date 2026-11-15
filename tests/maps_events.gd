extends "res://tests/harbor_warehouse.gd"
## Directed fixtures only: authenticated offers, real work/navigation and exact transport.


func run() -> void:
	for path: String in ["res://src/features/camp/scavenge.tres", "res://src/features/camp/rescue.tres"]:
		expect(load(path) is MissionSupply, "legacy mission loads without a destination dependency cycle")
	var base: Dictionary = _harbor_camp()
	base.day = 4
	base.settled_sorties = 2
	var offers: Array[Dictionary] = DailyActions.offers(base)
	var signature: String = RecordEncoding.fingerprint({"offers":offers})
	var action: Dictionary = {}
	for candidate: Dictionary in offers:
		if CapeStation.should_apply(candidate):
			action = candidate
			break
	expect(not action.is_empty(), "day four has a real ordinary supply departure to the station")
	if not action.is_empty():
		var supply: MissionSupply = DailyActions.supply(action)
		expect(CapeStation.is_layout(supply.layout), "normal dispatch selects cape_station")
		expect(TransactionReceipt.same(action, supply.generated) and DailyActions.matches(base, action), "destination preserves the complete authenticated descriptor")
		expect(String(supply.layout.id) == action.layout.id and supply.id == &"supermarket", "map and mission receipt IDs retain their source")
		expect(FrozenSettlement._rules_problem(FrozenSettlement.pool_rules(base, supply)).is_empty(), "settlement accepts original rewards and IDs")
		_station_geometry(supply)
		_station_exclusions(action)
		await _station_menu(base, supply)
		await _station_work(base, supply)
		await _blockade(base, supply)
		expect(signature == RecordEncoding.fingerprint({"offers":DailyActions.offers(base)}), "building, menu and runtime cannot mutate or reroll offers")
	print("BH_MAPS_EVENTS " + JSON.stringify({"checks":checks, "failures":failures}))
	quit(0 if failures == 0 else 1)


func _station_geometry(supply: MissionSupply) -> void:
	var street: StreetLayout = supply.layout
	var nav: FieldNavigation = FieldNavigation.new()
	nav.configure(street.blockers(), street.world_bounds)
	expect(street.bus_block.size == Vector2(108, 32), "locked bus dimensions")
	for road: Rect2 in street.roads:
		expect(minf(road.size.x, road.size.y) == 96.0, "locked asphalt width")
	for row: Array in street.world_data.grounds.sidewalks:
		var walk: Rect2 = WorldLayout.rect(row)
		expect(minf(walk.size.x, walk.size.y) == 32.0, "locked sidewalk width")
	var ids: Array[String] = []
	for entity: Dictionary in street.world_data.entities:
		var body: Rect2 = WorldLayout.rect(entity.rect)
		expect(street.world_bounds.encloses(body) and not nav.is_clear(body.get_center()), "closed building body blocks entry: " + entity.id)
		expect(not IsoAtlas.info(entity.art).is_empty(), "registered exterior art: " + entity.id)
		for other: Dictionary in street.world_data.entities:
			if other.id != entity.id:
				expect(not body.intersects(WorldLayout.rect(other.rect)), "independent station footprints")
		if not String(entity.site_id).is_empty():
			expect(entity.site_id not in ids, "one physical point per signed source")
			ids.append(entity.site_id)
	expect(ids.size() == supply.generated.sites.size(), "all primary, optional and object sites are bound")
	for site: Dictionary in supply.generated.sites:
		var point: Vector2 = TaskActions.site_point(supply.generated, site)
		expect(TaskActions.outdoor_site(supply.generated, StringName(site.id)) and nav.is_clear(point) and _reaches(nav, street.bus_door, point), "source work is reachable outdoors: " + site.id)
	for point: Vector2 in street.arrivals + street.enemy_points + [Vector2(688, 400), Vector2(1776, 400)]:
		expect(nav.is_clear(point) and _reaches(nav, street.bus_door, point), "arrival, entrance and both platform approaches connect")
	expect(not nav.is_clear(Vector2(1216, 240)), "short track is a physical obstacle")
	for offset: Vector2 in [Vector2(-48, -32), Vector2(48, -32), Vector2(-48, 16), Vector2(48, 16)]:
		expect(nav.is_clear(street.bus_door + offset), "complete squad fits around boarding door")
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(supply.generated))).payload
	expect(TransactionReceipt.same(DailyActions.supply(decoded).layout.world_data, street.world_data), "exact transport rebuilds station terrain and bindings")


func _station_exclusions(action: Dictionary) -> void:
	for day: int in [2, 3, 5, 7]:
		var other: Dictionary = action.duplicate(true)
		other.day = day
		expect(not CapeStation.should_apply(other), "only even days from day four use station")
	for key: String in CapeStation.EXCLUSIONS:
		var other: Dictionary = action.duplicate(true)
		other[key] = {}
		expect(not CapeStation.should_apply(other), "independently signed spatial action retains original terrain: " + key)


func _station_menu(base: Dictionary, supply: MissionSupply) -> void:
	var menu: MissionSelect = MissionSelect.new()
	menu.review_enabled = true
	root.add_child(menu)
	menu.refresh_daily(base)
	var index: int = menu.daily_offers.find_custom(func(row: Dictionary) -> bool: return row.id == supply.generated.id)
	expect(index >= 0, "real menu offers station")
	if index >= 0:
		var emitted: Array[MissionSupply] = []
		menu.selected.connect(func(value: MissionSupply) -> void: emitted.append(value))
		menu._choose(index)
		menu._confirm_departure()
		expect(emitted.size() == 1 and CapeStation.is_layout(emitted[0].layout), "normal confirmation enters formal destination")
		expect(menu._titles[index].text.contains(CapeStation.TITLE) and menu._descriptions[index].text.contains("封锁夜预告"), "destination and night warning appear before departure")
	menu.queue_free()
	await process_frame


func _station_work(base: Dictionary, supply: MissionSupply) -> void:
	var world: Expedition = _maps_field(base, supply)
	expect(world.setup_problem.is_empty() and world.mission_title == CapeStation.TITLE, "real expedition builds station and HUD")
	world.bus_view.skip()
	var worker: FieldActor = world.survivors[0]
	var site: Expedition.SearchSite = world.search_site(&"food")
	var nominal: float = 0.0
	for source: Dictionary in supply.generated.sites:
		if source.id == "food":
			nominal = float(source.seconds)
	expect(site.seconds == nominal, "nominal source work time is unchanged")
	world._assign_search(site, worker, world.navigation.path_between(worker.position, site.door))
	for tick: int in range(1800):
		worker.advance(1.0 / 30.0)
		world.elapsed += 1.0 / 30.0
		world._update_search(1.0 / 30.0)
		if site.progress >= 2.0:
			break
	expect(site.progress >= 2.0 and worker.visible and worker.activity == FieldActor.Activity.RECOVERING, "worker reaches doorway and remains outside during work")
	world.toggle_pause()
	var captured: Dictionary = SortieSnapshot.capture(world)
	expect(not captured.is_empty(), "paused station work can be captured")
	if not captured.is_empty():
		var restored: Expedition = _maps_field(base, DailyActions.supply(supply.generated))
		var data: Dictionary = restored.layout.world_data.duplicate(true)
		restored.layout.world_data.entities[0].door[0] += 16
		expect(SortieSnapshot.apply(restored, captured) == "WORLD_BUILD_DATA_VIEWPORT_MISMATCH", "station work anchors participate in snapshot compatibility")
		restored.layout.world_data = data
		var issue: String = SortieSnapshot.apply(restored, captured)
		expect(issue.is_empty() and restored.search_site(&"food").progress == site.progress, "partial work and assignment reconstruct: " + issue)
		restored.get_viewport().queue_free()
	world.toggle_pause()
	for tick: int in range(1800):
		world.elapsed += 1.0 / 30.0
		world._update_search(1.0 / 30.0)
		if site.searched:
			break
	expect(site.searched and world.food_loot == site.reward, "real work carries the original food reward")
	world.request_bus_gather()
	for tick: int in range(1800):
		for member: FieldActor in world.survivors:
			member.advance(1.0 / 30.0, false, false)
		FieldContacts.move(world.survivors, world.survivors, world.navigation, 1.0 / 30.0, true)
		if world.boarding_status().arrived == world.survivors.size():
			break
	expect(world.boarding_status().arrived == world.survivors.size(), "all living members can return to the bus")
	world.request_extraction()
	expect(world.phase == Expedition.Phase.ENGINE, "normal engine startup remains usable")
	world.get_viewport().queue_free()
	await process_frame


func _blockade(base: Dictionary, supply: MissionSupply) -> void:
	var action: Dictionary = supply.generated
	expect(CampaignPressureV1.blockade_night(action), "day-four pressure action forecasts blockade night")
	for day: int in [3, 5, 6, 8]:
		var other: Dictionary = action.duplicate(true)
		other.day = day
		other.campaign_pressure = CampaignPressureV1.marker(day - 2)
		expect(not CampaignPressureV1.blockade_night(other), "ordinary intervening days retain original night")
	for stage: int in range(4):
		for index: int in range(12):
			var kind: String = CampaignPressureV1.blockade_kind(action, EnemyRules.NORMAL, index, stage)
			var expected: String = EnemyRules.NORMAL if stage < 2 or index % 3 == 2 else EnemyRules.HEAVY if index % 3 == 0 else EnemyRules.RUSH
			expect(kind == expected, "blockade strengthens only night ambient ordinary slots")
			expect(CampaignPressureV1.blockade_kind(action, CombatEnemyRules.TOXIC, index, stage) == CombatEnemyRules.TOXIC, "special species retain their original roll")
	var world: Expedition = _maps_field(base, supply)
	world.bus_view.skip()
	world.elapsed = world.tuning.daylight_seconds
	world.threat.update(world.elapsed, world.tuning.daylight_seconds, world.tuning.spawn_seconds)
	var changed: bool = false
	for index: int in range(18):
		var original: String = CombatEnemyRules.pick(world.sortie_id, index, 2)
		var kind: String = CombatEnemyRules.pick_for(action, world.sortie_id, index, 2)
		changed = changed or kind != original
		# Instantiate through the same actor/spawn registry owners, avoiding camera-dependent spawn availability in this fixture.
		var enemy: FieldActor = world._make_actor(true, index, world.layout.enemy_points[index % world.layout.enemy_points.size()])
		world.enemies.append(enemy)
		world._spawn_count += 1
		world._spawn_attempts += 1
		if enemy.enemy_behavior.kind == ScreamerPolicyV1.KIND:
			world.combat.screamer.spawned(world, enemy)
		if enemy.enemy_behavior.kind == BurstRuntimeV1.KIND:
			world.combat.burst.spawned(world, enemy)
	expect(changed, "deterministic night identity actually upgrades some original ordinary rolls")
	world.toggle_pause()
	var captured: Dictionary = SortieSnapshot.capture(world)
	expect(not captured.is_empty(), "blockade night captures with existing combat provenance")
	if not captured.is_empty():
		var receipt: Dictionary = {"transaction_id":world.sortie_id, "base":base, "rules":FrozenSettlement.pool_rules(base, supply), "joins":[]}
		var issue: String = CombatRuntime.problem(captured.combat, captured, receipt)
		expect(issue.is_empty(), "night spawn registry authenticates: " + issue)
		var forged: Dictionary = captured.duplicate(true)
		var converted: bool = false
		for key: String in forged.combat.spawns:
			var record: Dictionary = forged.combat.spawns[key]
			if record.kind in [EnemyRules.HEAVY, EnemyRules.RUSH] and CombatEnemyRules.pick(world.sortie_id, int(key), 2) == EnemyRules.NORMAL:
				record.kind = EnemyRules.NORMAL
				converted = true
				break
		expect(converted and CombatRuntime.problem(forged.combat, forged, receipt) == "COMBAT_SPAWN_SOURCE", "forged ordinary roll cannot erase a recorded blockade upgrade")
		for row: Dictionary in captured.enemies:
			expect(CombatEnemyRules.snapshot_problem(row, captured, receipt).is_empty(), "night enemy retains strict source, health and movement checks")
		var restored: Expedition = _maps_field(base, supply)
		expect(SortieSnapshot.apply(restored, captured).is_empty(), "night reconstructs with its existing registry")
		expect(TransactionReceipt.same(restored.combat.spawns, world.combat.spawns), "resume never rerolls the high-pressure wave")
		restored.get_viewport().queue_free()
	expect(SortieEvents.summary(action, {"elapsed":104.0, "evacuated":true}, 105.0).contains("天黑前撤离") and SortieEvents.summary(action, {"elapsed":105.0}, 105.0).contains("经历入夜"), "durable elapsed time reconstructs both night outcomes")
	world.get_viewport().queue_free()
	await process_frame


func _visible_events() -> void:
	# Search only pure selectors, then generate a single board for each event kind.
	# Synthetic camps exercise real offer construction, never write player saves.
	for type: String in ["emergency", "cold"]:
		var base: Dictionary = _harbor_camp()
		base.day = 4
		base.settled_sorties = 2
		var found: bool = false
		for index: int in range(128):
			var seed: String = ("maps-events-%s-%d" % [type, index]).md5_text()
			var no_rescue: bool = ("m25-action-choice:%s:4" % seed).sha256_text().left(1).hex_to_int() % 2 == 1
			if (type == "emergency" and EventSortieV1.selected(seed, 4, SortieRiskV1.SLOT) and RareSortie.selection(seed, 4, RareSortie.SLOT).is_empty() and no_rescue) or (type == "cold" and RareSortie.selection(seed, 4, RareSortie.SLOT) == "supply"):
				base.journey.seed = seed
				found = true
				break
		expect(found, "fixed event fixture selector has a reproducible seed")
		base.journey.build = WorldgenState.initial_build(base.journey.seed, true, true)
		base.journey.build.powers = PowerState.initial_progression(SpecialPowers.M48_VERSION)
		BuildState.enable_m48(base.journey.build)
		# Day four avoids the day-three hardware offer replacing the optional event.
		var action: Dictionary = {}
		for offer: Dictionary in DailyActions.offers(base):
			if (type == "emergency" and offer.has("event_sortie")) or (type == "cold" and SortieEvents.cold_store(offer)):
				action = offer
				break
		expect(not action.is_empty(), "real board exposes " + type)
		if action.is_empty():
			continue
		var issue: String = DailyActions.problem(action)
		expect(issue.is_empty(), "selected event authenticates before construction: " + type + " " + issue)
		if not issue.is_empty():
			continue
		var world: Expedition = _maps_field(base, DailyActions.supply(action))
		world.bus_view.skip()
		expect(not SortieEvents.field_hint(world).is_empty() and DailyActions.problem(action).is_empty(), "visible event uses original authenticated policy")
		if type == "emergency":
			await _emergency_branches(base, action, world)
		else:
			for id: String in ["food", "food_2"]:
				expect(world.search_site(StringName(id)).prop.get_meta("power_outage", false), "both cold-room exteriors visibly lose power")
			world._feedback._atmosphere.refresh(world, 1.0)
			var summary: String = SortieEvents.summary(action, {"site_facts":{"food":{"searched":true}, "food_2":{"searched":false}}}, 105.0)
			expect(summary.contains("近处已搜集") and summary.contains("远端未搜集"), "existing site facts reconstruct the event outcome after save transport")
			for id: String in ["food", "food_2"]:
				expect(world.search_site(StringName(id)).prop.window_glow == 0.0, "outage leaves cold-room windows dark without changing atmosphere curve")
		world.get_viewport().queue_free()
		await process_frame


func _emergency_branches(base: Dictionary, action: Dictionary, first: Expedition) -> void:
	for branch: String in [EventSortieV1.QUIET, EventSortieV1.FORCE]:
		var world: Expedition = first if branch == EventSortieV1.QUIET else _maps_field(base, DailyActions.supply(action))
		world.bus_view.skip()
		var site: Expedition.SearchSite = world.search_site(&"cash")
		var worker: FieldActor = world.survivors[0]
		worker.position = site.door
		world.event_sortie_panel.present()
		expect(world.confirm_event_choice(branch), "arrival locks a real event choice")
		for tick: int in range(1800):
			world.elapsed += 1.0 / 30.0
			world._update_search(1.0 / 30.0)
			if site.searched:
				break
		expect(site.searched and world.task_event.started == (branch == EventSortieV1.FORCE), "quiet and force resolve with their own reinforcement rules")
		var report: Dictionary = {"site_facts":WorldSites.facts(world), "task_event":world.task_event.duplicate(true), "evacuated":true}
		var outcome: Dictionary = TaskActions.outcome(action, report)
		var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(outcome))).payload
		expect(TaskActions.summary_problem(decoded).is_empty() and decoded.branch == branch and decoded.event_food == (3 if branch == EventSortieV1.QUIET else 0) and decoded.event_cash == (6 if branch == EventSortieV1.FORCE else 0), "event outcome persists exact branch and original reward")
		if world != first:
			world.get_viewport().queue_free()
		await process_frame


func _maps_field(base: Dictionary, supply: MissionSupply) -> Expedition:
	var world: Expedition = Expedition.new()
	world.supply = supply
	world.battle_survival = true
	world.sortie_id = base.profile_id + ":3"
	world.day = int(supply.generated.day)
	world.crew_snapshot.assign(base.crew)
	world.loadout_snapshot = WeaponInventory.snapshot(base)
	world.field_departure = base
	world.growth_binding = {"run_id":base.profile_id, "root_id":base.journey.root_id, "transaction_id":world.sortie_id,
		"base_hash":SurvivalContracts.fingerprint(base), "rules_hash":SurvivalContracts.fingerprint(FrozenSettlement.pool_rules(base, supply))}
	world.ui_theme = preload("res://assets/ui/c1/hud_theme.tres")
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.world_2d = World2D.new()
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	viewport.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	return world
