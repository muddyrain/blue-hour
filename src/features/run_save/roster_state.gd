class_name RosterState
extends RefCounted
## Explicit109 capacity policy. Shared owners retain all history and transaction authority.

const SCHEMA: int = 109
const FORMAT: String = "BH_ROSTER_V1"
const MAX_HISTORY: int = 5 # PROJECT_TEMP, not a verified original-game limit.
const MAX_LIVING: int = 4


static func is_state(data: Dictionary) -> bool:
	return SurvivalContracts.integer(data.get("schema_version"),SCHEMA,SCHEMA)


static func is_family(data: Dictionary) -> bool:
	return is_state(data) or WeaponState.is_family(data)


static func initial(seed: String = "") -> Dictionary:
	var value: Dictionary = RescuePoolState.initial(seed)
	value.format = FORMAT
	return value


static func snapshot(camp: Dictionary, journey: Dictionary, recruits: Array, history: Array = []) -> Dictionary:
	var value: Dictionary = RescuePoolState.snapshot(camp,journey,recruits,history)
	value.schema_version = SCHEMA
	return value


static func problem(data: Dictionary, generated_maps: bool = false) -> String:
	return TrainingState.family_problem(data,true,true,generated_maps) if is_state(data) else "ROSTER_FORMAT"


static func living_count(data: Dictionary) -> int:
	return data.crew.filter(func(member: Dictionary) -> bool: return member.health>0).size()


static func unavailable_reason(data: Dictionary) -> String:
	if living_count(data)>=MAX_LIVING:
		return "存活编制已满（4人）；历史名册%d/5" % data.crew.size()
	return "候选已全部登记；历史名册%d/5" % data.crew.size()
