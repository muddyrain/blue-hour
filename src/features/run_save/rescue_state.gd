class_name RescueState
extends RefCounted
## Explicit MVP format. Old two-member formats keep their own validators.

const SCHEMA: int = 103
const FORMAT: String = "BH_RESCUE_V1"
const SCOPE: String = "SURVIVAL_RESCUE_ISOLATED"
const TARGET: String = "market-first-contact"


static func is_state(data: Dictionary) -> bool:
	return SurvivalContracts.integer(data.get("schema_version"),SCHEMA,SCHEMA)


static func initial() -> Dictionary:
	var meta: Dictionary = SurvivalState.initial()
	meta.format = FORMAT
	return meta


static func snapshot(camp: Dictionary, journey: Dictionary, recruits: Array) -> Dictionary:
	var value: Dictionary = BattleState.snapshot(camp,journey)
	value.schema_version = SCHEMA
	value.origin = {}
	value.recruits = recruits.duplicate(true)
	return value


static func is_family(data: Dictionary) -> bool:
	return is_state(data) or GrowthState.is_family(data)


static func problem(data: Dictionary) -> String:
	return family_problem(data)


static func family_problem(data: Dictionary, growth: bool = false, field: bool = false, traits: bool = false) -> String:
	if data.get("schema_version") != (TraitState.SCHEMA if traits else (FieldJoinState.SCHEMA if field else (GrowthState.SCHEMA if growth else SCHEMA))) or data.size() != 15 or not data.has_all(FrozenSettlement.STATE_KEYS) or not data.get("profile_id") is String or data.profile_id.length() != 32 or not data.profile_id.is_valid_hex_number(false) or not SurvivalContracts.integer(data.get("settled_sorties"),0,RunSave.MAX_COUNTER-2) or not data.get("journey") is Dictionary or not data.get("origin") is Dictionary or not data.origin.is_empty() or not data.get("recruits") is Array or data.recruits.size() > 1 or not data.get("crew") is Array:
		return "RESCUE_FIELDS"
	var meta: Dictionary = data.journey
	if meta.size() != 7 or not meta.has_all(["format","transaction_version","root_id","seed","deaths","active_member_ids","state"]) or meta.get("format") != (TraitState.FORMAT if traits else (FieldJoinState.FORMAT if field else (GrowthState.FORMAT if growth else FORMAT))) or meta.get("transaction_version") != TransactionReceipt.VERSION or not meta.get("root_id") is String or meta.root_id.length() != 32 or not meta.root_id.is_valid_hex_number(false) or meta.get("seed") != "NONE" or not meta.get("deaths") is Array or not meta.get("active_member_ids") is Array:
		return "RESCUE_JOURNEY"
	var ids: Array[int] = []
	for member: Variant in data.crew:
		if traits and (not member is Dictionary or not TraitRules.member_problem(member).is_empty()):
			return "TRAIT_MEMBER"
		if growth and (not member is Dictionary or not GrowthRules.member_problem(member).is_empty()):
			return "GROWTH_MEMBER"
		if not member is Dictionary or not SurvivalContracts.integer(member.get("id"),1,3) or int(member.id) in ids or member.get("definition_id") != "crew_%d" % int(member.id) or not SurvivalContracts.number(member.get("health")) or member.health < 0 or member.health > (GrowthRules.maximum(member) if growth else 200.0) or member.get("condition") != ("active" if member.health > 0 else "dead"):
			return "RESCUE_MEMBER"
		ids.append(int(member.id))
	ids.sort()
	if ids != ([1,2] if data.recruits.is_empty() else [1,2,3]):
		return "RESCUE_MEMBER_PROVENANCE"
	if not data.recruits.is_empty():
		var record: Variant = data.recruits[0]
		if not record is Dictionary or record.size() != (6 if field else 4) or record.get("rescue_id") != TARGET or record.get("member_id") != 3 or record.get("recruit_id") != data.profile_id + ":recruit:3" or not record.get("settlement_id") is String:
			return "RESCUE_RECRUIT_RECORD"
		var count: String = record.settlement_id.get_slice(":",1)
		if record.settlement_id.get_slice_count(":") != 2 or record.settlement_id.get_slice(":",0) != data.profile_id or not count.is_valid_int() or not SurvivalContracts.integer(int(count),1,int(data.settled_sorties)) or record.settlement_id != "%s:%d" % [data.profile_id,int(count)]:
			return "RESCUE_RECRUIT_IDENTITY"
		if WeaponInventory.find(data,weapon(data.profile_id).instance_id).is_empty():
			return "RESCUE_UNIQUE_EQUIPMENT_MISSING"
	if field and not FieldJoinRules.camp_record_problem(data).is_empty():
		return "FIELD_JOIN_CAMP_RECORD"
	for death: Variant in meta.deaths:
		if not death is Dictionary or not DeathRules.problem(death,data.profile_id).is_empty() or death.cause not in ["BATTLE","STARVATION"] or int(death.transaction_id.get_slice(":",1)) > int(data.settled_sorties):
			return "RESCUE_DEATH_HISTORY"
		if int(death.member_id) == 3 and (data.recruits.is_empty() or (int(death.transaction_id.get_slice(":",1)) < int(data.recruits[0].settlement_id.get_slice(":",1)) if field and data.recruits[0].field_status == "LOST" else int(death.transaction_id.get_slice(":",1)) <= int(data.recruits[0].settlement_id.get_slice(":",1)))):
			return "RESCUE_DEATH_BEFORE_JOIN"
	if meta.state != DeathRules.journey(data.crew,meta.deaths,data.profile_id,growth):
		return "RESCUE_LIFE_HISTORY"
	var actual: Dictionary = TraitState.snapshot(data,meta,data.recruits) if traits else FieldJoinState.snapshot(data,meta,data.recruits) if field else (GrowthState.snapshot(data,meta,data.recruits) if growth else snapshot(data,meta,data.recruits))
	if not TransactionReceipt.same({"v":actual.journey.active_member_ids},{"v":meta.active_member_ids}):
		return "RESCUE_ACTIVE_IDENTITIES"
	var common: Dictionary = data.duplicate(true)
	for member: Dictionary in common.crew:
		member.condition = "active" if member.health > 0 else "down"
	return FrozenSettlement.common_problem(common)


