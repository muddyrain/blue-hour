extends SceneTree
## Pure catalogue/identity fixtures; no roster admission, actor effect or save-flow claim.

const SEED_ONE: String = "00000000000000000000000000000001"
const SEED_F: String = "ffffffffffffffffffffffffffffffff"
const VECTOR_ONE: Array = [
	["keen_search_v1", "clumsy_reload_v1"], ["light_step_v1", "clumsy_reload_v1"],
	["ranged_focus_v1", "distracted_search_v1"], ["melee_practice_v1", "distracted_search_v1"],
	["melee_practice_v1", "clumsy_reload_v1"],
]
const VECTOR_F: Array = [
	["keen_search_v1", "heavy_step_v1"], ["keen_search_v1", "clumsy_reload_v1"],
	["melee_practice_v1", "heavy_step_v1"], ["ranged_focus_v1", "distracted_search_v1"],
	["quick_hands_v1", "distracted_search_v1"],
]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("PERSONA_RULES_FAIL " + label)


func recipe(positive: String, negative: String, id: int = 1) -> Dictionary:
	return {"member_id":id, "definition_id":"crew_%d" % id, "positive_id":positive, "negative_id":negative}


func near(value: float, expected: float) -> bool:
	return absf(value - expected) < 0.0000000001


func _generation() -> void:
	for index: int in range(32):
		var seed: String = ("persona-v1-fixture-%d" % index).md5_text()
		var first: Dictionary = SurvivorPersona.generate(seed)
		var second: Dictionary = SurvivorPersona.generate(seed)
		expect(SurvivorPersona.problem(first, seed).is_empty() and first == second, "seed %d has one stable five-person recomputation" % index)
		var pairs: Dictionary = {}
		for id: int in range(1, 6):
			var person: Dictionary = SurvivorPersona.member(first, id, "crew_%d" % id)
			var again: Dictionary = SurvivorPersona.member(second, id)
			expect(not person.is_empty() and person == again and SurvivorPersona.recipe_problem(person).is_empty(), "seed %d stable member %d recipe" % [index, id])
			pairs[person.positive_id + "|" + person.negative_id] = true
		expect(pairs.size() == 5, "seed %d assigns five distinct compatible pairs" % index)
	for fixture: Dictionary in [{"seed":SEED_ONE, "pairs":VECTOR_ONE}, {"seed":SEED_F, "pairs":VECTOR_F}]:
		var generated: Dictionary = SurvivorPersona.generate(fixture.seed)
		for index: int in range(5):
			var row: Dictionary = generated.members[index]
			expect(row.member_id == index + 1 and row.definition_id == "crew_%d" % (index + 1) and row.positive_id == fixture.pairs[index][0] and row.negative_id == fixture.pairs[index][1], "known vector %s member %d" % [fixture.seed, index + 1])
	var original: Dictionary = SurvivorPersona.generate(SEED_ONE)
	var detached: Dictionary = SurvivorPersona.member(original, 1)
	detached.positive_id = "ranged_focus_v1"
	expect(original.members[0].positive_id == "keen_search_v1", "member reads return detached facts")
	expect(SurvivorPersona.member(original, 0).is_empty() and SurvivorPersona.member(original, 6).is_empty() and SurvivorPersona.member(original, 1, "crew_2").is_empty(), "unknown or mismatched stable identities return no recipe")
	var transported: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(original))).payload
	expect(SurvivorPersona.problem(transported, SEED_ONE).is_empty(), "exact transport retains versioned identity and seeded source")
	var catalogue: Dictionary = SurvivorPersona.policy()
	catalogue.positive.ranged_focus_v1.factor = 90.0
	expect(SurvivorPersona.policy().positive.ranged_focus_v1.factor == 1.15, "policy views cannot mutate version-one definitions")


