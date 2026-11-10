extends SceneTree
## Pure inventory boundaries; no player state, saved progress or gameplay completion injection.

const RUN: String = "0123456789abcdef0123456789abcdef"
const SEED: String = "fedcba9876543210fedcba9876543210"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("BUILD_ITEMS_FAIL " + label)


func run() -> void:
	_test_definitions_and_slots()
	_test_drop()
	_test_catalog_pool()
	_test_specialty_gear()
	print(JSON.stringify({"checks":checks, "failures":failures,
		"scope":"pure passive definitions, frozen drops, inventory and two-slot factors",
		"gameplay_acquisition":"A integration acceptance required", "source":"PROJECT_TEMP"}))
	quit(0 if failures == 0 else 1)


func _test_catalog_pool() -> void:
	var context: Dictionary = _context()
	var original: Array[String] = BuildItems.ids()
	var pool: int = BuildItems.CATALOG_POOL
	var mask: String = BuildItems.FILTER
	expect(BuildItems.drop(context, []).size() == 2 and BuildItems.drop(context, original).is_empty(),
		"original pool keeps its candidates and is exhausted after six")
	context.version = pool
	expect(BuildItems.drop(context, original).is_empty() and BuildItems.drop(context, original, pool) == [mask],
		"only an authorized V2 context can roll the seventh item")
	expect(BuildItems.drop(context, original + [mask], pool).is_empty(), "owned mask cannot roll again")
	context.version = BuildItems.VERSION
	var legacy_drops: Array[String] = BuildItems.drop(context, [mask], pool)
	expect(legacy_drops.size() == 2 and legacy_drops.all(func(id: String) -> bool: return id in original)
		and BuildItems.drop(context, [], pool) == BuildItems.drop(context, []),
		"V1 contexts in V2 journeys retain the six candidates")
	expect(not BuildItems.problem([mask], [mask, ""]).is_empty()
		and BuildItems.problem([mask], [mask, ""], pool).is_empty(), "only V2 inventory can equip the mask")
	var equipped: Dictionary = BuildItems.frozen_factors({"version":pool, "slots":[mask, ""]})
	expect(equipped.get("poison") == 0.5 and BuildItems.factors(["", ""], pool).get("poison", 1.0) == 1.0,
		"equipping the frozen mask changes the periodic poison factor")
	equipped.erase("poison")
	expect(equipped == BuildItems.BASE_FACTORS, "the mask preserves all six historical factors")


func _test_specialty_gear() -> void:
	var pool: int = BuildItems.SPECIALTY_POOL
	var context: Dictionary = _context()
	var action: Dictionary = BuildActions.with_gear_drops({
		"version":9, "type":"airdrop", "slot":2, "mission_policy":1, "campaign":{"is_finale":false},
		"layout":{"topology":"commercial"}, "objective":{"site_ids":["cash"]},
		"sites":[{"id":"cash", "source":"primary", "weapon":true, "work_mode":"outdoor", "seconds":12.0}],
		"build":{"version":pool, "drop_context":context, "owned":[]},
		"powers":{"version":SpecialPowers.M47_VERSION, "owned":[], "sample":""},
	})
	var policy: Dictionary = {"plan":"scavenge", "eligible":[SpecialPowers.RADIO, BuildItems.GUIDED_MAG, BuildItems.STRIDE_HARNESS]}
	var preferred: Dictionary = BuildActions.with_specialization_drop(action, policy)
	expect(BuildActions.specialization_candidate(preferred) == BuildItems.STRIDE_HARNESS
		and preferred.build.drops.size() == action.build.drops.size() and preferred.sites == action.sites,
		"own specialty replaces exactly one normal item on the same site")
	var owned: Dictionary = action.duplicate(true)
	owned.build.owned = [BuildItems.STRIDE_HARNESS]
	var radio: Dictionary = BuildActions.with_specialization_drop(owned, policy)
	expect(BuildActions.specialization_candidate(radio) == SpecialPowers.RADIO
		and radio.build.drops.size() + 1 == action.build.drops.size() and radio.sites == action.sites,
		"first shared ID occupies an existing gear position as a power sample")
	owned.powers.owned = [SpecialPowers.RADIO]
	var next: Dictionary = BuildActions.with_specialization_drop(owned, policy)
	expect(BuildActions.specialization_candidate(next) == BuildItems.GUIDED_MAG,
		"both passive and power ownership remove candidates in stable shared order")
	for flag: String in ["rare_policy", "investigation", "event_sortie", "finale_policy", "billboard_target"]:
		var dedicated: Dictionary = action.duplicate(true)
		dedicated[flag] = true
		expect(BuildActions.with_specialization_drop(dedicated, policy) == dedicated, "dedicated source excluded " + flag)
	var industrial: Dictionary = action.duplicate(true)
	industrial.layout.topology = "industrial"
	industrial.layout.loading_yard = {}
	expect(BuildActions.with_specialization_drop(industrial, policy) == industrial, "industrial yard keeps its reward")
	var mask_only: Dictionary = action.duplicate(true)
	mask_only.build.drops = [BuildItems.FILTER]
	expect(BuildActions.with_specialization_drop(mask_only, policy) == mask_only, "mask does not open a replaceable position")
	var depleted: Dictionary = action.duplicate(true)
	depleted.build.drops = []
	expect(BuildActions.with_specialization_drop(depleted, policy) == depleted, "no normal position retains original rewards")
	expect(BuildActions.with_specialization_drop(action, {"plan":"scavenge", "eligible":[]}) == action,
		"opening choice without catalog eligibility keeps original rewards")
	expect(BuildState.acquired(preferred, {"cash":{"searched":true}}, true) == preferred.build.drops
		and BuildState.acquired(preferred, {"cash":{"searched":true}}, false).is_empty()
		and BuildState.acquired(preferred, {"cash":{"searched":false}}, true).is_empty(),
		"only a successful return with the real cash work fact acquires the specialty item")
	expect(is_equal_approx(BuildItems.factors(["quick_loader_v1", BuildItems.GUIDED_MAG], pool).reload, 0.75 * 0.90)
		and is_equal_approx(BuildItems.factors([BuildItems.GUIDED_MAG, "quick_loader_v1"], pool).reload, 0.75 * 0.90),
		"guided magazine multiplies original reload independently of slot order")
	expect(is_equal_approx(BuildItems.factors([BuildItems.STRIDE_HARNESS, ""], pool).move, 1.10)
		and BuildItems.factors([BuildItems.STRIDE_HARNESS, ""], pool).work == 1.0,
		"stride changes movement without changing work")
	expect(is_equal_approx(BuildItems.factors([BuildItems.AID_KIT, ""], pool).heal, 1.20)
		and BuildItems.factors(["", ""], pool).heal == 1.0
		and BuildItems.factors([BuildItems.AID_KIT, ""], BuildItems.WAVE_POOL).is_empty(),
		"support starter applies only while equipped in the new pool")


