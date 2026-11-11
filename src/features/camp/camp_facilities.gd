class_name CampFacilities
extends RefCounted
## PROJECT_TEMP. CampEdit owns the one-time purchase and FrozenSettlement owns supply.

const VERSION: int = 1
const TIER_TWO_VERSION: int = 2
const SUPPLY: String = "supply"
const WORKSHOP: String = "workshop"
const BUILD_COST: int = 12
const UPGRADE_COST: int = 10
const SUPPLY_FOOD: int = 2
const UPGRADED_SUPPLY_FOOD: int = 3
const REPAIR_DISCOUNT: int = 4


static func initial() -> Dictionary:
	return {"version": VERSION, "facility": "", "built_day": 0}


static func initial_tier_two() -> Dictionary:
	return {"version":TIER_TWO_VERSION, "facility":"", "built_day":0, "upgraded_day":0}


static func enable_tier_two(campaign: Dictionary) -> void:
	assert(campaign.midgame == initial())
	campaign.midgame = {"version": TIER_TWO_VERSION, "facility": "", "built_day": 0, "upgraded_day": 0}


static func marker_problem(value: Variant) -> String:
	if not value is Dictionary or not value.has_all(["version", "facility", "built_day"]):
		return "MIDGAME_FIELDS"
	if not SurvivalContracts.integer(value.version, VERSION, TIER_TWO_VERSION) or not value.facility is String or value.facility not in ["", SUPPLY, WORKSHOP]:
		return "MIDGAME_POLICY"
	var tier_two: bool = value.version == TIER_TWO_VERSION
	if value.size() != (4 if tier_two else 3) or (tier_two and not value.has("upgraded_day")):
		return "MIDGAME_FIELDS"
	var minimum_day: int = 0 if value.facility == "" else 3
	var maximum_day: int = 0 if value.facility == "" else RunSave.MAX_COUNTER
	if not SurvivalContracts.integer(value.built_day, minimum_day, maximum_day):
		return "MIDGAME_BUILD_DAY"
	if tier_two and (not SurvivalContracts.integer(value.upgraded_day, 0, maximum_day)
			or (value.upgraded_day != 0 and value.upgraded_day <= value.built_day)):
		return "MIDGAME_UPGRADE_DAY"
	return ""


static func enabled(camp: Dictionary) -> bool:
	return CampaignRules.midgame_enabled(camp.get("journey", {}).get("campaign"))


static func selected(camp: Dictionary) -> String:
	if EconomyBuildV1.enabled(camp):
		return WORKSHOP if EconomyBuildV1.level(camp, WORKSHOP) > 0 else SUPPLY if EconomyBuildV1.level(camp, SUPPLY) > 0 else ""
	return camp.journey.campaign.midgame.facility if enabled(camp) else ""


static func tier_two_enabled(camp: Dictionary) -> bool:
	return enabled(camp) and camp.journey.campaign.midgame.version == TIER_TWO_VERSION


static func upgraded(camp: Dictionary) -> bool:
	if EconomyBuildV1.enabled(camp): return EconomyBuildV1.level(camp, WORKSHOP) >= 2
	return tier_two_enabled(camp) and camp.journey.campaign.midgame.upgraded_day > 0


static func can_build(camp: Dictionary, choice: String) -> bool:
	if EconomyBuildV1.enabled(camp): return false # New purchases require stable M48 edit intents.
	return (enabled(camp) and choice in [SUPPLY, WORKSHOP] and selected(camp).is_empty()
		and camp.journey.campaign.outcome == "ACTIVE" and camp.get("cash", 0) >= BUILD_COST
		and camp.get("last_day", {}).get("evacuated") == true)


static func build(before: Dictionary, choice: String) -> Dictionary:
	if not can_build(before, choice):
		return {}
	var after: Dictionary = before.duplicate(true)
	after.journey.campaign.midgame.facility = choice
	after.journey.campaign.midgame.built_day = int(before.day)
	after.cash = int(before.cash) - BUILD_COST
	after.camp_spending = int(before.camp_spending) + BUILD_COST
	return after


