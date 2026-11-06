extends SceneTree
class ClockWorld extends Expedition:
	func _ready() -> void: pass
	func _update_ui() -> void: pass

## Controlled component geometry and negative copies only; no journey or disk acceptance claim.

const BINDING: Dictionary = {
	"run_id":"0123456789abcdef0123456789abcdef", "root_id":"fedcba9876543210fedcba9876543210",
	"transaction_id":"0123456789abcdef0123456789abcdef:2",
	"base_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
	"rules_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
}

var checks: int = 0
var failures: int = 0
var oracle_used: bool = false
var oracle_uses_checked: bool = false


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("POWER_BOUNDARIES_FAIL " + label)


func same(left: Variant, right: Variant) -> bool:
	return TransactionReceipt.same({"v":left}, {"v":right})


func _actor(point: Vector2, adapter: Expedition) -> FieldActor:
	var actor: FieldActor = FieldActor.new()
	actor.member_id = 3
	actor.definition_id = &"crew_3"
	actor.position = point
	actor.weapon_definition = WeaponInventory.definition("carbine").duplicate() as WeaponDefinition
	actor.magazine = WeaponMagazine.new("controlled-power-boundary", "carbine")
	root.add_child(actor)
	var profile: Dictionary = {"id":3, "definition_id":"crew_3", "growth":{"trait":{"id":"agile_v1", "level":3, "progress":3}}}
	TraitRules.apply(actor, profile, 125.0)
	adapter.apply_build(actor)
	actor.command_path(PackedVector2Array([point, point + Vector2(1100, 0)]))
	return actor


func _movement() -> void:
	var adapter: Expedition = Expedition.new()
	adapter.supply = MissionSupply.new()
	adapter.supply.generated = {"build":{"slots":["light_boots_v1", "quick_loader_v1"]}}
	var base: FieldActor = _actor(Vector2(200, 300), adapter)
	var boosted: FieldActor = _actor(Vector2(200, 700), adapter)
	var direct: FieldActor = _actor(Vector2(200, 1100), adapter)
	var expected_speed: float = 125.0 * 1.16 * 1.15
	expect(base.speed == expected_speed and boosted.speed == expected_speed, "real Trait and passive adapters derive the base once")
	var fresh: Dictionary = SpecialPowers.initial(BINDING, "speed_boost_v1")
	var power: Dictionary = SpecialPowers.accept(fresh, SpecialPowers.request(fresh), 2.0)
	for tick: int in range(12):
		boosted.power_move_factor = SpecialPowers.move_factor(power, 2.5)
	expect(boosted.speed == expected_speed and boosted.effective_speed() == expected_speed * 1.5, "repeated effect refresh never compounds stored base or Trait/passive factors")
	var navigation: FieldNavigation = FieldNavigation.new()
	navigation.configure([])
	var baseline: Array[FieldActor] = [base]
	var accelerated: Array[FieldActor] = [boosted]
	FieldContacts.move(baseline, baseline, navigation, 0.5)
	FieldContacts.move(accelerated, accelerated, navigation, 0.5)
	var normal_distance: float = base.position.x - 200.0
	var fast_distance: float = boosted.position.x - 200.0
	expect(absf(normal_distance - expected_speed * 0.5) < 0.001 and absf(fast_distance - normal_distance * 1.5) < 0.001, "actual swept FieldContacts displacement receives exactly the speed factor")
	direct.power_move_factor = SpecialPowers.move_factor(power, 2.5)
	direct.advance(0.5, true, false)
	expect(absf(direct.position.x - 200.0 - fast_distance) < 0.001, "FieldActor path movement and contact movement use the same effective speed")
	var attack_interval: float = boosted.weapon_definition.shot_interval(boosted.trait_shot_factor)
	boosted.cooldown = attack_interval
	for shot: int in range(boosted.magazine.capacity()):
		boosted.magazine.commit_shot()
	var reload_before: float = boosted.magazine.remaining
	var work_factor: float = boosted.trait_search_factor
	boosted.advance(0.25, false, false)
	boosted.magazine.advance(0.25)
	expect(boosted.cooldown == maxf(0.0, attack_interval - 0.25) and boosted.weapon_definition.shot_interval(boosted.trait_shot_factor) == attack_interval, "speed factor leaves actual attack cooldown and interval unchanged")
	expect(reload_before == 1.6 * 0.75 and boosted.magazine.remaining == reload_before - 0.25 and boosted.trait_search_factor == work_factor, "speed factor leaves existing reload and work factors unchanged")
	boosted.power_move_factor = SpecialPowers.move_factor(power, 10.0)
	var at_expiry: float = boosted.position.x
	FieldContacts.move(accelerated, accelerated, navigation, 0.5)
	expect(boosted.speed == expected_speed and boosted.effective_speed() == expected_speed and absf(boosted.position.x - at_expiry - normal_distance) < 0.001, "exact expiry restores base value and actual unboosted displacement")
	var rebuilt: FieldActor = _actor(Vector2(200, 900), adapter)
	rebuilt.power_move_factor = SpecialPowers.move_factor(power, 3.0)
	expect(rebuilt.speed == expected_speed and rebuilt.effective_speed() == expected_speed * 1.5, "fresh actor reconstruction derives Trait/passive/power once")
	expect(SpecialPowers.request(power).is_empty() and SpecialPowers.remaining(power, 100.0) == 0.0, "expiration consumes the daily opportunity without cooldown refill")
	for actor: FieldActor in [base, boosted, direct, rebuilt]:
		actor.free()
	adapter.free()


