class_name CampEdit
extends RefCounted
## Pure confirmation proposals reuse existing camp rules, never advance a sortie or change HP.


static func propose(before: Dictionary, request: Dictionary) -> Dictionary:
	if request.size() != 3 or not request.get("kind") is String or not request.get("value") is String or not SurvivalContracts.integer(request.get("member_id"), 0, SurvivalContracts.MAX_ID):
		return {}
	if RescueState.is_family(before):
		if not SurvivalState.extended_problem(before).is_empty() or before.journey.state != "ACTIVE" or (request.kind not in ["build_slot","power_slot","power_equip"] and request.member_id > 0 and not WeaponInventory._living(before,int(request.member_id))):
			return {}
		return _propose_valid(before,request)
	if SurvivalState.is_extended(before):
		if not SurvivalState.extended_problem(before).is_empty() or before.journey.state != "ACTIVE":
			return {}
		if request.member_id > 0 and SurvivorRoster.member(before.crew,int(request.member_id)).get("health",0) <= 0:
			return {}
		var changed: Dictionary = propose(SurvivalState.legacy(before),request)
		return SurvivalState.rebuild(before,changed,before.journey) if not changed.is_empty() else {}
	if not RunSave.validate(before).is_empty() or before.schema_version != 5:
		return {}
	return _propose_valid(before,request)


static func _propose_valid(before: Dictionary, request: Dictionary) -> Dictionary:
	var member_id: int = int(request.member_id)
	match request.kind:
		"power_slot":
			return PowerState.equip(before,request.value) if member_id==0 else {}
		"power_equip":
			return PowerState.equip_progression(before, member_id, request.value)
		"power_invest":
			return PowerState.invest(before, request.value) if member_id == 0 else {}
		"build_slot":
			return BuildState.equip(before,member_id,request.value)
		"facility":
			return CampFacilities.build(before, request.value) if member_id == 0 else {}
		WorkshopV1.EXTENDED, WorkshopV1.QUICK:
			return WorkshopV1.install(before, request.value, request.kind) if member_id == 0 else {}
		"train_trait":
			return TrainingRules.propose(before,request)
		"rename":
			if not SurvivorRoster.name_problem(request.value).is_empty() or SurvivorRoster.member(before.crew, member_id).is_empty():
				return {}
			var after: Dictionary = before.duplicate(true)
			SurvivorRoster.member(after.crew, member_id).call_sign = request.value
			return after
		"equip":
			if WeaponInventory.owner(before, request.value) == member_id and member_id > 0:
				return before.duplicate(true)
			return WeaponInventory.equip(before, member_id, request.value).get("data", {})
		"repair":
			if member_id != 0:
				return {}
			return WeaponInventory.repair(before, request.value).get("data", {})
	return {}


static func record(before: Dictionary, request: Dictionary, identity: String, previous: Dictionary) -> Dictionary:
	if request.get("kind") is String and request.kind=="train_trait":
		var intent: Dictionary = TrainingRules.intent_for(request)
		if not intent.get("edit_id") is String or intent.edit_id!=identity:
			return {}
	var after: Dictionary = propose(before, request)
	if after.is_empty() or TransactionReceipt.same(before, after) or not TransactionReceipt.camp_problem(after).is_empty():
		return {}
	var value: Dictionary = TransactionReceipt.registration(before, previous.root_id)
	value.revision = previous.revision + 1
	value.phase = "EDIT_READY"
	value.transaction_id = identity
	value.deaths = previous.deaths.duplicate(true)
	value.rules = {"ruleset_id":"camp-edit", "data_version":1, "request":request.duplicate(true)}
	value.envelope = {"before_hash":SurvivalContracts.fingerprint(before),
		"after_hash":SurvivalContracts.fingerprint(after), "result":after}
	return value


static func problem(value: Dictionary) -> String:
	var expected: Array[Dictionary] = SurvivalContracts.participants(value.base.crew, WeaponInventory.snapshot(value.base),true,GrowthState.is_family(value.base))
	if not value.participants is Array or not TransactionReceipt.same({"v":expected}, {"v":value.participants}) or not value.health is Array or not value.deaths is Array or not value.envelope is Dictionary or value.camp_key != "":
		return "CAMP_RECORD_FIELDS"
	var health: Array[Dictionary] = []
	for row: Dictionary in expected:
		health.append({"id":row.id, "health":row.health_before})
	if not TransactionReceipt.same({"v":health}, {"v":value.health}):
		return "CAMP_EDIT_HEALTH_CHANGED"
	var ids: Array[int] = []
	for checkpoint: Variant in value.deaths:
		if not checkpoint is Dictionary or checkpoint.size() != 2 or not checkpoint.get("death") is Dictionary or not SurvivalContracts.integer(checkpoint.death.get("member_id"),1,SurvivalContracts.MAX_ID) or not SurvivalContracts.number(checkpoint.get("health_before")) or checkpoint.health_before <= 0 or checkpoint.health_before > (GrowthRules.maximum(SurvivorRoster.member(value.base.crew,int(checkpoint.death.get("member_id",0)))) if GrowthState.is_family(value.base) else 200.0):
			return "CAMP_DEATH_FIELDS"
		var death: Dictionary = checkpoint.death
		var member: Dictionary = SurvivorRoster.member(value.base.crew, int(death.get("member_id", 0)))
		if not DeathRules.problem(death, value.base.profile_id).is_empty() or member.is_empty() or member.health != 0 or int(death.member_id) in ids:
			return "CAMP_DEATH_HISTORY"
		ids.append(int(death.member_id))
	if value.phase == "CAMP_REGISTERED":
		var opening_issue: String = OpeningBuild.registration_problem(value.base)
		if not opening_issue.is_empty():
			return opening_issue
		var power_issue: String = PowerState.registration_problem(value.base)
		if not power_issue.is_empty():
			return power_issue
		return "" if value.transaction_id == "" and value.deaths.is_empty() and value.envelope.is_empty() and TransactionReceipt.same(value.rules, {"ruleset_id":"camp-registration", "data_version":1}) else "REGISTRATION_FIELDS"
	var parts: PackedStringArray = String(value.transaction_id).split(":")
	if parts.size() != 3 or parts[0] != value.base.profile_id or parts[1] != "edit" or parts[2].length() != 32 or not parts[2].is_valid_hex_number(false):
		return "EDIT_ID"
	if not value.rules is Dictionary or value.rules.size() != 3 or value.rules.get("ruleset_id") != "camp-edit" or value.rules.get("data_version") != 1 or not value.rules.get("request") is Dictionary:
		return "EDIT_RULES"
	if value.rules.request.get("kind") is String and value.rules.request.kind=="train_trait":
		var intent: Dictionary = TrainingRules.intent_for(value.rules.request)
		if not intent.get("edit_id") is String or intent.edit_id!=value.transaction_id:
			return "TRAINING_EDIT_ID_CONFLICT"
	var after: Dictionary = propose(value.base, value.rules.request)
	if after.is_empty() or TransactionReceipt.same(after, value.base) or value.envelope.size() != 3 or value.envelope.get("before_hash") != SurvivalContracts.fingerprint(value.base) or value.envelope.get("after_hash") != SurvivalContracts.fingerprint(after) or not value.envelope.get("result") is Dictionary or not TransactionReceipt.same(value.envelope.result, after):
		return "EDIT_FROZEN_RESULT"
	return ""
