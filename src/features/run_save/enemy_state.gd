class_name EnemyState
extends RefCounted
## Explicit111 policy adapter; the original transaction owners remain authoritative.

const SCHEMA: int = 111
const FORMAT: String = "BH_ENEMY_PILOT_V1"


static func is_state(data: Dictionary) -> bool:
	return SurvivalContracts.integer(data.get("schema_version"),SCHEMA,SCHEMA)


static func initial(seed: String = "") -> Dictionary:
	var value: Dictionary = WeaponState.initial(seed)
	value.format = FORMAT
	return value


static func snapshot(camp: Dictionary, journey: Dictionary, recruits: Array, history: Array = []) -> Dictionary:
	var value: Dictionary = WeaponState.snapshot(camp,journey,recruits,history)
	value.schema_version = SCHEMA
	return value


static func problem(data: Dictionary) -> String:
	if not is_state(data) or not data.get("journey") is Dictionary or data.journey.get("format")!=FORMAT:
		return "ENEMY_PILOT_FORMAT"
	var projected: Dictionary = data.duplicate(true)
	projected.schema_version = WeaponState.SCHEMA
	projected.journey.format = WeaponState.FORMAT
	return WeaponState.problem(projected)