func _row(id: int, foot: Vector2, alive: bool = true) -> Dictionary:
	return {"id":id, "foot":foot, "alive":alive, "available":true}


func _ack(result: Dictionary) -> Dictionary:
	var state: Dictionary = result.state
	for hit: Dictionary in result.hits:
		state = ToxicV1.ack(state, hit)
	return state


func _toxic_clocks() -> void:
	var clear: Array[ShotObstacle] = []
	var old_source: Array[Dictionary] = [_row(21, Vector2(100, 100))]
	var members: Array[Dictionary] = [_row(1, Vector2(180, 100))]
	var started: Dictionary = ToxicV1.plan(ToxicV1.initial(), 0.0, old_source, members, clear)
	var held: Dictionary = ToxicV1.plan(started.state, 4.0, old_source, members, clear, false)
	expect(same(held.state, started.state) and held.hits.is_empty(), "frozen caster preserves exact windup without release or accumulated time")
	var resumed: Dictionary = ToxicV1.plan(held.state, 0.4, old_source, members, clear)
	expect(resumed.state.zones.is_empty() and is_equal_approx(resumed.state.casters["21"].remaining, 0.5), "unfreeze resumes original windup rather than repaying frozen seconds")
	var release: Dictionary = ToxicV1.plan(resumed.state, 0.5, old_source, members, clear)
	expect(release.state.zones.size() == 1 and release.state.releases.size() == 1 and release.hits.is_empty(), "resumed caster releases once only after its retained windup")
	var cooldown: Dictionary = release.state.casters["21"].duplicate(true)
	var with_cooldown: Dictionary = ToxicV1.plan(release.state, 0.75, old_source, members, clear, false)
	expect(same(with_cooldown.state.casters["21"], cooldown) and with_cooldown.state.zones[0].age == 0.75 and with_cooldown.hits.size() == 1 and with_cooldown.hits[0].amount == 6.0, "frozen cooldown holds while existing zone advances and requests actual configured tick damage")
	# The original source dies; a new source can naturally wind up beside its surviving zone.
	var dead_source: Array[Dictionary] = [_row(21, Vector2(100, 100), false)]
	var orphan: Dictionary = ToxicV1.plan(release.state, 0.0, dead_source, members, clear, false)
	var new_source: Array[Dictionary] = [_row(22, Vector2(100, 100))]
	var overlapping: Dictionary = ToxicV1.plan(orphan.state, 0.0, new_source, members, clear)
	expect(ToxicV1.problem(overlapping.state).is_empty() and overlapping.state.casters["22"].phase == "windup", "original source death preserves zone while a distinct live caster begins its own action")
	var state: Dictionary = overlapping.state
	var damage: float = 0.0
	for tick: int in range(1, 5):
		var frozen_tick: Dictionary = ToxicV1.plan(state, 0.75, new_source, members, clear, false)
		expect(frozen_tick.state.casters["22"].remaining == 0.9 and frozen_tick.state.releases.size() == 1 and frozen_tick.hits.size() == 1 and frozen_tick.hits[0].tick == tick, "held new windup coexists with independent old-zone tick %d" % tick)
		for hit: Dictionary in frozen_tick.hits:
			damage += float(hit.amount)
		state = _ack(frozen_tick)
	expect(state.zones.is_empty() and damage == 24.0 and state.casters["22"].remaining == 0.9, "zone reaches its original lifetime and all four damage ticks while caster stays frozen")
	var no_debt: Dictionary = ToxicV1.plan(state, 0.1, new_source, members, clear)
	expect(no_debt.hits.is_empty() and no_debt.state.releases.size() == 1 and is_equal_approx(no_debt.state.casters["22"].remaining, 0.8), "unfreeze neither repeats retired zone damage nor bursts owed releases")
	var cooldown_resumed: Dictionary = ToxicV1.plan(_ack(with_cooldown), 0.25, old_source, members, clear)
	expect(cooldown_resumed.state.casters["21"].remaining == 5.75 and cooldown_resumed.state.releases.size() == 1 and cooldown_resumed.hits.is_empty(), "cooldown resumes from retained remainder without catch-up attacks")
	var frozen_newborn: Dictionary = ToxicV1.plan(ToxicV1.initial(), 4.0, new_source, members, clear, false)
	expect(frozen_newborn.state.sequence == 0 and frozen_newborn.state.casters["22"].phase == "chase" and frozen_newborn.state.zones.is_empty(), "a newly present caster cannot start an action under global freeze")


