extends "res://tests/persona_rules.gd"
## Pure generation and signed-action boundaries. Windows flow covers actual carrying and settlement.


func run() -> void:
	var routine_seed: String = "m35-risk-0".md5_text()
	var deep_seed: String = "m35-risk-1".md5_text()
	expect(SortieRiskV1.selection(routine_seed, 3, 2) == SortieRiskV1.ROUTINE, "routine seed vector")
	expect(SortieRiskV1.selection(deep_seed, 3, 2) == SortieRiskV1.DEEP, "deep seed vector")
	expect(SortieRiskV1.selection(deep_seed, 2, 2).is_empty()
		and SortieRiskV1.selection(deep_seed, 3, 1).is_empty(), "risk is limited to the later optional slot")
	var invalid: Dictionary = CampaignRules.initial_mission("0123456789abcdef0123456789abcdef", true)
	for marker: Variant in [0, 2, "1", true]:
		invalid.sortie_risk_policy = marker
		expect(not CampaignRules.sortie_risk_enabled(invalid) and not CampaignRules.problem(invalid).is_empty(),
			"unknown or mistyped campaign risk marker rejects")
	_verify_offer("m35-risk-0", SortieRiskV1.ROUTINE, false)
	_verify_offer("m35-risk-1", SortieRiskV1.ROUTINE, true)
	_verify_offer("m35-sortie-risk-27", SortieRiskV1.DEEP, false)
	print(JSON.stringify({"suite":"sortie_risk", "checks":checks, "failures":failures, "scope":"PURE_SIGNED_ACTION"}))
	quit(1 if failures else 0)


func _verify_offer(label: String, tier: String, fallback: bool) -> void:
	var base: Dictionary = _camp_fixture()
	var seed: String = label.md5_text()
	base.day = 3
	base.settled_sorties = 1
	base.journey.seed = seed
	base.journey.build = WorldgenState.initial_build(seed, true, true)
	base.journey.campaign = CampaignRules.initial_mission(base.profile_id, true, true, true, true, true, true, true, true)
	var old: Dictionary = base.duplicate(true)
	old.journey.campaign.erase("sortie_risk_policy")
	var offer: Dictionary = _optional_slot(base)
	var historical: Dictionary = _optional_slot(old)
	expect(SortieRiskV1.enabled(offer) and historical.get("type") == "airdrop"
		and not historical.has("sortie_risk"), "only opted-in camp marks ordinary gear " + label)
	if not SortieRiskV1.enabled(offer) or historical.is_empty():
		return
	var expected_size: String = "large" if tier == SortieRiskV1.DEEP else "medium"
	expect(offer.sortie_risk.tier == tier and offer.sortie_risk.fallback == fallback
		and offer.layout.size == expected_size, "the fixed seed gives its expected final tier and size " + label)
	expect(DailyActions.problem(offer).is_empty() and DailyActions.matches(base, offer)
		and DailyActions.problem(historical).is_empty() and DailyActions.matches(old, historical),
		"each campaign authenticates its actual offer " + label)
	expect(not DailyActions.matches(old, offer) and not DailyActions.matches(base, historical),
		"risk policy cannot be added to an old camp or dropped from the new offer " + label)
	var action_id: String = base.profile_id + ":2"
	expect(offer.id == historical.id and TransactionReceipt.same(
		WeaponInventory.site_reward(action_id, offer, _site(offer, "cash"), true),
		WeaponInventory.site_reward(action_id, historical, _site(historical, "cash"), true)),
		"map size preserves the ordinary weapon instance and affix roll " + label)
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(offer))).payload
	expect(DailyActions.problem(decoded).is_empty() and DailyActions.matches(base, decoded),
		"the exact decoded descriptor still authenticates " + label)
	var edited: Dictionary = offer.duplicate(true)
	edited.sortie_risk.fallback = not edited.sortie_risk.fallback
	expect(not DailyActions.problem(edited).is_empty() and not DailyActions.matches(base, edited),
		"altered fallback rejects " + label)
	edited = offer.duplicate(true)
	edited.exploration.level.routes["bus>cash"].length += 1.0
	expect(not DailyActions.problem(edited).is_empty() and not DailyActions.matches(base, edited),
		"altered frozen route length rejects " + label)
	var summary: Dictionary = offer.exploration.level
	var optional: Dictionary = _site(offer, summary.optional.site_id)
	var seconds: float = SortieRiskV1.round_trip_seconds(summary)
	expect(seconds > 0.0 and optional.get("amount", 0) > 0
		and summary.optional.added_team_seconds > 0.0, "real route and nonempty optional material " + label)
	if offer.sortie_risk.tier == SortieRiskV1.DEEP:
		var medium: Dictionary = SortieRiskV1._map(ExplorationActions.origin(offer), "medium",
			offer.layout.topology, offer.layout.has("loading_yard"))
		expect(not medium.is_empty(), "same seed supplies a certified medium control " + label)
		if not medium.is_empty():
			var baseline: float = SortieRiskV1.round_trip_seconds(medium.exploration.level)
			expect(seconds >= baseline + 10.0 and seconds >= baseline * 1.2,
				"large main route exceeds both certified medium margins " + label)
	elif offer.sortie_risk.fallback:
		var rejected: Dictionary = SortieRiskV1._map(ExplorationActions.origin(offer), "large",
			offer.layout.topology, offer.layout.has("loading_yard"))
		expect(rejected.is_empty() or not SortieRiskV1._deep_fits(offer, rejected),
			"uncertifiable deep map falls back to the actual medium route " + label)
	print("SORTIE_RISK_SAMPLE " + JSON.stringify({"label":label, "tier":offer.sortie_risk.tier,
		"fallback":offer.sortie_risk.fallback, "size":offer.layout.size, "topology":offer.layout.topology,
		"round_trip_seconds":seconds, "optional_id":optional.get("id", ""), "optional_kind":optional.get("kind", ""),
		"optional_amount":optional.get("amount", 0), "optional_seconds":summary.optional.added_team_seconds}))


func _optional_slot(base: Dictionary) -> Dictionary:
	for offer: Dictionary in DailyActions.offers(base):
		if offer.slot == SortieRiskV1.SLOT:
			return offer
	return {}


func _site(offer: Dictionary, id: String) -> Dictionary:
	for site: Dictionary in offer.sites:
		if site.id == id:
			return site
	return {}
