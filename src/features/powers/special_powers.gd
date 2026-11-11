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
const PROGRESSION_VERSION: int = 2
const WAVE_VERSION: int = 3
const M47_VERSION: int = 4
const UPGRADED_FREEZE_SECONDS: float = 7.0
const FREEZE: String = "map_freeze_v1"
const SPEED: String = "speed_boost_v1"
const SUPPRESSION: String = "suppression_pulse_v1"
const SUPPRESSION_DEFINITION: Dictionary = {"name":"抑制脉冲", "duration":12.0, "move_factor":1.0, "direct_damage_factor":0.5}
const RADIO: String = "aid_broadcast_v1"
const RADIO_DEFINITION: Dictionary = {"name":"急救广播", "duration":0.0, "heal_amount":24.0}
const RADIO_HELP: String = "立即为户外受伤且生命比例最低的在场队员恢复最多 24 HP。没有合格目标时保留次数。"


static func progression_version(version: Variant) -> bool:
	return SurvivalContracts.integer(version, PROGRESSION_VERSION, M47_VERSION)


static func wave_version(version: Variant) -> bool:
	return SurvivalContracts.integer(version, WAVE_VERSION, M47_VERSION)


static func policy(version: int) -> Dictionary:
	if wave_version(version):
		var catalog: Dictionary = POLICY.duplicate()
		catalog[SUPPRESSION] = SUPPRESSION_DEFINITION
		if version == M47_VERSION:
			catalog[RADIO] = RADIO_DEFINITION
		return catalog
	return POLICY


static func definition(id: String) -> Dictionary:
	if id == RADIO:
		return RADIO_DEFINITION
	return SUPPRESSION_DEFINITION if id == SUPPRESSION else POLICY.get(id, {})


static func initial(binding: Dictionary, equipped: Variant) -> Dictionary:
	if equipped is Dictionary:
		if not _binding_valid(binding) or not loadout_valid(equipped):
			return {}
		return {"version":equipped.version, "binding":binding.duplicate(true),
			"loadout":equipped.duplicate(true), "accepted":[]}
	if not equipped is String or not _binding_valid(binding) or (not equipped.is_empty() and not POLICY.has(equipped)):
		return {}
	return {"version":1, "binding":binding.duplicate(true), "equipped":equipped, "accepted":[]}


static func problem(value: Variant, binding: Dictionary, equipped: Variant, elapsed: float) -> String:
	if equipped is Dictionary:
		return _progression_problem(value, binding, equipped, elapsed)
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


static func request(state: Dictionary, slot: int = 0) -> Dictionary:
	if progression_version(state.get("version")):
		if not state.get("binding") is Dictionary or not _binding_valid(state.binding) \
				or not loadout_valid(state.get("loadout")) or not state.get("accepted") is Array:
			return {}
		var id: String = equipped_at(state, slot)
		# Radio consumes its use only alongside the confirmed health change.
		if id.is_empty() or id == RADIO or not event_at(state, slot).is_empty():
			return {}
		return {"id":_request_id(state.binding, id), "ability_id":id, "slot":slot}
	if slot != 0:
		return {}
	if not _keys(state, KEYS) or not state.binding is Dictionary or not state.equipped is String or not state.accepted is Array or not state.accepted.is_empty() or state.equipped.is_empty():
		return {}
	if not problem(state, state.binding, state.equipped, 0.0).is_empty():
		return {}
	return {"id":_request_id(state.binding, state.equipped), "ability_id":state.equipped}


static func accept(state: Dictionary, proposal: Dictionary, at: float) -> Dictionary:
	if progression_version(state.get("version")):
		if not SurvivalContracts.integer(proposal.get("slot"), 0, 1) \
				or not state.get("binding") is Dictionary or not state.get("loadout") is Dictionary \
				or not problem(state, state.binding, state.loadout, at).is_empty():
			return {}
		var slot: int = int(proposal.slot)
		if proposal.is_empty() or not TransactionReceipt.same(proposal, request(state, slot)):
			return {}
		var next: Dictionary = state.duplicate(true)
		var event: Dictionary = proposal.duplicate(true)
		event.at = at
		event.until = at + duration(proposal.ability_id, state.loadout.investments.freeze > 0)
		next.accepted.append(event)
		return next if problem(next, next.binding, next.loadout, at).is_empty() else {}
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


