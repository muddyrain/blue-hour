class_name FieldJoinState
extends RefCounted
## Explicit successor; old growth/rescue camps keep their original contracts.

const SCHEMA: int = 105
const FORMAT: String = "BH_FIELD_JOIN_V1"
const SCOPE: String = "FIELD_JOIN_PILOT"


static func is_state(data: Dictionary) -> bool:
	return SurvivalContracts.integer(data.get("schema_version"),SCHEMA,SCHEMA)


static func is_family(data: Dictionary) -> bool:
	return is_state(data) or TraitState.is_family(data)


static func initial() -> Dictionary:
	var value: Dictionary = GrowthState.initial()
	value.format = FORMAT
	return value


static func snapshot(camp: Dictionary, journey: Dictionary, recruits: Array) -> Dictionary:
	var value: Dictionary = GrowthState.snapshot(camp,journey,recruits)
	value.schema_version = SCHEMA
	return value


static func problem(data: Dictionary) -> String:
	return RescueState.family_problem(data,true,true) if is_state(data) else "FIELD_JOIN_FORMAT"
