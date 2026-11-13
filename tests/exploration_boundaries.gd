extends SceneTree
## Controlled components only: actors start at work points, without a played path or save claim.

class QuietProp extends FieldProp:
	func _ready() -> void:
		pass

class QuietHud extends ExpeditionHud:
	func _ready() -> void:
		pass
	func hide_screen() -> void:
		pass

class ClockWorld extends Expedition:
	var completions: Array[Dictionary] = []
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func _update_ui() -> void:
		pass
	func _complete_search(actor: FieldActor, site: Expedition.SearchSite) -> bool:
		# Observe the original completion owner, including its reward and duplicate guard.
		var accepted: bool = super._complete_search(actor, site)
		if accepted:
			completions.append({"member_id":actor.member_id, "site_id":String(site.id), "at":elapsed})
		return accepted

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
var settlement_packet_checked: bool = false


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("EXPLORATION_BOUNDARIES_FAIL " + label)


func near(value: float, expected: float, tolerance: float = 0.000001) -> bool:
	return absf(value - expected) <= tolerance


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
	var journey: Dictionary = EnemyState.initial("exploration-boundaries-context")
	journey.seed = SEED
	journey.campaign = CampaignRules.initial(camp.profile_id)
	journey.build = ExplorationState.initial_build(SEED)
	var value: Dictionary = EnemyState.snapshot(camp, journey, [], [])
	return RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(value))).payload


func _task(context: Dictionary) -> Dictionary:
	for value: Dictionary in DailyActions.offers(context):
		if value.get("version") == 9 and value.sites.any(func(site: Dictionary) -> bool: return site.source == "primary" and site.kind == "food"):
			return value
	return {}


func _definition(task: Dictionary, id: String) -> Dictionary:
	for definition: Dictionary in task.sites:
		if definition.id == id:
			return definition
	return {}


func _world(task: Dictionary, tools: bool) -> ClockWorld:
	var world: ClockWorld = ClockWorld.new()
	world.supply = MissionSupply.new()
	world.supply.generated = task.duplicate(true)
	# Explicit factor parameters; this edit does not claim that tools or Lv5 were earned.
	world.supply.generated.build.slots = ["field_tools_v1", ""] if tools else ["", ""]
	world.supply.cash_reward = int(task.cash)
	world.supply.food_reward = int(task.food)
	world.layout = ExplorationLayout.resource(task.layout)
	world.navigation = ExplorationLayout._routing(task.layout).nav
	world.parallel_search = true
	world.trait_inputs.configure(BINDING)
	world.xp_inputs.configure(BINDING)
	world.basic_support.configure(BINDING)
	world.powers = SpecialPowers.initial(BINDING, task.powers.slot)
	root.add_child(world)
	return world


func _install(world: ClockWorld, definition: Dictionary) -> Expedition.SearchSite:
	var site: Expedition.SearchSite = Expedition.SearchSite.new(StringName(definition.kind), ExplorationSites.site_point(world.supply.generated.layout, definition))
	site.id = StringName(definition.id)
	site.seconds = float(definition.seconds)
	site.reward = int(definition.amount)
	site.weapon = definition.weapon
	site.prop = QuietProp.new()
	site.prop.title = definition.id
	world.add_child(site.prop)
	world.sites.append(site)
	return site


func _actor(world: ClockWorld, context: Dictionary, id: int, point: Vector2) -> FieldActor:
	var profile: Dictionary = SurvivorRoster.member(context.crew, id).duplicate(true)
	if id == 2:
		profile.growth.trait.level = 5
		profile.growth.trait.progress = 10
	var item: Dictionary = WeaponInventory.for_member(context, id)
	var actor: FieldActor = FieldActor.new()
	actor.member_id = id
	actor.actor_id = id - 1
	actor.definition_id = StringName(profile.definition_id)
	actor.position = point
	actor.call_sign = profile.call_sign
	actor.weapon_instance_id = item.instance_id
	actor.weapon_definition = WeaponModifiers.combat_definition(item)
	actor.magazine = WeaponMagazine.new(item.instance_id, item.weapon_id)
	world.add_child(actor)
	world.apply_build(actor, profile, item)
	world.survivors.append(actor)
	return actor


