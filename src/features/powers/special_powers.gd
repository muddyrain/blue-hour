class_name SpecialPowers
extends RefCounted
## PROJECT_TEMP. Pure proposals and effect intervals; the original journal owns acceptance.

const POLICY: Dictionary = {
	"speed_boost_v1":{"name":"疾行号令", "duration":8.0, "move_factor":1.5},
	"map_freeze_v1":{"name":"全域冻结", "duration":4.0, "move_factor":1.0},
}
const KEYS: Array[String] = ["version", "binding", "equipped", "accepted"]
const BINDING_KEYS: Array[String] = ["run_id", "root_id", "transaction_id", "base_hash", "rules_hash"]
const REQUEST_KEYS: Array[String] = ["id", "ability_id"]
const ACCEPTED_KEYS: Array[String] = ["id", "ability_id", "at", "until"]


static func initial(binding: Dictionary, equipped: String) -> Dictionary:
	if not _binding_valid(binding) or (not equipped.is_empty() and not POLICY.has(equipped)):
		return {}
	return {"version":1, "binding":binding.duplicate(true), "equipped":equipped, "accepted":[]}


static func problem(value: Variant, binding: Dictionary, equipped: String, elapsed: float) -> String:
	if not _keys(value, KEYS) or not SurvivalContracts.json_value(value) or not SurvivalContracts.integer(value.version, 1, 1):
		return "POWER_FIELDS"
	if not _binding_valid(binding) or not value.binding is Dictionary or not TransactionReceipt.same(value.binding, binding):
		return "POWER_BINDING"
	if not value.equipped is String or value.equipped != equipped or (not equipped.is_empty() and not POLICY.has(equipped)):
		return "POWER_EQUIPPED"
	if not is_finite(elapsed) or elapsed < 0.0:
		return "POWER_CLOCK"
	if not value.accepted is Array or value.accepted.size() > 1:
		return "POWER_DAILY_USES"
	if value.accepted.is_empty():
		return ""
	var event: Variant = value.accepted[0]
	if equipped.is_empty() or not _keys(event, ACCEPTED_KEYS) or not event.id is String or not event.ability_id is String or event.ability_id != equipped or event.id != _request_id(binding, equipped):
		return "POWER_ACTIVATION_ID"
	if not SurvivalContracts.number(event.at) or not SurvivalContracts.number(event.until) or event.at < 0.0 or event.at > elapsed or event.until <= event.at or event.until != float(event.at) + float(POLICY[equipped].duration):
		return "POWER_EFFECT_INTERVAL"
	return ""


static func request(state: Dictionary) -> Dictionary:
	if not _keys(state, KEYS) or not state.binding is Dictionary or not state.equipped is String or not state.accepted is Array or not state.accepted.is_empty() or state.equipped.is_empty():
		return {}
	if not problem(state, state.binding, state.equipped, 0.0).is_empty():
		return {}
	return {"id":_request_id(state.binding, state.equipped), "ability_id":state.equipped}


static func accept(state: Dictionary, proposal: Dictionary, at: float) -> Dictionary:
	if not _keys(state, KEYS) or not state.binding is Dictionary or not state.equipped is String or not problem(state, state.binding, state.equipped, at).is_empty() or not _keys(proposal, REQUEST_KEYS):
		return {}
	if not proposal.id is String or not proposal.ability_id is String or state.equipped.is_empty() or proposal.ability_id != state.equipped or proposal.id != _request_id(state.binding, state.equipped):
		return {}
	if not state.accepted.is_empty():
		# ACK retry must preserve the original interval, including its start.
		return state.duplicate(true) if state.accepted[0].at == at else {}
	var next: Dictionary = state.duplicate(true)
	next.accepted.append({"id":proposal.id, "ability_id":proposal.ability_id, "at":at, "until":at + float(POLICY[proposal.ability_id].duration)})
	return next if problem(next, next.binding, next.equipped, at).is_empty() else {}


static func remaining(state: Dictionary, elapsed: float) -> float:
	if not _keys(state, KEYS) or not state.binding is Dictionary or not state.equipped is String or not problem(state, state.binding, state.equipped, elapsed).is_empty() or state.accepted.is_empty():
		return 0.0
	return maxf(0.0, float(state.accepted[0].until) - elapsed)


static func move_factor(state: Dictionary, elapsed: float) -> float:
	return float(POLICY.speed_boost_v1.move_factor) if state.get("equipped") == "speed_boost_v1" and remaining(state, elapsed) > 0.0 else 1.0


static func frozen(state: Dictionary, elapsed: float) -> bool:
	return state.get("equipped") == "map_freeze_v1" and remaining(state, elapsed) > 0.0


static func _request_id(binding: Dictionary, equipped: String) -> String:
	return String(binding.transaction_id) + ":power:" + equipped


static func _binding_valid(binding: Dictionary) -> bool:
	if not _keys(binding, BINDING_KEYS):
		return false
	for key: String in BINDING_KEYS:
		if not binding[key] is String:
			return false
	for key: String in ["run_id", "root_id", "base_hash", "rules_hash"]:
		if binding[key].length() != (32 if key in ["run_id", "root_id"] else 64) or not binding[key].is_valid_hex_number(false):
			return false
	var parts: PackedStringArray = String(binding.transaction_id).split(":")
	return parts.size() == 2 and parts[0] == binding.run_id and parts[1].is_valid_int() and int(parts[1]) > 0 and binding.transaction_id == "%s:%d" % [binding.run_id, int(parts[1])]


static func _keys(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() and value.has_all(keys)