func _exact_step_boundary() -> void:
	var world: ClockWorld=ClockWorld.new()
	world.set_process(false);world.set_physics_process(false)
	root.add_child(world)
	world.supply=MissionSupply.new()
	world.supply.generated={"powers":{"slot":"speed_boost_v1"},"build":{"slots":["",""]}}
	world.navigation=FieldNavigation.new();world.navigation.configure([])
	world._effects=Node2D.new();world.add_child(world._effects)
	world._spawn_clock=INF;world._ai_clock=INF
	world.powers=SpecialPowers.initial(BINDING,"speed_boost_v1")
	world.powers=SpecialPowers.accept(world.powers,SpecialPowers.request(world.powers),0.0)
	var member: FieldActor=_actor(Vector2(200,300),world)
	world.survivors=[member]
	world.elapsed=7.75
	var start: float=member.position.x
	world.step(0.25)
	expect(world.elapsed==8.0 and absf(member.position.x-start-member.speed*1.5*0.25)<0.001,"last active fraction receives boost through original world step")
	expect(member.effective_speed()==member.speed,"exact expiry boundary immediately exposes the original speed")
	start=member.position.x
	world.step(0.25)
	expect(absf(member.position.x-start-member.speed*0.25)<0.001,"next world step moves at the exact original speed")
	world.powers=SpecialPowers.initial(BINDING,"map_freeze_v1")
	world.powers=SpecialPowers.accept(world.powers,SpecialPowers.request(world.powers),8.25)
	world.elapsed=12.0
	var enemy: FieldActor=_actor(Vector2(400,1000),world)
	enemy.is_enemy=true;enemy.member_id=0;enemy.cooldown=1.0
	world.enemies=[enemy]
	var foot: Vector2=enemy.position
	world.step(0.25)
	expect(world.elapsed==12.25 and enemy.position==foot and enemy.cooldown==1.0 and not world.power_frozen,"freeze preserves enemy motion/action remainder through its exact final fraction")
	world.step(0.25)
	expect(enemy.position!=foot and enemy.cooldown==0.75,"thaw resumes retained enemy time without owed attacks")
	enemy.free();member.free();world.free()


