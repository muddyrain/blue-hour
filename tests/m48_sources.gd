extends SceneTree
## Directed source fixtures. These synthetic camp days are never claimed as played returns.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://.local/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		quit(2)
		return
	var app: Node = load("res://src/app/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app._new_game("scavenge", {"version":CatalogProgress.VERSION, "unlock":""},
		{"version":OpeningBuild.POLICY_VERSION, "eligible":[]})
	var registration: Dictionary = app.progress_session.inspect()
	var registered: bool = not app._progress_blocked and registration.get("error") == OK \
		and registration.get("state") == "CAMP" and registration.get("receipt", {}).get("phase") == "CAMP_REGISTERED"
	_check(registered, "source fixture starts from an actually acknowledged isolated registration")
	var fresh: Dictionary = app.camp_snapshot() if registered else {}
	_check(EconomyActions.camp_enabled(fresh), "ordinary M48 creation selects the explicit source policy")
	if EconomyActions.camp_enabled(fresh):
		for day: int in [3, 4, 6, 9]:
			var camp: Dictionary = _at_day(fresh, day)
			var offers: Array[Dictionary] = DailyActions.offers(camp)
			_check(offers.size() == 3, "three original signed slots remain available on day %d" % day)
			var hardware: Dictionary = {}
			for action: Dictionary in offers:
				_check(EconomyActions.enabled(action), "M48 source marker freezes every version-nine action")
				if action.slot == 1:
					_check(action.has("investigation"), "fixed investigation slot keeps its source")
				if EconomyActions.hardware(action):
					hardware = action
			_check((not hardware.is_empty()) == (day % 3 == 0), "hardware occupies only the scheduled random opportunity")
			if not hardware.is_empty():
				_hardware_cases(camp, hardware)
		_facility_cases(fresh)
		_normal_tool_case(fresh)
		_billboard_case(fresh)
		_finale_priority_case(fresh)
	app.audio.shutdown()
	app.queue_free()
	await process_frame
	print(JSON.stringify({"checks":checks, "failures":failures, "scope":"directed-source-fixtures"}))
	quit(0 if failures == 0 else 1)


func _at_day(fresh: Dictionary, day: int) -> Dictionary:
	var camp: Dictionary = fresh.duplicate(true)
	camp.day = day
	camp.settled_sorties = day - 2
	return camp


func _hardware_cases(camp: Dictionary, action: Dictionary) -> void:
	_check(action.cash > 0 and action.slot == 2 and action.weapons == 0 and action.build.drops.is_empty()
		and action.powers.sample.is_empty(), "hardware replaces the random weapon and both equipment samples")
	_check(DailyActions.problem(action).is_empty() and DailyActions.matches(camp, action),
		"the full action authenticates independently and against the exact camp")
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(action))).payload
	_check(DailyActions.problem(decoded).is_empty() and TransactionReceipt.same(action, decoded),
		"source and changed fields survive exact independent decoding")
	var camp_projection: Dictionary = JSON.parse_string(JSON.stringify(action, "", true, true))
	_check(ExplorationActions.problem(camp_projection, true).is_empty(),
		"M48 specialty pool accepts the exact ordinary JSON camp projection with numeric version 5.0")
	var original: Dictionary = EconomyActions.origin(action)
	_check(not original.has("economy_source") and ExplorationActions.problem(original).is_empty(),
		"the pre-M48 source retains its complete strict proof")
	var wrong_version: Dictionary = original.duplicate(true)
	wrong_version.powers.version = SpecialPowers.M47_VERSION
	_check(ExplorationActions.problem(wrong_version) == "EXPLORATION_SPECIALTY_POOL",
		"M48 item pool cannot be paired with the historical M47 power version")
	var facts: Dictionary = {}
	for site: Dictionary in action.sites:
		facts[site.id] = {"searched":false, "progress":0.0}
		if site.id == "cash":
			_check(site.seconds == 12.0 and site.weapon == false and site.amount == 0
				and site.work_mode == "outdoor", "main cabinet uses real exposed twelve-second work")
	var tools: Array[Dictionary] = EconomyActions.tool_sources(action)
	_check(tools.size() in [1, 2] and tools[0] == {"site_id":"cash", "count":2}, "two main units and at most one optional unit")
	var optional_count: int = 0
	if tools.size() == 2:
		facts[tools[1].site_id].searched = true
		optional_count = 1
		_check(tools[1].count == 1 and tools[1].site_id != "cash", "the optional route has one distinct source")
	_check(EconomyActions.carried(action, facts) == optional_count, "unfinished main work never produces its tools")
	var report: Dictionary = {"site_facts":facts, "evacuated":true, "weapons":[]}
	_check(TaskActions.outcome(action, report).status == "EARLY", "optional-only return keeps the unfinished task outcome")
	facts.cash = {"searched":true, "progress":12.0}
	_check(EconomyActions.carried(action, facts) == 2 + optional_count
		and TaskActions.outcome(action, report).status == "COMPLETED", "main completion drives the hardware objective without a phantom weapon")
	var repeated: Dictionary = EconomyActions.freeze(original, true)
	_check(TransactionReceipt.same(action, repeated), "the same seed and source recreate identical units and action")
	for mutation: String in ["grade", "tool", "reward", "source", "duplicate"]:
		var forged: Dictionary = action.duplicate(true)
		match mutation:
			"grade": forged.economy_source.loot_grade = 1 if EconomyActions.grade(action) != 1 else 3
			"tool": forged.economy_source.tools[0].count = 1
			"reward": forged.cash += 1
			"source": forged.economy_source.source_fields.sites[0].seconds += 1.0
			"duplicate": forged.economy_source.tools.append(forged.economy_source.tools[0].duplicate())
		_check(not DailyActions.problem(forged).is_empty() and not DailyActions.matches(camp, forged),
			"source proof rejects altered " + mutation)
	_check(DailyActions.supply(action).description.contains("工具 ×2")
		and LevelSummary.mission_card_text(action).contains("随机行动机会"), "normal card explains tools and the replaced opportunity")


