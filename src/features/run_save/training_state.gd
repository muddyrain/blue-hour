class_name TrainingState
extends RefCounted
## Explicit successor. Its read-only projection preserves the strict106 natural-history contract.

const SCHEMA: int = 107
const FORMAT: String = "BH_TRAINING_V1"


static func is_state(data: Dictionary) -> bool:
	return SurvivalContracts.integer(data.get("schema_version"),SCHEMA,SCHEMA)


static func is_family(data: Dictionary) -> bool:
	return is_state(data) or RescuePoolState.is_family(data)


static func initial() -> Dictionary:
	var meta: Dictionary = TraitState.initial()
	meta.format = FORMAT
	return meta


static func initialize(crew: Array) -> void:
	for member: Dictionary in crew:
		member.growth.training_state = "campfire"


static func snapshot(camp: Dictionary, journey: Dictionary, recruits: Array, history: Array = []) -> Dictionary:
	var value: Dictionary = TraitState.snapshot(camp,journey,recruits)
	value.schema_version = SCHEMA
	value.training = history.duplicate(true)
	return value


static func credits(data: Dictionary, member_id: int, current_day: bool = false) -> int:
	var total: int = 0
	for row: Variant in data.get("training",[]):
		if row is Dictionary and SurvivalContracts.integer(row.get("member_id"),1,5 if RescuePoolState.is_family(data) else 3) and (member_id==0 or row.member_id==member_id) and (not current_day or row.get("day")==data.get("day")):
			total += 1
	return total


static func problem(data: Dictionary) -> String:
	return family_problem(data)


static func family_problem(data: Dictionary, pool: bool = false, roster: bool = false, generated_maps: bool = false, build_context: Dictionary = {}) -> String:
	if not (RosterState.is_state(data) if roster else RescuePoolState.is_state(data) if pool else is_state(data)) or data.size()!=16 or not data.get("profile_id") is String or not data.get("training") is Array or data.training.size()>(50 if roster else 40 if pool else 30) or not data.get("crew") is Array or not data.get("journey") is Dictionary or not data.journey.get("format") is String or data.journey.format!=(RosterState.FORMAT if roster else RescuePoolState.FORMAT if pool else FORMAT) or not SurvivalContracts.integer(data.get("day"),2,RunSave.MAX_COUNTER) or not SurvivalContracts.integer(data.get("food"),0,CampRules.FOOD_LIMIT):
		return "TRAINING_FIELDS"
	var seen: Array[String] = []
	var previous_day: int = 0
	var previous_food: int = 0
	var progress: Dictionary = {}
	for row: Variant in data.training:
		if not row is Dictionary or row.size()!=8 or not row.has_all(["ruleset_id","edit_id","member_id","trait_id","progress_before","day","food_before","base_hash"]):
			return "TRAINING_HISTORY_FIELDS"
		for key: String in ["ruleset_id","edit_id","trait_id","base_hash"]:
			if not row[key] is String:
				return "TRAINING_HISTORY_TYPES"
		if not SurvivalContracts.integer(row.member_id,1,5 if pool else 3) or not SurvivalContracts.integer(row.progress_before,0,9) or not SurvivalContracts.integer(row.day,2,int(data.day)) or not SurvivalContracts.integer(row.food_before,1,CampRules.FOOD_LIMIT) or row.ruleset_id!=TrainingRules.RULESET or row.trait_id!=TraitRules.IDS[TraitRules.role({"id":row.member_id})-1] or not TrainingRules.edit_identity(row.edit_id,String(data.get("profile_id",""))) or row.edit_id in seen or row.base_hash.length()!=64 or not row.base_hash.is_valid_hex_number(false):
			return "TRAINING_HISTORY_IDENTITY"
		if row.day<previous_day or (row.day==previous_day and row.food_before!=previous_food-1) or row.progress_before<int(progress.get(int(row.member_id),-1)):
			return "TRAINING_HISTORY_SEQUENCE"
		seen.append(row.edit_id)
		progress[int(row.member_id)] = int(row.progress_before)+1
		previous_day = int(row.day)
		previous_food = int(row.food_before)
	if previous_day==data.day and data.food!=previous_food-1:
		return "TRAINING_FOOD_AFTER"
	var projected: Dictionary = data.duplicate(true)
	projected.erase("training")
	projected.schema_version = RosterState.SCHEMA if roster else RescuePoolState.SCHEMA if pool else TraitState.SCHEMA
	projected.journey.format = RosterState.FORMAT if roster else RescuePoolState.FORMAT if pool else TraitState.FORMAT
	projected.food += credits(data,0,true)
	if data.day==2 and projected.food!=RunSave.DefaultRules.initial_food:
		return "TRAINING_INITIAL_FOOD"
	for member: Variant in projected.crew:
		if not member is Dictionary or not SurvivalContracts.integer(member.get("id"),1,5 if pool else 3) or not member.get("growth") is Dictionary or not member.growth.get("training_state") is String or member.growth.training_state!="campfire":
			return "TRAINING_MEMBER"
		var bought: int = credits(data,int(member.id))
		if bought>10 or not TraitRules.member_problem(member,bought,pool).is_empty() or member.growth.trait.progress<int(progress.get(int(member.id),0)):
			return "TRAINING_MEMBER_PROGRESS"
		member.growth.trait.progress -= bought
		member.growth.trait.level = TraitRules.level_for(int(member.growth.trait.progress))
		member.growth.training_state = "unavailable"
	var issue: String = RescuePoolState.natural_problem(projected,roster,generated_maps,build_context) if pool else TraitState.problem(projected)
	if not issue.is_empty():
		return issue
	for row: Dictionary in data.training:
		if SurvivorRoster.member(data.crew,int(row.member_id)).is_empty():
			return "TRAINING_UNKNOWN_MEMBER"
		var recruit: Dictionary = {}
		for entry: Dictionary in data.recruits:
			if entry.member_id==row.member_id:
				recruit = entry
		if row.member_id>2 and (recruit.is_empty() or recruit.field_status!="RETURNED" or row.day<int(recruit.settlement_id.get_slice(":",1))+2):
			return "TRAINING_BEFORE_RECRUIT"
		for death: Dictionary in data.journey.deaths:
			if death.member_id==row.member_id and row.day>int(death.transaction_id.get_slice(":",1))+1:
				return "TRAINING_AFTER_DEATH"
	return ""
