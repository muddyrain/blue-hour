extends "res://tests/persona_rules.gd"
## Directed contracts: signed source, real navigation, field work and snapshot rebuild.
## Synthetic day fixtures, not a claim of earned campaign progress; no disk writes.


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("BH_HARBOR_FAIL " + label)


func run() -> void:
	# Loading either legacy mission must not recursively load its own script.
	for path: String in ["res://src/features/camp/scavenge.tres", "res://src/features/camp/rescue.tres"]:
		expect(load(path) is MissionSupply, "mission resource loads without a harbor dependency cycle: " + path)
	var base: Dictionary = _harbor_camp()
	var offers: Array[Dictionary] = DailyActions.offers(base)
	var signed: String = RecordEncoding.fingerprint({"offers":offers})
	var selected: MissionSupply
	for offer: Dictionary in offers:
		if EconomyActions.hardware(offer):
			selected = DailyActions.supply(offer)
	expect(offers.size() == 3 and selected != null, "day-three optional hardware mission is available")
	if selected == null:
		_finish_harbor()
		return
	expect(HarborWarehouse.is_layout(selected.layout), "normal supply dispatch selects north harbor")
	expect(DailyActions.problem(selected.generated).is_empty() and DailyActions.matches(base, selected.generated), "harbor retains the original signed action")
	var rules: Dictionary = FrozenSettlement.pool_rules(base, selected)
	expect(FrozenSettlement._rules_problem(rules).is_empty(), "existing settlement owner accepts the harbor mission")
	expect(selected.id == &"scavenge" and String(selected.layout.id) == selected.generated.layout.id, "mission and map receipt identities remain canonical")
	_geometry(selected)
	_water(selected.layout)
	var gear: MissionSupply = DailyActions.supply(EconomyActions.origin(selected.generated))
	expect(HarborWarehouse.is_layout(gear.layout) and gear.has_weapon_sample, "original ordinary equipment source offers weapons at the same harbor")
	_geometry(gear)
	_exclusions(selected.generated)
	await _selection(base, offers, selected)
	await _field(base, selected)
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(selected.generated))).payload
	var restored: MissionSupply = DailyActions.supply(decoded)
	expect(TransactionReceipt.same(restored.layout.world_data, selected.layout.world_data), "exact action transport rebuilds all harbor geometry and bindings")
	expect(RecordEncoding.fingerprint({"offers":DailyActions.offers(base)}) == signed, "map construction and menu never mutate offers or their fingerprints")
	_finish_harbor()


func _finish_harbor() -> void:
	print("BH_HARBOR " + JSON.stringify({"checks":checks, "failures":failures, "scope":"directed harbor contracts; no player-save writes"}))
	quit(0 if failures == 0 else 1)


func _harbor_camp() -> Dictionary:
	var base: Dictionary = _camp_fixture()
	base.day = 3
	base.settled_sorties = 1
	base.journey.campaign = CampaignRules.initial_mission(base.profile_id, true, true, true, true, true, true, true, true, true, true)
	CampFacilities.enable_tier_two(base.journey.campaign)
	base.journey.campaign.night_hound_policy = NightHoundV1.VERSION
	base.journey.campaign.workshop = WorkshopV1.initial()
	base.journey.campaign.event_sortie_policy = EventSortieV1.VERSION
	base.journey.campaign.recon_policy = ReconActionV1.SOURCE_VERSION
	base.journey.campaign.barricade_policy = BarricadeV1.VERSION
	base.journey.campaign.billboard_policy = BillboardActionV1.VERSION
	base.journey.campaign.open_streets_policy = OpenStreetsV1.VERSION
	base.journey.campaign.economy = EconomyBuildV1.initial()
	base.journey.build = WorldgenState.initial_build(base.journey.seed, true, true)
	base.journey.build.powers = PowerState.initial_progression(SpecialPowers.M48_VERSION)
	BuildState.enable_m48(base.journey.build)
	return base


