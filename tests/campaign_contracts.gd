extends SceneTree
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value: failures+=1;printerr("CAMPAIGN_CONTRACT_FAIL "+label)
func run() -> void:
	assert("/.local/" in OS.get_user_data_dir().replace("\\","/"))
	var app: Node=load("res://src/app/main.tscn").instantiate();root.add_child(app)
	await process_frame
	app._new_game("scavenge", {"version":CatalogProgress.VERSION, "unlock":""}, {"version":OpeningBuild.POLICY_VERSION, "eligible":[]})
	var base: Dictionary=app.camp_snapshot()
	check(TransactionReceipt.camp_problem(base).is_empty(),"normal new short camp strict")
	check(CampaignRules.pump_station_enabled(base.journey.campaign), "ordinary new entry opts into the explicit pump finale policy")
	var daily: Array[Dictionary] = DailyActions.offers(base)
	check(CampaignRules.is_mission(base.journey.campaign) and daily.size() == 3,
		"ordinary new entry issues three mission-mode cards")
	if daily.size() == 3:
		var clue: Dictionary = daily[2]
		var optional: Dictionary = daily[1]
		var gear: bool = optional.type == "airdrop" and optional.weapons == 1 and TaskActions.outdoor_site(optional, &"cash")
		var rescue: bool = (optional.type == "rescue" and optional.weapons == 0
			and int(optional.recruit) in RescuePoolState.available(base)
			and optional.exploration.level.routes.has_all(["bus>rescue", "rescue>bus"]))
		check(daily[0].type == "supply" and (gear or rescue) and DailyActions.matches(base, optional)
			and clue.get("investigation", {}).get("clue_id") == "dispatch_log" and clue.weapons == 0,
			"normal first day offers supplies, a legal gear or rescue choice, and an indoor clue")
		var old_mode: Dictionary = base.duplicate(true)
		old_mode.journey.campaign = CampaignRules.initial(base.profile_id)
		check(not DailyActions.matches(old_mode, clue), "historical short mode cannot accept an investigation offer")
		old_mode.journey.campaign = CampaignRules.initial_investigation(base.profile_id)
		var old_clue: Dictionary = DailyActions.offers(old_mode)[1]
		check(not old_clue.has("mission_policy") and old_clue.weapons == 1 and DailyActions.matches(old_mode, old_clue)
			and not DailyActions.matches(old_mode, clue) and not DailyActions.matches(base, old_clue),
			"M18 and M19 regenerate and authenticate their own investigation rewards only")
		var altered: Dictionary = clue.duplicate(true)
		altered.investigation.clue_id = "checkpoint_pass"
		check(not DailyActions.matches(base, altered), "offer with the next clue cannot authorize departure early")
		altered = clue.duplicate(true)
		altered.investigation.site_id = "food"
		check(not DailyActions.problem(altered).is_empty() and not DailyActions.matches(base, altered),
			"wrong site rejects at both canonical and camp-bound checks")
		altered = clue.duplicate(true)
		altered.erase("investigation")
		check(not DailyActions.problem(altered).is_empty() and not DailyActions.matches(base, altered),
			"original task with its required investigation identity removed is not today's offer")
		altered = clue.duplicate(true)
		altered.investigation.version = CampaignRules.INVESTIGATION_VERSION
		check(not DailyActions.problem(altered).is_empty(), "old investigation marker cannot authenticate new rewards")
		var projected: Dictionary = JSON.parse_string(JSON.stringify(clue, "", true, true))
		check(ExplorationActions.problem(projected, true).is_empty(), "plain camp JSON can retain the canonical ability source")
		if RecordEncoding.fingerprint(projected) != RecordEncoding.fingerprint(clue):
			check(not DailyActions.problem(projected).is_empty() and not DailyActions.matches(base, projected),
				"warming the camp projection cannot authorize the rounded action in a receipt")
		projected.exploration.metrics.routes.cash.length += 1.0
		check(not ExplorationActions.problem(projected, true).is_empty(), "camp projection rejects a different route")
	for action:Dictionary in daily:
		var supply:MissionSupply=DailyActions.supply(action)
		var rules:Dictionary=FrozenSettlement.pool_rules(base,supply)
		var issue:String=FrozenSettlement._rules_problem(rules)
		print("CAMPAIGN_POLICY ",issue," version ",rules.data_version," mission ",DailyActions.mission_problem(rules.mission))
		check(issue.is_empty(),"new rules authenticate "+issue)
		var receipt:Dictionary=TransactionReceipt.initial(base,base.profile_id+":1",rules,TransactionReceipt.registration(base,base.journey.root_id))
		check(TransactionReceipt.problem(receipt).is_empty(),"new receipt strict "+TransactionReceipt.problem(receipt))
		var decoded:Dictionary=RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(receipt)))
		print("CAMPAIGN_READBACK ",FrozenSettlement._rules_problem(decoded.payload.rules)," action ",DailyActions.problem(decoded.payload.rules.mission.generated))
		check(TransactionReceipt.problem(decoded.payload).is_empty(),"exact new receipt roundtrip "+TransactionReceipt.problem(decoded.payload))
	check(not DailyActions.matches(base,WeaponActions.offers(base)[0]),"short mode rejects old task policy before departure")
	# Pure generator fixtures below do not count as a played or settled journey.
	for size:String in NeighborhoodLayout.SIZES:
		for topology:String in NeighborhoodLayout.TOPOLOGIES:
			var old:Dictionary=WeaponActions._upgrade(TaskActions._make("m8-arena-grid".md5_text(),6,0,"supply",topology,size,0))
			var action:Dictionary=CampaignActions._upgrade(old,base.profile_id,4)
			check(CampaignActions.problem(action).is_empty(),"all size/topology finale descriptors have legal interior spawn: "+size+topology)
	for key:String in ["settled_sorties","last_day"]:
		var bad:Dictionary=base.duplicate(true);bad.erase(key)
		check(not TransactionReceipt.camp_problem(bad).is_empty(),"short camp rejects missing "+key+" without attribute errors")
	_rare_sorties(base)
	_opening_build(base)
	_catalog_terminal(base)
	_screamer_policy(base)
	app.audio.shutdown();app.queue_free();await process_frame
	print("CAMPAIGN_CONTRACTS checks=",checks," failures=",failures)
	quit(1 if failures else 0)