func _test_definitions_and_slots() -> void:
	var ids: Array[String] = BuildItems.ids()
	var definitions: Dictionary = BuildItems.definitions()
	expect(ids.size() == 6 and definitions.size() == 6, "exactly six original passive IDs")
	expect(BuildItems.problem([], ["", ""]).is_empty(), "empty initial inventory and slots are valid")
	expect(BuildItems.problem(ids, [ids[0], ids[5]]).is_empty(), "two different owned passives are valid")
	var expected_keys: Array[String] = ["damage", "reload", "move", "work", "blast", "heal"]
	var expected_factors: Array[float] = [1.20, 0.75, 1.15, 0.75, 1.30, 1.50]
	for index: int in range(ids.size()):
		var id: String = ids[index]
		var factor: Dictionary = BuildItems.factors([id, ""])
		expect(definitions[id].source == "PROJECT_TEMP" and definitions[id].name.length() == 4,
			"definition scope and original name " + id)
		expect(factor[expected_keys[index]] == expected_factors[index], "approved V1 factor " + id)
		for key: String in expected_keys:
			expect(factor[key] == (expected_factors[index] if key == expected_keys[index] else 1.0),
				"passive changes only its own effect " + id + ":" + key)
		expect(BuildItems.factors([id, ""]) == factor, "repeated derivation cannot compound " + id)
		factor[expected_keys[index]] = 999.0
		expect(BuildItems.factors([id, ""])[expected_keys[index]] == expected_factors[index],
			"caller cannot mutate factor source " + id)
	var three: Array = [ids[0], ids[1], ids[2]]
	var slots: Array = [ids[0], ids[1]]
	expect(BuildItems.problem(three, slots).is_empty(), "inventory can exceed two slots")
	expect(BuildItems.factors(slots).move == 1.0, "owned unequipped boots do not apply")
	slots[0] = ids[2]
	expect(BuildItems.problem(three, slots).is_empty(), "third item legally replaces occupied slot")
	expect(BuildItems.factors(slots).damage == 1.0 and BuildItems.factors(slots).move == 1.15,
		"replacement removes previous effect")
	slots[1] = ""
	expect(BuildItems.problem(three, slots).is_empty() and BuildItems.factors(slots).reload == 1.0,
		"unloading preserves owned item without its effect")
	expect(three.size() == 3, "slot operations preserve inventory")
	for bad: Variant in [null, {}, [ids[0], ids[0]], ["unknown"], [1], [true], [StringName(ids[0])]]:
		expect(not BuildItems.problem(bad, ["", ""]).is_empty(), "reject malformed owned " + str(bad))
	for bad: Variant in [null, {}, [], [""], ["", "", ""], [ids[0], ids[0]], ["unknown", ""], [1, ""], [true, ""]]:
		expect(not BuildItems.problem(ids, bad).is_empty(), "reject malformed slots " + str(bad))
	expect(not BuildItems.problem([], [ids[0], ""]).is_empty(), "cannot equip an unowned item")
	expect(BuildItems.factors([ids[0], ids[0]]).is_empty(), "duplicate slot never doubles a factor")
	expect(BuildItems.factors(["unknown", ""]).is_empty(), "unknown factor is not silently corrected")
	ids.append("injected")
	definitions.pressure_rounds_v1.factor = 999.0
	expect(BuildItems.ids().size() == 6 and BuildItems.definitions().pressure_rounds_v1.factor == 1.20,
		"external UI cannot modify definitions or order")