static func weapon(profile: String) -> Dictionary:
	return {"instance_id":profile+":recruit:3:carbine","weapon_id":"carbine","condition":"ready","origin":"rescue-first-contact","acquired_sortie":""}


static func grant(after: Dictionary, identity: String) -> void:
	var members: Array[Dictionary] = [{"id":3,"health":200.0}]
	SurvivorRoster.initialize(members)
	after.crew.append(members[0])
	after.recruits.append({"rescue_id":TARGET,"member_id":3,"recruit_id":after.profile_id+":recruit:3","settlement_id":identity})
	after.weapons.append(weapon(after.profile_id))
	after.loadout.append({"member_id":3,"instance_id":weapon(after.profile_id).instance_id})


static func transition_problem(before: Dictionary, after: Dictionary, report: Dictionary) -> String:
	if not report.get("evacuated") is bool or not report.get("sortie_id") is String or not report.get("rescue") is Dictionary or not RescueTarget.fact_problem(report.rescue).is_empty():
		return "RESCUE_REPORT"
	var granted: bool = report.evacuated and report.rescue.status == "RESCUED" and before.recruits.is_empty()
	if granted:
		var expected: Dictionary = before.duplicate(true)
		if GrowthState.is_state(before):
			GrowthState.grant(expected,report.sortie_id)
		else:
			grant(expected,report.sortie_id)
		if not TransactionReceipt.same({"v":after.recruits},{"v":expected.recruits}) or not TransactionReceipt.same(SurvivorRoster.member(after.crew,3),SurvivorRoster.member(expected.crew,3)) or not TransactionReceipt.same(WeaponInventory.find(after,weapon(before.profile_id).instance_id),weapon(before.profile_id)):
			return "RESCUE_GRANT_MISMATCH"
	elif not TransactionReceipt.same({"v":before.recruits},{"v":after.recruits}) or before.crew.size() != after.crew.size():
		return "RESCUE_UNEARNED_MEMBER"
	return ""