func _geometry(supply: MissionSupply) -> void:
	var street: StreetLayout = supply.layout
	var nav: FieldNavigation = FieldNavigation.new()
	nav.configure(street.blockers(), street.world_bounds)
	expect(street.bus_block.size == Vector2(108, 32), "locked bus dimensions")
	for road: Rect2 in street.roads:
		expect(minf(road.size.x, road.size.y) == 96.0, "locked road width")
	for row: Array in street.world_data.grounds.sidewalks:
		var walk: Rect2 = WorldLayout.rect(row)
		expect(minf(walk.size.x, walk.size.y) == 32.0, "locked sidewalk width")
	var bound_ids: Array[String] = []
	var container_groups: Dictionary = {}
	for entity: Dictionary in street.world_data.entities:
		var body: Rect2 = WorldLayout.rect(entity.rect)
		expect(street.world_bounds.encloses(body), "solid remains inside harbor: " + entity.id)
		for other: Dictionary in street.world_data.entities:
			if other.id != entity.id:
				expect(not body.intersects(WorldLayout.rect(other.rect)), "independent solid footprints: " + entity.id + "/" + other.id)
		if not String(entity.site_id).is_empty():
			expect(entity.site_id not in bound_ids, "site has one physical work point")
			bound_ids.append(entity.site_id)
			if String(entity.id).begins_with("container_"):
				var group: String = "west" if entity.id in ["container_a", "container_b"] else "east" if entity.id in ["container_c", "container_d"] else "quay"
				expect(not container_groups.has(group), "container group has at most one searchable point: " + group)
				container_groups[group] = entity.site_id
		expect(not IsoAtlas.info(entity.art).is_empty(), "registered closed exterior art: " + entity.id)
	expect(bound_ids.size() == supply.generated.sites.size(), "every signed site is represented, including vehicle/tree sources")
	for site: Dictionary in supply.generated.sites:
		var point: Vector2 = TaskActions.site_point(supply.generated, site)
		expect(nav.is_clear(point) and _reaches(nav, street.bus_door, point), "loot point reachable from bus: " + site.id)
	for point: Vector2 in street.arrivals + street.enemy_points:
		expect(nav.is_clear(point) and _reaches(nav, street.bus_door, point), "arrival and threat entrance reachable")
	for choke: Rect2 in HarborWarehouse.CHOKES:
		var from: Vector2 = Vector2(choke.position.x - 32, choke.get_center().y)
		var to: Vector2 = Vector2(choke.end.x + 32, choke.get_center().y)
		expect(nav._segment_is_clear(from, to) and _reaches(nav, from, to), "64-unit container bottleneck admits the actor footprint")
	for point: Vector2 in [Vector2(1904, 464), Vector2(2256, 1136)]:
		expect(nav.is_clear(point) and _reaches(nav, street.bus_door, point), "both piers have a legal return route")
	for point: Vector2 in [Vector2(1920, 224), Vector2(2208, 768), Vector2(2384, 1120)]:
		expect(not nav.is_clear(point), "water is solid to navigation")
	for offset: Vector2 in [Vector2(-48, -32), Vector2(48, -32), Vector2(-48, 16), Vector2(48, 16)]:
		expect(nav.is_clear(street.bus_door + offset) and _reaches(nav, street.bus_door, street.bus_door + offset), "boarding area accommodates the locked squad")
	var tiles: IsoTiles = IsoTiles.new()
	tiles.fill_from_layout(street)
	expect(tiles.cells[Vector2i(60, 7)] == "harbor_water" and tiles.cells[Vector2i(60, 14)] == "harbor_wood", "pier ground overrides the sea without widening it")
	tiles.free()
	var uncached: Dictionary = street.world_data
	uncached.entities[0].title = "local mutation"
	expect(HarborWarehouse.world_data(supply.generated).entities[0].title != "local mutation", "layout cache does not expose shared mutable map data")
	street.world_data = HarborWarehouse.world_data(supply.generated)


func _water(street: StreetLayout) -> void:
	var ground: HarborGround = HarborGround.new()
	ground.layout = street
	var still: Array[PackedVector2Array] = ground.water_ripples(0.0)
	var moved: Array[PackedVector2Array] = ground.water_ripples(4.0)
	expect(not still.is_empty() and not moved.is_empty() and still[0] != moved[0], "restrained water ripples drift over time")
	for ripple: PackedVector2Array in still + moved:
		for point: Vector2 in ripple:
			var map_point: Vector2 = IsoSpace.to_map(point)
			expect(WorldLayout.rect(street.world_data.grounds.harbor_water[0]).has_point(map_point), "ripple stays on the sea")
			for pier: Array in street.world_data.grounds.harbor_wood:
				expect(not WorldLayout.rect(pier).has_point(map_point), "ripple never crosses a wooden pier")
	ground.free()


func _reaches(nav: FieldNavigation, from: Vector2, to: Vector2) -> bool:
	var route: PackedVector2Array = nav.path_between(from, to)
	return not route.is_empty() and route[-1].distance_to(to) <= 14.0


