class_name BasicSupport
extends RefCounted
## Pure requests and exact cooldown state. Only the original world owner accepts effects.

const POLICY: Dictionary = {
	"heal_amount":40.0,
	"heal_cooldown":30.0,
	"airstrike_range":320.0,
	"airstrike_radius":90.0,
	"airstrike_damage":72.0,
	"airstrike_cooldown":20.0,
}
const KINDS: Array[String] = ["heal", "airstrike"]
const KEYS: Array[String] = ["version", "binding", "sequence", "cooldowns", "accepted"]
const REQUEST_KEYS: Array[String] = ["id", "kind", "payload"]
const ACCEPTED_KEYS: Array[String] = ["id", "kind", "payload", "facts"]

var _state: Dictionary = {}
var _allow_first_aid: bool = false
var _allow_radio: bool = false
var _used_once: Dictionary = {}


static func problem(value: Variant, binding: Dictionary, allow_first_aid: bool = false,
		allow_radio: bool = false) -> String:
	if not value is Dictionary or value.size() != KEYS.size() or not value.has_all(KEYS):
		return "BASIC_SUPPORT_FIELDS"
	if not SurvivalContracts.json_value(value):
		return "BASIC_SUPPORT_VALUE"
	if not SurvivalContracts.integer(value.version, 1, 1) or not value.binding is Dictionary or not _binding_valid(binding) or not TransactionReceipt.same(value.binding, binding):
		return "BASIC_SUPPORT_BINDING"
	if not SurvivalContracts.integer(value.sequence, 0, SurvivalContracts.MAX_JSON_INTEGER) or not value.accepted is Array or value.sequence != value.accepted.size():
		return "BASIC_SUPPORT_SEQUENCE"
	if not value.cooldowns is Dictionary or value.cooldowns.size() != KINDS.size() or not value.cooldowns.has_all(KINDS):
		return "BASIC_SUPPORT_COOLDOWNS"
	var used: Dictionary = {}
	for index: int in range(value.accepted.size()):
		var event: Variant = value.accepted[index]
		if not event is Dictionary or event.size() != ACCEPTED_KEYS.size() or not event.has_all(ACCEPTED_KEYS):
			return "BASIC_SUPPORT_ACCEPTED_FIELDS"
		if not event.id is String or event.id != _request_id(binding, index) or not _kind_allowed(event.kind, allow_first_aid, allow_radio) or not event.payload is Dictionary or not event.facts is Dictionary:
			return "BASIC_SUPPORT_ACCEPTED_IDENTITY"
		if event.kind == FirstAidV1.KIND and used.has(event.kind):
			return "FIRST_AID_ALREADY_USED"
		if event.kind == SpecialPowers.RADIO and used.has(event.kind):
			return "AID_BROADCAST_ALREADY_USED"
		used[event.kind] = true
	for kind: String in KINDS:
		var remaining_time: Variant = value.cooldowns[kind]
		if not SurvivalContracts.number(remaining_time) or remaining_time < 0.0 or remaining_time > POLICY[kind + "_cooldown"]:
			return "BASIC_SUPPORT_COOLDOWN_RANGE"
		if not used.has(kind) and remaining_time != 0.0:
			return "BASIC_SUPPORT_COOLDOWN_SOURCE"
	return ""


static func _binding_valid(binding: Dictionary) -> bool:
	return binding.get("transaction_id") is String and not String(binding.transaction_id).is_empty() and SurvivalContracts.json_value(binding)


static func _kind_allowed(kind: Variant, allow_first_aid: bool, allow_radio: bool) -> bool:
	return (kind in KINDS or (allow_first_aid and kind == FirstAidV1.KIND)
		or (allow_radio and kind == SpecialPowers.RADIO))


static func _request_id(binding: Dictionary, sequence: int) -> String:
	return String(binding.transaction_id) + ":basic:" + str(sequence)


static func _member_valid(member: Dictionary) -> bool:
	return (
		SurvivalContracts.integer(member.get("member_id"), 1, SurvivalContracts.MAX_ID)
		and SurvivalContracts.number(member.get("health"))
		and SurvivalContracts.number(member.get("max_health"))
		and member.health >= 0.0
		and member.max_health > 0.0
		and member.health <= member.max_health
		and member.get("present") is bool
	)


static func _point_valid(point: Variant) -> bool:
	return point is Vector2 and point.is_finite()


func configure(binding: Dictionary, allow_first_aid: bool = false, allow_radio: bool = false) -> void:
	assert(_binding_valid(binding))
	_allow_first_aid = allow_first_aid
	_allow_radio = allow_radio
	_used_once.clear()
	_state = {
		"version":1,
		"binding":binding.duplicate(true),
		"sequence":0,
		"cooldowns":{"heal":0.0, "airstrike":0.0},
		"accepted":[],
	}


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func restore(value: Dictionary, allow_first_aid: bool = false, allow_radio: bool = false) -> void:
	assert(problem(value, value.get("binding", {}), allow_first_aid, allow_radio).is_empty())
	_state = value.duplicate(true)
	_allow_first_aid = allow_first_aid
	_allow_radio = allow_radio
	_used_once.clear()
	for event: Dictionary in value.accepted:
		if event.kind not in KINDS:
			_used_once[event.kind] = true


func advance(delta: float, active: bool) -> void:
	assert(is_finite(delta) and delta >= 0.0)
	if not active or _state.is_empty():
		return
	for kind: String in KINDS:
		_state.cooldowns[kind] = maxf(0.0, float(_state.cooldowns[kind]) - delta)


