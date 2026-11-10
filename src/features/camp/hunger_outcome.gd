class_name HungerOutcome
extends RefCounted
## Explicit pure candidates only; the app never enables direct starvation by default.

const DIRECT: String = "DIRECT_STARVATION_V1"


static func candidate(ledger: Dictionary) -> Dictionary:
	if ledger.is_empty():
		return {"loss_count":0,"victim_ids":[],"applied":false}
	return {"loss_count":mini(int(ledger.food_shortage), ledger.ration_member_ids.size()),
		"victim_ids":[],"applied":false}


static func settle(food: Dictionary, battle: Array, policy: Dictionary, binding: Dictionary = {}, limits: Dictionary = {},
		expected_facility_food: int = -1) -> Dictionary:
	if not SurvivalContracts.food_problem(food, expected_facility_food).is_empty():
		return {"error":"FOOD_LEDGER"}
	if policy.get("ruleset_id") == DIRECT:
		return _direct(food, battle, policy, binding, limits, expected_facility_food)
	var shortage: int = int(food.food_shortage)
	if shortage > 0 and policy.is_empty():
		return {"error":"POLICY_REQUIRED", "reason":"HUNGER_RULE"}
	if not policy.is_empty() and (policy.size() != 4 or policy.get("ruleset_id") != "EQUAL_FROZEN_SHARE_V1" or policy.get("source") != "PROJECT_TEMP" or policy.get("scope") != "ISOLATED_CANDIDATE" or not SurvivalContracts.number(policy.get("full_shortage_damage"))):
		return {"error":"HUNGER_POLICY"}
	var full_damage: float = float(policy.get("full_shortage_damage", 0.0))
	if full_damage < 0.0 or full_damage > 200.0:
		return {"error":"HUNGER_POLICY"}
	var effects: Array[Dictionary] = []
	var allocation: Array[Dictionary] = []
	# Freeze shares before any deaths. There is no reallocation or implicit rounding.
	var fraction: float = float(shortage) / float(food.food_required) if food.food_required > 0 else 0.0
	var nominal: float = full_damage * fraction
	for id: int in food.ration_member_ids:
		var member: Dictionary = SurvivorRoster.member(battle, id)
		if member.is_empty() or not SurvivalContracts.number(member.get("health")) or member.health <= 0:
			return {"error":"RATION_MEMBER_NOT_ALIVE"}
		var damage: float = minf(nominal, float(member.health))
		effects.append({"id":id,"health_before":member.health,"damage":damage,"health_after":float(member.health)-damage})
		allocation.append({"id":id,"required":food.ration_per_member,
			"provided":float(food.ration_per_member)*(1.0-fraction),"nominal_damage":nominal,"actual_damage":damage})
	var ledger: Dictionary = {"ruleset_id":policy.get("ruleset_id", "NO_SHORTAGE"),
		"ration_member_ids":food.ration_member_ids.duplicate(),"effects":effects}
	var issue: String = SurvivalContracts.ledgers_problem(food, ledger, battle, limits, expected_facility_food)
	return {"error":"", "ledger":ledger,"allocation":allocation} if issue.is_empty() else {"error":issue}


static func description(ledger: Dictionary) -> String:
	var result: Dictionary = candidate(ledger)
	if int(result.loss_count) == 0:
		return "本次口粮足够。"
	return "缺粮 %d：成员损失候选 %d 人，尚未应用；原作可能减员。" % [ledger.food_shortage, result.loss_count]


static func _direct(food: Dictionary, battle: Array, policy: Dictionary, binding: Dictionary, limits: Dictionary,
		expected_facility_food: int) -> Dictionary:
	if policy.size() != 3 or policy.get("scope") != "ISOLATED_CANDIDATE" or policy.get("source") != "PROJECT_TEMP" or food.ration_per_member != 1:
		return {"error":"DIRECT_POLICY"}
	if binding.size() != 5 or not binding.has_all(["run_id", "root_id", "transaction_id", "base_hash", "rules_hash"]):
		return {"error":"DIRECT_BINDING"}
	for key: String in ["run_id", "root_id", "base_hash", "rules_hash"]:
		if not binding[key] is String or binding[key].length() != (32 if key in ["run_id", "root_id"] else 64) or not binding[key].is_valid_hex_number(false):
			return {"error":"DIRECT_BINDING"}
	if not binding.transaction_id is String:
		return {"error":"DIRECT_BINDING"}
	var parts: PackedStringArray = binding.transaction_id.split(":")
	if parts.size() != 2 or parts[0] != binding.run_id or not parts[1].is_valid_int() or int(parts[1]) < 1 or parts[1] != str(int(parts[1])):
		return {"error":"DIRECT_BINDING"}
	var ids: Array = food.ration_member_ids.duplicate()
	ids.sort()
	var alive: Array[int] = []
	var seen: Array[int] = []
	for row: Variant in battle:
		if not row is Dictionary or not SurvivalContracts.integer(row.get("id"), 1, SurvivalContracts.MAX_ID) or int(row.id) in seen or not SurvivalContracts.number(row.get("health")) or row.health < 0.0 or row.health > float(limits.get(int(row.id),200.0)):
			return {"error":"DIRECT_BATTLE_MEMBERS"}
		seen.append(int(row.id))
		if row.health > 0.0:
			alive.append(int(row.id))
	alive.sort()
	if ids != alive:
		return {"error":"DIRECT_RATION_MEMBERS"}
	# Exclude array-sensitive base_hash: membership is canonical, while the coordinator binds the complete base.
	var seed: String = SurvivalContracts.fingerprint({"algorithm":"SHA256_RANK_V1", "run_id":binding.run_id,
		"root_id":binding.root_id, "transaction_id":binding.transaction_id, "rules_hash":binding.rules_hash, "candidate_ids":ids})
	var ranked: Array[Dictionary] = []
	for id: int in ids:
		ranked.append({"id":id, "rank":SurvivalContracts.fingerprint({"selection_hash":seed, "member_id":id})})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id if a.rank == b.rank else a.rank < b.rank)
	var victims: Array[int] = []
	for index: int in range(mini(int(food.food_shortage), ids.size())):
		victims.append(int(ranked[index].id))
	victims.sort()
	var effects: Array[Dictionary] = []
	var allocation: Array[Dictionary] = []
	for id: int in ids:
		var member: Dictionary = SurvivorRoster.member(battle, id)
		var selected: bool = id in victims
		var outcome: String = "STARVATION" if selected else "SURVIVED"
		effects.append({"id":id, "health_before":member.health, "health_after":0.0 if selected else member.health, "outcome":outcome})
		allocation.append({"id":id, "required":1, "provided":0 if selected else 1, "outcome":outcome})
	var ledger: Dictionary = {"ruleset_id":DIRECT, "ration_member_ids":ids, "victim_ids":victims, "selection_hash":seed, "effects":effects}
	var issue: String = SurvivalContracts.ledgers_problem(food, ledger, battle, limits, expected_facility_food)
	return {"error":"", "ledger":ledger, "allocation":allocation} if issue.is_empty() else {"error":issue}