func _exclusions(action: Dictionary) -> void:
	var early: Dictionary = action.duplicate(true)
	early.day = 2
	expect(not HarborWarehouse.should_apply(early), "day two keeps seaside town and its existing alternatives")
	for key: String in ["finale_policy", "investigation", "event_sortie", "rare_policy", "recon", "barricade", "billboard", "billboard_target", "sortie_risk"]:
		var special: Dictionary = action.duplicate(true)
		special[key] = {}
		expect(not HarborWarehouse.should_apply(special), "spatially signed special retains original map: " + key)
	var gear: Dictionary = action.duplicate(true)
	gear.erase("economy_source")
	expect(HarborWarehouse.should_apply(gear), "ordinary gear also uses the location, independent of hardware rewards")


func _selection(base: Dictionary, offers: Array[Dictionary], supply: MissionSupply) -> void:
	var menu: MissionSelect = MissionSelect.new()
	menu.review_enabled = true
	root.add_child(menu)
	menu.refresh_daily(base)
	var found: int = -1
	for index: int in range(menu.daily_offers.size()):
		if menu.daily_offers[index].id == supply.generated.id:
			found = index
	expect(found >= 0, "camp mission select includes the harbor offer")
	if found >= 0:
		var emitted: Array[MissionSupply] = []
		menu.selected.connect(func(value: MissionSupply) -> void: emitted.append(value))
		menu._choose(found)
		menu._confirm_departure()
		expect(emitted.size() == 1 and HarborWarehouse.is_layout(emitted[0].layout), "normal selection and confirmation emit the playable harbor supply")
		expect(menu._titles[found].text.contains(HarborWarehouse.TITLE) and menu._descriptions[found].text.contains("工具 ×2"), "camp card names the location and actual primary loot")
	expect(TransactionReceipt.same({"offers":offers}, {"offers":menu.daily_offers}), "menu preserves the original three signed offers")
	menu.queue_free()
	await process_frame


func _field(base: Dictionary, supply: MissionSupply) -> void:
	var world: Expedition = _new_field(base, supply)
	expect(world.setup_problem.is_empty() and world.sites.size() == supply.generated.sites.size(), "real expedition constructs every bound site")
	if not world.setup_problem.is_empty():
		world.get_viewport().queue_free()
		return
	world.bus_view.skip()
	expect(world.mission_title == HarborWarehouse.TITLE, "HUD and minimap receive the destination name")
	for prop: FieldProp in world._buildings:
		expect(prop._work.visible == prop.searchable, "only a real work point displays a loot label: " + prop.title)
		if not prop.searchable:
			expect(prop.loot_category.is_empty(), "decorative container has no warehouse badge")
	var main: Expedition.SearchSite = world.search_site(&"cash")
	var worker: FieldActor = world.survivors[0]
	world._assign_search(main, worker, world.navigation.path_between(worker.position, main.door))
	for tick: int in range(1800):
		worker.advance(1.0 / 30.0)
		world.elapsed += 1.0 / 30.0
		world._update_search(1.0 / 30.0)
		if main.progress >= 2.0:
			break
	expect(main.progress >= 2.0 and not main.searched and world.task_event.started, "reachable outdoor cargo work triggers the existing one-time reinforcement event")
	# Capture uses the same paused boundary as the real suspend/save flow.
	expect(SortieSnapshot.capture(world).is_empty(), "running simulation cannot be captured between work ticks")
	world.toggle_pause()
	var captured: Dictionary = SortieSnapshot.capture(world)
	expect(not captured.is_empty(), "paused partial work produces a resumable snapshot")
	var snapshot: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(captured))).payload
	var source: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(supply.generated))).payload
	var restored: Expedition = _new_field(base, DailyActions.supply(source))
	var geometry: Dictionary = restored.layout.world_data.duplicate(true)
	restored.layout.world_data.entities[0].door[0] += 16
	expect(SortieSnapshot.apply(restored, snapshot) == "WORLD_BUILD_DATA_VIEWPORT_MISMATCH", "snapshot rejects a changed harbor work point before restoring state")
	restored.layout.world_data = geometry
	var restore_issue: String = SortieSnapshot.apply(restored, snapshot)
	expect(restore_issue.is_empty(), "snapshot reapplies using the original source and the same harbor geometry: " + restore_issue)
	expect(restored.search_site(&"cash").door == main.door and is_equal_approx(restored.search_site(&"cash").progress, main.progress), "partial work and work-point location survive reconstruction")
	expect(TransactionReceipt.same(restored.search_assignments.snapshot(), world.search_assignments.snapshot()), "partial work retains its assigned member and phase")
	world.toggle_pause()
	var work_started: float = world.elapsed
	var remaining: float = main.seconds - main.progress
	var factor: float = worker.trait_search_factor * worker.persona_work_factor * float(BuildItems.frozen_factors(supply.generated.build).work)
	for tick: int in range(1800):
		world.elapsed += 1.0 / 30.0
		world._update_search(1.0 / 30.0)
		if main.searched or world.is_paused:
			break
	expect(main.searched and world._carried_tools() == 2, "real work completion carries the existing two tools")
	expect(world.elapsed - work_started >= remaining * factor * 1.5 - 0.04, "harbor work takes 1.5 times the existing character-adjusted duration")
	world.request_bus_gather()
	expect(world.phase == Expedition.Phase.ACTIVE and world.goal == world.layout.bus_door, "gather issues a real movement order before engine startup")
	for tick: int in range(1800):
		for actor: FieldActor in world.survivors:
			actor.advance(1.0 / 30.0, false, false)
		FieldContacts.move(world.survivors, world.survivors, world.navigation, 1.0 / 30.0, true)
		if world.boarding_status().arrived == world.survivors.size():
			break
	expect(world.boarding_status().arrived == world.survivors.size(), "real gather orders return all living members inside the boarding circle")
	world.elapsed = maxf(20.0, world.elapsed)
	world.request_extraction()
	expect(world.phase == Expedition.Phase.ENGINE, "existing bus engine action is enabled at the harbor stop")
	# A repeated gather must refresh individual routes even with the same group goal.
	world.survivors[0].command_path(world.navigation.path_between(world.survivors[0].position, main.door))
	world.request_bus_gather()
	expect(world.survivors[0].path[-1].distance_to(world.layout.bus_door) <= world.tuning.boarding_radius, "engine-stage gather replaces a stale individual route")
	world.phase = Expedition.Phase.BOARDING
	world.request_bus_gather()
	expect(world.boarding_status().ordered, "boarding retains the same complete-squad gather order")
	await _night_hint(world)
	var atmosphere: ExpeditionAtmosphere = world._feedback._atmosphere
	atmosphere.refresh(world, 1.0)
	expect(atmosphere._scenery_lights.size() == 5 and atmosphere._lights.size() == 7, "night uses five dock work lights plus the existing bus headlights")
	expect(atmosphere._scenery_lights.any(func(light: PointLight2D) -> bool: return light.color == Color("d8e5df")), "dock includes restrained cool-white work lighting")
	var facts: Dictionary = WorldSites.facts(world)
	expect(WorldSites.problem(supply.generated.sites, facts, true).is_empty() and EconomyActions.carried(supply.generated, facts) == 2, "original source facts settle exactly two main tools, with no invented rewards")
	world.get_viewport().queue_free()
	restored.get_viewport().queue_free()
	await process_frame


