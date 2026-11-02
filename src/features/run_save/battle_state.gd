class_name BattleState
extends RefCounted
## Isolated format only. Validation reuses the unchanged v5 public fields without migrating them.

const SCHEMA: int = 101
const FORMAT: String = "BH_BATTLE_SLICE_V1"


static func is_state(data: Dictionary) -> bool:
	return SurvivalContracts.integer(data.get("schema_version"),SCHEMA,SCHEMA)


static func initial() -> Dictionary:
	return {"format":FORMAT,"root_id":RunSave.new_profile_id(),"state":"ACTIVE",
		"active_member_ids":[1,2],"deaths":[],"seed":"NONE"}


static func projected(data: Dictionary) -> Dictionary:
	var value: Dictionary = data.duplicate(true)
	value.erase("journey")
	value.schema_version = 5
	for member: Dictionary in value.get("crew",[]):
		member.condition = "active" if member.health > 0 else "down"
	return value


static func snapshot(camp: Dictionary, journey: Dictionary) -> Dictionary:
	var value: Dictionary = camp.duplicate(true)
	value.schema_version = SCHEMA
	value.journey = journey.duplicate(true)
	value.journey.deaths.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.member_id) < int(b.member_id))
	var active: Array[int] = []
	for member: Dictionary in value.crew:
		member.condition = "active" if member.health > 0 else "dead"
		if member.health > 0:
			active.append(int(member.id))
	active.sort()
	value.journey.active_member_ids = active
	value.journey.state = "FAILED" if active.is_empty() else "ACTIVE"
	return value


static func problem(data: Dictionary) -> String:
	return fields_problem(data, SCHEMA, FORMAT, ["BATTLE"])


static func fields_problem(data: Dictionary, schema: int, format_name: String, causes: Array[String]) -> String:
	if data.get("schema_version") != schema or data.size() != 13 or not data.get("journey") is Dictionary or not SurvivalContracts.json_value(data):
		return "BATTLE_FORMAT"
	var meta: Dictionary = data.journey
	if meta.size() != 6 or not meta.has_all(["format","root_id","state","active_member_ids","deaths","seed"]) or meta.format != format_name or not meta.get("root_id") is String or meta.root_id.length() != 32 or not meta.root_id.is_valid_hex_number(false):
		return "BATTLE_ROOT_OR_VERSION"
	if not meta.deaths is Array or not meta.active_member_ids is Array or meta.seed not in ["NONE","LOW_HP_4_FOOD_12"]:
		return "BATTLE_METADATA"
	if not data.get("crew") is Array:
		return "BATTLE_ROSTER"
	for member: Variant in data.crew:
		if not member is Dictionary or not SurvivalContracts.number(member.get("health")) or member.get("condition") != ("active" if member.health > 0 else "dead"):
			return "BATTLE_LIFE_STATE"
	var common: Dictionary = projected(data)
	var issue: String = RunSave.validate(common)
	if not issue.is_empty():
		return "BATTLE_COMMON:"+issue
	for death: Variant in meta.deaths:
		if not death is Dictionary or not DeathRules.problem(death,data.profile_id).is_empty() or death.cause not in causes or int(death.transaction_id.get_slice(":",1)) > int(data.settled_sorties):
			return "BATTLE_DEATH_HISTORY"
	var state: String = DeathRules.journey(common.crew,meta.deaths,data.profile_id)
	if state == "REVIEW_REQUIRED" or meta.state != state:
		return "BATTLE_JOURNEY_STATE"
	var actual: Dictionary = snapshot(data,meta)
	if SurvivalContracts.fingerprint({"ids":meta.active_member_ids}) != SurvivalContracts.fingerprint({"ids":actual.journey.active_member_ids}):
		return "BATTLE_ACTIVE_IDENTITIES"
	return ""
