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


static func post_battle_food(day: int, crew: Array, food: int, found: int, per_member: int, growth: bool = false,
		facility_food: int = 0) -> Dictionary:
	if not SurvivalContracts.identity_problem(crew,growth).is_empty() or food < 0 or food > CampRules.FOOD_LIMIT or found < 0 or found > RunSave.MAX_COUNTER or per_member < 1 or per_member > 100:
		return {}
	var rules: CampRules = CampRules.new()
	rules.ration_per_member = per_member
	var stored: int = mini(found, CampRules.FOOD_LIMIT - food)
	var facility_stored: int = mini(facility_food, CampRules.FOOD_LIMIT - food - stored)
	var available: int = food + stored + facility_stored
	var daily: Dictionary = rations(day, crew, available, rules)
	var consumed: int = mini(available, int(daily.required))
	var ledger: Dictionary = {"food_before":food, "food_found":found, "food_stored":stored,
		"food_overflow":found-stored, "food_required":daily.required, "food_consumed":consumed,
		"food_shortage":daily.shortage, "food_after":available-consumed,
		"ration_member_ids":daily.member_ids, "ration_per_member":per_member}
	if facility_food != 0:
		ledger.facility_food = facility_food
		ledger.facility_stored = facility_stored
	return ledger if SurvivalContracts.food_problem(ledger).is_empty() else {}


static func preview(before: Dictionary, report: Dictionary, identity: String, rules: CampRules) -> Dictionary:
	if not RunSave.validate(before).is_empty():
		return {}
	if identity != "%s:%d" % [before.profile_id, int(before.settled_sorties) + 1]:
		return {}
	var canonical: bool = report.has("contract_version")
	if canonical:
		if not SurvivalContracts.report_problem(before.crew,report).is_empty() or report.get("sortie_id") != identity:
			return {}
		var equipment: Array[Dictionary] = WeaponInventory.snapshot(before)
		var expected: Array[Dictionary] = SurvivalContracts.participants(before.crew,equipment)
		for participant: Dictionary in report.participants:
			var source: Dictionary = SurvivorRoster.member(expected,int(participant.id))
			if participant.definition_id != source.definition_id or float(participant.health_before) != float(source.health_before) or participant.weapon_instance_id != source.weapon_instance_id:
				return {}
		# Legacy aliases remain auditable, never a second source of health or service.
		var records: Array[Dictionary] = []
		for result: Dictionary in report.member_results:
			records.append({"id":result.id,"kills":result.kills,"damage_received":result.damage_received})
		if not report.get("member_records") is Array or report.member_records.size() != records.size():
			return {}
		var seen: Array[int] = []
		for record: Variant in report.member_records:
			if not record is Dictionary or not SurvivalContracts.integer(record.get("id"),1,SurvivalContracts.MAX_ID):
				return {}
			var actual: Dictionary = SurvivorRoster.member(records,int(record.id))
			if int(record.id) in seen or actual.is_empty() or record.size() != 3 or record.get("kills") != actual.kills or record.get("damage_received") != actual.damage_received:
				return {}
			seen.append(int(record.id))
		if not report.get("health") is Array or report.health.size() != report.member_results.size():
			return {}
		var ids: Array[int] = []
		for result: Dictionary in report.member_results:
			ids.append(int(result.id))
		ids.sort()
		for index: int in range(ids.size()):
			var actual: Dictionary = SurvivorRoster.member(report.member_results,ids[index])
			if not SurvivalContracts.number(report.health[index]) or not is_equal_approx(float(report.health[index]),float(actual.health)):
				return {}
	elif not report.get("evacuated") is bool or not report.get("health") is Array or report.health.size() != 2:
		return {}
	var cash_found: Variant = report.get("loot", 0)
	var food_found: Variant = report.get("food", 0)
	if canonical:
		if not SurvivalContracts.integer(cash_found,0,RunSave.MAX_COUNTER) or not SurvivalContracts.integer(food_found,0,RunSave.MAX_COUNTER):
			return {}
		cash_found = int(cash_found)
		food_found = int(food_found)
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
		if canonical:
			var result: Dictionary = SurvivorRoster.member(report.member_results, int(member.id))
			if not result.is_empty():
				member.health = result.health
		else:
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