static func remaining(state: Dictionary, elapsed: float, slot: int = -1) -> float:
	if progression_version(state.get("version")):
		var next_expiry: float = INF
		for event: Dictionary in state.accepted:
			if (slot == -1 or event.slot == slot) and event.at <= elapsed and event.until > elapsed:
				next_expiry = minf(next_expiry, float(event.until) - elapsed)
		return 0.0 if is_inf(next_expiry) else next_expiry
	if slot > 0:
		return 0.0
	if not _keys(state, KEYS) or not state.binding is Dictionary or not state.equipped is String or not problem(state, state.binding, state.equipped, elapsed).is_empty() or state.accepted.is_empty():
		return 0.0
	return maxf(0.0, float(state.accepted[0].until) - elapsed)


static func move_factor(state: Dictionary, elapsed: float) -> float:
	return float(POLICY[SPEED].move_factor) if ability_remaining(state, SPEED, elapsed) > 0.0 else 1.0


static func frozen(state: Dictionary, elapsed: float) -> bool:
	return ability_remaining(state, FREEZE, elapsed) > 0.0


static func ability_remaining(state: Dictionary, id: String, elapsed: float) -> float:
	if progression_version(state.get("version")):
		var slot: int = state.loadout.slots.find(id)
		return remaining(state, elapsed, slot) if slot >= 0 else 0.0
	return remaining(state, elapsed) if state.get("equipped") == id else 0.0


static func equipped_at(state: Dictionary, slot: int) -> String:
	if progression_version(state.get("version")):
		var slots: Array = state.loadout.slots
		return slots[slot] if slot >= 0 and slot < slots.size() else ""
	return state.get("equipped", "") if slot == 0 else ""


static func event_at(state: Dictionary, slot: int) -> Dictionary:
	for event: Dictionary in state.accepted:
		if event.get("slot", 0) == slot:
			return event
	return {}


static func duration(id: String, upgraded: bool) -> float:
	if upgraded and id == FREEZE:
		return UPGRADED_FREEZE_SECONDS
	return float(definition(id).duration)


static func loadout_valid(loadout: Variant) -> bool:
	if not _keys(loadout, ["version", "slots", "investments"]) \
			or not progression_version(loadout.version) \
			or not _keys(loadout.investments, ["second_slot", "freeze"]) or not loadout.slots is Array:
		return false
	for day: Variant in loadout.investments.values():
		if not SurvivalContracts.integer(day, 0, RunSave.MAX_COUNTER) or day == 1:
			return false
	if loadout.slots.size() != (2 if loadout.investments.second_slot != 0 else 1):
		return false
	var catalog: Dictionary = policy(int(loadout.version))
	for id: Variant in loadout.slots:
		if not id is String or (id != "" and (not catalog.has(id) or loadout.slots.count(id) != 1)):
			return false
	return true


static func _progression_problem(value: Variant, binding: Dictionary, loadout: Dictionary, elapsed: float) -> String:
	if not _keys(value, ["version", "binding", "loadout", "accepted"]) \
			or not SurvivalContracts.json_value(value) \
			or not progression_version(value.version) or value.version != loadout.get("version"):
		return "POWER_FIELDS"
	if not _binding_valid(binding) or not value.binding is Dictionary or not TransactionReceipt.same(value.binding, binding):
		return "POWER_BINDING"
	if not loadout_valid(loadout) or not value.loadout is Dictionary or not TransactionReceipt.same(value.loadout, loadout):
		return "POWER_EQUIPPED"
	if not is_finite(elapsed) or elapsed < 0.0:
		return "POWER_CLOCK"
	if not value.accepted is Array or value.accepted.size() > loadout.slots.size():
		return "POWER_DAILY_USES"
	var used: Array[int] = []
	var previous_at: float = 0.0
	for event: Variant in value.accepted:
		if not _keys(event, ["id", "ability_id", "slot", "at", "until"]) \
				or not SurvivalContracts.integer(event.slot, 0, loadout.slots.size() - 1):
			return "POWER_ACTIVATION_ID"
		var slot: int = int(event.slot)
		var id: String = loadout.slots[slot]
		if slot in used or id.is_empty() or id == RADIO or event.ability_id != id or event.id != _request_id(binding, id):
			return "POWER_ACTIVATION_ID"
		if not SurvivalContracts.number(event.at) or not SurvivalContracts.number(event.until) \
				or event.at < previous_at or event.at > elapsed or event.until <= event.at \
				or event.until != float(event.at) + duration(id, loadout.investments.freeze != 0):
			return "POWER_EFFECT_INTERVAL"
		used.append(slot)
		previous_at = float(event.at)
	return ""


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
