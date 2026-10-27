class_name CampEconomy
extends RefCounted
## Pure proposal: the app commits this once on Return to Camp, then retries only I/O.


static func rations(day: int, crew: Array, food: int, rules: CampRules) -> Dictionary:
	var identities: Array[int] = []
	for member: Dictionary in crew:
		if float(member.health) > 0.0:
			identities.append(int(member.id))
	identities.sort()
	var required: int = identities.size() * rules.ration_per_member
	return {"day":day,"member_ids":identities,"per_member":rules.ration_per_member,
		"required":required,"shortage":maxi(0,required-food)}


static func preview(before: Dictionary, report: Dictionary, identity: String, rules: CampRules) -> Dictionary:
	if not RunSave.validate(before).is_empty():
		return {}
	if identity != "%s:%d" % [before.profile_id, int(before.settled_sorties) + 1]:
		return {}
	if not report.get("evacuated") is bool or not report.get("health") is Array or report.health.size() != 2:
		return {}
	var cash_found: Variant = report.get("loot", 0)
	var food_found: Variant = report.get("food", 0)
	if not cash_found is int or not food_found is int or cash_found < 0 or food_found < 0:
		return {}
	var brought_cash: int = cash_found if report.evacuated else 0
	var brought_food: int = food_found if report.evacuated else 0
	var daily: Dictionary = rations(int(before.day), before.crew, int(before.food), rules)
	var stored: int = mini(brought_food, CampRules.FOOD_LIMIT - int(before.food))
	var available: int = int(before.food) + stored
	var consumed: int = mini(available, int(daily.required))
	var after: Dictionary = before.duplicate(true)
	after.day = int(before.day) + 1
	after.cash = int(before.cash) + brought_cash
	after.food = available - consumed
	after.settled_sorties = int(before.settled_sorties) + 1
	after.last_settlement_id = identity
	if int(after.schema_version) >= 3:
		after.camp_spending = 0
	for member: Dictionary in after.crew:
		member.health = report.health[int(member.id) - 1]
	if int(after.schema_version) >= 4:
		if not SurvivorRoster.record(after, before, report, identity).is_empty():
			return {}
	if int(after.schema_version) >= 3:
		var rewards: Variant = report.get("weapons", [])
		if not rewards is Array:
			return {}
		if not WeaponInventory.bank(after, rewards if report.evacuated else [], identity).is_empty():
			return {}
	if int(after.schema_version) >= 5:
		if not SurvivorGrowth.bank(after,before,report,identity).is_empty():
			return {}
	after.last_day = {"settlement_id":identity,"day":int(before.day),
		"food_before":int(before.food),"food_found":brought_food,"food_stored":stored,
		"food_overflow":brought_food-stored,"ration_member_ids":daily.member_ids,
		"ration_per_member":daily.per_member,"food_required":daily.required,
		"food_consumed":consumed,"food_shortage":int(daily.required)-consumed,"food_after":after.food,
		"cash_before":int(before.cash),"cash_gained":brought_cash,"cash_after":after.cash,
		"evacuated":report.evacuated}
	return after if RunSave.validate(after).is_empty() else {}
