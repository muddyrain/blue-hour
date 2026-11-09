extends "res://tests/persona_rules.gd"
## Pure policy fixtures; the Windows run separately proves departures and settlement.


func run() -> void:
	_verify_tiers()
	_verify_board(0, false)
	_verify_board(3, false)
	_verify_board(5, true)
	print(JSON.stringify({"suite":"campaign_pressure", "checks":checks, "failures":failures,
		"scope":"PURE_SIGNED_ACTION"}))
	quit(1 if failures else 0)


func _verify_tiers() -> void:
	for row: Array in [[0, 0, 1.0], [1, 0, 1.0], [2, 0, 1.0], [3, 1, 0.9], [4, 1, 0.9],
			[5, 2, 0.8], [6, 2, 0.8], [RunSave.MAX_COUNTER - 2, 2, 0.8]]:
		var settled: int = row[0]
		var frozen: Dictionary = {"version":9, "mission_policy":1, "day":settled + 2,
			"campaign":{"pressure":1.0}, "campaign_pressure":CampaignPressureV1.marker(settled)}
		expect(CampaignPressureV1.tier_for(settled) == row[1] and CampaignPressureV1.enabled(frozen)
			and near(CampaignPressureV1.spawn_factor(frozen), row[2]),
			"confirmed return boundary %d freezes the expected factor" % settled)
	var legacy: Dictionary = {"version":6, "campaign":{"pressure":CampaignRules.BREAKOUT_INTERVAL}}
	expect(CampaignPressureV1.spawn_factor(legacy) == CampaignRules.BREAKOUT_INTERVAL,
		"short campaign retains its own historical breakout pressure")
	var current: Dictionary = {"version":9, "mission_policy":1, "day":7,
		"campaign":{"pressure":1.0}, "campaign_pressure":CampaignPressureV1.marker(5)}
	var director: ThreatDirector = ThreatDirector.new()
	for row: Array in [[0.0, 0, 5.6], [70.0, 1, 4.0], [105.0, 2, 2.8], [140.0, 3, 2.0]]:
		director.update(row[0], 105.0, 7.0 * CampaignPressureV1.spawn_factor(current))
		expect(director.stage == row[1] and near(director.interval, row[2]),
			"frozen pressure and original day-night rules multiply once")
	for bad_marker: Variant in [null, [], {"version":2, "tier":2}, {"version":"1", "tier":2},
			{"version":1, "tier":true}, {"version":1, "tier":1}, {"version":1, "tier":2, "extra":0}]:
		current.campaign_pressure = bad_marker
		expect(not CampaignPressureV1.enabled(current), "foreign frozen pressure rejects")
	var invalid: Dictionary = CampaignRules.initial_mission("0123456789abcdef0123456789abcdef")
	for bad_version: Variant in [0, 2, "1", true]:
		invalid.campaign_pressure_policy = bad_version
		expect(not CampaignRules.campaign_pressure_enabled(invalid)
			and CampaignRules.problem(invalid) == "CAMPAIGN_PRESSURE_POLICY",
			"foreign journey pressure version rejects")


func _verify_board(settled: int, finale: bool) -> void:
	var base: Dictionary = _pressure_camp(settled, finale)
	var historical: Dictionary = base.duplicate(true)
	historical.journey.campaign.erase("campaign_pressure_policy")
	expect(TransactionReceipt.camp_problem(base).is_empty() and TransactionReceipt.camp_problem(historical).is_empty(),
		"both explicit and historical camps authenticate at %d confirmed returns" % settled)
	var offers: Array[Dictionary] = DailyActions.offers(base)
	var old_offers: Array[Dictionary] = DailyActions.offers(historical)
	expect(offers.size() == 3 and old_offers.size() == offers.size(), "original day board remains available")
	if offers.size() != 3 or old_offers.size() != offers.size():
		return
	expect(offers.any(func(action: Dictionary) -> bool: return action.get("type") == "supply" and not PumpStationAction.enabled(action))
		and offers.any(func(action: Dictionary) -> bool: return PumpStationAction.enabled(action) if finale else action.has("investigation")),
		"board covers ordinary and %s actions" % ("pump" if finale else "investigation"))
	for index: int in range(offers.size()):
		var action: Dictionary = offers[index]
		var old_action: Dictionary = old_offers[index]
		var kind: String = "pump" if PumpStationAction.enabled(action) else String(action.type)
		expect(CampaignPressureV1.enabled(action) and action.get("campaign_pressure") == CampaignPressureV1.marker(settled)
			and DailyActions.problem(action).is_empty() and DailyActions.matches(base, action),
			"%s action authenticates its current frozen pressure" % kind)
		var stripped: Dictionary = action.duplicate(false)
		stripped.erase("campaign_pressure")
		expect(RecordEncoding.fingerprint(stripped) == RecordEncoding.fingerprint(old_action)
			and DailyActions.problem(old_action).is_empty() and DailyActions.matches(historical, old_action),
			"%s original map and action remain exact with no pressure opt-in" % kind)
		expect(not DailyActions.matches(base, stripped) and not DailyActions.matches(historical, action),
			"%s cannot carry pressure across incompatible departure camps" % kind)
		var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(action))).payload
		expect(DailyActions.problem(decoded).is_empty() and DailyActions.matches(base, decoded),
			"%s frozen pressure authenticates after exact decoding" % kind)
		var forged: Dictionary = action.duplicate(true)
		forged.campaign_pressure.tier = (int(action.campaign_pressure.tier) + 1) % 3
		expect(not DailyActions.problem(forged).is_empty() and not DailyActions.matches(base, forged),
			"%s wrong frozen tier rejects" % kind)
		if PumpStationAction.enabled(action):
			expect(PumpStationAction.problem(forged) == "CAMPAIGN_PRESSURE_ACTION_POLICY",
				"direct pump validation also rejects an invalid tier")


func _pressure_camp(settled: int, finale: bool) -> Dictionary:
	var base: Dictionary = _camp_fixture()
	base.journey.build = WorldgenState.initial_build(base.journey.seed, true, true)
	base.journey.campaign = CampaignRules.initial_mission(base.profile_id,
		true, true, true, false, false, false, false, false, true)
	for day: int in range(2, settled + 2):
		base.day = day + 1
		base.settled_sorties = day - 1
		base.last_settlement_id = "%s:%d" % [base.profile_id, base.settled_sorties]
		base.last_day = CampEconomy.post_battle_food(day, base.crew, int(base.food), 2, 1, true)
		base.food = base.last_day.food_after
		base.last_day.merge({"day":day, "settlement_id":base.last_settlement_id, "evacuated":true,
			"cash_before":base.cash, "cash_after":base.cash, "cash_gained":0})
	if finale:
		for index: int in range(CampaignRules.CLUE_IDS.size()):
			base.journey.campaign.clues.append({"id":CampaignRules.CLUE_IDS[index],
				"transaction_id":"%s:%d" % [base.profile_id, index + 1],
				"action_id":("daily-v4:%s:%d:1" % [base.journey.seed, index + 2]).sha256_text(), "site_id":"cash"})
	return base
