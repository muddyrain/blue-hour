extends SceneTree
## Controlled actors, clocks and parameter fixtures only. No played or saved journey result.

class ClockWorld extends Expedition:
	var completions: Array[Dictionary] = []
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func _update_ui() -> void:
		pass
	func _complete_search(actor: FieldActor, site: Expedition.SearchSite) -> bool:
		# A readout sink for the real progress integrator; it grants no loot, XP or inventory.
		completions.append({"member_id":actor.member_id, "elapsed":elapsed, "progress":site.progress})
		site.searched = true
		search_assignments.release_member(actor.member_id)
		return true

const SEED: String = "ffffffffffffffffffffffffffffffff"
const BINDING: Dictionary = {
	"run_id":"0123456789abcdef0123456789abcdef", "root_id":"fedcba9876543210fedcba9876543210",
	"transaction_id":"0123456789abcdef0123456789abcdef:1",
	"base_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
	"rules_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
}

var checks: int = 0
var failures: int = 0
var observations: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("PERSONA_RUNTIME_FAIL " + label)


func near(value: float, expected: float, tolerance: float = 0.000000001) -> bool:
	return absf(value - expected) <= tolerance


func _profile(id: int, trait_level: int = 1) -> Dictionary:
	var crew: Array[Dictionary] = [{"id":id, "health":200.0}]
	SurvivorRoster.initialize(crew)
	GrowthRules.initialize(crew)
	TraitRules.initialize(crew)
	TrainingState.initialize(crew)
	# A permitted Lv5 factor fixture; no assertion of earned training or saved history.
	crew[0].growth.trait.level = trait_level
	crew[0].growth.trait.progress = TraitRules.THRESHOLDS[trait_level - 1]
	return crew[0]


func _item(id: int, gun: String) -> Dictionary:
	return WeaponModifiers.baseline({"instance_id":"controlled-persona:%d:%s" % [id, gun],
		"weapon_id":gun, "condition":"ready", "origin":"initial", "acquired_sortie":""})


func _world(slots: Array, task_type: String = "equipment") -> ClockWorld:
	var world: ClockWorld = ClockWorld.new()
	world.supply = MissionSupply.new()
	world.supply.generated = {"version":8, "seed":SEED, "type":task_type, "build":{"slots":slots.duplicate()},
		"sites":[{"id":"cash", "point":[400.0, 400.0], "building":"" if task_type == "airdrop" else "controlled-building"}],
		"persona":{"facts":SurvivorPersona.generate(SEED), "policy":SurvivorPersona.policy()}}
	root.add_child(world)
	return world


func _actor(world: ClockWorld, profile: Dictionary, gun: String, point: Vector2) -> FieldActor:
	var actor: FieldActor = FieldActor.new()
	actor.member_id = int(profile.id)
	actor.definition_id = StringName(profile.definition_id)
	actor.position = point
	actor.weapon_instance_id = _item(actor.member_id, gun).instance_id
	actor.weapon_definition = WeaponModifiers.combat_definition(_item(actor.member_id, gun))
	if not CombatEquipment.melee(gun):
		actor.magazine = WeaponMagazine.new(actor.weapon_instance_id, gun)
	world.add_child(actor)
	world.apply_build(actor, profile, _item(actor.member_id, gun))
	world.survivors.append(actor)
	return actor