func remaining(kind: String) -> float:
	return float(_state.get("cooldowns", {}).get(kind, 0.0))


func ready(kind: String) -> bool:
	if _state.is_empty() or not _kind_allowed(kind, _allow_first_aid, _allow_radio):
		return false
	return remaining(kind) == 0.0 if kind in KINDS else not _used_once.has(kind)


func plan_heal(members: Array[Dictionary], factor: float = 1.0) -> Dictionary:
	if not is_finite(factor) or factor <= 0.0:
		return {}
	return plan_recovery(members, float(POLICY.heal_amount) * factor)


static func plan_recovery(members: Array[Dictionary], maximum_amount: float) -> Dictionary:
	if is_nan(maximum_amount) or maximum_amount <= 0.0:
		return {}
	var chosen: Dictionary = {}
	var lowest_ratio: float = INF
	var seen: Dictionary = {}
	for member: Dictionary in members:
		if not _member_valid(member) or seen.has(int(member.member_id)):
			return {}
		seen[int(member.member_id)] = true
		if not member.present or member.health <= 0.0 or member.health == member.max_health:
			continue
		var ratio: float = float(member.health) / float(member.max_health)
		if ratio < lowest_ratio or (ratio == lowest_ratio and int(member.member_id) < int(chosen.member_id)):
			chosen = member
			lowest_ratio = ratio
	if chosen.is_empty():
		return {}
	var amount: float = minf(maximum_amount, float(chosen.max_health) - float(chosen.health))
	if not is_finite(amount) or amount <= 0.0:
		return {}
	return {"member_id":int(chosen.member_id), "amount":amount}


func plan_airstrike(members: Array[Dictionary], enemies: Array[Dictionary], point: Vector2,
		radius_factor: float, point_legal: Callable, line_clear: Callable) -> Dictionary:
	# Navigation and LOS stay with the existing world; no second geometry model.
	if not point.is_finite() or not is_finite(radius_factor) or radius_factor <= 0.0 or not point_legal.is_valid() or not line_clear.is_valid():
		return {}
	if point_legal.call(point) != true:
		return {}
	var chosen: Dictionary = {}
	var nearest: float = INF
	var seen: Dictionary = {}
	for member: Dictionary in members:
		if not SurvivalContracts.integer(member.get("member_id"), 1, SurvivalContracts.MAX_ID) or seen.has(int(member.member_id)) or not SurvivalContracts.number(member.get("health")) or member.health < 0.0 or not member.get("present") is bool or not member.get("working") is bool or not _point_valid(member.get("position")):
			return {}
		seen[int(member.member_id)] = true
		if member.health <= 0.0 or not member.present or member.working:
			continue
		var distance: float = member.position.distance_squared_to(point)
		if distance > float(POLICY.airstrike_range) * float(POLICY.airstrike_range) or line_clear.call(member.position, point) != true:
			continue
		if distance < nearest or (distance == nearest and int(member.member_id) < int(chosen.member_id)):
			chosen = member
			nearest = distance
	if chosen.is_empty():
		return {}
	var radius: float = float(POLICY.airstrike_radius) * radius_factor
	if not is_finite(radius):
		return {}
	var targets: Array[int] = []
	seen.clear()
	for enemy: Dictionary in enemies:
		if not SurvivalContracts.integer(enemy.get("enemy_id"), 0, SurvivalContracts.MAX_JSON_INTEGER) or seen.has(int(enemy.enemy_id)) or not SurvivalContracts.number(enemy.get("health")) or enemy.health < 0.0 or not enemy.get("present") is bool or not _point_valid(enemy.get("position")):
			return {}
		seen[int(enemy.enemy_id)] = true
		if enemy.health <= 0.0 or not enemy.present or enemy.position.distance_to(point) > radius:
			continue
		if line_clear.call(point, enemy.position) == true:
			targets.append(int(enemy.enemy_id))
	targets.sort()
	return {"member_id":int(chosen.member_id), "point":[point.x, point.y], "radius":radius, "targets":targets}


func request(kind: String, payload: Dictionary) -> Dictionary:
	if not ready(kind) or not SurvivalContracts.json_value(payload):
		return {}
	return {"id":_request_id(_state.binding, int(_state.sequence)), "kind":kind, "payload":payload.duplicate(true)}


func accept(proposal: Dictionary, facts: Dictionary) -> bool:
	if _state.is_empty() or proposal.size() != REQUEST_KEYS.size() or not proposal.has_all(REQUEST_KEYS) or not proposal.get("id") is String or not _kind_allowed(proposal.get("kind"), _allow_first_aid, _allow_radio) or not proposal.get("payload") is Dictionary or not SurvivalContracts.json_value(proposal) or not SurvivalContracts.json_value(facts):
		return false
	var accepted: Dictionary = proposal.duplicate(true)
	accepted.facts = facts.duplicate(true)
	for event: Dictionary in _state.accepted:
		if event.id == proposal.id:
			return TransactionReceipt.same(event, accepted)
	if proposal.id != _request_id(_state.binding, int(_state.sequence)) or not ready(proposal.kind):
		return false
	# A invokes this only on a candidate that its original journal commits atomically.
	_state.accepted.append(accepted)
	_state.sequence = int(_state.sequence) + 1
	if proposal.kind in KINDS:
		_state.cooldowns[proposal.kind] = POLICY[proposal.kind + "_cooldown"]
	else:
		_used_once[proposal.kind] = true
	return true
