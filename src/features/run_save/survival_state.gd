class_name SurvivalState
extends RefCounted
## Schema102 is explicit and separate; schema101 remains battle-only.

const SCHEMA: int = 102
const FORMAT: String = "BH_SURVIVAL_V1"
const ORIGIN_KEYS: Array[String] = ["policy_id", "migration_id", "source_path_key", "target_path_key", "source_choice",
	"source_main_hash", "source_backup_hash", "selected_hash", "source_state_hash", "source_settled_sorties", "root_id", "target_schema"]


static func is_state(data: Dictionary) -> bool:
	return SurvivalContracts.integer(data.get("schema_version"),SCHEMA,SCHEMA)


static func is_extended(data: Dictionary) -> bool:
	return is_state(data) or BattleState.is_state(data) or RescueState.is_family(data)


static func is_survival(data: Dictionary) -> bool:
	return is_state(data) or RescueState.is_family(data)


static func initial() -> Dictionary:
	var meta: Dictionary = BattleState.initial()
	meta.format = FORMAT
	meta.transaction_version = TransactionReceipt.VERSION
	return meta


static func legacy(data: Dictionary) -> Dictionary:
	var value: Dictionary = BattleState.projected(data)
	value.erase("origin")
	value.erase("recruits")
	return value


static func snapshot(camp: Dictionary, journey: Dictionary, origin: Dictionary = {}) -> Dictionary:
	var value: Dictionary = BattleState.snapshot(camp, journey)
	value.schema_version = SCHEMA
	value.origin = origin.duplicate(true)
	return value


static func rebuild(before: Dictionary, camp: Dictionary, journey: Dictionary) -> Dictionary:
	if EnemyState.is_state(before):
		return EnemyState.snapshot(camp,journey,camp.get("recruits",before.recruits),before.training)
	if WeaponState.is_state(before):
		return WeaponState.snapshot(camp,journey,camp.get("recruits",before.recruits),before.training)
	if RosterState.is_state(before):
		return RosterState.snapshot(camp,journey,camp.get("recruits",before.recruits),before.training)
	if RescuePoolState.is_family(before):
		return RescuePoolState.snapshot(camp,journey,camp.get("recruits",before.recruits),before.training)
	if TrainingState.is_state(before):
		return TrainingState.snapshot(camp,journey,camp.get("recruits",before.recruits),before.training)
	if TraitState.is_state(before):
		return TraitState.snapshot(camp,journey,camp.get("recruits",before.recruits))
	if FieldJoinState.is_state(before):
		return FieldJoinState.snapshot(camp,journey,camp.get("recruits",before.recruits))
	if GrowthState.is_state(before):
		return GrowthState.snapshot(camp,journey,camp.get("recruits",before.recruits))
	if RescueState.is_state(before):
		return RescueState.snapshot(camp,journey,camp.get("recruits",before.recruits))
	return snapshot(camp, journey, before.origin) if is_state(before) else BattleState.snapshot(camp, journey)


static func extended_problem(data: Dictionary) -> String:
	if RescuePoolState.is_family(data):
		return RescuePoolState.problem(data)
	if TrainingState.is_state(data):
		return TrainingState.problem(data)
	if TraitState.is_state(data):
		return TraitState.problem(data)
	if FieldJoinState.is_state(data):
		return FieldJoinState.problem(data)
	if GrowthState.is_state(data):
		return GrowthState.problem(data)
	if RescueState.is_state(data):
		return RescueState.problem(data)
	return problem(data) if is_state(data) else BattleState.problem(data)


static func problem(data: Dictionary) -> String:
	if not is_state(data) or data.size() != 14 or not data.get("origin") is Dictionary or not data.get("journey") is Dictionary:
		return "SURVIVAL_FORMAT"
	if data.journey.size() != 7 or data.journey.get("transaction_version") != TransactionReceipt.VERSION:
		return "SURVIVAL_TRANSACTION_VERSION"
	var common: Dictionary = data.duplicate(true)
	common.erase("origin")
	common.journey.erase("transaction_version")
	var issue: String = BattleState.fields_problem(common, SCHEMA, FORMAT, ["BATTLE", "STARVATION"])
	if not issue.is_empty():
		return issue
	var origin: Dictionary = data.origin
	if origin.is_empty():
		return ""
	if origin.size() != ORIGIN_KEYS.size() or not origin.has_all(ORIGIN_KEYS) or origin.policy_id != "V5_SAFE_MIGRATION_V1" or origin.target_schema != SCHEMA or origin.root_id != data.journey.root_id or origin.source_choice not in ["MAIN", "BACKUP"] or data.journey.seed != "NONE":
		return "SURVIVAL_MIGRATION_ORIGIN"
	for key: String in ["migration_id", "source_path_key", "target_path_key", "selected_hash", "source_state_hash"]:
		if not origin[key] is String or origin[key].length() != (32 if key == "migration_id" else 64) or not origin[key].is_valid_hex_number(false):
			return "SURVIVAL_ORIGIN_HASH"
	for key: String in ["source_main_hash", "source_backup_hash"]:
		if not origin[key] is String or (origin[key] != "MISSING" and (origin[key].length() != 64 or not origin[key].is_valid_hex_number(false))):
			return "SURVIVAL_SOURCE_HASH"
	if origin.selected_hash != origin["source_main_hash" if origin.source_choice == "MAIN" else "source_backup_hash"] or not SurvivalContracts.integer(origin.source_settled_sorties, 0, int(data.settled_sorties)):
		return "SURVIVAL_SOURCE_IDENTITY"
	for death: Dictionary in data.journey.deaths:
		if int(death.transaction_id.get_slice(":", 1)) <= int(origin.source_settled_sorties):
			return "SURVIVAL_PRE_MIGRATION_DEATH"
	return ""
