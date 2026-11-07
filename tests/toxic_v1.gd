extends SceneTree
## Pure intent/geometry fixtures; actual HP, death and disk flow belong to integration.

var checks: int = 0
var failures: int = 0
var clear: Array[ShotObstacle] = []


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("TOXIC_V1_FAIL " + label)


func row(id: int, point: Vector2, alive: bool = true, available: bool = true) -> Dictionary:
	return {"id":id, "foot":point, "alive":alive, "available":available}


func same(a: Variant, b: Variant) -> bool:
	return TransactionReceipt.same({"v":a}, {"v":b})


func apply_all(result: Dictionary) -> Dictionary:
	var state: Dictionary = result.state
	for hit: Dictionary in result.hits:
		state = ToxicV1.ack(state, hit)
	return state


func released(casters: Array[Dictionary], members: Array[Dictionary]) -> Dictionary:
	var started: Dictionary = ToxicV1.plan(ToxicV1.initial(), 0.0, casters, members, clear)
	return ToxicV1.plan(started.state, 0.90, casters, members, clear).state


func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	var casters: Array[Dictionary] = [row(21, Vector2.ZERO)]
	var members: Array[Dictionary] = [row(2, Vector2(80.0, 0.0)), row(1, Vector2(80.0, 0.0))]
	var fresh: Dictionary = ToxicV1.initial()
	expect(ToxicV1.problem(fresh).is_empty(), "exact fresh state")
	var zero_caster: Array[Dictionary] = [row(0, Vector2.ZERO)]
	var zero_source: Dictionary = released(zero_caster, members)
	expect(zero_source.zones.size() == 1 and zero_source.zones[0].source_id == 0 and ToxicV1.problem(zero_source).is_empty(), "natural actor ID zero is valid casting and released source")
	var started: Dictionary = ToxicV1.plan(fresh, 0.0, casters, members, clear)
	expect(same(fresh, ToxicV1.initial()), "planning never mutates caller")
	expect(started.state.casters["21"].phase == "windup" and started.state.casters["21"].remaining == 0.9, "cast begins with full windup")
	expect(same(started.state.casters["21"].point, [80.0, 0.0]) and started.state.sequence == 1, "stable locked point and sequence")
	expect(ToxicV1.problem(started.state).is_empty(), "windup state validates")
	members = [row(1, Vector2(300.0, 0.0)), row(2, Vector2(300.0, 0.0))]
	var mid: Dictionary = ToxicV1.plan(started.state, 0.4, casters, members, clear)
	expect(mid.state.casters["21"].remaining == 0.5 and same(mid.state.casters["21"].point, [80.0, 0.0]), "movement never retargets windup")
	var cast: Dictionary = ToxicV1.plan(mid.state, 0.5, casters, members, clear)
	expect(cast.state.zones.size() == 1 and cast.hits.is_empty(), "release does not damage immediately")
	expect(cast.state.zones[0].age == 0.0 and cast.state.zones[0].next_tick == 1, "release starts original three second clock")
	expect(cast.state.casters["21"].phase == "cooldown" and cast.state.casters["21"].remaining == 6.0, "successful release gets six second cooldown")
	expect(same(cast.state.zones[0].point, [80.0, 0.0]) and cast.state.releases[0].id == "toxic:21:1", "stable release source is independent of moved target")
	expect(ToxicV1.problem(cast.state).is_empty(), "released state validates")
	members = [row(1, Vector2(80.0, 0.0)), row(2, Vector2(140.0, 0.0))]
	var state: Dictionary = cast.state
	var total: int = 0
	for tick: int in range(1, 5):
		var result: Dictionary = ToxicV1.plan(state, 0.75, casters, members, clear)
		expect(result.hits.size() == 2 and result.hits[0].tick == tick and result.hits[1].tick == tick, "each scheduled tick sees current circle including boundary %d" % tick)
		expect(result.hits[0].member_id == 1 and result.hits[1].member_id == 2 and result.hits[0].amount == 6.0, "fixed damage and stable member ordering %d" % tick)
		expect(ToxicV1.problem(result.state).is_empty(), "pending validates %d" % tick)
		total += result.hits.size()
		state = apply_all(result)
		expect(ToxicV1.problem(state).is_empty(), "acknowledged tick validates %d" % tick)
	expect(total == 8 and state.zones.is_empty(), "four ticks include 3.00 endpoint and then expire")
	var extra: Dictionary = ToxicV1.plan(state, 0.74, casters, members, clear)
	expect(extra.hits.is_empty(), "no fifth or lingering debuff tick")
	var dead_casters: Array[Dictionary] = [row(21, Vector2.ZERO, false)]
	var cancelled: Dictionary = ToxicV1.plan(started.state, 1.0, dead_casters, members, clear)
	expect(cancelled.state.zones.is_empty() and cancelled.state.releases.is_empty() and cancelled.state.casters.is_empty(), "death before release cancels instead of posthumous cast")
	var unavailable: Array[Dictionary] = [row(21, Vector2.ZERO, true, false)]
	cancelled = ToxicV1.plan(started.state, 0.1, unavailable, members, clear)
	expect(cancelled.state.casters["21"].phase == "cooldown" and cancelled.state.casters["21"].remaining == 6.0 and cancelled.state.zones.is_empty(), "illegal caster cancels into configured recovery")
	var after_death: Dictionary = ToxicV1.plan(cast.state, 0.75, dead_casters, members, clear)
	expect(after_death.hits.size() == 2 and after_death.state.casters.is_empty() and after_death.state.releases.size() == 1, "released zone survives source death with retained source fact")
	expect(ToxicV1.problem(after_death.state).is_empty(), "posthumous zone and pending validate")
	var frozen: Dictionary = after_death.state.duplicate(true)
	var original_hit: Dictionary = after_death.hits[0]
	state = ToxicV1.ack(after_death.state, original_hit)
	expect(state.pending.cursor == 1 and same(after_death.state, frozen), "first acknowledgement advances only immutable cursor")
	expect(same(state, ToxicV1.ack(state, original_hit)), "replayed committed hit cannot acknowledge next member")
	var moved: Array[Dictionary] = [row(1, Vector2(500.0, 500.0), false), row(2, Vector2(500.0, 500.0))]
	var retry: Dictionary = ToxicV1.plan(state, 9.0, dead_casters, moved, clear)
	expect(retry.hits.size() == 1 and retry.hits[0].member_id == 2 and same(retry.state, state), "partial failure retry freezes clocks and original uncommitted victim")
	state = apply_all(retry)
	expect(state.pending.is_empty() and state.zones[0].age == 0.75, "resume does not extend lifetime or reset next tick")
	var left: Dictionary = ToxicV1.plan(state, 0.75, dead_casters, moved, clear)
	expect(left.hits.is_empty() and left.state.zones[0].next_tick == 3, "real exit prevents subsequent tick; no damage follows player")
	var wall: Array[ShotObstacle] = [ShotObstacle.new(&"wall", Rect2(35.0, -20.0, 10.0, 40.0), true)]
	var behind: Array[Dictionary] = [row(1, Vector2(80.0, 0.0))]
	var blocked: Dictionary = ToxicV1.plan(ToxicV1.initial(), 0.0, casters, behind, wall)
	expect(blocked.state.casters["21"].phase == "chase", "wall blocks cast acquisition")
	blocked = ToxicV1.plan(started.state, 0.9, casters, behind, wall)
	expect(blocked.state.zones.is_empty() and blocked.state.casters["21"].phase == "cooldown", "release rechecks locked point wall")
	var narrow_wall: Array[ShotObstacle] = [ShotObstacle.new(&"divider", Rect2(95.0, -20.0, 5.0, 40.0), true)]
	var split: Array[Dictionary] = [row(1, Vector2(80.0, 0.0)), row(2, Vector2(110.0, 0.0))]
	blocked = ToxicV1.plan(cast.state, 0.75, casters, split, narrow_wall)
	expect(blocked.hits.size() == 1 and blocked.hits[0].member_id == 1, "zone cannot damage through wall within radius")
	var hidden: Array[Dictionary] = [row(1, Vector2(80.0, 0.0), true, false), row(2, Vector2(80.0, 0.0), false)]
	expect(ToxicV1.plan(cast.state, 0.75, casters, hidden, clear).hits.is_empty(), "unavailable indoor or dead member is protected")
	var boundary: Array[Dictionary] = [row(1, Vector2(220.0, 0.0))]
	expect(ToxicV1.plan(ToxicV1.initial(), 0.0, casters, boundary, clear).state.casters["21"].phase == "chase", "cast range uses existing strict foot boundary")
	boundary = [row(1, Vector2(140.001, 0.0))]
	expect(ToxicV1.plan(cast.state, 0.75, casters, boundary, clear).hits.is_empty(), "outside radius is not hit")
	var tied: Array[Dictionary] = [row(2, Vector2(-80.0, 0.0)), row(1, Vector2(80.0, 0.0))]
	expect(same(ToxicV1.plan(ToxicV1.initial(), 0.0, casters, tied, clear).state.casters["21"].point, [80.0, 0.0]), "nearest target tie uses stable member ID")
	var invalid: Dictionary = cast.state.duplicate(true)
	invalid.version = 2
	expect(not ToxicV1.problem(invalid).is_empty(), "unknown version fails closed")
	invalid = cast.state.duplicate(true)
	invalid.erase("pending")
	expect(not ToxicV1.problem(invalid).is_empty(), "missing state field is never defaulted")
	invalid = cast.state.duplicate(true)
	invalid.zones[0].next_tick = 4
	expect(not ToxicV1.problem(invalid).is_empty(), "tick clock cannot skip elapsed source")
	invalid = cast.state.duplicate(true)
	invalid.zones[0].age = 3.01
	expect(not ToxicV1.problem(invalid).is_empty(), "expired lifetime cannot be extended")
	invalid = cast.state.duplicate(true)
	invalid.zones[0].source_id = 99
	expect(not ToxicV1.problem(invalid).is_empty(), "zone cannot substitute source enemy")
	invalid = cast.state.duplicate(true)
	invalid.releases.clear()
	expect(not ToxicV1.problem(invalid).is_empty(), "zone requires retained successful release fact")
	invalid = cast.state.duplicate(true)
	invalid.releases[0].source_point = [1000.0, 1000.0]
	expect(not ToxicV1.problem(invalid).is_empty(), "release retains valid actual source-to-landing range")
	invalid = after_death.state.duplicate(true)
	invalid.pending.hits.append(invalid.pending.hits[0].duplicate(true))
	expect(not ToxicV1.problem(invalid).is_empty(), "same zone tick member cannot occur twice")
	invalid = after_death.state.duplicate(true)
	invalid.pending.hits[0].amount = 12.0
	expect(not ToxicV1.problem(invalid).is_empty(), "pending amount remains exact configured damage")
	invalid = after_death.state.duplicate(true)
	invalid.pending.hits[0].member_point = [1000.0, 1000.0]
	expect(not ToxicV1.problem(invalid).is_empty(), "pending hit retains in-circle historical member foot")
	invalid = after_death.state.duplicate(true)
	invalid.pending.cursor = invalid.pending.hits.size()
	expect(not ToxicV1.problem(invalid).is_empty(), "fully committed pending cannot be replayed")
	invalid = started.state.duplicate(true)
	invalid.casters["21"].remaining = 0.0
	expect(not ToxicV1.problem(invalid).is_empty(), "zero windup must transition before save")
	invalid = started.state.duplicate(true)
	invalid.sequence = 2
	expect(not ToxicV1.problem(invalid).is_empty(), "active windup must own current cast sequence")
	var too_many: Array[Dictionary] = [row(21, Vector2.ZERO), row(22, Vector2.ONE)]
	expect(same(ToxicV1.plan(fresh, 0.0, too_many, members, clear).state, fresh), "extra live caster fails closed")
	var doubled: Dictionary = cast.state.duplicate(true)
	var second: Dictionary = doubled.releases[0].duplicate(true)
	second.id = "toxic:21:2"
	second.sequence = 2
	doubled.sequence = 2
	doubled.releases.append(second)
	var zone: Dictionary = second.duplicate(true)
	zone.age = 0.0
	zone.next_tick = 1
	doubled.zones.append(zone)
	doubled.casters["21"] = {"id":21, "phase":"chase", "remaining":0.0, "point":[], "sequence":0}
	expect(ToxicV1.problem(doubled).is_empty(), "two exact source zones is permitted hard cap")
	var capped: Dictionary = ToxicV1.plan(doubled, 0.0, casters, members, clear)
	expect(capped.state.casters["21"].phase == "chase" and capped.state.sequence == 2, "full zones prevent new windup without consuming sequence")
	invalid = doubled.duplicate(true)
	invalid.zones.append(zone.duplicate(true))
	expect(not ToxicV1.problem(invalid).is_empty(), "third zone rejected")
	var four_hits: Dictionary = ToxicV1.plan(doubled, 0.75, casters, members, clear)
	expect(four_hits.hits.size() == 4, "two overlapping zones each tick each member once")
	var found_toxic: bool = false
	for index: int in range(40):
		var kind: String = ToxicV1.pick("toxic-v1-pure-fixture", index, 3)
		if kind == ToxicV1.KIND:
			found_toxic = true
			expect(ToxicV1.pick("toxic-v1-pure-fixture", index, 3, 1) == EnemyRules.NORMAL, "toxic cap falls back normal without reroll")
	expect(found_toxic, "fixed bucket fixture includes toxic type")
	var view: ToxicVisualV1 = ToxicVisualV1.new()
	view.present(started.state)
	expect(same(started.state, view._state), "restored windup displays the exact locked point and timer")
	view.present(cast.state)
	expect(same(cast.state, view._state), "restored active gas displays the exact zone and age")
	view.present(ToxicV1.initial())
	expect(view._state.casters.is_empty() and view._state.zones.is_empty(), "no danger boundary survives retirement")
	view.free()
	_carrier_art()
	print("TOXIC_V1 checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _carrier_art() -> void:
	var sprite: Sprite2D = Sprite2D.new()
	expect(ToxicCarrierVisualV1.SHEET.get_size() == Vector2(800, 1920), "registered atlas has twelve poses in five source views")
	for octant: int in range(8):
		ToxicCarrierVisualV1.pose(sprite, Vector2.RIGHT.rotated(octant * PI / 4.0), &"windup", 0.0, 0.0, 0.0, 0.8)
		expect(sprite.frame == 40 + NormalInfectedV1.SOURCE_FOR_OCTANT[octant] and sprite.flip_h == (octant in [3, 4, 5])
			and sprite.offset == Vector2(0, -64), "late cast uses the normal octant and fixed foot anchor")
	var rows: Array[int] = [
		ToxicCarrierVisualV1.frame_for(&"idle", 0.0, 0.0, 0.0, 0.0),
		ToxicCarrierVisualV1.frame_for(&"move", 0.25, 0.0, 0.0, 0.0),
		ToxicCarrierVisualV1.frame_for(&"attack", 0.0, 0.30, 0.0, 0.0),
		ToxicCarrierVisualV1.frame_for(&"windup", 0.0, 0.0, 0.0, 0.0),
		ToxicCarrierVisualV1.frame_for(&"hit", 0.0, 0.0, 0.0, 0.0),
		ToxicCarrierVisualV1.frame_for(&"defeated", 0.0, 0.0, 0.30, 0.0),
	]
	expect(rows == [0, 2, 5, 7, 9, 11], "idle, gait, contact, cast, hit and fallen choose distinct frames")
	sprite.free()
