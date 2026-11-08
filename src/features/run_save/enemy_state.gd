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
	if data.get("last_day") is Dictionary and data.last_day.has("task"):
		var issue: String = TaskActions.summary_problem(data.last_day.task)
		if not issue.is_empty() or (data.last_day.task.status=="COMPLETED" and not data.last_day.get("evacuated",false)): return "ENEMY_TASK_SUMMARY"
	var build_issue: String=BuildState.problem(data)
	if not build_issue.is_empty(): return build_issue
	var facility_issue: String = CampFacilities.camp_problem(data)
	if not facility_issue.is_empty(): return facility_issue
	var projected: Dictionary = data.duplicate(true)
	projected.journey.erase("campaign")
	projected.journey.erase("build")
	# Explicit111 extension; older schemas retain their exact last_day whitelist.
	if projected.get("last_day") is Dictionary:
		projected.last_day.erase("task")
		CampFacilities.project_legacy_food(projected.last_day)
	projected.schema_version = WeaponState.SCHEMA
	projected.journey.format = WeaponState.FORMAT
	# Validation context comes from the original campaign, never the projected old shape.
	var weapon_affixes: bool = CampaignRules.weapon_affix_enabled(data.journey.get("campaign"))
	var issue: String = WeaponState.problem(projected, true, data.journey.get("build", {}), weapon_affixes)
	if not issue.is_empty(): return issue
	issue=CampaignState.problem(data)
	return issue if not issue.is_empty() else BuildState.problem(data)