func _start_pair(world: ClockWorld, car: Expedition.SearchSite, tree: Expedition.SearchSite) -> void:
	world.request_search(car.id)
	world.request_search(tree.id)
	world._update_search(0.0)


func _work(context: Dictionary, task: Dictionary, tools: bool) -> void:
	var world: ClockWorld = _world(task, tools)
	var car: Expedition.SearchSite = _install(world, _definition(task, "vehicle_01"))
	var tree: Expedition.SearchSite = _install(world, _definition(task, "tree_01"))
	var fast: FieldActor = _actor(world, context, 2, car.door)
	var slow: FieldActor = _actor(world, context, 1, tree.door)
	_start_pair(world, car, tree)
	expect(fast.activity == FieldActor.Activity.RECOVERING and slow.activity == FieldActor.Activity.RECOVERING
		and fast.visible and slow.visible and world.search_assignments.ordered().size() == 2, "original request owner starts independent visible car and tree work")
	var tool_factor: float = 0.75 if tools else 1.0
	var car_duration: float = 8.0 * 0.70 * 0.85 * tool_factor
	var tree_duration: float = 6.0 * 0.85 * tool_factor
	expect(car.seconds == 8.0 and tree.seconds == 6.0 and near(fast.trait_search_factor, 0.70)
		and near(slow.trait_search_factor, 1.0) and near(fast.persona_work_factor, 0.85) and near(slow.persona_work_factor, 0.85), "generated9 object bases and personal factors are injected independently")
	world.elapsed = 1.0
	world._update_search(1.0)
	expect(near(car.progress, 1.0 / (0.70 * 0.85 * tool_factor)) and near(tree.progress, 1.0 / (0.85 * tool_factor)), "real object integrator applies own Trait, persona and tool exactly once")
	for tick: int in range(650):
		if world.completions.size() == 2:
			break
		world.elapsed += 0.01
		world._update_search(0.01)
	var completed: Dictionary = {}
	for event: Dictionary in world.completions:
		completed[event.site_id] = event
	expect(completed.size() == 2 and car.searched and tree.searched and car.progress == 8.0 and tree.progress == 6.0
		and near(float(completed.get("vehicle_01", {}).get("at", -1)), car_duration, 0.011)
		and near(float(completed.get("tree_01", {}).get("at", -1)), tree_duration, 0.011), "both real completion clocks match their different eight/six-second bases")
	expect(world.loot == 1 and world.food_loot == 1 and world.weapon_loot.is_empty() and world.trait_inputs.events.size() == 2, "original completion owner grants each object once with only original category Trait events")
	var before: Dictionary = {"loot":world.loot, "food":world.food_loot, "events":world.trait_inputs.events.size(), "completions":world.completions.size()}
	expect(not world._complete_search(fast, car) and not world._complete_search(slow, tree), "duplicate completed objects fail before any reward or event")
	world.request_search(car.id)
	world.request_search(tree.id)
	world._update_search(1.0)
	expect(before == {"loot":world.loot, "food":world.food_loot, "events":world.trait_inputs.events.size(), "completions":world.completions.size()}
		and world.search_assignments.ordered().is_empty(), "repeated requests and later updates cannot repeat object completion")
	var definitions: Array = [_definition(task, "vehicle_01"), _definition(task, "tree_01")]
	var facts: Dictionary = WorldSites.facts(world)
	expect(WorldSites.problem(definitions, facts, true).is_empty()
		and WorldSites.carry(definitions, facts, BINDING.transaction_id, true, task) == {"loot":1, "food":1, "weapons":[]}, "original carry derives bounded rewards from exact completed object facts")
	observations["work_tools" if tools else "work_without_tools"] = completed
	world.free()


