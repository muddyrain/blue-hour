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
	app._new_game()
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
	for preparations:int in range(5):
		var fixture:Dictionary=base.duplicate(true)
		fixture.journey.campaign = CampaignRules.initial(base.profile_id)
		fixture.journey.campaign.preparations=preparations
		fixture.day=preparations+2;fixture.settled_sorties=preparations
		var offers:Array[Dictionary]=DailyActions.offers(fixture)
		check(offers.size()==(1 if preparations==4 else 3),"pure phase offer count")
		for action:Dictionary in offers:
			check(DailyActions.matches(fixture,action),"phase identity binds to confirmed count")
			check(action.campaign.pressure==(0.9 if preparations in [2,3] else 1.0),"single explicit pressure parameter")
			var bad:Dictionary=action.duplicate(true);bad.campaign.pressure=0.81
			check(not DailyActions.problem(bad).is_empty(),"cannot compound stage pressure")
			bad=action.duplicate(true);bad.campaign.run_id="bad"
			check(not DailyActions.problem(bad).is_empty(),"malformed action run identity rejects normally")
			if preparations==4:
				var supply:MissionSupply=DailyActions.supply(action)
				var nav:FieldNavigation=FieldNavigation.new();nav.configure(supply.layout.blockers(),supply.layout.world_bounds)
				var point:Vector2=SortieSnapshot._vec(action.encounter.position)
				check(supply.layout.world_bounds.grow(-320).has_point(point) and nav.is_clear(point) and nav.path_between(supply.layout.arrivals[0],point).size()>=2,"boss spawn and original bus arrival share real navigation")
				bad=action.duplicate(true);bad.encounter.position=[0,0]
				check(not DailyActions.problem(bad).is_empty(),"boss spawn cannot be replaced")
	for size:String in NeighborhoodLayout.SIZES:
		for topology:String in NeighborhoodLayout.TOPOLOGIES:
			var old:Dictionary=WeaponActions._upgrade(TaskActions._make("m8-arena-grid".md5_text(),6,0,"supply",topology,size,0))
			var action:Dictionary=CampaignActions._upgrade(old,base.profile_id,4)
			check(CampaignActions.problem(action).is_empty(),"all size/topology finale descriptors have legal interior spawn: "+size+topology)
	var legacy:Dictionary=base.duplicate(true);legacy.journey.erase("campaign");legacy.journey.erase("build")
	check(TransactionReceipt.camp_problem(legacy).is_empty() and DailyActions.offers(legacy)[0].version==5,"old completed camp keeps old mode and V5 offers")
	for key:String in ["settled_sorties","last_day"]:
		var bad:Dictionary=base.duplicate(true);bad.erase(key)
		check(not TransactionReceipt.camp_problem(bad).is_empty(),"short camp rejects missing "+key+" without attribute errors")
	_facilities(base)
	app.audio.shutdown();app.queue_free();await process_frame
	print("CAMPAIGN_CONTRACTS checks=",checks," failures=",failures)
	quit(1 if failures else 0)