func _test_drop() -> void:
	var context: Dictionary = _context()
	var original: Dictionary = context.duplicate(true)
	var first: Array[String] = BuildItems.drop(context, [])
	expect(first == ["pressure_rounds_v1", "light_boots_v1"], "V1 frozen drop golden identity")
	expect(first.size() == 2 and first[0] != first[1], "empty inventory drops two distinct items")
	expect(BuildItems.drop(context, []) == first, "cancel browse or reload cannot reroll same candidate")
	expect(context == original, "drop does not mutate frozen context")
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(context))
	expect(BuildItems.drop(decoded, []) == first, "JSON decoded integral numbers preserve drop")
	var reordered: Dictionary = {"version":1.0, "site_id":"cash", "day":2.0,
		"seed":SEED, "action_id":"frozen-action-01", "run_id":RUN}
	expect(BuildItems.drop(reordered, []) == first, "dictionary insertion order cannot reroll drop")
	var known: Array[String] = BuildItems.ids()
	for count: int in range(7):
		var owned: Array = known.slice(0, count)
		var copy: Array = owned.duplicate(true)
		var result: Array[String] = BuildItems.drop(context, owned)
		expect(result.size() == mini(2, 6 - count), "remaining pool count %d" % count)
		for id: String in result:
			expect(id in known and id not in owned, "only a not-yet-owned definition can drop %d" % count)
		owned.reverse()
		expect(BuildItems.drop(context, owned) == result, "inventory order irrelevant %d" % count)
		owned.reverse()
		expect(owned == copy, "drop leaves owned collection intact %d" % count)
	expect(BuildItems.drop(context, known.slice(0, 5)) == [known[5]], "last item is awarded without replacement currency")
	expect(BuildItems.drop(context, known).is_empty(), "complete set awards no passive")
	var next: Array[String] = BuildItems.drop(context, first)
	expect(next.size() == 2 and next[0] not in first and next[1] not in first,
		"confirmed prior acquisitions are excluded")
	var all: Array = first.duplicate()
	all.append_array(next)
	all.append_array(BuildItems.drop(context, all))
	expect(all.size() == 6 and BuildItems.problem(all, ["", ""]).is_empty(), "three acquisitions exhaust six unique items")
	var variations: Dictionary = {}
	for day: int in [2, 3, 4, 5]:
		var candidate: Dictionary = context.duplicate(true)
		candidate.day = day
		variations[str(BuildItems.drop(candidate, []))] = true
	expect(variations.size() > 1, "small fixed-day sample is not a hardcoded pair")
	for key: String in BuildItems.CONTEXT_KEYS:
		var bad: Dictionary = context.duplicate(true)
		bad.erase(key)
		expect(BuildItems.drop(bad, []).is_empty(), "missing frozen context rejected " + key)
	for change: String in ["extra", "version", "day_fraction", "day_bool", "day_negative", "run", "seed", "action", "site"]:
		var bad: Dictionary = context.duplicate(true)
		match change:
			"extra":
				bad.extra = "not committed"
			"version":
				bad.version = 2
			"day_fraction":
				bad.day = 2.5
			"day_bool":
				bad.day = true
			"day_negative":
				bad.day = -1
			"run":
				bad.run_id = "foreign"
			"seed":
				bad.seed = "not-a-seed"
			"action":
				bad.action_id = ""
			"site":
				bad.site_id = 3
		expect(BuildItems.drop(bad, []).is_empty(), "bad frozen context rejected " + change)
	expect(BuildItems.drop(context, ["unknown"]).is_empty(), "unknown owned cannot authorize new drop")
	seed(8713)
	var expected_random: int = randi()
	seed(8713)
	BuildItems.drop(context, [])
	expect(randi() == expected_random, "drop does not consume global random sequence")
	print("BUILD_ITEMS_FIXED_DROP=" + JSON.stringify(first))


func _context() -> Dictionary:
	return {"run_id":RUN, "seed":SEED, "day":2, "action_id":"frozen-action-01", "site_id":"cash", "version":1}
