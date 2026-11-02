class_name GrowthState
extends RefCounted
## Explicit successor only. Existing rescue saves remain schema103 with null progression.

const SCHEMA: int = 104
const FORMAT: String = "BH_GROWTH_V1"
const SCOPE: String = "GROWTH_PILOT"


static func is_state(data: Dictionary) -> bool:
	return SurvivalContracts.integer(data.get("schema_version"),SCHEMA,SCHEMA)


static func is_family(data: Dictionary) -> bool:
	return is_state(data) or FieldJoinState.is_family(data)


static func initial() -> Dictionary:
	var value: Dictionary = SurvivalState.initial()
	value.format = FORMAT
	return value


static func snapshot(camp: Dictionary, journey: Dictionary, recruits: Array) -> Dictionary:
	var value: Dictionary = BattleState.snapshot(camp,journey)
	value.schema_version = SCHEMA
	value.origin = {}
	value.recruits = recruits.duplicate(true)
	return value


static func problem(data: Dictionary) -> String:
	if not is_state(data):
		return "GROWTH_FORMAT"
	return RescueState.family_problem(data,true)


static func grant(after: Dictionary, identity: String) -> void:
	RescueState.grant(after,identity)
	GrowthRules.initialize([SurvivorRoster.member(after.crew,3)])
