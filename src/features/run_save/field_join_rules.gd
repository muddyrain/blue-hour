class_name FieldJoinRules
extends RefCounted
## Membership facts extend the existing action; the departure base/token never change.


static func policy() -> Dictionary:
	return {"policy_id":"FIELD_JOIN_V1","source":"PROJECT_TEMP","first_meal":"DEPARTURE_SURVIVORS_ONLY"}


static func event(base: Dictionary, identity: String, at_ms: int) -> Dictionary:
	if RescuePoolState.is_family(base):
		var id: int = RescuePoolState.choice(base,identity)
		return {"join_id":"%s:join:%d" % [identity,id],"rescue_id":RescueState.TARGET,"member_id":id,
			"at_ms":at_ms,"instance_id":RescuePoolState.weapon(base.profile_id,id).instance_id}
	return {"join_id":identity+":join:3","rescue_id":RescueState.TARGET,"member_id":3,
		"at_ms":at_ms,"instance_id":RescueState.weapon(base.profile_id).instance_id}


static func problem(value: Variant, base: Dictionary, identity: String) -> String:
	if not value is Array or value.size() > 1:
		return "FIELD_JOIN_EVENTS"
	if value.is_empty():
		return ""
	var row: Variant = value[0]
	if (RescuePoolState.available(base).is_empty() if RescuePoolState.is_family(base) else not base.recruits.is_empty()) or not row is Dictionary or not SurvivalContracts.integer(row.get("at_ms"),10000,RunSave.MAX_COUNTER):
		return "FIELD_JOIN_SOURCE"
	return "" if TransactionReceipt.same(row,event(base,identity,int(row.at_ms))) else "FIELD_JOIN_IDENTITY"


static func record(base: Dictionary, row: Dictionary, status: String) -> Dictionary:
	if RescuePoolState.is_family(base):
		var id: int = int(row.member_id)
		return {"rescue_id":RescueState.TARGET,"member_id":id,"recruit_id":"%s:recruit:%d" % [base.profile_id,id],
			"settlement_id":String(row.join_id).trim_suffix(":join:%d" % id),"joined_at_ms":row.at_ms,"field_status":status}
	return {"rescue_id":RescueState.TARGET,"member_id":3,"recruit_id":base.profile_id+":recruit:3",
		"settlement_id":String(row.join_id).trim_suffix(":join:3"),"joined_at_ms":row.at_ms,"field_status":status}


static func action_base(base: Dictionary, joins: Array) -> Dictionary:
	var value: Dictionary = base.duplicate(true)
	if RescuePoolState.is_family(base):
		if not joins.is_empty():
			RescuePoolState.grant(value,int(joins[0].member_id))
			value.recruits.append(record(base,joins[0],"RETURNED"))
		return value
	if not joins.is_empty():
		# Transient action context, never published as a camp or used to replace its base hash.
		GrowthState.grant(value,String(joins[0].join_id).trim_suffix(":join:3"))
		if TraitState.is_family(base):
			TraitRules.initialize([SurvivorRoster.member(value.crew,3)])
		if TrainingState.is_state(base):
			TrainingState.initialize([SurvivorRoster.member(value.crew,3)])
		value.recruits = [record(base,joins[0],"RETURNED")]
	return value


static func context(receipt: Dictionary) -> Dictionary:
	return action_base(receipt.base,receipt.joins) if FieldJoinState.is_family(receipt.base) else receipt.base


static func participants(receipt: Dictionary) -> Array[Dictionary]:
	var base: Dictionary = context(receipt)
	return SurvivalContracts.participants(base.crew,WeaponInventory.snapshot(base),true,GrowthState.is_family(base))


static func meal_members(rows: Array, departure: Dictionary) -> Array:
	if not FieldJoinState.is_family(departure):
		return rows
	return rows.filter(func(row: Dictionary) -> bool: return not SurvivorRoster.member(departure.crew,int(row.id)).is_empty())