static func upgrade_offer(camp: Dictionary, choice: String) -> Dictionary:
	var reason: String = _upgrade_problem(camp, choice)
	return {"available": reason.is_empty(), "reason": reason, "cost": UPGRADE_COST}


static func _upgrade_problem(camp: Dictionary, choice: String) -> String:
	if EconomyBuildV1.enabled(camp): return "请使用营地设施的独立投资操作"
	if not tier_two_enabled(camp):
		return "二级设施仅在新旅程开放"
	if camp.journey.get("state") != "ACTIVE" or camp.journey.campaign.outcome != "ACTIVE":
		return "当前旅程无法升级设施"
	if choice not in [SUPPLY, WORKSHOP] or selected(camp) != choice:
		return "请先建成该设施"
	if upgraded(camp):
		return "该设施已升至二级"
	if not _confirmed_return_since_build(camp):
		return "建成后须再完成一次成功归航并确认"
	if int(camp.get("cash", 0)) < UPGRADE_COST:
		return "还差 %d 币" % (UPGRADE_COST - int(camp.get("cash", 0)))
	return ""


static func _confirmed_return_since_build(camp: Dictionary) -> bool:
	var ledger: Variant = camp.get("last_day")
	var sortie_day: int = int(camp.day) - 1
	var identity: String = "%s:%d" % [camp.profile_id, sortie_day - 1]
	return sortie_day >= int(camp.journey.campaign.midgame.built_day) \
		and ledger is Dictionary and ledger.get("evacuated") == true \
		and SurvivalContracts.integer(ledger.get("day"), sortie_day, sortie_day) \
		and ledger.get("settlement_id") == identity and camp.get("last_settlement_id") == identity


static func upgrade(before: Dictionary, choice: String) -> Dictionary:
	if not _upgrade_problem(before, choice).is_empty():
		return {}
	var after: Dictionary = before.duplicate(true)
	after.journey.campaign.midgame.upgraded_day = int(before.day)
	after.cash = int(before.cash) - UPGRADE_COST
	after.camp_spending = int(before.camp_spending) + UPGRADE_COST
	return after


static func offered_food(camp: Dictionary, day: int, evacuated: bool) -> int:
	if EconomyBuildV1.enabled(camp):
		var tier: int = EconomyBuildV1.level_at(camp, SUPPLY, day - 1)
		return tier + 1 if evacuated and tier > 0 else 0
	if evacuated and selected(camp) == SUPPLY and day >= int(camp.journey.campaign.midgame.built_day):
		if upgraded(camp) and day >= int(camp.journey.campaign.midgame.upgraded_day):
			return UPGRADED_SUPPLY_FOOD
		return SUPPLY_FOOD
	return 0


static func has_food_fields(ledger: Dictionary) -> bool:
	return ledger.has("facility_food") or ledger.has("facility_stored")