func _movement_and_reload() -> void:
	var world: ClockWorld = _world(["light_boots_v1", "quick_loader_v1"])
	var first: FieldActor = _actor(world, _profile(1), "carbine", Vector2(200, 300))
	var second: FieldActor = _actor(world, _profile(2), "carbine", Vector2(200, 700))
	var actors: Array[FieldActor] = [first, second]
	for actor: FieldActor in actors:
		actor.command_path(PackedVector2Array([actor.position, actor.position + Vector2(1100, 0)]))
	var navigation: FieldNavigation = FieldNavigation.new()
	navigation.configure([])
	for tick: int in range(10):
		world.elapsed += 0.1
		FieldContacts.move(actors, actors, navigation, 0.1)
	var moved: Array[float] = [first.position.x - 200.0, second.position.x - 200.0]
	expect(near(first.speed, 125.0 * 0.90 * 1.15) and near(second.speed, 125.0 * 1.15), "two actors derive distinct personal move speeds in one world")
	expect(near(moved[0], first.speed, 0.01) and near(moved[1], second.speed, 0.01) and moved[1] > moved[0], "same-clock swept path displacement reflects each person's own factor")
	for actor: FieldActor in actors:
		for shot: int in range(actor.magazine.capacity()):
			actor.magazine.commit_shot()
	var reloaded: Array[float] = [-1.0, -1.0]
	for tick: int in range(1, 151):
		for index: int in range(actors.size()):
			actors[index].magazine.advance(0.01)
			if reloaded[index] < 0.0 and not actors[index].magazine.reloading:
				reloaded[index] = tick * 0.01
	expect(near(first.magazine.seconds(), 1.2) and near(second.magazine.seconds(), 1.38), "same gun and passive retain independent personal reload durations")
	expect(near(reloaded[0], 1.2, 0.01) and near(reloaded[1], 1.38, 0.01) and reloaded[1] > reloaded[0], "actual magazines finish on their own simulated reload clocks")
	observations.movement = moved
	observations.reload_finished = reloaded
	world.free()


func _repeat_derivation() -> void:
	var world: ClockWorld = _world(["pressure_rounds_v1", "quick_loader_v1"])
	for fixture: Dictionary in [{"id":4, "gun":"carbine", "damage":24.84},
		{"id":3, "gun":"fire_axe_v1", "damage":40.8}, {"id":4, "gun":"shotgun_v1", "damage":12.42}]:
		var profile: Dictionary = _profile(int(fixture.id))
		var item: Dictionary = _item(int(fixture.id), fixture.gun)
		var actor: FieldActor = _actor(world, profile, fixture.gun, Vector2(400, 1000))
		var interval: float = actor.weapon_definition.shot_interval(actor.trait_shot_factor)
		var rounds: int = 0
		if actor.magazine != null:
			actor.magazine.commit_shot()
			rounds = actor.magazine.rounds
		for repeat: int in range(12):
			world.apply_build(actor, profile, item)
		expect(near(actor.weapon_definition.damage, float(fixture.damage)) and actor.weapon_definition.shot_interval(actor.trait_shot_factor) == interval, "repeated fresh-instance derivation never compounds damage or interval " + fixture.gun)
		expect(actor.magazine == null or actor.magazine.rounds == rounds, "rederivation does not refill ammunition " + fixture.gun)
		if fixture.gun == "shotgun_v1":
			expect(near(actor.weapon_definition.damage * 5.0, 62.1) and actor.magazine.capacity() == 4, "shotgun personal damage acts once per pellet without changing capacity")
		var fresh: Dictionary = SpecialPowers.initial(BINDING, "speed_boost_v1")
		world.powers = SpecialPowers.accept(fresh, SpecialPowers.request(fresh), 0.0)
		world.elapsed = 1.0
		world.apply_build(actor, profile, item)
		expect(near(actor.effective_speed(), actor.speed * 1.5) and near(actor.weapon_definition.damage, float(fixture.damage)), "active speed ability affects movement alone after rederivation " + fixture.gun)
		world.elapsed = 8.0
		world.apply_build(actor, profile, item)
		expect(actor.effective_speed() == actor.speed and near(actor.weapon_definition.damage, float(fixture.damage)), "ability expiry restores exact base without stripping personal damage " + fixture.gun)
		world.survivors.erase(actor)
		actor.free()
	expect(WeaponInventory.definition("carbine").damage == 18.0 and CombatEquipment.definition("fire_axe_v1").damage == 34.0 and CombatEquipment.definition("shotgun_v1").damage == 9.0, "runtime derivation never mutates original weapon resources")
	world.free()


