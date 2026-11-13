class_name DailyActions
extends RefCounted
## Current journey dispatch; source projections remain with their action validators.
static func offers(base: Dictionary) -> Array[Dictionary]:
	if CampaignRules.is_investigation(base.get("journey", {}).get("campaign")):
		return InvestigationActions.offers(base)
	return ExplorationActions.offers(base)
static func problem(value: Variant) -> String:
	return ExplorationActions.problem(value)
static func matches(base: Dictionary, value: Variant) -> bool:
	if CampaignRules.is_investigation(base.get("journey", {}).get("campaign")):
		return InvestigationActions.matches(base,value)
	if value is Dictionary and (value.has("investigation") or value.has("mission_policy")):
		return false
	return ExplorationActions.matches(base,value)
static func supply(value: Dictionary) -> MissionSupply:
	return ExplorationActions.supply(value)
static func mission_problem(mission: Dictionary) -> String:
	return ExplorationActions.mission_problem(mission)
