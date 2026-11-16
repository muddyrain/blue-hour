extends "res://tests/harbor_warehouse.gd"
## Directed valid eight-person camps, real clock/AI/navigation, boarding and settlement.
## These fixtures are not an earned campaign or an account of human play.

const SquadFixture: Script = preload("res://tests/squad_recruit.gd")
const STEP: float = 1.0 / 30.0


func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	for day: int in [8, 10]:
		await _long_sortie(day)
	print("BH_SQUAD_LONG_RUN " + JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)


func _fixture(day: int) -> Dictionary:
	var base: Dictionary = SquadFixture.view_camp(8)
	base.journey.campaign = _harbor_camp().journey.campaign.duplicate(true)
	base.journey.build = WorldgenState.initial_build(base.journey.seed, true, true)
	base.journey.build.powers = PowerState.initial_progression(SpecialPowers.M48_VERSION)
	BuildState.enable_m48(base.journey.build)
	var opening: Dictionary = OpeningBuild.source("scavenge", base.profile_id, base.journey.root_id,
		base.journey.seed, {"version":OpeningBuild.POLICY_VERSION,"eligible":[]})
	base.journey.build.opening = opening
	base.journey.build.owned.append(opening.item_id)
	base.journey.build.slots[0] = opening.item_id
	base.journey.build.catalog = {"version":CatalogProgress.VERSION,"unlock":""}
	while base.day < day:
		var next: Dictionary = SquadFixture.returned(base)
		base = EnemyState.snapshot(next, next.journey, next.recruits, next.training)
	return base