func _normal_tool_case(fresh: Dictionary) -> void:
	var camp: Dictionary = _at_day(fresh, 5)
	var context: Dictionary = DailyActions.offers(camp)[0]
	var task: Dictionary = TaskActions._make(camp.journey.seed, int(camp.day), 2, "airdrop", "industrial", "medium", 0)
	var source: Dictionary = ExplorationActions.source_from_task(task, context)
	var normal: Dictionary = InvestigationActions._offer(source, "airdrop", 0, true, false)
	normal = BuildActions.with_gear_drops(normal)
	normal = ContentWaveV1.freeze_action(normal)
	normal.night_hound_policy = NightHoundV1.VERSION
	var action: Dictionary = EconomyActions.freeze(normal)
	_check(DailyActions.problem(action).is_empty() and not EconomyActions.hardware(action)
		and EconomyActions.tool_sources(action).size() <= 1, "ordinary industrial source has its own bounded tool policy: " + DailyActions.problem(action))
	_check(EconomyActions.tool_sources(action).size() == 1 and CampFacilities.selected(camp).is_empty(),
		"a legal ordinary detour offers a tool before any workshop is built")
	_check(action.sites == normal.sites and action.cash == normal.cash and action.food == normal.food,
		"ordinary tool preserves the original site's actual money and food")


func _billboard_case(fresh: Dictionary) -> void:
	var camp: Dictionary = _at_day(fresh, 6)
	# M44 chain fixture certifies a real supermarket on day six. This is an explicit
	# synthetic selection fixture, not a claimed historical camp or earned intel.
	var fixture_seed: String = "m44-chain-00".md5_text()
	camp.journey.seed = fixture_seed
	camp.journey.build.persona = SurvivorPersona.generate(fixture_seed)
	camp.journey.build.opening.seed = fixture_seed
	print("M48_SOURCE_FIXTURE " + JSON.stringify({"case":"billboard-priority", "seed_argument":"m44-chain-00", "seed":fixture_seed, "day":6}))
	var strategy: Dictionary = BillboardActionV1.target(camp.journey.seed, int(camp.day))
	_check(not strategy.is_empty(), "known M44 chain fixture has a certified day-six supermarket target")
	if strategy.is_empty():
		return
	var source: String = BillboardActionV1.action_id(camp.journey.seed, 5, 2)
	camp.journey.campaign.billboard_intel = {"destination":BillboardActionV1.DESTINATION,
		"source_day":5, "day":6, "slot":2, "action_id":source, "billboard_id":BillboardActionV1.board_id(source),
		"transaction_id":"%s:4" % camp.profile_id, "strategy":strategy}
	var offers: Array[Dictionary] = DailyActions.offers(camp)
	_check(offers.size() == 3 and offers.any(func(action: Dictionary) -> bool:
		return action.slot == 2 and action.has("billboard_target") and not EconomyActions.hardware(action)),
		"confirmed billboard opportunity takes precedence over scheduled hardware")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("M48_SOURCE_FAIL " + message)