func _work_progress(seconds: float) -> void:
	var world: ClockWorld = _world(["field_tools_v1", ""], "airdrop" if seconds == 12.0 else "equipment")
	var profile: Dictionary = _profile(2, 5)
	var actor: FieldActor = _actor(world, profile, "carbine", Vector2(400, 400))
	var site: Expedition.SearchSite = Expedition.SearchSite.new(&"cash", actor.position)
	site.seconds = seconds
	world.sites.assign([site])
	world._cash_site = site
	world.search_assignments.assign(actor.member_id, "cash")
	world.search_assignments.begin(actor.member_id)
	actor.activity = FieldActor.Activity.RECOVERING if seconds == 12.0 else FieldActor.Activity.SEARCHING
	actor.visible = seconds == 12.0
	var expected: float = seconds * 0.70 * 0.85 * 0.75
	world.elapsed = 1.0
	world._update_search(1.0)
	expect(near(site.progress, 1.0 / (0.70 * 0.85 * 0.75)), "actual work integrator advances the original %.0f-second site with each factor once" % seconds)
	for tick: int in range(ceili(expected * 100.0) + 2):
		if not world.completions.is_empty():
			break
		world.elapsed += 0.01
		world._update_search(0.01)
	expect(world.completions.size() == 1 and near(world.completions[0].elapsed, expected, 0.011), "real progress reaches the original %.0f-second threshold at the derived duration" % seconds)
	if seconds == 30.0:
		expect(near(expected, 13.3875), "fastest permitted Lv5/persona/tool composition is exactly 13.3875 seconds")
	observations["work_%.0f" % seconds] = world.completions[0].elapsed if not world.completions.is_empty() else -1.0
	world.free()


func _context() -> Dictionary:
	var crew: Array[Dictionary] = SurvivorRoster.new_crew()
	GrowthRules.initialize(crew)
	TraitRules.initialize(crew)
	TrainingState.initialize(crew)
	var camp: Dictionary = {"schema_version":5, "profile_id":BINDING.run_id, "day":2, "cash":53,
		"food":RunSave.DefaultRules.initial_food, "last_day":{}, "settled_sorties":0, "last_settlement_id":"", "crew":crew}
	WeaponInventory.initialize(camp, "initial")
	for index: int in range(camp.weapons.size()):
		camp.weapons[index] = WeaponModifiers.baseline(camp.weapons[index])
	var journey: Dictionary = EnemyState.initial("persona-runtime-context")
	journey.seed = SEED
	journey.campaign = CampaignRules.initial(camp.profile_id)
	journey.build = PersonaState.initial_build(SEED)
	var result: Dictionary = EnemyState.snapshot(camp, journey, [], [])
	return RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(result))).payload


func _shared_work() -> void:
	var world: ClockWorld = _world(["field_tools_v1", ""])
	var fast: FieldActor = _actor(world, _profile(2, 5), "carbine", Vector2(400, 400))
	var slow: FieldActor = _actor(world, _profile(1), "carbine", Vector2(400, 400))
	var site: Expedition.SearchSite = Expedition.SearchSite.new(&"cash", Vector2(400, 400))
	world.sites.assign([site])
	world._cash_site = site
	world.search_assignments.assign(fast.member_id, "cash")
	world.search_assignments.begin(fast.member_id)
	fast.activity = FieldActor.Activity.SEARCHING
	fast.hide()
	world.elapsed = 10.0
	world._update_search(10.0)
	var carried: float = site.progress
	world.search_assignments.release_member(fast.member_id)
	fast.clear_order()
	world.search_assignments.assign(slow.member_id, "cash")
	world.search_assignments.begin(slow.member_id)
	slow.activity = FieldActor.Activity.SEARCHING
	slow.hide()
	for tick: int in range(1000):
		if not world.completions.is_empty():
			break
		world.elapsed += 0.01
		world._update_search(0.01)
	var full_slow: float = 30.0 * slow.trait_search_factor * slow.persona_work_factor * 0.75
	expect(carried > 0.0 and world.completions.size() == 1 and world.completions[0].member_id == slow.member_id and world.completions[0].elapsed < full_slow, "actual shared site progress allows a slower worker to complete earlier work without restarting it")
	observations.relay_elapsed = world.completions[0].elapsed if not world.completions.is_empty() else -1.0
	world.free()


