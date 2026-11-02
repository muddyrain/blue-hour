class_name SurvivalContracts
extends RefCounted
## Value-only P0 contracts. Contract version is independent of the active v5 save format.

const VERSION: int = 1
const MAX_ID: int = SurvivorRoster.MAX_MEMBER_ID
const MAX_JSON_INTEGER: int = 9_007_199_254_740_991
const MISSION_RESULTS: Array[String] = ["EXTRACTED", "FAILED", "ABORTED"]
const JOURNEY_RESULTS: Array[String] = ["ACTIVE", "FAILED", "REVIEW_REQUIRED"]


static func identity_problem(crew: Array, growth: bool = false) -> String:
	if crew.is_empty():
		return "名册不能为空"
	var ids: Array[int] = []
	for value: Variant in crew:
		if not value is Dictionary or not integer(value.get("id"), 1, MAX_ID):
			return "成员身份必须是有效正整数"
		if int(value.id) in ids:
			return "成员身份重复"
		ids.append(int(value.id))
		if not value.get("definition_id") is String or SurvivorRoster.definition_by_id(value.definition_id) == null:
			return "成员模板未知"
		if not number(value.get("health")) or float(value.health) < 0.0 or float(value.health) > (GrowthRules.maximum(value) if growth else 200.0):
			return "成员生命无效"
		if not SurvivorRoster.name_problem(value.get("call_sign")).is_empty():
			return "成员呼号无效"
	return ""