func _facility_fixture(fresh: Dictionary, tier: int = 2) -> Dictionary:
	# Pure directed inputs, deliberately not saved or used as a legal played camp.
	var before: Dictionary = fresh.duplicate(true)
	before.day = 5
	before.settled_sorties = 3
	var economy: Dictionary = EconomyBuildV1.initial()
	for id: String in EconomyBuildV1.FACILITIES:
		economy.facilities[id] = {"level":tier, "built_sortie":1, "upgraded_sortie":2 if tier == 2 else 0}
		if tier > 0: economy.edits.append({"op":"build", "target":id, "sortie":1})
		if tier == 2: economy.edits.append({"op":"upgrade_facility", "target":id, "sortie":2})
	before.journey.campaign.economy = economy
	return before


func _facility_settle(before: Dictionary, after: Dictionary, evacuated: bool = true) -> Dictionary:
	var report: Dictionary = {"sortie_id":"%s:%d" % [before.profile_id, int(before.settled_sorties) + 1],
		"evacuated":evacuated, "site_facts":{}}
	EconomyBuildV1.settled(before, after, report, {"sites":[]})
	return after


func _fixture_damaged(before: Dictionary, suffix: String, ordinal: int) -> Dictionary:
	return WeaponModifiers.baseline({"instance_id":"%s:directed:%s" % [before.profile_id, suffix],
		"weapon_id":"carbine", "condition":"damaged", "origin":"directed-auto-queue",
		"acquired_sortie":"%s:%d" % [before.profile_id, ordinal]})