func _cancel_and_death(context: Dictionary, task: Dictionary) -> void:
	var world: ClockWorld = _world(task, true)
	var car: Expedition.SearchSite = _install(world, _definition(task, "vehicle_01"))
	var tree: Expedition.SearchSite = _install(world, _definition(task, "tree_01"))
	var first: FieldActor = _actor(world, context, 2, car.door)
	var second: FieldActor = _actor(world, context, 1, tree.door)
	_start_pair(world, car, tree)
	world.elapsed = 1.0
	world._update_search(1.0)
	var car_progress: float = car.progress
	var tree_progress: float = tree.progress
	world.request_search(car.id)
	expect(not world.has_search_job(first.member_id) and world.has_search_job(second.member_id)
		and near(car.progress, car_progress) and near(tree.progress, tree_progress) and first.visible, "cancelling one actual request preserves its accumulated work and the other ownership")
	world.elapsed += 0.25
	world._update_search(0.25)
	expect(near(car.progress, car_progress) and tree.progress > tree_progress and second.activity == FieldActor.Activity.RECOVERING, "cancelled work stays still while the other original job advances")
	world.request_search(car.id)
	world._update_search(0.0)
	expect(world.has_search_job(first.member_id) and near(car.progress, car_progress) and first.visible
		and first.activity == FieldActor.Activity.RECOVERING, "reassigning resumes the same outdoor object's preserved work")
	var before_health: float = first.health
	expect(world._combatant(first).available and first.take_damage(7.0) and first.health == before_health - 7.0
		and first.visible and first.activity == FieldActor.Activity.RECOVERING, "outdoor worker remains a real visible damageable combat target")
	tree_progress = tree.progress
	expect(first.take_damage(first.health + 1.0) and first.activity == FieldActor.Activity.DOWN, "original damage owner downs the outdoor worker")
	world._update_search(0.0)
	expect(not world.has_search_job(first.member_id) and car.progress == 0.0 and not car.searched
		and world.has_search_job(second.member_id) and near(tree.progress, tree_progress) and second.visible
		and second.activity == FieldActor.Activity.RECOVERING, "death clears only the dead worker's job and progress, preserving the independent job")
	world.elapsed += 0.1
	world._update_search(0.1)
	expect(tree.progress > tree_progress and world.loot == 0 and world.food_loot == 0, "surviving outdoor work continues without granting the interrupted reward")
	world.free()


func _failure_report(context: Dictionary, task: Dictionary) -> void:
	var world: ClockWorld = _world(task, true)
	var car: Expedition.SearchSite = _install(world, _definition(task, "vehicle_01"))
	var tree: Expedition.SearchSite = _install(world, _definition(task, "tree_01"))
	_actor(world, context, 2, car.door)
	_actor(world, context, 1, tree.door)
	world.participants_snapshot = SurvivalContracts.participants(context.crew, WeaponInventory.snapshot(context), true, true)
	_start_pair(world, car, tree)
	for tick: int in range(600):
		if car.searched and tree.searched:
			break
		world.elapsed += 0.01
		world._update_search(0.01)
	expect(world.loot == 1 and world.food_loot == 1, "controlled full-wipe fixture first earns real carried object rewards")
	for actor: FieldActor in world.survivors:
		actor.take_damage(actor.health + 1.0)
	expect(world.living_count() == 0, "actual damage downs every controlled participant before failed closeout")
	# Only presentation endpoints are quiet; the report below is Expedition._finish itself.
	world._effects = Node2D.new()
	world.add_child(world._effects)
	world._hud = QuietHud.new()
	world.add_child(world._hud)
	world._readouts = SquadReadouts.new()
	world.add_child(world._readouts)
	world.camera = FieldCamera.new()
	world.add_child(world.camera)
	world.camera.set_process(false)
	var reports: Array[Dictionary] = []
	world.finished.connect(func(report: Dictionary) -> void: reports.append(report))
	world._finish(false)
	world._finish(true)
	expect(reports.size() == 1 and reports[0].mission_outcome == "FAILED" and not reports[0].evacuated
		and reports[0].loot == 0 and reports[0].food == 0 and reports[0].weapons.is_empty()
		and reports[0].site_facts.vehicle_01.searched and reports[0].site_facts.tree_01.searched,
		"original failed finish emits once with no bankable rewards while retaining completed object facts")
	expect(not reports.is_empty() and SurvivalContracts.report_problem(context.crew, reports[0], true, true).is_empty(), "actual failed report preserves original participant, health and damage consistency")
	observations.failed_report = {"reports":reports.size(), "carried_cash":world.loot, "carried_food":world.food_loot,
		"reported_cash":reports[0].loot if not reports.is_empty() else -1, "reported_food":reports[0].food if not reports.is_empty() else -1}
	world.free()