static func participants(crew: Array, equipment: Array = [], require_all_equipment: bool = true, growth: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not identity_problem(crew,growth).is_empty():
		return result
	if not equipment.is_empty() and not WeaponInventory.snapshot_problem(crew,equipment,require_all_equipment).is_empty():
		return result
	for value: Dictionary in crew:
		if float(value.health) <= 0.0:
			continue
		var weapon: String = ""
		for equipped: Dictionary in equipment:
			if int(equipped.member_id) == int(value.id):
				weapon = String(equipped.instance.instance_id)
		result.append({"id":int(value.id), "definition_id":value.definition_id,
			"health_before":float(value.health), "weapon_instance_id":weapon})
	# Save array order must not change actor order, first-shot attribution or formation.
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	return result


static func report_problem(crew: Array, report: Dictionary, growth: bool = false) -> String:
	var problem: String = identity_problem(crew,growth)
	if not problem.is_empty():
		return problem
	if report.get("contract_version") != VERSION or not report.get("participants") is Array or not report.get("member_results") is Array:
		return "出击报告合同或成员列表无效"
	if not report.get("mission_outcome") in MISSION_RESULTS or not report.get("evacuated") is bool:
		return "任务结果无效"
	if bool(report.evacuated) != (report.mission_outcome == "EXTRACTED"):
		return "撤离标志与任务结果冲突"
	var expected: Array[Dictionary] = participants(crew,[],true,growth)
	if expected.is_empty() or report.participants.size() != expected.size() or report.member_results.size() != expected.size():
		return "出击参与者或结果不完整"
	var seen: Array[int] = []
	var weapons: Array[String] = []
	for value: Variant in report.participants:
		if not value is Dictionary or value.size() != 4 or not integer(value.get("id"), 1, MAX_ID):
			return "参与者字段无效"
		var source: Dictionary = SurvivorRoster.member(expected, int(value.id))
		if source.is_empty() or int(value.id) in seen or value.get("definition_id") != source.definition_id:
			return "参与者身份重复或模板错配"
		if not number(value.get("health_before")) or float(value.health_before) != float(source.health_before):
			return "参与者生命与出发快照不符"
		if not value.get("weapon_instance_id") is String:
			return "参与者武器身份无效"
		if not value.weapon_instance_id.is_empty():
			if value.weapon_instance_id in weapons:
				return "参与者重复引用装备"
			weapons.append(value.weapon_instance_id)
		seen.append(int(value.id))
	seen.clear()
	var living: int = 0
	var kills: int = 0
	for value: Variant in report.member_results:
		if not value is Dictionary or value.size() != 4 or not integer(value.get("id"), 1, MAX_ID):
			return "成员结果字段无效"
		var source: Dictionary = SurvivorRoster.member(expected, int(value.id))
		if source.is_empty() or int(value.id) in seen:
			return "成员结果身份未知或重复"
		if not number(value.get("health")) or not number(value.get("damage_received")) or not integer(value.get("kills"), 0, MAX_ID):
			return "成员结果数字无效"
		if not _loss_consistent(float(source.health_before),float(value.health),float(value.damage_received)):
			return "战斗生命与独立伤害账不一致"
		seen.append(int(value.id))
		living += int(float(value.health) > 0.0)
		kills += int(value.kills)
	if report.get("kills") != kills or (report.mission_outcome == "EXTRACTED" and living == 0):
		return "击退总数或撤离存活人数无效"
	return ""


static func hunger_problem(ledger: Dictionary, battle_results: Array, limits: Dictionary = {}) -> String:
	if ledger.get("ruleset_id") == "DIRECT_STARVATION_V1":
		return _direct_hunger_problem(ledger, battle_results, limits)
	if ledger.size() != 3 or not ledger.get("ruleset_id") is String or ledger.ruleset_id.is_empty() or not ledger.get("ration_member_ids") is Array or not ledger.get("effects") is Array:
		return "饥饿账本合同无效"
	var ids: Array[int] = []
	for id: Variant in ledger.ration_member_ids:
		if not integer(id, 1, MAX_ID) or int(id) in ids:
			return "口粮名单身份重复或无效"
		ids.append(int(id))
	if ledger.effects.size() != ids.size():
		return "饥饿效果名单不完整"
	var seen: Array[int] = []
	for value: Variant in ledger.effects:
		if not value is Dictionary or value.size() != 4 or not integer(value.get("id"), 1, MAX_ID):
			return "饥饿效果字段无效"
		var source: Dictionary = SurvivorRoster.member(battle_results, int(value.id))
		if int(value.id) not in ids or int(value.id) in seen or source.is_empty():
			return "饥饿效果身份未知或重复"
		if not number(value.get("health_before")) or not number(value.get("damage")) or not number(value.get("health_after")):
			return "饥饿数字无效"
		# This is a copied fact, so approximate equality must not invent positive HP.
		if float(value.health_before) != float(source.health) or not _loss_consistent(float(value.health_before),float(value.health_after),float(value.damage)):
			return "饥饿与战斗账本不一致"
		seen.append(int(value.id))
	return ""


static func food_problem(ledger: Dictionary) -> String:
	for key: String in ["food_before","food_found","food_stored","food_overflow","food_required","food_consumed","food_shortage","food_after"]:
		if not integer(ledger.get(key),0,MAX_ID):
			return "食物账本数字无效"
	if not ledger.get("ration_member_ids") is Array or not integer(ledger.get("ration_per_member"),1,MAX_ID):
		return "口粮名单或单价无效"
	var seen: Array[int] = []
	for id: Variant in ledger.ration_member_ids:
		if not integer(id,1,MAX_ID) or int(id) in seen:
			return "口粮身份无效或重复"
		seen.append(int(id))
	if int(ledger.food_before) > CampRules.FOOD_LIMIT or int(ledger.food_after) > CampRules.FOOD_LIMIT:
		return "食物容量无效"
	var stored: int = mini(int(ledger.food_found),CampRules.FOOD_LIMIT-int(ledger.food_before))
	var available: int = int(ledger.food_before)+stored
	var required: int = seen.size()*int(ledger.ration_per_member)
	var consumed: int = mini(available,required)
	if ledger.food_stored != stored or ledger.food_overflow != ledger.food_found-stored or ledger.food_required != required or ledger.food_consumed != consumed or ledger.food_shortage != required-consumed or ledger.food_after != available-consumed:
		return "食物账本不守恒"
	return ""


static func ledgers_problem(food: Dictionary, hunger: Dictionary, battle_results: Array, limits: Dictionary = {}) -> String:
	var issue: String = food_problem(food)
	if issue.is_empty():
		issue = hunger_problem(hunger,battle_results,limits)
	if not issue.is_empty():
		return issue
	if hunger.ruleset_id == "DIRECT_STARVATION_V1" and (food.ration_per_member != 1 or hunger.victim_ids.size() != mini(int(food.food_shortage), food.ration_member_ids.size())):
		return "直接饥饿人数与冻结缺口不一致"
	var food_ids: Array = food.ration_member_ids.duplicate()
	var hunger_ids: Array = hunger.ration_member_ids.duplicate()
	food_ids.sort()
	hunger_ids.sort()
	return "" if food_ids == hunger_ids else "食物与饥饿名单不一致"


static func transaction(before: Dictionary, result: Dictionary, identity: String) -> Dictionary:
	if not before.get("profile_id") is String or before.profile_id.length() != 32 or not before.profile_id.is_valid_hex_number(false) or not integer(before.get("settled_sorties"), 0, MAX_ID - 1) or not integer(before.get("schema_version"), 1, MAX_ID) or result.is_empty():
		return {}
	if identity != "%s:%d" % [before.profile_id, int(before.settled_sorties) + 1]:
		return {}
	var base: String = fingerprint(before)
	var after: String = fingerprint(result)
	if base.is_empty() or after.is_empty():
		return {}
	return {"contract_version":VERSION, "transaction_id":identity, "profile_id":before.profile_id,
		"base_schema_version":int(before.schema_version), "base_version":base,
		"result_hash":after, "result":result.duplicate(true)}


static func transaction_problem(before: Dictionary, envelope: Dictionary) -> String:
	if envelope.size() != 7 or not envelope.get("result") is Dictionary or not envelope.get("transaction_id") is String:
		return "结果收据字段无效"
	var expected: Dictionary = transaction(before, envelope.result, envelope.transaction_id)
	if expected.is_empty():
		return "结果收据身份、基础版本或哈希不一致"
	for key: String in ["contract_version","transaction_id","profile_id","base_schema_version","base_version","result_hash"]:
		if not envelope.has(key) or envelope[key] != expected[key]:
			return "结果收据身份、基础版本或哈希不一致"
	return ""


static func fingerprint(value: Dictionary) -> String:
	if not json_value(value):
		return ""
	# JSON readers normalize integers to floats; normalize before hashing on either side.
	var normalized: Variant = JSON.parse_string(JSON.stringify(value, "", true, true))
	if not normalized is Dictionary:
		return ""
	return JSON.stringify(normalized, "", true, true).sha256_text()


static func json_value(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false
	if value == null or value is String or value is StringName or value is bool:
		return true
	if value is int:
		return value >= -MAX_JSON_INTEGER and value <= MAX_JSON_INTEGER
	if value is float:
		return is_finite(value)
	if value is Array:
		for item: Variant in value:
			if not json_value(item,depth+1):
				return false
		return true
	if value is Dictionary:
		var names: Array[String] = []
		for key: Variant in value:
			if not (key is String or key is StringName) or String(key) in names or not json_value(value[key],depth+1):
				return false
			names.append(String(key))
		return true
	return false


static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	return number(value) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _direct_hunger_problem(ledger: Dictionary, battle: Array, limits: Dictionary = {}) -> String:
	if ledger.size() != 5 or not ledger.has_all(["ruleset_id", "ration_member_ids", "victim_ids", "selection_hash", "effects"]) or not ledger.ration_member_ids is Array or not ledger.victim_ids is Array or not ledger.effects is Array:
		return "直接饥饿账本字段无效"
	if not ledger.selection_hash is String or ledger.selection_hash.length() != 64 or not ledger.selection_hash.is_valid_hex_number(false):
		return "直接饥饿选择绑定无效"
	var ids: Array[int] = []
	for id: Variant in ledger.ration_member_ids:
		if not integer(id, 1, MAX_ID) or int(id) in ids:
			return "直接饥饿名单无效"
		ids.append(int(id))
	ids.sort()
	if not TransactionReceipt.same({"v":ids},{"v":ledger.ration_member_ids}):
		return "直接饥饿名单未规范排序"
	var victims: Array[int] = []
	for id: Variant in ledger.victim_ids:
		if not integer(id, 1, MAX_ID) or int(id) not in ids or int(id) in victims:
			return "直接饥饿受害者无效"
		victims.append(int(id))
	victims.sort()
	if not TransactionReceipt.same({"v":victims},{"v":ledger.victim_ids}) or ledger.effects.size() != ids.size():
		return "直接饥饿效果名单不完整"
	var alive: Array[int] = []
	var seen: Array[int] = []
	for row: Variant in battle:
		if not row is Dictionary or not integer(row.get("id"), 1, MAX_ID) or int(row.id) in seen or not number(row.get("health")) or row.health < 0 or row.health > float(limits.get(int(row.id),200.0)):
			return "直接饥饿战后名单无效"
		seen.append(int(row.id))
		if row.health > 0:
			alive.append(int(row.id))
	alive.sort()
	if alive != ids:
		return "直接饥饿必须冻结完整活人名单"
	seen.clear()
	for row: Variant in ledger.effects:
		if not row is Dictionary or row.size() != 4 or not integer(row.get("id"), 1, MAX_ID) or int(row.id) not in ids or int(row.id) in seen:
			return "直接饥饿效果身份无效"
		var before: Dictionary = SurvivorRoster.member(battle, int(row.id))
		var selected: bool = int(row.id) in victims
		if not number(row.get("health_before")) or row.health_before != before.health or not number(row.get("health_after")) or row.health_after != (0.0 if selected else before.health) or row.get("outcome") != ("STARVATION" if selected else "SURVIVED"):
			return "直接饥饿不是伤害或回血"
		seen.append(int(row.id))
	return ""


static func _loss_consistent(previous: float, current: float, damage: float) -> bool:
	if previous < 0.0 or current < 0.0 or current > previous or damage < 0.0 or damage > previous:
		return false
	if damage == 0.0 and current != previous:
		return false
	return is_equal_approx(previous-current,damage)
