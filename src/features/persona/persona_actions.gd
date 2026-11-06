class_name PersonaActions
extends RefCounted
## Explicit projection keeps mission, map, reward, rescue and power randomness unchanged.
static func legacy(value: Dictionary) -> Dictionary:
	var old: Dictionary=value.duplicate(true)
	old.erase("persona")
	return old

static func upgrade(value: Dictionary, facts: Dictionary) -> Dictionary:
	var result: Dictionary=value.duplicate(true)
	result.persona={"facts":facts.duplicate(true),"policy":SurvivorPersona.policy()}
	return result

static func offers(base: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for old: Dictionary in PowerActions.offers(base): result.append(upgrade(old,base.journey.build.persona))
	return result

static func problem(value: Variant) -> String:
	if not value is Dictionary or not value.get("persona") is Dictionary or value.persona.size()!=2 or not value.persona.has_all(["facts","policy"]) or not value.get("seed") is String or not value.persona.get("policy") is Dictionary: return "PERSONA_ACTION_FIELDS"
	var issue: String=SurvivorPersona.problem(value.persona.facts,value.seed)
	if not issue.is_empty(): return issue
	if not TransactionReceipt.same(value.persona.policy,SurvivorPersona.policy()): return "PERSONA_ACTION_POLICY"
	return PowerActions.problem(legacy(value))

static func matches(base: Dictionary, value: Variant) -> bool:
	if not PersonaState.enabled(base) or not problem(value).is_empty(): return false
	for offer: Dictionary in offers(base):
		if TransactionReceipt.same(value,offer): return true
	return false

static func supply(value: Dictionary) -> MissionSupply:
	assert(problem(value).is_empty())
	var result: MissionSupply=PowerActions.supply(legacy(value))
	result.generated=value.duplicate(true)
	return result

static func mission_problem(mission: Dictionary) -> String:
	var issue: String=problem(mission.get("generated"))
	if not issue.is_empty(): return issue
	var old: Dictionary=mission.duplicate(true)
	old.generated=legacy(mission.generated)
	return PowerActions.mission_problem(old)