func _trait_bounds(context: Dictionary, task: Dictionary) -> void:
	var controlled: Dictionary = context.duplicate(true)
	var fast: Dictionary = SurvivorRoster.member(controlled.crew, 2)
	fast.growth.trait.level = 5
	fast.growth.trait.progress = 10
	var source: Dictionary = task.duplicate(true)
	source.build.slots = ["field_tools_v1", ""]
	var report: Dictionary = {"xp_inputs":{"diagnostic":false}, "growth_inputs":{"duration_ms":60000},
		"participants":SurvivalContracts.participants(controlled.crew, WeaponInventory.snapshot(controlled), true, true),
		"field_joins":[], "searched":true, "food_searched":false, "site_facts":{}}
	for site: Dictionary in task.sites:
		report.site_facts[site.id] = {"searched":false, "progress":0.0}
	var event: Dictionary = {"member_id":2, "kind":"search_complete", "site":"cash", "at_ms":0}
	var facts: Dictionary = {"ruleset_id":TraitRules.RULESET, "binding":BINDING.duplicate(true), "diagnostic":false, "events":[event]}
	for fixture: Dictionary in [{"id":"vehicle_01", "kind":"cash", "seconds":8.0}, {"id":"tree_01", "kind":"food", "seconds":6.0}]:
		for site: Dictionary in task.sites:
			report.site_facts[site.id] = {"searched":false, "progress":0.0}
		report.site_facts[fixture.id] = {"searched":true, "progress":fixture.seconds}
		report.searched = fixture.kind == "cash"
		report.food_searched = fixture.kind == "food"
		event.site = fixture.kind
		event.member_id = 2
		event.at_ms = floori(float(fixture.seconds) * 0.70 * 0.85 * 0.75 * 1000.0)
		expect(TraitRules.inputs_problem(facts, BINDING, report, controlled, source).is_empty(), "actual completed %s owns its causal base and fastest real participant" % fixture.id)
		event.at_ms -= 1
		expect(not TraitRules.inputs_problem(facts, BINDING, report, controlled, source).is_empty(), "completed %s rejects one millisecond before its own lower bound" % fixture.id)
		event.at_ms += 1
		event.member_id = 1
		var restricted: Dictionary = report.duplicate(true)
		restricted.participants = [SurvivorRoster.member(report.participants, 1)]
		expect(not TraitRules.inputs_problem(facts, BINDING, restricted, controlled, source).is_empty(), "unparticipating fast member cannot lower %s's bound" % fixture.id)
		restricted = report.duplicate(true)
		restricted.field_joins = [{"member_id":2, "at_ms":event.at_ms + 1}]
		expect(not TraitRules.inputs_problem(facts, BINDING, restricted, controlled, source).is_empty(), "a fast member joining after %s completes cannot lend a factor" % fixture.id)
	for fixture: Dictionary in [{"id":"cash", "kind":"cash", "fast":"vehicle_01", "fast_seconds":8.0},
		{"id":"food", "kind":"food", "fast":"tree_01", "fast_seconds":6.0}]:
		for site: Dictionary in task.sites:
			report.site_facts[site.id] = {"searched":false, "progress":0.0}
		var actual: Dictionary = _definition(task, fixture.id)
		report.site_facts[fixture.id] = {"searched":true, "progress":actual.seconds}
		report.searched = fixture.kind == "cash"
		report.food_searched = fixture.kind == "food"
		event.member_id = 2
		event.site = fixture.kind
		event.at_ms = floori(float(fixture.fast_seconds) * 0.70 * 0.85 * 0.75 * 1000.0)
		expect(not TraitRules.inputs_problem(facts, BINDING, report, controlled, source).is_empty(), "unfinished %s cannot lend its shorter base to completed %s" % [fixture.fast, fixture.id])
		event.at_ms = floori(float(actual.seconds) * 0.70 * 0.85 * 0.75 * 1000.0)
		expect(TraitRules.inputs_problem(facts, BINDING, report, controlled, source).is_empty(), "actual completed indoor %s retains its own full base" % fixture.id)
	var facts_only: Dictionary = report.site_facts.duplicate(true)
	facts_only["vehicle_99"] = {"searched":true, "progress":8.0}
	expect(not WorldSites.problem(task.sites, facts_only, true).is_empty(), "original fact owner rejects an illegal object identity")
	var bad: Dictionary = task.duplicate(true)
	for site: Dictionary in bad.sites:
		if site.id == "vehicle_01":
			site.id = "vehicle_99"
	expect(not ExplorationActions.problem(bad).is_empty(), "full canonical action rejects an invented object before Trait or carry projection")
	bad = task.duplicate(true)
	for site: Dictionary in bad.sites:
		if site.id == "tree_01":
			site.seconds = 0.1
	expect(not ExplorationActions.problem(bad).is_empty(), "canonical object seconds cannot be shortened to forge a work lower bound")


