class_name WeaponState
extends RefCounted
## Explicit110 adapter. Old109 validation is reused only on a read-only projection.

const SCHEMA: int = 110
const FORMAT: String = "BH_WEAPON_INSTANCE_V1"


static func is_state(data: Dictionary) -> bool:
	return SurvivalContracts.integer(data.get("schema_version"),SCHEMA,SCHEMA)


static func is_family(data: Dictionary) -> bool:
	return is_state(data) or EnemyState.is_state(data)


static func initial(seed: String = "") -> Dictionary:
	var value: Dictionary = RosterState.initial(seed)
	value.format = FORMAT
	return value


static func snapshot(camp: Dictionary, journey: Dictionary, recruits: Array, history: Array = []) -> Dictionary:
	var value: Dictionary = RosterState.snapshot(camp,journey,recruits,history)
	value.schema_version = SCHEMA
	return value


static func projected(data: Dictionary) -> Dictionary:
	var value: Dictionary = data.duplicate(true)
	value.schema_version = RosterState.SCHEMA
	value.journey.format = RosterState.FORMAT
	for item: Dictionary in value.weapons:
		for key: String in WeaponModifiers.KEYS:
			item.erase(key)
	return value


static func problem(data: Dictionary) -> String:
	if not is_state(data) or not data.get("journey") is Dictionary or data.journey.get("format")!=FORMAT or not data.get("weapons") is Array:
		return "WEAPON_INSTANCE_CONTAINER"
	for item: Variant in data.weapons:
		if not item is Dictionary or not WeaponModifiers.problem(item).is_empty():
			return "WEAPON_INSTANCE_ATTRIBUTES"
	var issue: String = RosterState.problem(projected(data))
	if not issue.is_empty():
		return issue
	for item: Dictionary in data.weapons:
		var old: Dictionary = item.duplicate(true)
		for key: String in WeaponModifiers.KEYS:
			old.erase(key)
		var expected: Dictionary = WeaponModifiers.reward(old) if old.get("origin")=="north-cache" else WeaponModifiers.baseline(old)
		if not TransactionReceipt.same(item,expected):
			return "WEAPON_INSTANCE_PROVENANCE"
	return ""