func _numeric_factors() -> void:
	var cases: Array[Dictionary] = [
		{"positive":"ranged_focus_v1", "negative":"heavy_step_v1", "metric":"ranged", "factor":1.15},
		{"positive":"melee_practice_v1", "negative":"heavy_step_v1", "metric":"melee", "factor":1.20},
		{"positive":"light_step_v1", "negative":"clumsy_reload_v1", "metric":"move", "factor":1.10},
		{"positive":"quick_hands_v1", "negative":"heavy_step_v1", "metric":"reload", "factor":0.85},
		{"positive":"keen_search_v1", "negative":"heavy_step_v1", "metric":"work", "factor":0.85},
		{"positive":"ranged_focus_v1", "negative":"heavy_step_v1", "metric":"move", "factor":0.90},
		{"positive":"ranged_focus_v1", "negative":"clumsy_reload_v1", "metric":"reload", "factor":1.15},
		{"positive":"ranged_focus_v1", "negative":"distracted_search_v1", "metric":"work", "factor":1.15},
	]
	for fixture: Dictionary in cases:
		var factors: Dictionary = SurvivorPersona.factors(recipe(fixture.positive, fixture.negative))
		expect(factors.size() == 5 and factors[fixture.metric] == fixture.factor, "fixed trait factor " + fixture.positive + "/" + fixture.negative + "/" + fixture.metric)
	var ranged: Dictionary = SurvivorPersona.factors(recipe("ranged_focus_v1", "heavy_step_v1"))
	var melee: Dictionary = SurvivorPersona.factors(recipe("melee_practice_v1", "heavy_step_v1"))
	var reload: Dictionary = SurvivorPersona.factors(recipe("ranged_focus_v1", "clumsy_reload_v1"))
	var work: Dictionary = SurvivorPersona.factors(recipe("keen_search_v1", "heavy_step_v1"))
	var move: Dictionary = SurvivorPersona.factors(recipe("light_step_v1", "clumsy_reload_v1"))
	expect(near(18.0 * ranged.ranged, 20.7), "carbine with personal ranged trait is 20.7")
	expect(near(18.0 * ranged.ranged * 1.20, 24.84), "carbine personal and original pressure-round factors apply once")
	expect(near(34.0 * melee.melee, 40.8) and melee.ranged == 1.0 and ranged.melee == 1.0, "axe personal factor is 40.8 and weapon categories remain independent")
	expect(near(1.6 * reload.reload * 0.75, 1.38), "clumsy reload and quick-loader duration is 1.38")
	expect(near(30.0 * 0.70 * work.work * 0.75, 13.3875), "fastest legal work combination is 13.3875 seconds")
	expect(near(125.0 * move.move * 1.50, 206.25), "light-step and special-speed factor is 206.25")
	expect(ranged.reload == 1.0 and ranged.work == 1.0 and work.ranged == 1.0 and work.reload == 1.0, "unaffected personal metrics retain their exact neutral factors")