func _parallel_work() -> void:
	var world: ClockWorld = _world(["field_tools_v1", ""])
	var slow: FieldActor = _actor(world, _profile(1), "carbine", Vector2(400, 400))
	var fast: FieldActor = _actor(world, _profile(2, 5), "carbine", Vector2(800, 400))
	var cash: Expedition.SearchSite = Expedition.SearchSite.new(&"cash", slow.position)
	var food: Expedition.SearchSite = Expedition.SearchSite.new(&"food", fast.position)
	cash.seconds = 30.0
	food.seconds = 30.0
	world.sites.assign([cash, food])
	world._cash_site = cash
	world._food_site = food
	for fixture: Dictionary in [{"actor":slow, "site":"cash"}, {"actor":fast, "site":"food"}]:
		var actor: FieldActor = fixture.actor
		world.search_assignments.assign(actor.member_id, fixture.site)
		world.search_assignments.begin(actor.member_id)
		actor.activity = FieldActor.Activity.SEARCHING
		actor.hide()
	expect(world.search_assignments.ordered().size() == 2, "two real members own separate thirty-second jobs in the same controlled world")
	var independent: bool = false
	var progress_when_first_finishes: float = 0.0
	for tick: int in range(2200):
		if world.completions.size() == 2:
			break
		world.elapsed += 0.01
		world._update_search(0.01)
		if world.completions.size() == 1 and not independent:
			progress_when_first_finishes = cash.progress
			independent = int(world.completions[0].member_id) == fast.member_id and cash.progress > 0.0 and not cash.searched and world.has_search_job(slow.member_id) and not world.has_search_job(fast.member_id)
	expect(independent, "finishing the faster member's job leaves the slower member's assignment and accumulated progress intact")
	var times: Dictionary = {}
	var counts: Dictionary = {}
	for completion: Dictionary in world.completions:
		var id: String = str(int(completion.member_id))
		times[id] = completion.elapsed
		counts[id] = int(counts.get(id, 0)) + 1
	expect(world.completions.size() == 2 and counts.get("1") == 1 and counts.get("2") == 1 and cash.searched and food.searched, "each concurrently advancing site completes exactly once for its own member")
	expect(times.has_all(["1", "2"]) and near(float(times["1"]), 19.125, 0.011) and near(float(times["2"]), 13.3875, 0.011) and times["1"] > times["2"], "two thirty-second jobs finish at different actual times derived from each member's own factors")
	world.elapsed += 1.0
	world._update_search(1.0)
	expect(world.completions.size() == 2 and world.search_assignments.ordered().is_empty(), "further work updates cannot repeat either completed job")
	observations.parallel_work = {"finished_at":times, "slower_progress_at_first_finish":progress_when_first_finishes}
	world.free()


