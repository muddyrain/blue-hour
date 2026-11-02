class_name TraitState
extends RefCounted
## New explicit scope only; old105 null Traits remain strict.

const SCHEMA: int = 106
const FORMAT: String = "BH_TRAIT_V1"
const SCOPE: String = "TRAIT_PILOT"


static func is_state(data: Dictionary) -> bool:
	return SurvivalContracts.integer(data.get("schema_version"),SCHEMA,SCHEMA)


static func is_family(data: Dictionary) -> bool:
	return is_state(data) or TrainingState.is_family(data)


static func initial() -> Dictionary:
	var value: Dictionary = FieldJoinState.initial()
	value.format = FORMAT
	return value


static func snapshot(camp: Dictionary, journey: Dictionary, recruits: Array) -> Dictionary:
	var value: Dictionary = FieldJoinState.snapshot(camp,journey,recruits)
	value.schema_version = SCHEMA
	return value


static func problem(data: Dictionary) -> String:
	if not is_state(data):
		return "TRAIT_FORMAT"
	# GDScript Variant/String comparisons can throw before the shared validator rejects.
	var meta: Variant = data.get("journey")
	if not meta is Dictionary or not SurvivalContracts.integer(meta.get("transaction_version"),TransactionReceipt.VERSION,TransactionReceipt.VERSION) or not meta.get("format") is String or not meta.get("seed") is String or not meta.get("state") is String or not data.get("crew") is Array or not data.get("recruits") is Array:
		return "TRAIT_CONTAINER_TYPES"
	for member: Variant in data.crew:
		if not member is Dictionary or not member.get("condition") is String:
			return "TRAIT_MEMBER_TYPES"
	for record: Variant in data.recruits:
		if not record is Dictionary or record.size()!=6 or not record.has_all(["rescue_id","member_id","recruit_id","settlement_id","joined_at_ms","field_status"]):
			return "TRAIT_RECRUIT_FIELDS"
		if not SurvivalContracts.integer(record.member_id,3,3) or not SurvivalContracts.integer(record.joined_at_ms,10000,RunSave.MAX_COUNTER):
			return "TRAIT_RECRUIT_NUMBERS"
		for key: String in ["rescue_id","recruit_id","settlement_id","field_status"]:
			if not record[key] is String:
				return "TRAIT_RECRUIT_TYPES"
	return RescueState.family_problem(data,true,true,true)