func _negative_cases() -> void:
	for seed: String in ["", "0000000000000000000000000000001", "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF", "0000000000000000000000000000000x", " 0000000000000000000000000000001"]:
		expect(SurvivorPersona.generate(seed).is_empty() and not SurvivorPersona.problem({}, seed).is_empty(), "seed is exact lowercase 32-character hexadecimal")
	for pair: Array in SurvivorPersona.INCOMPATIBLE_PAIRS:
		var bad_pair: Dictionary = recipe(pair[0], pair[1])
		expect(SurvivorPersona.recipe_problem(bad_pair) == "PERSONA_RECIPE_INCOMPATIBLE" and SurvivorPersona.factors(bad_pair).is_empty(), "incompatible pair never silently yields neutral factors " + pair[0])
	for mutation: String in ["missing", "extra", "fractional_id", "bool_id", "unknown_id", "definition", "positive", "negative", "reversed"]:
		var bad_recipe: Dictionary = recipe("ranged_focus_v1", "heavy_step_v1")
		match mutation:
			"missing": bad_recipe.erase("negative_id")
			"extra": bad_recipe.factor = 1.0
			"fractional_id": bad_recipe.member_id = 1.5
			"bool_id": bad_recipe.member_id = true
			"unknown_id": bad_recipe.member_id = 6
			"definition": bad_recipe.definition_id = "crew_2"
			"positive": bad_recipe.positive_id = "unknown_v1"
			"negative": bad_recipe.negative_id = []
			"reversed": bad_recipe.positive_id = "heavy_step_v1"
		expect(not SurvivorPersona.recipe_problem(bad_recipe).is_empty() and SurvivorPersona.factors(bad_recipe).is_empty(), "malformed recipe rejects " + mutation)
	expect(SurvivorPersona.factors(null).is_empty() and SurvivorPersona.factors([]).is_empty(), "nonobject recipe fails closed")
	var original: Dictionary = SurvivorPersona.generate(SEED_ONE)
	for mutation: String in ["missing", "extra", "version", "catalogue", "seed", "uppercase", "members", "count", "row", "order", "duplicate"]:
		var bad: Dictionary = original.duplicate(true)
		match mutation:
			"missing": bad.erase("members")
			"extra": bad.revealed = []
			"version": bad.version = 2
			"catalogue": bad.catalog_id = "BH_SURVIVOR_PERSONA_V2"
			"seed": bad.seed = SEED_F
			"uppercase": bad.seed = SEED_F.to_upper()
			"members": bad.members = {}
			"count": bad.members.pop_back()
			"row":
				var rows: Array = []
				for row: Variant in bad.members:
					rows.append(row)
				rows[0] = null
				bad.members = rows
			"order": bad.members.reverse()
			"duplicate":
				bad.members[1].positive_id = bad.members[0].positive_id
				bad.members[1].negative_id = bad.members[0].negative_id
		expect(not SurvivorPersona.problem(bad, SEED_ONE).is_empty(), "strict versioned fact rejects " + mutation)
	var altered: Dictionary = original.duplicate(true)
	altered.members[0] = recipe("quick_hands_v1", "heavy_step_v1")
	expect(SurvivorPersona.problem(altered, SEED_ONE) == "PERSONA_SOURCE", "otherwise legal unique recipe cannot replace seeded source")
	expect(not SurvivorPersona.problem(original, SEED_F).is_empty(), "external journey seed binds the entire recipe fact")


func _camp_fixture() -> Dictionary:
	# The same initializers as Main, without a scene, disk write or simulated completion.
	var crew: Array[Dictionary] = SurvivorRoster.new_crew()
	GrowthRules.initialize(crew)
	TraitRules.initialize(crew)
	TrainingState.initialize(crew)
	var camp: Dictionary = {"schema_version":5, "profile_id":"0123456789abcdef0123456789abcdef",
		"day":2, "cash":53, "food":RunSave.DefaultRules.initial_food, "last_day":{},
		"settled_sorties":0, "last_settlement_id":"", "crew":crew}
	WeaponInventory.initialize(camp, "initial")
	for index: int in range(camp.weapons.size()):
		camp.weapons[index] = WeaponModifiers.baseline(camp.weapons[index])
	var journey: Dictionary = EnemyState.initial("persona-actions-fixture")
	journey.campaign = CampaignRules.initial(camp.profile_id)
	journey.build = PersonaState.initial_build(journey.seed)
	return EnemyState.snapshot(camp, journey, [], [])



func _dispatch_current() -> void:
	var base: Dictionary = _camp_fixture()
	base.journey.build = WorldgenState.initial_build(base.journey.seed, true, true)
	var offers: Array[Dictionary] = DailyActions.offers(base)
	expect(offers.size() == 3, "current journey exposes three persona-bearing exploration offers")
	for offer: Dictionary in offers:
		expect(DailyActions.problem(offer).is_empty() and DailyActions.matches(base, offer), "current persona source authenticates")
		var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(offer))).payload
		expect(TransactionReceipt.same(decoded, offer) and DailyActions.matches(base, decoded), "exact current source transport retains persona provenance")
		var changed: Dictionary = offer.duplicate(true)
		changed.persona.facts.members[0].positive_id = "unknown_v1"
		expect(not DailyActions.problem(changed).is_empty(), "current frozen recipe rejects an unknown trait")


func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	_generation()
	_numeric_factors()
	_negative_cases()
	_dispatch_current()
	print(JSON.stringify({"suite":"persona_rules", "checks":checks, "failures":failures, "policy_source":"PROJECT_TEMP", "scope":"PURE_CATALOGUE_AND_SEEDED_IDENTITY"}))
	quit(0 if failures == 0 else 1)