func _long_sortie(day: int) -> void:
	var base: Dictionary = _fixture(day)
	expect(TransactionReceipt.camp_problem(base).is_empty(), "directed eight-person camp validates on day %d: %s" % [day, TransactionReceipt.camp_problem(base)])
	var offers: Array[Dictionary] = DailyActions.offers(base)
	var signature: String = RecordEncoding.fingerprint({"offers":offers})
	var supply: MissionSupply = DailyActions.supply(offers[0])
	expect(CapeStation.is_layout(supply.layout) and DailyActions.matches(base, supply.generated), "normal signed supply uses formal station on day %d" % day)
	expect(CampaignPressureV1.blockade_night(supply.generated) == (day == 10), "only day ten is blockade in the two long-run fixtures")
	var world: Expedition = Expedition.new()
	world.supply = supply
	world.battle_survival = true
	world.sortie_id = "%s:%d" % [base.profile_id, int(base.settled_sorties) + 1]
	world.day = day
	world.initial_food = base.food
	world.crew_snapshot.assign(base.crew)
	world.loadout_snapshot = WeaponInventory.snapshot(base)
	world.field_departure = base
	var rules: Dictionary = FrozenSettlement.pool_rules(base, supply)
	world.growth_binding = {"run_id":base.profile_id,"root_id":base.journey.root_id,"transaction_id":world.sortie_id,
		"base_hash":SurvivalContracts.fingerprint(base),"rules_hash":SurvivalContracts.fingerprint(rules)}
	world.ui_theme = preload("res://assets/ui/c1/hud_theme.tres")
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1024,576)
	viewport.world_2d = World2D.new()
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	for actor: FieldActor in world.survivors:
		actor.permanent_death_enabled = true
	expect(world.setup_problem.is_empty() and world.survivors.size() == 8, "eight real equipped actors build without a setup error")
	expect(BusJourney.route_problem(world.bus_view.route).is_empty()
		and WorldLayout.point(world.bus_view.route.passenger_door) == WorldLayout.point(world.layout.world_data.bus.passenger_door), "formal journey has the authored passenger door")
	var reports: Array[Dictionary] = []
	var cues: Array[StringName] = []
	world.finished.connect(func(report: Dictionary) -> void: reports.append(report))
	world.bus_view.audio_cue_requested.connect(func(cue: StringName) -> void: cues.append(cue))
	await _advance(world, func() -> bool: return not world.bus_view.running(), 900)
	expect(world.survivors.all(func(actor: FieldActor) -> bool: return actor.visible), "all eight disembark through the formal arrival")
	var site: Expedition.SearchSite = world.search_site(&"food")
	expect(site != null, "formal food site exists")
	if site == null:
		viewport.free()
		return
	print("BH_SQUAD_LONG_ROUTE " + JSON.stringify({"day":day,"level":world.layout.display_name,
		"food":str(site.door),"bus":str(world.layout.bus_door),"passenger_door":world.bus_view.route.passenger_door}))
	var starts: Dictionary = {}
	for actor: FieldActor in world.survivors:
		starts[actor.member_id] = actor.position
	world.command_move(site.door)
	world.request_search(site.id)
	await _advance(world, func() -> bool: return site.searched or world.phase == Expedition.Phase.FINISHED, 3000)
	expect(site.searched and world.food_loot > 0, "real approach and work integrator complete food search")
	var moved: int = 0
	for actor: FieldActor in world.survivors:
		if actor.position.distance_to(starts[actor.member_id]) > 80.0: moved += 1
	expect(moved == 8, "all eight traverse the level using real formation/navigation")
	await _capture(viewport, world, "day-eight" if day == 8 else "day-ten")
	# Continue through night with the real director, damage and contact solver.
	world.request_bus_gather()
	await _advance(world, func() -> bool: return world.elapsed >= 122.0 or world.phase == Expedition.Phase.FINISHED, 4200)
	expect(world.elapsed >= 122.0 and world.phase == Expedition.Phase.ACTIVE and world.living_count() > 0,
		"night does not auto-depart; living members remain controllable after 105 seconds")
	expect(world.tuning.daylight_seconds == 105.0 and world.threat.stage >= ThreatDirector.Stage.NIGHT,
		"real clock crosses the unchanged daylight boundary")
	if day == 10:
		var upgraded: bool = false
		for key: String in world.combat.spawns:
			var record: Dictionary = world.combat.spawns[key]
			if record.stage >= ThreatDirector.Stage.NIGHT and record.kind != CombatEnemyRules.pick(world.sortie_id, int(key), int(record.stage)):
				upgraded = true
		expect(upgraded, "real post-night director records at least one blockade upgrade")
	await _capture(viewport, world, "night-day-%d" % day)
	world.toggle_pause()
	var snapshot: Dictionary = SortieSnapshot.capture(world)
	var receipt: Dictionary = TransactionReceipt.initial(base, world.sortie_id, rules, TransactionReceipt.registration(base, base.journey.root_id))
	var snapshot_issue: String = SortieSnapshot.problem(snapshot, receipt)
	expect(snapshot_issue.is_empty(), "eight-person night pause validates against the runtime reinforcement clock: " + snapshot_issue)
	if snapshot_issue.is_empty():
		var forged: Dictionary = snapshot.duplicate(true)
		forged.threat.interval += 1.0
		expect(SortieSnapshot.problem(forged, receipt) == "WORLD_THREAT_CLOCK", "altered reinforcement interval remains strictly rejected")
	world.toggle_pause()
	if day == 10:
		# Directed casualty enters the real damage path; it is not natural attrition.
		var fallen: FieldActor = world.search_member(3)
		fallen.damage_gate = func(_actor: FieldActor, _proposal: Dictionary) -> int: return OK
		fallen.take_damage(fallen.health)
		expect(fallen.health == 0.0 and fallen.activity == FieldActor.Activity.DOWN, "directed field death removes a living boarding requirement")
	world.request_bus_action()
	expect(world.phase == Expedition.Phase.ENGINE, "B starts engine after night")
	await _advance(world, func() -> bool: return world.phase == Expedition.Phase.BOARDING, 600)
	world.request_bus_gather()
	await _advance(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED, 1800)
	expect(world.phase == Expedition.Phase.FINISHED and reports.size() == 1 and reports[0].evacuated,
		"all surviving members gather and produce exactly one real evacuation report")
	await _capture(viewport, world, "boarding-day-%d" % day)
	if not reports.is_empty():
		var report: Dictionary = reports[0]
		expect(report.member_results.size() == 8 and world.bus_view.final_boarding.x == world.living_count()
			and world.bus_view.final_boarding.y == world.living_count(), "result retains all eight identities and boards every living member")
		var computed: Dictionary = FrozenSettlement.compute({"before":base,"token":world.growth_binding,
			"participants":SurvivalContracts.participants(base.crew, WeaponInventory.snapshot(base), true, true),
			"rules":rules,"report":report,"carried":{"loot":world.loot,"food":world.food_loot,"weapons":world.weapon_loot.duplicate(true)},
			"prior_deaths":base.journey.deaths,"completion":"COMPLETED","searching_member_ids":[]})
		expect(computed.error.is_empty(), "formal FrozenSettlement accepts night return, casualties, growth and meals: " + String(computed.get("reason",computed.error)))
		if computed.error.is_empty() and day == 10:
			var after: Dictionary = computed.packet.envelope.result.camp
			expect(SurvivorRoster.member(after.crew, 3).health == 0.0 and after.journey.deaths.any(func(row: Dictionary) -> bool: return row.member_id == 3 and row.cause == "BATTLE"),
				"formal settlement preserves the named field death and its equipment policy")
		print("BH_SQUAD_LONG_RESULT " + JSON.stringify({"day":day,"elapsed":world.elapsed,"living":world.living_count(),
			"members":report.member_results,"boarding":str(world.bus_view.final_boarding),"settlement_error":computed.error,
			"spawns":world._spawn_count,"joins":report.field_joins.size()}))
		world.bus_view.departure()
		world.bus_view.departure()
		await _advance(world, func() -> bool: return not world.bus_view.running(), 1500)
		expect(world.bus_view.stage == "done" and cues == [&"bus_board", &"bus_depart"], "complete eight-person bus presentation emits each stage once")
	expect(signature == RecordEncoding.fingerprint({"offers":DailyActions.offers(base)}), "long run leaves signed offers intact")
	viewport.free()
	await process_frame


func _advance(world: Expedition, done: Callable, cap: int) -> void:
	for tick: int in range(cap):
		if done.call() or world.is_paused: return
		world.step(STEP)
		if tick % 30 == 0: await process_frame


func _capture(viewport: SubViewport, world: Expedition, label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	world._update_ui()
	for frame: int in range(3): await process_frame
	RenderingServer.force_draw()
	var image: Image = viewport.get_texture().get_image()
	var path: String = "res://.local/squad-long-run/" + label + ".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	expect(image != null and not image.is_empty() and image.save_png(path) == OK, "native renderer captures " + label)
	print("BH_SQUAD_LONG_RENDER " + path)