func _facilities(fresh: Dictionary) -> void:
	var supply_request: Dictionary = {"kind": "facility", "member_id": 0, "value": "supply"}
	var workshop_request: Dictionary = {"kind": "facility", "member_id": 0, "value": "workshop"}
	check(CampFacilities.enabled(fresh) and CampEdit.propose(fresh, supply_request).is_empty(),
		"new journey opts in, but construction requires a confirmed successful return")
	if not CampFacilities.enabled(fresh):
		return
	# Pure day-three ledger fixture, without writing or playing a synthetic sortie.
	var camp: Dictionary = _after_food(fresh, 4, 0)
	check(TransactionReceipt.camp_problem(camp).is_empty(), "unchanged field food ledger is valid before construction")
	var legacy: Dictionary = camp.duplicate(true)
	legacy.journey.campaign.erase("finale_policy")
	check(TransactionReceipt.camp_problem(legacy).is_empty() and CampFacilities.enabled(legacy)
		and not CampaignRules.pump_station_enabled(legacy.journey.campaign), "M27 facilities remain valid without opting into the pump finale")
	legacy.journey.campaign.erase("midgame")
	check(TransactionReceipt.camp_problem(legacy).is_empty() and CampEdit.propose(legacy, supply_request).is_empty(),
		"M25 camp remains valid and cannot opt in from a camp edit")
	var supply: Dictionary = CampEdit.propose(camp, supply_request)
	var workshop: Dictionary = CampEdit.propose(camp, workshop_request)
	check(not supply.is_empty() and not workshop.is_empty(), "same affordable camp can choose either facility")
	if supply.is_empty() or workshop.is_empty():
		return
	check(supply.cash == camp.cash - CampFacilities.BUILD_COST and supply.camp_spending == CampFacilities.BUILD_COST
		and TransactionReceipt.camp_problem(supply).is_empty() and TransactionReceipt.camp_problem(workshop).is_empty(),
		"construction is a canonical camp edit with matching cash and spending")
	check(CampEdit.propose(supply, workshop_request).is_empty() and CampEdit.propose(workshop, supply_request).is_empty()
		and CampEdit.propose(supply, supply_request).is_empty(), "facility choice is permanent and repeat purchases are denied")
	var quote: Dictionary = {"weapon_id": "fire_axe_v1"}
	check(WeaponInventory.repair_quote(supply, quote) == 10 and WeaponInventory.repair_quote(workshop, quote) == 6,
		"the workshop and normal repair share one exact quote")
	var old: Dictionary = TransactionReceipt.registration(camp, camp.journey.root_id)
	var edit_id: String = "%s:edit:%s" % [camp.profile_id, "0".repeat(32)]
	var ready: Dictionary = CampEdit.record(camp, supply_request, edit_id, old)
	check(not ready.is_empty() and TransactionReceipt.problem(ready).is_empty(),
		"the facility purchase produces an authentic frozen edit that can be retried")
	if not ready.is_empty():
		var forged_edit: Dictionary = ready.duplicate(true)
		forged_edit.envelope.result.journey.campaign.midgame.facility = "workshop"
		check(not TransactionReceipt.problem(forged_edit).is_empty(), "changing the facility in a pending purchase is rejected")
	check(CampFacilities.offered_food(supply, 2, true) == 0 and CampFacilities.offered_food(supply, 3, false) == 0
		and CampFacilities.offered_food(supply, 3, true) == 2 and CampFacilities.offered_food(workshop, 3, true) == 0,
		"facility payout only applies to subsequent successful returns of the selected supply build")
	var capped: Dictionary = CampEconomy.post_battle_food(3, supply.crew, CampRules.FOOD_LIMIT - 3, 2, 1, true, 2)
	check(not capped.is_empty() and capped.food_found == 2 and capped.food_stored == 2 and capped.facility_food == 2
		and capped.facility_stored == 1 and capped.food_consumed == 2 and capped.food_after == CampRules.FOOD_LIMIT - 2,
		"field food fills capacity first, then facility food, then original rations")
	var settled: Dictionary = _after_food(supply, 1, 2)
	var result_food: Dictionary = CampEconomy.post_battle_food(3, supply.crew, int(supply.food), 1, 1, true, 2)
	var result: Dictionary = {"food": result_food, "battle": {"food": 1, "evacuated": true}}
	check(TransactionReceipt.camp_problem(settled).is_empty() and CampFacilities.result_problem(supply, settled, result).is_empty(),
		"new ledger authenticates field and facility earnings against the frozen departure camp")
	result_food.facility_stored = 0
	check(not CampFacilities.result_problem(supply, settled, result).is_empty(), "forged facility payout is rejected")
	var stripped: Dictionary = settled.duplicate(true)
	stripped.journey.campaign.erase("finale_policy")
	stripped.journey.campaign.erase("midgame")
	check(not TransactionReceipt.camp_problem(stripped).is_empty(), "historic camp cannot authenticate a facility payout")


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
