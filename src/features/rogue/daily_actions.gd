class_name DailyActions
extends RefCounted
## Dispatch by explicit version; old receipt authentication never uses the new generator.
static func offers(base: Dictionary) -> Array[Dictionary]:
	return WorldActions.offers(base)
static func problem(value: Variant) -> String:
	return WorldActions.problem(value) if value is Dictionary and value.get("version")==2 else RogueActions.problem(value)
static func matches(base: Dictionary, value: Variant) -> bool:
	return WorldActions.matches(base,value) if value is Dictionary and value.get("version")==2 else RogueActions.matches(base,value)
static func supply(value: Dictionary) -> MissionSupply:
	return WorldActions.supply(value) if value.get("version")==2 else RogueActions.supply(value)
static func mission_problem(mission: Dictionary) -> String:
	return WorldActions.mission_problem(mission) if mission.get("generated",{}).get("version")==2 else RogueActions.mission_problem(mission)