func _facility_cases(fresh: Dictionary) -> void:
	for tier: int in [1, 2]:
		var before: Dictionary = _facility_fixture(fresh, tier)
		var first: Dictionary = _fixture_damaged(before, "earliest", 1)
		var tie_z: Dictionary = _fixture_damaged(before, "z", 2)
		var tie_a: Dictionary = _fixture_damaged(before, "a", 2)
		before.weapons.append_array([tie_z, first, tie_a])
		var after: Dictionary = before.duplicate(true)
		var newest: Dictionary = _fixture_damaged(before, "new-this-return", 4)
		after.weapons.append(newest)
		var health_before: Array = after.crew.map(func(member: Dictionary) -> float: return float(member.health))
		after = _facility_settle(before, after)
		var row: Dictionary = EconomyBuildV1.state(after).returns.back()
		var expected: Array = [first.instance_id] if tier == 1 else [first.instance_id, tie_a.instance_id]
		_check(row.repairs == expected, "T4 directed auto queue uses acquired sortie then exact identity at tier %d" % tier)
		_check(WeaponInventory.find(after, newest.instance_id).condition == "damaged"
			and WeaponInventory.find(after, tie_z.instance_id).condition == "damaged",
			"T4 new loot and candidates beyond the exact repair limit stay damaged")
		_check(WeaponInventory.for_member(after, 1).condition == "ready" and WeaponInventory.for_member(after, 2).condition == "ready",
			"T4 equipped ready instances retain their existing state")
		_check(row.food == tier + 1 and row.planning.points == tier,
			"T4 frozen facility levels determine supply and planning amounts")
		_check(row.planning.member_id == 1 and row.planning_candidates[0].member_id == 1,
			"T4 equal trait level and progress break ties by stable member identity")
		_check(after.crew.map(func(member: Dictionary) -> float: return float(member.health)) == health_before,
			"T4 planning never changes final injury or hunger health")
		for member: Dictionary in after.crew:
			var old_growth: Dictionary = SurvivorRoster.member(before.crew, int(member.id)).growth.duplicate(true)
			var new_growth: Dictionary = member.growth.duplicate(true)
			old_growth.erase("trait")
			new_growth.erase("trait")
			_check(TransactionReceipt.same(old_growth, new_growth), "T4 planning does not add ordinary experience")
		var replay: Dictionary = before.duplicate(true)
		replay.weapons.append(newest.duplicate(true))
		replay = _facility_settle(before, replay)
		_check(TransactionReceipt.same(after, replay), "T4 recomputing the same departure/report produces the same whole automatic result")
		var failed: Dictionary = before.duplicate(true)
		failed = _facility_settle(before, failed, false)
		_check(EconomyBuildV1.state(failed).returns.is_empty() and failed.weapons == before.weapons
			and failed.crew == before.crew, "T4 failed evacuation has no automatic facility award")
	var before: Dictionary = _facility_fixture(fresh)
	var after: Dictionary = before.duplicate(true)
	SurvivorRoster.member(after.crew, 1).growth.trait.merge({"level":3, "progress":5}, true)
	SurvivorRoster.member(after.crew, 2).growth.trait.merge({"level":3, "progress":3}, true)
	after = _facility_settle(before, after)
	_check(EconomyBuildV1.state(after).returns.back().planning.member_id == 2,
		"T4 same-level planning chooses lower progress before stable identity")
	after = before.duplicate(true)
	SurvivorRoster.member(after.crew, 1).growth.trait.merge({"level":4, "progress":6}, true)
	SurvivorRoster.member(after.crew, 2).growth.trait.merge({"level":3, "progress":5}, true)
	after = _facility_settle(before, after)
	_check(EconomyBuildV1.state(after).returns.back().planning.member_id == 2,
		"T4 lower trait level precedes the absolute progress comparison")
	after = before.duplicate(true)
	SurvivorRoster.member(after.crew, 1).health = 0.0
	after = _facility_settle(before, after)
	_check(EconomyBuildV1.state(after).returns.back().planning.member_id == 2,
		"T4 final post-hunger death is excluded from planning")
	after = before.duplicate(true)
	for member: Dictionary in after.crew: member.growth.trait.merge({"level":5, "progress":10}, true)
	after = _facility_settle(before, after)
	_check(EconomyBuildV1.state(after).returns.back().planning.is_empty()
		and EconomyBuildV1.state(after).returns.back().planning_candidates.is_empty(),
		"T4 all maximum-level members produce a recorded no-award result")

	after = before.duplicate(true)
	for member: Dictionary in after.crew: member.growth.trait.merge({"level":5, "progress":10}, true)
	var guest: Dictionary = after.crew[0].duplicate(true)
	guest.id = 3
	guest.definition_id = "crew_3"
	guest.growth.trait = {"id":TraitRules.IDS[2], "level":1, "progress":0}
	after.crew.append(guest)
	var registered_after: Dictionary = after.duplicate(true)
	registered_after.recruits.append({"member_id":3, "field_status":"RETURNED"})
	after = _facility_settle(before, after)
	registered_after = _facility_settle(before, registered_after)
	_check(EconomyBuildV1.state(after).returns.back().planning.is_empty(),
		"T4 unregistered final crew entry cannot receive planning")
	_check(EconomyBuildV1.state(registered_after).returns.back().planning.member_id == 3,
		"T4 newly formally registered survivor can receive this return's planning after final membership")
	var recent_build: Dictionary = _facility_fixture(fresh, 0)
	recent_build.journey.campaign.economy.facilities.supply = {"level":1, "built_sortie":3, "upgraded_sortie":0}
	recent_build.journey.campaign.economy.edits = [{"op":"build", "target":"supply", "sortie":3}]
	_check(CampFacilities.offered_food(recent_build, 4, true) == 0 and CampFacilities.offered_food(recent_build, 5, true) == 2,
		"T4 newly constructed supply never repays the already confirmed return")
	recent_build.journey.campaign.economy.facilities.supply = {"level":2, "built_sortie":1, "upgraded_sortie":3}
	recent_build.journey.campaign.economy.edits = [{"op":"build", "target":"supply", "sortie":1}, {"op":"upgrade_facility", "target":"supply", "sortie":3}]
	_check(CampFacilities.offered_food(recent_build, 4, true) == 2 and CampFacilities.offered_food(recent_build, 5, true) == 3
		and CampFacilities.offered_food(recent_build, 5, false) == 0,
		"T4 upgrade preserves the old confirmed amount and only improves the next successful return")


func _finale_priority_case(fresh: Dictionary) -> void:
	var camp: Dictionary = _at_day(fresh, 6)
	camp.journey.campaign.clues = []
	for index: int in range(CampaignRules.CLUE_IDS.size()):
		camp.journey.campaign.clues.append({"id":CampaignRules.CLUE_IDS[index],
			"transaction_id":"%s:%d" % [camp.profile_id, index + 1],
			"action_id":("daily-v4:%s:%d:1" % [camp.journey.seed, index + 2]).sha256_text(), "site_id":"cash"})
	var offers: Array[Dictionary] = DailyActions.offers(camp)
	var finales: Array = offers.filter(func(action: Dictionary) -> bool: return PumpStationAction.enabled(action))
	_check(offers.size() == 3 and finales.size() == 1 and finales[0].slot != 2,
		"T2 scheduled hardware never replaces the fixed pump finale slot")
	_check(offers.any(func(action: Dictionary) -> bool: return action.slot == 2 and EconomyActions.hardware(action)),
		"T2 final challenge and the scheduled random hardware opportunity coexist")