func _oracle(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and parsed.has("record_encoding"):
		var decoded: Dictionary = RecordEncoding.unpack(parsed)
		parsed = decoded.get("payload") if decoded.get("error") == OK else null
	if not parsed is Dictionary or not parsed.get("world") is Dictionary or not parsed.get("receipt") is Dictionary or not parsed.get("camp") is Dictionary:
		expect(false, "oracle has authenticated world/receipt/camp objects")
		return
	oracle_used = true
	var world: Dictionary = parsed.world
	var receipt: Dictionary = parsed.receipt
	var camp: Dictionary = parsed.camp
	expect(SortieSnapshot.problem(world, receipt).is_empty() and TransactionReceipt.problem(receipt).is_empty() and PowerState.problem(camp).is_empty(), "unmodified real-flow oracle validates before negative copies")
	for broken: Variant in [null, [], {"data_version":9, "mission":[]}, {"data_version":9, "mission":{"generated":[]}}]:
		expect(not PowerAuthority.mode(broken), "broken mode containers fail closed without field access errors")
	for field: String in ["sim", "powers", "survivors", "generated"]:
		var bad: Dictionary = world.duplicate(true)
		match field:
			"sim": bad.sim = []
			"powers": bad.powers = {}
			"survivors": bad.survivors = [null]
			"generated": bad.generated = {"powers":{"slot":[]}}
		expect(PowerAuthority.propose(bad, {}).is_empty(), "activation rejects broken " + field + " before consuming or exposing effect")
	var bad_receipt: Dictionary = receipt.duplicate(true)
	bad_receipt.rules.mission = []
	expect(not TransactionReceipt.problem(bad_receipt).is_empty(), "receipt rejects broken mission before mode projection")
	if not receipt.powers.is_empty():
		bad_receipt = receipt.duplicate(true)
		bad_receipt.powers[0].at = []
		expect(not TransactionReceipt.problem(bad_receipt).is_empty(), "receipt rejects nonnumeric activation time without conversion errors")
		bad_receipt = receipt.duplicate(true)
		bad_receipt.phase = "STARTED"
		bad_receipt.envelope = {}
		expect(not TransactionReceipt.problem(bad_receipt).is_empty(), "STARTED cannot introduce an activation without its original proposal")
		var previous: Dictionary = receipt.duplicate(true)
		previous.powers = []
		var next: Dictionary = receipt.duplicate(true)
		next.phase = "SUSPEND_READY"
		next.envelope.power_proposal = {"before":{"survivors":[null]}, "request":{}}
		expect(not PowerAuthority.transition(previous, next).is_empty(), "transition rejects broken before-actor proof before reading actor state")
	var bad_camp: Dictionary = camp.duplicate(true)
	bad_camp.journey.build = []
	expect(not BuildState.problem(bad_camp).is_empty(), "broken old build container rejects through the original validation boundary")
	if camp.journey.build.powers.uses.is_empty():
		print("POWER_BOUNDARIES_ORACLE_USES_NOT_PROVIDED")
		return
	oracle_uses_checked = true
	for field: String in ["ability_id", "until", "root", "before_acquisition"]:
		bad_camp = camp.duplicate(true)
		var used: Dictionary = bad_camp.journey.build.powers.uses[0]
		match field:
			"ability_id": used.event.ability_id = []
			"until": used.event.until = []
			"root": used.binding.root_id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" if camp.journey.root_id != "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" else "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
			"before_acquisition":
				for source: Dictionary in camp.journey.build.powers.sources:
					if source.ability_id == used.event.ability_id:
						used.day = source.generated.day
						used.binding.transaction_id = "%s:%d" % [camp.profile_id, int(used.day) - 1]
						used.event.id = used.binding.transaction_id + ":power:" + used.event.ability_id
		expect(not PowerState.problem(bad_camp).is_empty(), "camp rejects malformed or unearned use " + field)


func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	_movement()
	_exact_step_boundary()
	_toxic_clocks()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--power-oracle="):
			_oracle(argument.trim_prefix("--power-oracle="))
	print(JSON.stringify({"suite":"power_boundaries", "checks":checks, "failures":failures, "scope":"CONTROLLED_COMPONENT_AND_NEGATIVE_COPIES", "oracle_used":oracle_used, "oracle_uses_checked":oracle_uses_checked}))
	quit(0 if failures == 0 else 1)