func _actual_combat_damage() -> void:
	# Nonlethal controlled targets exercise the existing hit owner; no XP or death claim.
	for fixture: Dictionary in [{"id":3, "gun":"fire_axe_v1", "damage":40.8},
		{"id":4, "gun":"shotgun_v1", "damage":62.1}]:
		var world: ClockWorld = _world(["pressure_rounds_v1", ""])
		world._effects = Node2D.new()
		world.add_child(world._effects)
		var actor: FieldActor = _actor(world, _profile(int(fixture.id)), fixture.gun, Vector2(400, 400))
		actor.visual.set_weapon(actor.weapon_definition.presentation)
		var target: FieldActor = FieldActor.new()
		target.actor_id = 71
		target.is_enemy = true
		target.position = Vector2(430, 400)
		world.add_child(target)
		world.enemies.append(target)
		var before: float = target.health
		world.combat.attack(world, actor, 0.0)
		if fixture.gun == "fire_axe_v1":
			expect(target.health == before and world.combat.action(actor).remaining == CombatPatternsV1.POLICY.axe.windup, "personal axe retains its original real windup without early damage")
			world.combat.attack(world, actor, float(CombatPatternsV1.POLICY.axe.windup))
		expect(near(before - target.health, float(fixture.damage)) and world.combat.action(actor).committed.size() == 1, "actual hit commit subtracts the personal damage once for " + fixture.gun)
		if fixture.gun == "shotgun_v1":
			expect(actor.magazine.rounds == 3, "five actual personal-damage pellets aggregate into one hit commit and consume one shell")
		var accepted_health: float = target.health
		world.combat.attack(world, actor, 0.0)
		expect(target.health == accepted_health and world.combat.action(actor).committed.size() == 1, "repeated same-frame attack cannot replay accepted personal damage during recovery " + fixture.gun)
		observations[fixture.gun + "_actual_damage"] = before - target.health
		world.free()


