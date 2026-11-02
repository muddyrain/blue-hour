class_name DeathRules
extends RefCounted
## Explicit pure proposals only. No production caller enables permanent death in this phase.


static func propose(member: Dictionary, health_after: float, cause: String, transaction_id: String, existing: Dictionary = {}, growth: bool = false) -> Dictionary:
	if not SurvivalContracts.identity_problem([member],growth).is_empty() or not is_finite(health_after):
		return {"error":"成员或生命无效"}
	var parts: PackedStringArray = transaction_id.split(":")
	if parts.size() != 2 or parts[0].length() != 32 or not parts[0].is_valid_hex_number(false) or not parts[1].is_valid_int() or int(parts[1]) < 1 or parts[1] != str(int(parts[1])) or cause not in ["BATTLE", "HUNGER", "STARVATION"]:
		return {"error":"死亡来源无效"}
	if health_after < 0.0 or health_after > float(member.health):
		return {"error":"死亡计算不允许复活或负生命"}
	if not existing.is_empty():
		if not problem(existing, parts[0]).is_empty() or int(existing.member_id) != int(member.id) or float(member.health) != 0.0 or health_after != 0.0:
			return {"error":"既有死亡记录冲突"}
		return {"error":"", "health":0.0, "death":existing.duplicate(true), "created":false}
	if float(member.health) <= 0.0:
		return {"error":"旧版零生命需要明确兼容确认"}
	var death: Dictionary = {}
	if health_after == 0.0:
		death = {"death_id":"%s:death:%d" % [parts[0], int(member.id)], "member_id":int(member.id),
			"cause":cause, "transaction_id":transaction_id}
	return {"error":"", "health":health_after, "death":death, "created":not death.is_empty()}


static func problem(record: Dictionary, profile_id: String) -> String:
	if profile_id.length() != 32 or not profile_id.is_valid_hex_number(false):
		return "旅程身份无效"
	if record.size() != 4 or not SurvivalContracts.integer(record.get("member_id"), 1, SurvivalContracts.MAX_ID):
		return "死亡记录字段无效"
	if not record.get("death_id") is String or record.death_id != "%s:death:%d" % [profile_id, int(record.member_id)] or record.get("cause") not in ["BATTLE", "HUNGER", "STARVATION"]:
		return "死亡记录身份或来源无效"
	if not record.get("transaction_id") is String:
		return "死亡事务无效"
	var parts: PackedStringArray = record.transaction_id.split(":")
	if parts.size() != 2 or parts[0] != profile_id or not parts[1].is_valid_int() or int(parts[1]) < 1 or parts[1] != str(int(parts[1])):
		return "死亡事务不属于本旅程"
	return ""


static func journey(crew: Array, records: Array, profile_id: String, growth: bool = false) -> String:
	if not SurvivalContracts.identity_problem(crew,growth).is_empty():
		return "REVIEW_REQUIRED"
	var seen: Array[int] = []
	for record: Variant in records:
		if not record is Dictionary or not problem(record, profile_id).is_empty():
			return "REVIEW_REQUIRED"
		var member: Dictionary = SurvivorRoster.member(crew, int(record.member_id))
		if member.is_empty() or float(member.health) != 0.0 or int(record.member_id) in seen:
			return "REVIEW_REQUIRED"
		seen.append(int(record.member_id))
	var living: int = 0
	for member: Dictionary in crew:
		if float(member.health) > 0.0:
			living += 1
		elif int(member.id) not in seen:
			return "REVIEW_REQUIRED"
	return "ACTIVE" if living > 0 else "FAILED"