static func camp_problem(camp: Dictionary) -> String:
	if EconomyBuildV1.enabled(camp):
		var issue: String = EconomyBuildV1.problem(camp)
		if not issue.is_empty(): return issue
		var current_ledger: Dictionary = camp.get("last_day", {})
		if current_ledger.is_empty(): return ""
		var expected_food: int = offered_food(camp, int(current_ledger.get("day", 0)), current_ledger.get("evacuated") == true)
		return SurvivalContracts.food_problem(current_ledger, expected_food) if expected_food > 0 else "ECONOMY_UNEARNED_FOOD" if has_food_fields(current_ledger) else ""
	var day: Variant = camp.get("day")
	var ledger: Variant = camp.get("last_day")
	if enabled(camp) and (not SurvivalContracts.integer(day, 2, RunSave.MAX_COUNTER)
			or camp.journey.campaign.midgame.built_day > day):
		return "MIDGAME_BUILD_DAY"
	if not selected(camp).is_empty() and camp.journey.campaign.midgame.built_day == day:
		if (not ledger is Dictionary or ledger.get("evacuated") != true
				or not SurvivalContracts.integer(camp.get("camp_spending"), BUILD_COST, RunSave.MAX_COUNTER)):
			return "MIDGAME_BUILD_SOURCE"
	if upgraded(camp):
		var upgraded_day: int = int(camp.journey.campaign.midgame.upgraded_day)
		if upgraded_day > day:
			return "MIDGAME_UPGRADE_DAY"
		# Spending belongs to the current camp day. Prior debits are authenticated by
		# the edit receipts, since settlement clears this counter at each return.
		if upgraded_day == day and (not _confirmed_return_since_build(camp)
				or not SurvivalContracts.integer(camp.get("camp_spending"), UPGRADE_COST, RunSave.MAX_COUNTER)):
			return "MIDGAME_UPGRADE_SOURCE"
	if not ledger is Dictionary or ledger.is_empty():
		return ""
	if not SurvivalContracts.integer(ledger.get("day"), 2, RunSave.MAX_COUNTER):
		return "MIDGAME_LEDGER_DAY" if has_food_fields(ledger) else ""
	var expected: int = offered_food(camp, int(ledger.day), ledger.get("evacuated") == true)
	if expected == 0:
		return "MIDGAME_UNEARNED_FOOD" if has_food_fields(ledger) else ""
	if not SurvivalContracts.food_problem(ledger, expected).is_empty():
		return "MIDGAME_FOOD_LEDGER"
	return ""


static func project_legacy_food(ledger: Dictionary) -> void:
	# The previous schema authenticates the aggregate totals on a read-only copy.
	if not has_food_fields(ledger):
		return
	ledger.food_found += ledger.facility_food
	ledger.food_stored += ledger.facility_stored
	ledger.food_overflow += ledger.facility_food - ledger.facility_stored
	ledger.erase("facility_food")
	ledger.erase("facility_stored")


static func result_problem(before: Dictionary, after: Dictionary, result: Dictionary) -> String:
	var food: Variant = result.get("food")
	if not enabled(before) and not enabled(after):
		return "MIDGAME_UNEARNED_FOOD" if food is Dictionary and has_food_fields(food) else ""
	var before_campaign: Dictionary = before.get("journey", {}).get("campaign", {})
	var after_campaign: Dictionary = after.get("journey", {}).get("campaign", {})
	if not enabled(before) or not enabled(after) or not TransactionReceipt.same(before_campaign.midgame, after_campaign.midgame):
		return "MIDGAME_RESULT_FACILITY_CHANGED"
	var battle: Variant = result.get("battle")
	if not food is Dictionary or not battle is Dictionary or not battle.get("evacuated") is bool:
		return "MIDGAME_RESULT_LEDGER"
	if food.get("food_before") != before.food or food.get("food_found") != battle.get("food"):
		return "MIDGAME_RESULT_FIELD_FOOD"
	var ledger: Dictionary = after.last_day
	if ledger.get("evacuated") != battle.evacuated or ledger.get("food_before") != before.food:
		return "MIDGAME_RESULT_LEDGER"
	var expected: int = offered_food(before, int(before.day), battle.evacuated)
	if expected == 0 and has_food_fields(food):
		return "MIDGAME_UNEARNED_FOOD"
	if expected > 0 and food.get("facility_food") != expected:
		return "MIDGAME_RESULT_FACILITY_FOOD"
	if food.size() != 10 + (2 if expected > 0 else 0) or not SurvivalContracts.food_problem(food, expected).is_empty():
		return "MIDGAME_RESULT_LEDGER"
	for key: String in food:
		if ledger.get(key) != food[key]:
			return "MIDGAME_RESULT_LEDGER"
	return ""