func _trait_bounds() -> void:
	var context: Dictionary = _context()
	expect(PersonaState.enabled(context) and PowerState.enabled(context) and TransactionReceipt.camp_problem(context).is_empty(), "decoded full initial context retains both explicit modes and strict source validation")
	# From here the allowed Lv5 number is a controlled parameter, not a saved-history claim.
	var fast: Dictionary = SurvivorRoster.member(context.crew, 2)
	fast.growth.trait.level = 5
	fast.growth.trait.progress = 10
	var task: Dictionary = {"version":8, "type":"equipment", "build":{"slots":["field_tools_v1", ""]},
		"sites":[{"id":"cash", "kind":"cash", "building":"controlled-cash", "amount":1, "weapon":false, "seconds":30.0},
			{"id":"food", "kind":"food", "building":"controlled-food", "amount":1, "weapon":false, "seconds":30.0}],
		"persona":{"facts":context.journey.build.persona, "policy":SurvivorPersona.policy()}}
	var report: Dictionary = {"xp_inputs":{"diagnostic":false}, "growth_inputs":{"duration_ms":60000},
		"participants":SurvivalContracts.participants(context.crew, WeaponInventory.snapshot(context), true, true),
		"field_joins":[], "searched":true, "food_searched":false,
		"site_facts":{"cash":{"searched":true, "progress":30.0}, "food":{"searched":false, "progress":0.0}}}
	var minimum: int = floori(30.0 * 0.70 * 0.85 * 0.75 * 1000.0)
	var event: Dictionary = {"member_id":2, "kind":"search_complete", "site":"cash", "at_ms":minimum}
	var facts: Dictionary = {"ruleset_id":TraitRules.RULESET, "binding":BINDING.duplicate(true), "diagnostic":false, "events":[event]}
	expect(TraitRules.inputs_problem(facts, BINDING, report, context, task).is_empty(), "fastest real participant defines the new permitted integer-millisecond lower bound")
	event.at_ms = minimum - 1
	expect(not TraitRules.inputs_problem(facts, BINDING, report, context, task).is_empty(), "a completion one millisecond before the causal lower bound rejects")
	event.member_id = 1
	event.at_ms = floori(float(observations.relay_elapsed) * 1000.0)
	expect(TraitRules.inputs_problem(facts, BINDING, report, context, task).is_empty(), "shared progress completed by a slower member can inherit earlier work from the faster participant")
	var restricted: Dictionary = report.duplicate(true)
	restricted.participants = [report.participants[0]]
	expect(not TraitRules.inputs_problem(facts, BINDING, restricted, context, task).is_empty(), "unparticipating known recipes cannot lower the actual participant bound")
	var legacy: Dictionary = task.duplicate(true)
	legacy.erase("persona")
	legacy.build.slots = ["", ""]
	event.at_ms = 20999
	expect(not TraitRules.inputs_problem(facts, BINDING, report, context, legacy).is_empty(), "legacy mode retains the strict original 21-second floor")
	event.at_ms = 21000
	expect(TraitRules.inputs_problem(facts, BINDING, report, context, legacy).is_empty(), "legacy 21-second completion remains accepted")
	event.at_ms = 20000
	var food: Dictionary = {"member_id":1, "kind":"search_complete", "site":"food", "at_ms":25000}
	facts.events.append(food)
	report.food_searched = true
	report.site_facts.food = {"searched":true, "progress":30.0}
	expect(TraitRules.inputs_problem(facts, BINDING, report, context, task).is_empty(), "original cash and food category events both remain available")
	facts.events.append({"member_id":2, "kind":"search_complete", "site":"cash", "at_ms":30000})
	expect(not TraitRules.inputs_problem(facts, BINDING, report, context, task).is_empty(), "persona does not expand the original two-category event limit")
	facts.events.pop_back()
	food.site = "cash"
	expect(not TraitRules.inputs_problem(facts, BINDING, report, context, task).is_empty(), "the same original category cannot be awarded twice")
	food.site = "food"
	var airdrop: Dictionary = task.duplicate(true)
	airdrop.type = "airdrop"
	airdrop.sites[0].seconds = 12.0
	airdrop.sites[0].building = ""
	airdrop.sites[0].point = [400.0, 400.0]
	facts.events = [event]
	report.food_searched = false
	report.site_facts.food = {"searched":false, "progress":0.0}
	report.site_facts.cash = {"searched":true, "progress":12.0}
	event.at_ms = floori(12.0 * 0.70 * 0.85 * 0.75 * 1000.0)
	expect(TraitRules.inputs_problem(facts, BINDING, report, context, airdrop).is_empty(), "new air-drop lower bound uses its actual twelve-second base")
	event.at_ms -= 1
	expect(not TraitRules.inputs_problem(facts, BINDING, report, context, airdrop).is_empty(), "air-drop completion one millisecond early rejects")
	airdrop.sites.append({"id":"cash_2", "kind":"cash", "building":"controlled-indoor", "amount":1, "weapon":false, "seconds":30.0})
	report.site_facts.cash = {"searched":false, "progress":0.0}
	report.site_facts.cash_2 = {"searched":true, "progress":30.0}
	event.at_ms = floori(12.0 * 0.70 * 0.85 * 0.75 * 1000.0)
	expect(not TraitRules.inputs_problem(facts, BINDING, report, context, airdrop).is_empty(), "unfinished main air-drop cannot lend its twelve-second floor to a completed thirty-second indoor cash site")
	event.at_ms = floori(30.0 * 0.70 * 0.85 * 0.75 * 1000.0)
	expect(TraitRules.inputs_problem(facts, BINDING, report, context, airdrop).is_empty(), "completed optional indoor cash site retains its own thirty-second causal base")
	var missing_proof: Dictionary = report.duplicate(true)
	missing_proof.erase("site_facts")
	expect(not TraitRules.inputs_problem(facts, BINDING, missing_proof, context, airdrop).is_empty(), "new persona work facts require actual completed-site proof")
	missing_proof = report.duplicate(true)
	missing_proof.site_facts.cash_2 = {"searched":false, "progress":0.0}
	expect(not TraitRules.inputs_problem(facts, BINDING, missing_proof, context, airdrop).is_empty(), "an uncompleted category cannot claim a work-completion trait event")


func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	_movement_and_reload()
	_repeat_derivation()
	_work_progress(30.0)
	_work_progress(12.0)
	_shared_work()
	_parallel_work()
	_actual_combat_damage()
	_trait_bounds()
	print(JSON.stringify({"suite":"persona_runtime", "checks":checks, "failures":failures,
		"scope":"CONTROLLED_ACTOR_MAGAZINE_PROGRESS_AND_INPUT_BOUNDARIES", "observations":observations}))
	quit(0 if failures == 0 else 1)