func _catalog_terminal(base: Dictionary) -> void:
	# Test the terminal classification in isolation. Journal acknowledgement is tested separately.
	var camp: Dictionary = base.duplicate(true)
	camp.journey.build.catalog = {"version":CatalogProgress.VERSION, "unlock":""}
	camp.journey.state = "FAILED"
	camp.journey.active_member_ids = []
	var identity: String = base.profile_id + ":1"
	for evacuated: bool in [false, true]:
		var battle: Dictionary = {"evacuated":evacuated, "mission_outcome":"EXTRACTED" if evacuated else "FAILED",
			"sortie_id":identity}
		camp.journey.campaign = CampaignState.settled(base, camp, battle, {})
		var receipt: Dictionary = {"phase":"COMMITTED", "transaction_id":identity, "camp_key":"camp",
			"envelope":{"result":{"camp":camp, "battle":battle}}}
		check(CatalogProgress._terminal(receipt), "catalog uses the journey defeat for evacuated=%s" % str(evacuated))
		receipt.transaction_id = base.profile_id + ":2"
		check(not CatalogProgress._terminal(receipt), "catalog rejects a terminal bound to another transaction")


func _screamer_policy(fresh: Dictionary) -> void:
	var base: Dictionary = fresh.duplicate(true)
	base.journey.seed = "m30-opening-4".md5_text()
	base.journey.campaign = CampaignRules.initial_mission(base.profile_id, true, true, true, true, true)
	var build: Dictionary = WorldgenState.initial_build(base.journey.seed, true, true)
	var starter: Dictionary = OpeningBuild.source("scavenge", base.profile_id, base.journey.root_id, base.journey.seed)
	build.opening = starter
	build.owned = [starter.item_id]
	build.slots = [starter.item_id, ""]
	base.journey.build = build
	check(CampaignRules.screamer_enabled(base.journey.campaign) and CampaignRules.problem(base.journey.campaign).is_empty(),
		"the explicit M32 journey policy authenticates")
	var unknown: Dictionary = base.journey.campaign.duplicate(false)
	unknown.screamer_policy = 2
	check(CampaignRules.problem(unknown) == "SCREAMER_CAMPAIGN_POLICY", "unknown M32 journey policy rejects")
	var early: Array[Dictionary] = DailyActions.offers(base)
	check(early.size() == 3 and early.all(func(action: Dictionary) -> bool: return not action.has("screamer_policy")),
		"early airdrop remains unmarked")
	base = _after_food(_after_food(base, 5, 0), 0, 0)
	var older: Dictionary = base.duplicate(true)
	older.journey.campaign.erase("screamer_policy")
	var current: Array[Dictionary] = DailyActions.offers(base)
	var historical: Array[Dictionary] = DailyActions.offers(older)
	check(current.size() == 3 and historical.size() == 3, "both policy versions retain the day's three offers")
	if current.size() != 3 or historical.size() != 3:
		return
	var gear: Dictionary = current[1]
	check(ScreamerPolicyV1.enabled(gear) and DailyActions.problem(gear).is_empty() and DailyActions.matches(base, gear),
		"day-four ordinary industrial gear freezes and authenticates the screamer policy")
	var stripped: Dictionary = gear.duplicate(false)
	stripped.erase("screamer_policy")
	check(RecordEncoding.fingerprint(stripped) == RecordEncoding.fingerprint(historical[1])
		and DailyActions.matches(older, historical[1]) and not DailyActions.matches(older, gear)
		and not DailyActions.matches(base, stripped), "M31 retains the exact historical offer and rejects foreign policy")
	var altered: Dictionary = gear.duplicate(false)
	altered.screamer_policy = 2
	check(DailyActions.problem(altered) == "SCREAMER_ACTION_POLICY", "unknown action policy rejects")
	for index: int in [0, 2]:
		var forged: Dictionary = current[index].duplicate(false)
		forged.screamer_policy = ScreamerPolicyV1.VERSION
		check(RecordEncoding.fingerprint(current[index]) == RecordEncoding.fingerprint(historical[index])
			and DailyActions.problem(forged) == "SCREAMER_ACTION_POLICY", "supply and investigation reject the gear-only policy")