func _settlement_packet(path: String) -> void:
	if not ProjectSettings.globalize_path(path).begins_with(ProjectSettings.globalize_path("res://.local/")):
		expect(false, "settlement oracle stays inside isolated local fixtures")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and parsed.has("record_encoding"):
		parsed = RecordEncoding.unpack(parsed).get("payload")
	var input: Variant = parsed.get("input") if parsed is Dictionary else null
	if not input is Dictionary or not FrozenSettlement.input_problem(input).is_empty():
		expect(false, "optional real-flow full-wipe input authenticates through original settlement owner")
		return
	var result: Dictionary = FrozenSettlement.compute(input)
	expect(result.error.is_empty() and input.rules.mission.generated.version == 9 and not input.report.evacuated
		and input.report.member_results.all(func(row: Dictionary) -> bool: return row.health == 0.0)
		and input.carried.loot > 0 and input.carried.food > 0, "real-flow oracle is specifically a full wipe after carrying both object reward kinds")
	if not result.error.is_empty():
		return
	settlement_packet_checked = input.rules.mission.generated.version == 9 and not input.report.evacuated and input.report.member_results.all(func(row: Dictionary) -> bool: return row.health == 0.0) and input.carried.loot > 0 and input.carried.food > 0
	var after: Dictionary = result.packet.envelope.result.camp
	expect(after.cash == input.before.cash and after.last_day.cash_gained == 0 and after.last_day.food_found == 0
		and input.report.weapons.is_empty() and after.weapons.all(func(item: Dictionary) -> bool: return input.before.weapons.any(func(old: Dictionary) -> bool: return old.instance_id == item.instance_id)), "original frozen settlement banks no carried resources or weapons after full wipe")
	var bad: Dictionary = input.duplicate(true)
	bad.report.loot = bad.carried.loot
	bad.report.food = bad.carried.food
	expect(not FrozenSettlement.input_problem(bad).is_empty(), "failed extraction cannot turn completed object facts into banked rewards")


func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	var context: Dictionary = _context()
	expect(TransactionReceipt.camp_problem(context).is_empty() and ExplorationState.enabled(context), "decoded pure initialization supplies a legal explicit exploration context")
	var task: Dictionary = _task(context)
	expect(not task.is_empty() and ExplorationActions.problem(task).is_empty(), "original policies freeze a complete authentic generated9 object source")
	if not task.is_empty():
		_work(context, task, true)
		_work(context, task, false)
		_cancel_and_death(context, task)
		_failure_report(context, task)
		_trait_bounds(context, task)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--exploration-packet="):
			_settlement_packet(argument.trim_prefix("--exploration-packet="))
	var pending: Array[String] = ["REAL_FLOW_DURABLE_CONFIRMATION"]
	if not settlement_packet_checked:
		pending.append("REAL_FLOW_FULL_WIPE_SETTLEMENT_INPUT")
	print(JSON.stringify({"suite":"exploration_boundaries", "checks":checks, "failures":failures,
		"scope":"CONTROLLED_ORIGINAL_WORK_DAMAGE_REPORT_AND_FACT_OWNERS", "observations":observations,
		"settlement_packet_checked":settlement_packet_checked,
		"pending":pending}))
	quit(0 if failures == 0 else 1)
