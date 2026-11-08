class_name CampFacilities
extends RefCounted
## PROJECT_TEMP. CampEdit owns the one-time purchase and FrozenSettlement owns supply.

const VERSION: int = 1
const SUPPLY: String = "supply"
const WORKSHOP: String = "workshop"
const BUILD_COST: int = 12
const SUPPLY_FOOD: int = 2
const REPAIR_DISCOUNT: int = 4


static func initial() -> Dictionary:
	return {"version": VERSION, "facility": "", "built_day": 0}


static func marker_problem(value: Variant) -> String:
	if not value is Dictionary or value.size() != 3 or not value.has_all(["version", "facility", "built_day"]):
		return "MIDGAME_FIELDS"
	if not SurvivalContracts.integer(value.version, VERSION, VERSION) or not value.facility is String or value.facility not in ["", SUPPLY, WORKSHOP]:
		return "MIDGAME_POLICY"
	var minimum_day: int = 0 if value.facility == "" else 3
	var maximum_day: int = 0 if value.facility == "" else RunSave.MAX_COUNTER
	return "" if SurvivalContracts.integer(value.built_day, minimum_day, maximum_day) else "MIDGAME_BUILD_DAY"


static func enabled(camp: Dictionary) -> bool:
	return CampaignRules.midgame_enabled(camp.get("journey", {}).get("campaign"))


static func selected(camp: Dictionary) -> String:
	return camp.journey.campaign.midgame.facility if enabled(camp) else ""


static func can_build(camp: Dictionary, choice: String) -> bool:
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


static func offered_food(camp: Dictionary, day: int, evacuated: bool) -> int:
	if evacuated and selected(camp) == SUPPLY and day >= int(camp.journey.campaign.midgame.built_day):
		return SUPPLY_FOOD
	return 0


static func has_food_fields(ledger: Dictionary) -> bool:
	return ledger.has("facility_food") or ledger.has("facility_stored")


static func camp_problem(camp: Dictionary) -> String:
	var day: Variant = camp.get("day")
	var ledger: Variant = camp.get("last_day")
	if enabled(camp) and (not SurvivalContracts.integer(day, 2, RunSave.MAX_COUNTER)
			or camp.journey.campaign.midgame.built_day > day):
		return "MIDGAME_BUILD_DAY"
	if not selected(camp).is_empty() and camp.journey.campaign.midgame.built_day == day:
		if (not ledger is Dictionary or ledger.get("evacuated") != true
				or not SurvivalContracts.integer(camp.get("camp_spending"), BUILD_COST, RunSave.MAX_COUNTER)):
			return "MIDGAME_BUILD_SOURCE"
	if not ledger is Dictionary or ledger.is_empty():
		return ""
	if not SurvivalContracts.integer(ledger.get("day"), 2, RunSave.MAX_COUNTER):
		return "MIDGAME_LEDGER_DAY" if has_food_fields(ledger) else ""
	var expected: int = offered_food(camp, int(ledger.day), ledger.get("evacuated") == true)
	if expected == 0:
		return "MIDGAME_UNEARNED_FOOD" if has_food_fields(ledger) else ""
	if ledger.get("facility_food") != expected or not SurvivalContracts.food_problem(ledger).is_empty():
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
	if food.size() != 10 + (2 if expected > 0 else 0) or not SurvivalContracts.food_problem(food).is_empty():
		return "MIDGAME_RESULT_LEDGER"
	for key: String in food:
		if ledger.get(key) != food[key]:
			return "MIDGAME_RESULT_LEDGER"
	return ""