func _after_food(before: Dictionary, field_food: int, facility_food: int) -> Dictionary:
	var after: Dictionary = before.duplicate(true)
	after.day = int(before.day) + 1
	after.settled_sorties = int(before.settled_sorties) + 1
	after.last_settlement_id = "%s:%d" % [before.profile_id, after.settled_sorties]
	after.last_day = CampEconomy.post_battle_food(int(before.day), before.crew, int(before.food), field_food, 1, true, facility_food)
	after.food = after.last_day.food_after
	after.camp_spending = 0
	after.last_day.merge({"day": before.day, "settlement_id": after.last_settlement_id, "evacuated": true,
		"cash_before": before.cash, "cash_after": after.cash, "cash_gained": 0})
	return after


func _rare_sorties(fresh: Dictionary) -> void:
	check(CampaignRules.rare_sorties_enabled(fresh.journey.campaign), "normal new journey opts into rare actions")
	var unknown: Dictionary = fresh.journey.campaign.duplicate(true)
	unknown.rare_policy = "1"
	check(CampaignRules.problem(unknown) == "RARE_CAMPAIGN_POLICY", "unknown campaign marker rejects")


func _opening_build(fresh: Dictionary) -> void:
	var base: Dictionary = fresh.duplicate(true)
	var registration: Dictionary = TransactionReceipt.registration(base, base.journey.root_id)
	check(TransactionReceipt.problem(registration).is_empty(), "current M48 opening registration authenticates")
	for key: String in ["plan", "version", "item_id", "root_id", "run_id", "seed"]:
		var bad: Dictionary = base.duplicate(true)
		bad.journey.build.opening[key] = "forged"
		check(not BuildState.problem(bad).is_empty(), "forged opening " + key + " rejects")
	var bad: Dictionary = base.duplicate(true)
	bad.journey.build.owned.append(OpeningBuild.PLANS.firepower.item_id)
	check(not BuildState.problem(bad).is_empty(), "an unearned second starter rejects")
	bad = base.duplicate(true)
	bad.journey.build.erase("opening")
	check(not BuildState.problem(bad).is_empty(), "unmarked camp cannot hold an unearned starter")
