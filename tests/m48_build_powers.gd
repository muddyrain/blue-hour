extends SceneTree
## Directed pure-policy cases, not evidence of a played campaign or resource acquisition.
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_items()
	_powers()
	_support()
	print("M48_BUILD_POWERS " + JSON.stringify({"checks":checks, "failures":failures, "scope":"directed pure policies and component clocks"}))
	quit(0 if failures == 0 else 1)

func _items() -> void:
	var pool: int = BuildItems.M48_CATALOG_POOL
	for id: String in BuildItems.ids(pool):
		var slots: Array = [id, ""]
		var base: Dictionary = BuildItems.factors(slots, pool)
		var enhanced: Dictionary = BuildItems.factors(slots, pool, [id])
		var key: String = BuildItems.definitions(pool)[id].key
		_check(is_equal_approx(float(base[key]), float(BuildItems.definitions(pool)[id].factor)), "base factor " + id)
		_check(is_equal_approx(float(enhanced[key]), float(BuildItems.ENHANCED_FACTORS[id])), "enhanced factor " + id)
		_check(not BuildItems.effect_text(id, true, pool).is_empty(), "enhancement has a visible effect " + id)
	var all: Array = BuildItems.ids(pool)
	var slots: Array = ["quick_loader_v1", BuildItems.GUIDED_MAG, "light_boots_v1", BuildItems.STRIDE_HARNESS]
	var factors: Dictionary = BuildItems.factors(slots, pool, all)
	_check(is_equal_approx(factors.reload, 0.60 * 0.80) and is_equal_approx(factors.move, 1.25 * 1.20), "four unique items multiply once")
	slots.reverse()
	_check(TransactionReceipt.same(factors, BuildItems.factors(slots, pool, all)), "slot reordering cannot compound factors")
	_check(not BuildItems.problem(all, ["quick_loader_v1", "quick_loader_v1"], pool).is_empty(), "duplicate item rejected")
	_check(not BuildItems.problem([], ["", "", ""], BuildItems.SPECIALTY_POOL).is_empty(), "old policy rejects a third slot")
	_check(BuildItems.problem(all, ["", "", "", ""], pool).is_empty(), "M48 allows four empty slots")
	_check(not BuildItems.problem(all, ["", "", "", "", ""], pool).is_empty(), "M48 rejects a fifth slot")
	_check(BuildItems.factors(["", ""], pool, ["unknown"]).is_empty(), "unknown enhancement rejected")
	_check(BuildItems.heal_cooldown({"version":pool, "slots":[BuildItems.AID_KIT, ""], "enhanced":[BuildItems.AID_KIT]}) == 24.0, "equipped enhanced aid kit changes new Q cooldown")
	_check(BuildItems.heal_cooldown({"version":pool, "slots":["", ""], "enhanced":[BuildItems.AID_KIT]}) == 30.0, "unworn enhanced aid kit does not change Q")

func _powers() -> void:
	var inventory: Dictionary = PowerState.initial_progression(SpecialPowers.M48_VERSION)
	inventory.investments = {"second_slot":3, "third_slot":4, "freeze":5, "speed":5, "suppression":5, "radio":5}
	inventory.slots = [SpecialPowers.SPEED, SpecialPowers.FREEZE, SpecialPowers.SUPPRESSION]
	var loadout: Dictionary = PowerState.loadout(inventory)
	_check(SpecialPowers.loadout_valid(loadout), "three-slot M48 loadout")
	var token: Dictionary = {"run_id":"1".repeat(32), "root_id":"2".repeat(32), "transaction_id":"1".repeat(32) + ":8", "base_hash":"3".repeat(64), "rules_hash":"4".repeat(64)}
	var state: Dictionary = SpecialPowers.initial(token, loadout)
	for slot: int in range(3):
		state = SpecialPowers.accept(state, SpecialPowers.request(state, slot), float(slot))
		_check(not state.is_empty(), "independent activation in slot %d" % slot)
	_check(SpecialPowers.problem(state, token, loadout, 3.0).is_empty(), "three accepted effects validate together")
	_check(SpecialPowers.event_at(state, 0).until == 12.0 and SpecialPowers.event_at(state, 1).until == 8.0 and SpecialPowers.event_at(state, 2).until == 18.0, "upgraded intervals use each ability definition")
	_check(SpecialPowers.ability_remaining(state, SpecialPowers.FREEZE, 8.0) == 0.0 and SpecialPowers.ability_remaining(state, SpecialPowers.SPEED, 8.0) == 4.0 and SpecialPowers.ability_remaining(state, SpecialPowers.SUPPRESSION, 8.0) == 10.0, "expiry of one effect preserves the others")
	_check(SpecialPowers.request(state, 2).is_empty(), "third ability cannot consume twice")
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(state)))
	_check(decoded.error == OK and SpecialPowers.problem(decoded.payload, token, loadout, 3.0).is_empty() and RecordEncoding.fingerprint(decoded.payload) == RecordEncoding.fingerprint(state), "exact transport preserves independent clocks")
	_check(SpecialPowers.radio_amount(loadout) == 40.0, "upgraded broadcast cap")
	var old: Dictionary = PowerState.loadout(PowerState.initial_progression(SpecialPowers.M47_VERSION))
	_check(SpecialPowers.radio_amount(old) == 24.0 and SpecialPowers.effect_duration(old, SpecialPowers.SPEED) == 8.0, "old catalog keeps original radio and speed")
	var forged: Dictionary = loadout.duplicate(true)
	forged.investments.second_slot = 0
	_check(not SpecialPowers.loadout_valid(forged), "cannot buy third slot ahead of second")
	forged = loadout.duplicate(true)
	forged.slots[2] = SpecialPowers.FREEZE
	_check(not SpecialPowers.loadout_valid(forged), "same ability cannot occupy two slots")
	forged = state.duplicate(true)
	forged.accepted[2].until += 1.0
	_check(not SpecialPowers.problem(forged, token, loadout, 3.0).is_empty(), "forged enhanced interval rejected")
	var recovery: Dictionary = BasicSupport.plan_recovery([{"member_id":1,"health":85.0,"max_health":100.0,"present":true}], SpecialPowers.radio_amount(loadout))
	_check(recovery.amount == 15.0, "broadcast obeys maximum health")
	_check(BasicSupport.plan_recovery([{"member_id":1,"health":100.0,"max_health":100.0,"present":true}],40.0).is_empty(), "broadcast without eligible target has no proposal")

func _support() -> void:
	var support: BasicSupport = BasicSupport.new()
	support.configure({"transaction_id":"m48-directed"})
	var request: Dictionary = support.request("heal", {"member_id":1,"amount":10.0})
	_check(support.accept(request, {}, 24.0), "enhanced Q accepts explicit frozen cooldown")
	support.advance(23.5, true)
	_check(not support.ready("heal") and support.remaining("heal") == 0.5, "Q cannot be recast before upgraded cooldown")
	var before: Dictionary = support.snapshot()
	var resumed: BasicSupport = BasicSupport.new()
	resumed.restore(before)
	_check(resumed.remaining("heal") == 0.5, "restore does not erase an existing cooldown")
	resumed.advance(0.5, true)
	_check(resumed.ready("heal"), "Q becomes available at exact boundary")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("M48_BUILD_POWERS_FAIL " + message)