static func report_problem(base: Dictionary, report: Dictionary, joins: Array) -> String:
	if not report.get("rescue") is Dictionary or not RescueTarget.fact_problem(report.rescue).is_empty() or not report.get("member_results") is Array or not report.get("xp_inputs") is Dictionary or not report.xp_inputs.get("events") is Array or not SurvivalContracts.number(report.get("elapsed")) or not report.get("evacuated") is bool:
		return "FIELD_JOIN_REPORT_FIELDS"
	var issue: String = problem(report.get("field_joins"),base,String(report.get("sortie_id","")))
	if not issue.is_empty() or not TransactionReceipt.same({"v":report.field_joins},{"v":joins}):
		return "FIELD_JOIN_REPORT"
	if joins.is_empty():
		return "FIELD_JOIN_MISSING" if report.rescue.status == "RESCUED" else ""
	var joined: Dictionary = joins[0]
	if report.elapsed*1000.0+0.000001 < joined.at_ms:
		return "FIELD_JOIN_TIME"
	for row: Variant in report.xp_inputs.events:
		if not row is Dictionary or not SurvivalContracts.integer(row.get("member_id"),1,SurvivalContracts.MAX_ID) or not SurvivalContracts.integer(row.get("at_ms"),0,RunSave.MAX_COUNTER):
			return "FIELD_JOIN_XP_EVENT"
		if row.member_id == joined.member_id and row.at_ms < joined.at_ms:
			return "FIELD_JOIN_EARLY_XP"
	for row: Variant in report.member_results:
		if not row is Dictionary or not SurvivalContracts.integer(row.get("id"),1,SurvivalContracts.MAX_ID) or not SurvivalContracts.number(row.get("health")):
			return "FIELD_JOIN_MEMBER_RESULT"
	var member: Dictionary = SurvivorRoster.member(report.member_results,int(joined.member_id))
	if member.is_empty() or report.rescue.status != ("RESCUED" if report.evacuated and member.health > 0 else "FAILED"):
		return "FIELD_JOIN_OUTCOME"
	return ""


static func transition_problem(before: Dictionary, after: Dictionary, report: Dictionary) -> String:
	if not report.get("field_joins") is Array:
		return "FIELD_JOIN_REPORT"
	var issue: String = report_problem(before,report,report.field_joins)
	if not issue.is_empty():
		return issue
	var expected: Array = before.recruits.duplicate(true)
	if not report.field_joins.is_empty():
		var member: Dictionary = SurvivorRoster.member(after.crew,int(report.field_joins[0].member_id))
		expected.append(record(before,report.field_joins[0],"RETURNED" if report.evacuated and member.get("health",0) > 0 else "LOST"))
	return "" if TransactionReceipt.same({"v":expected},{"v":after.recruits}) and after.crew.size() == before.crew.size()+report.field_joins.size() else "FIELD_JOIN_CAMP_PROVENANCE"


static func camp_record_problem(data: Dictionary) -> String:
	if data.recruits.is_empty():
		return ""
	var row: Variant = data.recruits[0]
	if not row is Dictionary or row.size() != 6 or not row.has_all(["rescue_id","member_id","recruit_id","settlement_id","joined_at_ms","field_status"]) or row.field_status not in ["RETURNED","LOST"] or not SurvivalContracts.integer(row.joined_at_ms,10000,RunSave.MAX_COUNTER):
		return "FIELD_JOIN_CAMP_RECORD"
	if row.field_status == "LOST":
		var member: Dictionary = SurvivorRoster.member(data.crew,3)
		if member.is_empty() or member.health != 0 or not data.journey.deaths.any(func(death: Variant) -> bool: return death is Dictionary and death.get("member_id") == 3 and death.get("transaction_id") == row.settlement_id and death.get("cause") == "BATTLE"):
			return "FIELD_JOIN_LOST_HISTORY"
	return ""
