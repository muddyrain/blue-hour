extends SceneTree
## Pure component fixtures. These do not claim actual healing, kills or saved journeys.

const BINDING: Dictionary = {
	"run_id":"0123456789abcdef0123456789abcdef",
	"root_id":"fedcba9876543210fedcba9876543210",
	"transaction_id":"0123456789abcdef0123456789abcdef:1",
	"base_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
	"rules_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
}

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("BASIC_SUPPORT_FAIL " + label)


func same(left: Variant, right: Variant) -> bool:
	return TransactionReceipt.same({"v":left}, {"v":right})


func member(id: int, health: float, maximum: float = 200.0, present: bool = true) -> Dictionary:
	return {"member_id":id, "health":health, "max_health":maximum, "present":present}


func caller(id: int, point: Vector2, health: float = 100.0, present: bool = true, working: bool = false) -> Dictionary:
	return {"member_id":id, "position":point, "health":health, "present":present, "working":working}


func enemy(id: int, point: Vector2, health: float = 100.0, present: bool = true) -> Dictionary:
	return {"enemy_id":id, "position":point, "health":health, "present":present}


func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	var support: BasicSupport = BasicSupport.new()
	expect(support.request("heal", {}).is_empty() and not support.ready("heal"), "unconfigured cannot submit")
	support.configure(BINDING)
	expect(BasicSupport.problem(support.snapshot(), BINDING).is_empty(), "fresh exact state")
	expect(support.ready("heal") and support.ready("airstrike"), "fresh separate abilities ready")
	expect(not support.ready("special_power") and support.request("special_power", {}).is_empty(), "unknown ability rejects")
	var initial: Dictionary = support.snapshot()
	var none: Array[Dictionary] = []
	expect(support.plan_heal(none).is_empty(), "no heal target")
	var full: Array[Dictionary] = [member(1, 200.0), member(2, 200.0)]
	expect(support.plan_heal(full).is_empty() and same(support.snapshot(), initial), "full health plans no effect or cooldown")
	var dead: Array[Dictionary] = [member(1, 0.0), member(2, 20.0, 200.0, false)]
	expect(support.plan_heal(dead).is_empty(), "dead and absent never healed")
	var ratios: Array[Dictionary] = [member(2, 70.0, 100.0), member(1, 100.0, 200.0)]
	expect(same(support.plan_heal(ratios), {"member_id":1, "amount":40.0}), "relative health determines target")
	var tied: Array[Dictionary] = [member(2, 50.0, 100.0), member(1, 100.0, 200.0)]
	expect(support.plan_heal(tied).member_id == 1, "stable lower member ID breaks equal ratio")
	expect(support.plan_heal(tied, 1.5).amount == 60.0, "medical pack factor only changes cap")
	var almost: Array[Dictionary] = [member(1, 198.75)]
	expect(support.plan_heal(almost, 1.5).amount == 1.25, "heal exactly caps at missing health")
	var malformed: Array[Dictionary] = [member(1, 90.0), member(1, 100.0)]
	expect(support.plan_heal(malformed).is_empty(), "duplicate member fails closed")
	malformed = [member(1, -1.0)]
	expect(support.plan_heal(malformed).is_empty(), "negative health fails closed")
	malformed = [member(1, NAN)]
	expect(support.plan_heal(malformed).is_empty(), "nonfinite health fails closed")
	expect(support.plan_heal(tied, 0.0).is_empty() and support.plan_heal(tied, NAN).is_empty(), "invalid item factors rejected")
	var request_payload: Dictionary = support.plan_heal(tied)
	var request: Dictionary = support.request("heal", request_payload)
	expect(request.id == String(BINDING.transaction_id) + ":basic:0", "first request has stable transaction identity")
	expect(same(request, support.request("heal", request_payload)) and same(support.snapshot(), initial), "planning/repeated input does not consume")
	request_payload.amount = 999.0
	expect(request.payload.amount == 40.0, "request freezes payload copy")
	var facts: Dictionary = {"at_ms":1200, "member_id":1, "health_before":100.0, "health_after":140.0, "amount":40.0, "damage_received":100.0}
	expect(support.accept(request, facts), "authoritative accepted heal starts cooldown")
	expect(support.remaining("heal") == 30.0 and support.ready("airstrike") and not support.ready("heal"), "separate cooldowns")
	expect(support.request("heal", request.payload).is_empty(), "cooldown prevents fresh request")
	var accepted: Dictionary = support.snapshot()
	expect(BasicSupport.problem(accepted, BINDING).is_empty(), "accepted source state validates")
	expect(support.accept(request, facts) and same(support.snapshot(), accepted), "identical accept retry is idempotent")
	var conflicting: Dictionary = facts.duplicate(true)
	conflicting.amount = 39.0
	expect(not support.accept(request, conflicting) and same(support.snapshot(), accepted), "retry cannot replace accepted facts")
	facts.amount = 123.0
	expect(support.snapshot().accepted[0].facts.amount == 40.0, "facts are immutable copies")
	support.advance(3.75, false)
	expect(same(support.snapshot(), accepted), "pause freezes exact clocks")
	support.advance(3.75, true)
	expect(support.remaining("heal") == 26.25, "authoritative delta advances exact remainder")
	var strike: Dictionary = support.request("airstrike", {"member_id":2, "point":[40.0, 50.0]})
	expect(strike.id == String(BINDING.transaction_id) + ":basic:1", "each accepted ability shares stable sequence")
	expect(support.accept(strike, {"at_ms":4950, "member_id":2, "targets":[]}), "legal empty strike can be accepted")
	expect(support.remaining("airstrike") == 20.0 and support.remaining("heal") == 26.25, "strike leaves heal remainder intact")
	support.advance(5.125, true)
	var checkpoint: Dictionary = support.snapshot()
	expect(checkpoint.cooldowns.heal == 21.125 and checkpoint.cooldowns.airstrike == 14.875, "each cooldown independently exact")
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(checkpoint))).payload
	var resumed: BasicSupport = BasicSupport.new()
	resumed.restore(decoded)
	expect(same(resumed.snapshot(), checkpoint), "exact transport restores used state and nonzero cooldown")
	expect(resumed.accept(strike, {"at_ms":4950, "member_id":2, "targets":[]}) and same(resumed.snapshot(), checkpoint), "restored retry neither replays nor restarts cooldown")
	resumed.advance(15.0, true)
	expect(resumed.ready("airstrike") and resumed.remaining("heal") == 6.125, "no underflow or forced joint reset")
	resumed.advance(6.125, true)
	expect(resumed.ready("heal") and resumed.ready("airstrike"), "both return ready naturally")
	var third: Dictionary = resumed.request("heal", {"member_id":2, "amount":1.0})
	expect(third.id.ends_with(":basic:2") and resumed.accept(third, {"amount":1.0}), "reusable cooldown with no charges limit")
	var detached: Dictionary = resumed.snapshot()
	detached.accepted.clear()
	detached.cooldowns.heal = 0.0
	expect(resumed.snapshot().accepted.size() == 3 and resumed.remaining("heal") == 30.0, "snapshot mutation cannot alter runtime")
	var stale: Dictionary = {"id":String(BINDING.transaction_id) + ":basic:7", "kind":"airstrike", "payload":{}}
	expect(not resumed.accept(stale, {}), "out-of-order identity rejects")
	var foreign: Dictionary = BINDING.duplicate(true)
	foreign.transaction_id = String(foreign.run_id) + ":2"
	expect(not BasicSupport.problem(checkpoint, foreign).is_empty(), "foreign action binding rejects")
	for mutation: String in ["version", "missing", "extra", "sequence", "negative", "overflow", "nan", "cooldown_fields", "accepted_id", "accepted_extra", "accepted_kind", "accepted_payload", "accepted_facts"]:
		var bad: Dictionary = checkpoint.duplicate(true)
		match mutation:
			"version":
				bad.version = 2
			"missing":
				bad.erase("accepted")
			"extra":
				bad.extra = false
			"sequence":
				bad.sequence = 0
			"negative":
				bad.cooldowns.heal = -0.1
			"overflow":
				bad.cooldowns.airstrike = 20.1
			"nan":
				bad.cooldowns.heal = NAN
			"cooldown_fields":
				bad.cooldowns.unknown = 0.0
			"accepted_id":
				bad.accepted[0].id = String(BINDING.transaction_id) + ":basic:1"
			"accepted_extra":
				bad.accepted[0].extra = false
			"accepted_kind":
				bad.accepted[0].kind = "special_power"
			"accepted_payload":
				bad.accepted[0].payload = []
			"accepted_facts":
				bad.accepted[0].facts = null
		expect(not BasicSupport.problem(bad, BINDING).is_empty(), "strict state rejects " + mutation)
	var unsupported: Dictionary = initial.duplicate(true)
	unsupported.cooldowns.heal = 1.0
	expect(not BasicSupport.problem(unsupported, BINDING).is_empty(), "unused ability cannot claim cooldown source")
	var clear: Callable = func(_from: Vector2, _to: Vector2) -> bool: return true
	var legal: Callable = func(_point: Vector2) -> bool: return true
	var illegal: Callable = func(_point: Vector2) -> bool: return false
	var callers: Array[Dictionary] = [caller(2, Vector2(10, 0)), caller(1, Vector2(-10, 0))]
	var targets: Array[Dictionary] = [enemy(4, Vector2(70, 0)), enemy(0, Vector2.ZERO), enemy(3, Vector2(91, 0)), enemy(1, Vector2(50, 0), 0.0), enemy(2, Vector2(50, 0), 72.0, false)]
	var plan: Dictionary = support.plan_airstrike(callers, targets, Vector2.ZERO, 1.0, legal, clear)
	expect(plan.member_id == 1 and same(plan.targets, [0, 4]), "stable caller and target order includes boss and filters dead/absent/outside")
	expect(plan.radius == 90.0 and same(plan.point, [0.0, 0.0]), "strike freezes landing point and base radius")
	plan = support.plan_airstrike(callers, targets, Vector2.ZERO, 1.3, legal, clear)
	expect(plan.radius == 117.0 and same(plan.targets, [0, 3, 4]), "blast factor affects radius and actual candidates")
	expect(support.plan_airstrike(callers, targets, Vector2.ZERO, 1.0, illegal, clear).is_empty(), "illegal terrain produces no request plan")
	var blocked_caller: Callable = func(from: Vector2, _to: Vector2) -> bool: return from.x != -10.0
	plan = support.plan_airstrike(callers, targets, Vector2.ZERO, 1.0, legal, blocked_caller)
	expect(plan.member_id == 2, "blocked nearer tie candidate cannot call")
	var wall: Callable = func(_from: Vector2, to: Vector2) -> bool: return to.x != 70.0
	plan = support.plan_airstrike(callers, targets, Vector2.ZERO, 1.0, legal, wall)
	expect(same(plan.targets, [0]), "blast-to-enemy LOS rechecked separately")
	callers = [caller(1, Vector2(-320, 0))]
	expect(not support.plan_airstrike(callers, [], Vector2.ZERO, 1.0, legal, clear).is_empty(), "maximum caller distance inclusive and empty ground legal")
	callers = [caller(1, Vector2(-320.001, 0))]
	expect(support.plan_airstrike(callers, [], Vector2.ZERO, 1.0, legal, clear).is_empty(), "beyond maximum caller distance rejects")
	callers = [caller(1, Vector2.ZERO, 0.0), caller(2, Vector2.ZERO, 100.0, false), caller(3, Vector2.ZERO, 100.0, true, true)]
	expect(support.plan_airstrike(callers, [], Vector2.ZERO, 1.0, legal, clear).is_empty(), "dead absent and working callers excluded")
	callers = [caller(1, Vector2.ZERO)]
	var duplicate_enemies: Array[Dictionary] = [enemy(2, Vector2.ZERO), enemy(2, Vector2(10, 0))]
	expect(support.plan_airstrike(callers, duplicate_enemies, Vector2.ZERO, 1.0, legal, clear).is_empty(), "ambiguous duplicate enemy rejects entire plan")
	expect(support.plan_airstrike(callers, [], Vector2(INF, 0), 1.0, legal, clear).is_empty(), "nonfinite strike point rejects")
	expect(support.plan_airstrike(callers, [], Vector2.ZERO, NAN, legal, clear).is_empty(), "nonfinite strike factor rejects")
	expect(same(support.snapshot(), checkpoint), "all target planning leaves cooldown ledger immutable")
	print(JSON.stringify({"suite":"basic_support", "checks":checks, "failures":failures, "policy_source":"PROJECT_TEMP", "scope":"PURE_COMPONENT_ONLY"}))
	quit(0 if failures == 0 else 1)

