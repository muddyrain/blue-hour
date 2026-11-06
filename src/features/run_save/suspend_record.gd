class_name SuspendRecord
extends RefCounted
## Lives inside the existing immutable receipt chain; never an economic result.


static func make(world: Dictionary, token: Dictionary, head: String) -> Dictionary:
	return {"suspend_version":1,"binding":token.duplicate(true),"previous_head":head,
		"world_hash":SurvivalContracts.fingerprint(world),"world":world.duplicate(true)}


static func problem(receipt: Dictionary) -> String:
	var value: Dictionary = receipt.envelope
	if not SurvivalState.is_survival(receipt.base) or not receipt.camp_key.is_empty() or value.size() != 5+int(PowerAuthority.mode(receipt.rules) and value.has("power_proposal"))+int((receipt.rules.get("data_version")==8 or receipt.rules.get("data_version")==9) and value.has("support_proposal")) or not value.has_all(["suspend_version","binding","previous_head","world_hash","world"]):
		return "SUSPEND_FIELDS_OR_SCOPE"
	if value.suspend_version != 1 or not value.binding is Dictionary or not TransactionReceipt.same(value.binding,RunTransaction.token_for(receipt)) or not value.previous_head is String or value.previous_head.length() != 64 or not value.previous_head.is_valid_hex_number(false):
		return "SUSPEND_BINDING"
	if not value.world is Dictionary or not value.world_hash is String or value.world_hash.is_empty() or value.world_hash != SurvivalContracts.fingerprint(value.world):
		return "SUSPEND_WORLD_HASH"
	return SortieSnapshot.problem(value.world,receipt)
