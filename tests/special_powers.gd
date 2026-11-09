extends SceneTree
## Pure component fixtures. No HP, inventory, enemy or durable journal acceptance claim.

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
		printerr("SPECIAL_POWERS_FAIL " + label)


func same(left: Variant, right: Variant) -> bool:
	return TransactionReceipt.same({"v":left}, {"v":right})


func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	var empty: Dictionary = SpecialPowers.initial(BINDING, "")
	expect(SpecialPowers.problem(empty, BINDING, "", 0.0).is_empty(), "empty slot validates")
	expect(SpecialPowers.request(empty).is_empty() and SpecialPowers.move_factor(empty, 0.0) == 1.0 and not SpecialPowers.frozen(empty, 0.0), "empty slot grants no ability")
	expect(SpecialPowers.initial(BINDING, "airstrike").is_empty(), "basic support is not a special power")
	for ability: String in ["speed_boost_v1", "map_freeze_v1"]:
		var state: Dictionary = SpecialPowers.initial(BINDING, ability)
		var original: Dictionary = state.duplicate(true)
		var proposal: Dictionary = SpecialPowers.request(state)
		expect(proposal.id == String(BINDING.transaction_id) + ":power:" + ability and proposal.ability_id == ability, ability + " request binds original action and ability")
		expect(same(proposal, SpecialPowers.request(state)) and same(state, original), ability + " repeated input planning does not consume")
		var accepted: Dictionary = SpecialPowers.accept(state, proposal, 10.125)
		expect(not accepted.is_empty() and same(state, original), ability + " pure acceptance leaves before state intact")
		expect(SpecialPowers.problem(accepted, BINDING, ability, 10.125).is_empty() and SpecialPowers.remaining(accepted, 10.125) == float(SpecialPowers.POLICY[ability].duration), ability + " accepted interval validates")
		expect(SpecialPowers.request(accepted).is_empty(), ability + " used slot offers no new request")
		expect(same(SpecialPowers.accept(accepted, proposal, 10.125), accepted), ability + " exact ACK retry is idempotent")
		expect(SpecialPowers.accept(accepted, proposal, 10.25).is_empty(), ability + " retry cannot extend interval")
		expect(SpecialPowers.remaining(accepted, 11.375) == float(SpecialPowers.POLICY[ability].duration) - 1.25, ability + " simulation elapsed derives exact remainder")
		expect(SpecialPowers.remaining(accepted, 11.375) == SpecialPowers.remaining(accepted, 11.375), ability + " reading paused state does not advance time")
		var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(accepted))).payload
		expect(same(decoded, accepted) and SpecialPowers.remaining(decoded, 11.375) == SpecialPowers.remaining(accepted, 11.375), ability + " exact transport preserves activation and remaining time")
		var end: float = float(accepted.accepted[0].until)
		expect(SpecialPowers.remaining(accepted, end) == 0.0 and SpecialPowers.move_factor(accepted, end) == 1.0 and not SpecialPowers.frozen(accepted, end), ability + " exact end expires without changing base factor")
		expect(SpecialPowers.remaining(accepted, end + 30.0) == 0.0 and SpecialPowers.request(accepted).is_empty(), ability + " expiry never recharges daily use")
		expect(SpecialPowers.move_factor(accepted, 11.375) == (1.5 if ability == "speed_boost_v1" else 1.0), ability + " move factor is applied only by speed ability")
		expect(SpecialPowers.frozen(accepted, 11.375) == (ability == "map_freeze_v1"), ability + " freeze is an independent global effect")
		expect(not SpecialPowers.problem(accepted, BINDING, ability, 10.0).is_empty() and SpecialPowers.remaining(accepted, 10.0) == 0.0, ability + " future activation rejects")
		for mutation: String in ["extra", "missing", "version", "equipped", "duplicate", "event_extra", "event_id", "event_ability", "start", "duration", "nan", "binding"]:
			var bad: Dictionary = accepted.duplicate(true)
			match mutation:
				"extra": bad.extra = true
				"missing": bad.erase("accepted")
				"version": bad.version = 2
				"equipped": bad.equipped = ""
				"duplicate": bad.accepted.append(bad.accepted[0].duplicate(true))
				"event_extra": bad.accepted[0].remaining = 1.0
				"event_id": bad.accepted[0].id += ":retry"
				"event_ability": bad.accepted[0].ability_id = "airstrike_v1"
				"start": bad.accepted[0].at = -1.0
				"duration": bad.accepted[0].until += 0.125
				"nan": bad.accepted[0].at = NAN
				"binding": bad.binding.transaction_id = String(BINDING.run_id) + ":2"
			expect(not SpecialPowers.problem(bad, BINDING, ability, 11.375).is_empty(), ability + " strict state rejects " + mutation)
		var forged: Dictionary = proposal.duplicate(true)
		forged.extra = true
		expect(SpecialPowers.accept(state, forged, 10.125).is_empty(), ability + " extra request fields reject")
		forged = proposal.duplicate(true)
		forged.id = String(BINDING.transaction_id) + ":power:other"
		expect(SpecialPowers.accept(state, forged, 10.125).is_empty(), ability + " foreign request rejects")
		expect(SpecialPowers.accept(state, proposal, -0.1).is_empty() and SpecialPowers.accept(state, proposal, INF).is_empty(), ability + " invalid activation clocks reject")
		expect(not SpecialPowers.problem(accepted, BINDING, ability, NAN).is_empty(), ability + " nonfinite simulation clock rejects")
		var tomorrow: Dictionary = BINDING.duplicate(true)
		tomorrow.transaction_id = String(BINDING.run_id) + ":2"
		expect(not SpecialPowers.problem(accepted, tomorrow, ability, 11.375).is_empty(), ability + " other game day cannot reuse activation")
		var tomorrow_state: Dictionary = SpecialPowers.initial(tomorrow, ability)
		expect(not SpecialPowers.request(tomorrow_state).is_empty(), ability + " new original action can receive a fresh daily use")
	var malformed_binding: Dictionary = BINDING.duplicate(true)
	malformed_binding.extra = true
	expect(SpecialPowers.initial(malformed_binding, "speed_boost_v1").is_empty(), "binding fields are exact")
	malformed_binding = BINDING.duplicate(true)
	malformed_binding.transaction_id = "foreign:1"
	expect(SpecialPowers.initial(malformed_binding, "speed_boost_v1").is_empty(), "binding action belongs to journey")
	_progression()
	print(JSON.stringify({"suite":"special_powers", "checks":checks, "failures":failures, "policy_source":"PROJECT_TEMP", "scope":"PURE_COMPONENT_ONLY"}))
	quit(0 if failures == 0 else 1)


