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
	var drop_guns: Dictionary={}
	for item: Dictionary in value.weapons:
		if item.has("drop"):
			drop_guns[item.instance_id]=item.weapon_id
			item.erase("drop");item.weapon_id="long_rifle" # Only a read-only legacy ownership projection.
		for key: String in WeaponModifiers.KEYS:
			item.erase(key)
	# Check the real gun before projecting both sides of the legacy shape proof.
	# Only the read-only view changes; stored growth receipts retain their gun IDs.
	if value.get("crew") is Array:
		for member: Variant in value.crew:
			if not member is Dictionary or not member.get("growth") is Dictionary:continue
			var action: Variant=member.growth.get("last_action")
			if not action is Dictionary or not action.get("recent") is Array:continue
			for receipt: Variant in action.recent:
				if receipt is Dictionary and drop_guns.has(receipt.get("instance_id")):
					if receipt.get("weapon_id")!=drop_guns[receipt.instance_id]:return {}
					receipt.weapon_id="long_rifle"
	return value


static func problem(data: Dictionary, generated_maps: bool = false, build_context: Dictionary = {}) -> String:
	if not is_state(data) or not data.get("journey") is Dictionary or data.journey.get("format")!=FORMAT or not data.get("weapons") is Array:
		return "WEAPON_INSTANCE_CONTAINER"
	for item: Variant in data.weapons:
		if item is Dictionary and item.has("drop") and not generated_maps:return "WEAPON_DROP_SCHEMA"
		if not item is Dictionary or not WeaponModifiers.problem(item).is_empty():
			return "WEAPON_INSTANCE_ATTRIBUTES"
	var legacy: Dictionary=projected(data)
	if legacy.is_empty():return "WEAPON_DROP_GROWTH_SOURCE"
	var issue: String = RosterState.problem(legacy,generated_maps,build_context)
	if not issue.is_empty():
		return issue
	for item: Dictionary in data.weapons:
		var old: Dictionary = item.duplicate(true)
		for key: String in WeaponModifiers.KEYS:
			old.erase(key)
		var expected: Dictionary = WeaponInventory.instance_reward(data,item) if item.has("drop") else WeaponModifiers.reward(old) if old.get("origin")=="north-cache" else WeaponModifiers.baseline(old)
		if not TransactionReceipt.same(item,expected):
			return "WEAPON_INSTANCE_PROVENANCE"
	return ""