func _night_hint(world: Expedition) -> void:
	world.elapsed = world.tuning.daylight_seconds + 5.0
	world.threat.update(world.elapsed, world.tuning.daylight_seconds, world.tuning.spawn_seconds)
	world._show_notice(HarborWarehouse.ROUTE_HINT)
	world._update_ui()
	await process_frame
	await process_frame
	var hud: C1ExpeditionHud = world._hud.view
	expect(hud._hint.max_lines_visible == 2 and hud._hint_panel.size.y <= 56.0, "night route and evacuation notice occupies at most two compact lines")
	expect(hud._hint.tooltip_text == HarborWarehouse.ROUTE_HINT, "full route notice remains available in its tooltip")
	var style: StyleBoxFlat = hud._hint_panel.get_theme_stylebox("panel") as StyleBoxFlat
	expect(style.bg_color.a <= 0.55, "night notice background keeps the field visible")
	var strip: Control = hud.get_node("CommandStrip") as Control
	expect(hud._hint_panel.get_global_rect().end.y <= strip.get_global_rect().position.y, "compact notice sits immediately above the command lane")


func _new_field(base: Dictionary, supply: MissionSupply) -> Expedition:
	var world: Expedition = Expedition.new()
	world.supply = supply
	world.sortie_id = base.profile_id + ":2"
	world.day = 3
	world.crew_snapshot.assign(base.crew)
	world.loadout_snapshot = WeaponInventory.snapshot(base)
	world.field_departure = base
	world.growth_binding = {"run_id":base.profile_id, "root_id":base.journey.root_id, "transaction_id":world.sortie_id,
		"base_hash":SurvivalContracts.fingerprint(base), "rules_hash":SurvivalContracts.fingerprint(FrozenSettlement.pool_rules(base, supply))}
	world.ui_theme = preload("res://assets/ui/c1/hud_theme.tres")
	# Independent canvases keep two reconstructed worlds' light pools separate.
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.world_2d = World2D.new()
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	viewport.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	return world