func _progression() -> void:
	var equipment: Dictionary = {"version":2, "slots":[SpecialPowers.FREEZE,SpecialPowers.SPEED],
		"investments":{"second_slot":3,"freeze":4}}
	var state: Dictionary = SpecialPowers.initial(BINDING,equipment)
	var first: Dictionary = SpecialPowers.accept(state,SpecialPowers.request(state,1),10.125)
	var both: Dictionary = SpecialPowers.accept(first,SpecialPowers.request(first,0),11.25)
	expect(both.accepted.size()==2 and same(both.accepted[0],first.accepted[0]),"second proposal appends without changing original event")
	expect(SpecialPowers.request(both).is_empty() and SpecialPowers.request(both,1).is_empty(),"each slot is spent separately")
	expect(SpecialPowers.remaining(both,12.0,0)==6.25 and SpecialPowers.remaining(both,12.0,1)==6.125,"overlap has two exact intervals")
	expect(SpecialPowers.remaining(both,12.0)==6.125,"step splits at earliest expiry")
	expect(SpecialPowers.frozen(both,18.125) and SpecialPowers.move_factor(both,18.125)==1.0,"one effect survives the other's expiry")
	var changed: Dictionary = both.duplicate(true)
	changed.accepted[1].slot = 1
	expect(SpecialPowers.problem(changed,BINDING,equipment,12.0)=="POWER_ACTIVATION_ID","slot cannot be reassigned")
	changed = both.duplicate(true)
	changed.accepted[1].until = 15.25
	expect(SpecialPowers.problem(changed,BINDING,equipment,12.0)=="POWER_EFFECT_INTERVAL","duration is derived from frozen upgrade")
	expect(SpecialPowers.problem(both,BINDING,SpecialPowers.FREEZE,12.0)=="POWER_FIELDS","historical action rejects V2 state")
	equipment.slots[1] = SpecialPowers.FREEZE
	expect(SpecialPowers.initial(BINDING,equipment).is_empty(),"duplicate loadout rejected")
