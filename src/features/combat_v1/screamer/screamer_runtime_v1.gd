class_name ScreamerRuntimeV1
extends RefCounted
## A single, sortie-local interruption window. Existing field owners apply all damage.

const PRESENT_SECONDS: float = 0.55
var state: Dictionary = initial()


static func initial() -> Dictionary:
	return {"version":ScreamerPolicyV1.VERSION, "actor_id":-1, "phase":"unused", "remaining":0.0,
		"target_id":0, "origin":[], "target":[], "armed_at":0.0, "event":{}}


func holds(actor: FieldActor) -> bool:
	return state.phase == "windup" and state.actor_id == actor.actor_id


func spawned(world: Expedition, actor: FieldActor) -> void:
	state.actor_id = actor.actor_id
	state.phase = "chase"
	_feedback(world, "screamer_spawn")


func advance(world: Expedition, delta: float) -> void:
	if world.power_frozen or state.phase not in ["chase", "windup"]:
		present(world)
		return
	var actor: FieldActor = world.combat._enemy(world, int(state.actor_id))
	if actor == null:
		return
	if state.phase == "chase":
		var target: FieldActor = _target(world, actor)
		if target != null:
			state.phase = "windup"
			state.origin = ScreamerReleaseV1.pair_for(actor.position)
			state.target = ScreamerReleaseV1.pair_for(target.position)
			state.target_id = target.member_id
			state.armed_at = world.elapsed
			state.remaining = ScreamerPolicyV1.WINDUP
			actor.clear_order()
			actor.motion_locked = true
			actor.aim = actor.position.direction_to(target.position)
			_feedback(world, "screamer_windup")
			world._show_notice("尖啸蓄势 · 击倒它可阻止增援。")
	else:
		state.remaining = maxf(0.0, float(state.remaining) - delta)
		if state.remaining <= 0.000001:
			_release(world, actor)
	present(world)


func removed(world: Expedition, actor_id: int) -> void:
	if cancel(state, actor_id):
		report_cancelled(world)


func report_cancelled(world: Expedition) -> void:
	_feedback(world, "screamer_cancelled")
	if state.target_id != 0:
		world._show_notice("尖啸已打断 · 未叫来增援。")


static func cancel(value: Dictionary, actor_id: int) -> bool:
	if value.get("actor_id") != actor_id or value.get("phase") not in ["chase", "windup"]:
		return false
	value.phase = "cancelled"
	value.remaining = 0.0
	return true


func present(world: Expedition) -> void:
	if state.actor_id < 0:
		return
	var actor: FieldActor = world.combat._enemy(world, int(state.actor_id))
	if actor == null:
		return
	var phase: StringName = StringName(state.phase)
	var direction: Vector2 = actor.visual._facing
	var progress: float = 0.0
	if phase in [&"windup", &"released"]:
		direction = SortieSnapshot._vec(state.origin).direction_to(SortieSnapshot._vec(state.target))
		progress = 1.0 - float(state.remaining) / ScreamerPolicyV1.WINDUP if phase == &"windup" \
			else (world.elapsed - float(state.event.at)) / PRESENT_SECONDS
		if phase == &"released" and progress >= 1.0:
			phase = &"chase"
	actor.visual.present_screamer(direction, phase, clampf(progress, 0.0, 1.0))


func _target(world: Expedition, actor: FieldActor) -> FieldActor:
	var target: FieldActor = null
	var closest: float = INF
	for member: FieldActor in world.survivors:
		var distance: float = actor.position.distance_squared_to(member.position)
		if (distance < closest or (distance == closest and target != null and member.member_id < target.member_id)) \
				and actor.enemy_behavior.legal(world, actor, member, ScreamerPolicyV1.RANGE):
			closest = distance
			target = member
	return target


func _release(world: Expedition, actor: FieldActor) -> void:
	var visible: Rect2 = world.visible_world_rect()
	var party: Array[Array] = []
	var occupied: Array[Array] = []
	for member: FieldActor in world.survivors:
		if member.activity not in [FieldActor.Activity.DOWN, FieldActor.Activity.SEARCHING]:
			party.append(ScreamerReleaseV1.pair_for(member.position))
	for enemy: FieldActor in world.enemies:
		occupied.append(ScreamerReleaseV1.pair_for(enemy.position))
	var event: Dictionary = {"source_id":actor.actor_id, "event_id":"screamer:%d:1" % actor.actor_id,
		"at":world.elapsed, "stage":int(world.threat.stage), "first_id":world._spawn_count, "attempt":world._spawn_attempts,
		"view":[visible.position.x, visible.position.y, visible.size.x, visible.size.y],
		"viewport":ScreamerReleaseV1.pair_for(world.get_viewport_rect().size), "party":party, "occupied":occupied}
	event.merge(ScreamerReleaseV1.plan(event, world.layout, world.navigation, world.threat.rules))
	state.phase = "released"
	state.remaining = 0.0
	state.event = event
	actor.motion_locked = false
	world._spawn_screamer_batch(event)
	_feedback(world, "screamer_released")
	world._show_notice("尖啸已响 · %d 只普通感染者从街口接近。" % event.spawned.size() if not event.spawned.is_empty() \
		else "尖啸已响 · %s。" % ("街道已满" if event.reason == "capacity" else "没有可用街口"))


func _feedback(world: Expedition, kind: String) -> void:
	var event: Dictionary = {"kind":kind, "actor_id":state.actor_id, "elapsed":world.elapsed,
		"remaining":state.remaining, "event":state.event.duplicate(true)}
	world.combat_feedback.emit(event)
	print("BH_SCREAMER " + JSON.stringify(event))


static func summon_ids(world: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for row: Dictionary in world.get("combat", {}).get("screamer", {}).get("event", {}).get("spawned", []):
		result.append(int(row.enemy_id))
	return result


static func problem(value: Variant, world: Dictionary, receipt: Dictionary, layout: StreetLayout) -> String:
	if not value is Dictionary or value.size() != 9 or not value.has_all(initial().keys()) \
			or not SurvivalContracts.integer(value.version, ScreamerPolicyV1.VERSION, ScreamerPolicyV1.VERSION) \
			or not SurvivalContracts.integer(value.actor_id, -1, int(world.sim._spawn_count) - 1) \
			or value.phase not in ["unused", "chase", "windup", "cancelled", "released"] \
			or not SurvivalContracts.number(value.remaining) or value.remaining < 0.0 or value.remaining > ScreamerPolicyV1.WINDUP \
			or not SurvivalContracts.number(value.armed_at) or value.armed_at < 0.0 or value.armed_at > world.sim.elapsed \
			or not SurvivalContracts.integer(value.target_id, 0, SurvivalContracts.MAX_ID) \
			or not value.origin is Array or not value.target is Array or not value.event is Dictionary:
		return "SCREAMER_WORLD_FIELDS"
	if (value.phase == "windup") != (value.remaining > 0.0) or (value.phase == "released") == value.event.is_empty():
		return "SCREAMER_WORLD_PHASE"
	var active: Dictionary = {}
	for row: Dictionary in world.enemies:
		if row.state.actor_id == value.actor_id:
			active = row
		if (row.behavior.kind == ScreamerPolicyV1.KIND) != (row.state.actor_id == value.actor_id):
			return "SCREAMER_ACTOR_SOURCE"
	if value.phase == "unused":
		if not TransactionReceipt.same(value, initial()):
			return "SCREAMER_UNUSED_FIELDS"
	else:
		if value.actor_id < 0 or (value.phase in ["chase", "windup"] and active.is_empty()) \
				or (value.phase == "cancelled" and not active.is_empty()):
			return "SCREAMER_ACTOR_PHASE"
		var intent: String = _intent_problem(value, active, world, layout)
		if not intent.is_empty():
			return intent
	if value.phase == "released":
		var issue: String = ScreamerReleaseV1.problem(value.event, value, world, layout)
		if not issue.is_empty():
			return issue
	return _sources_problem(value, world, receipt)


static func _intent_problem(value: Dictionary, active: Dictionary, world: Dictionary, layout: StreetLayout) -> String:
	if value.target_id == 0:
		return "" if value.phase in ["chase", "cancelled"] and value.armed_at == 0.0 \
			and value.origin.is_empty() and value.target.is_empty() else "SCREAMER_INTENT_EMPTY"
	if value.phase == "chase" or not SortieSnapshot._vector(value.origin) or not SortieSnapshot._vector(value.target) \
			or SortieSnapshot._member(world.survivors, int(value.target_id)).is_empty():
		return "SCREAMER_INTENT_FIELDS"
	var origin: Vector2 = SortieSnapshot._vec(value.origin)
	var target: Vector2 = SortieSnapshot._vec(value.target)
	var director: ThreatDirector = ThreatDirector.new()
	director.update(float(value.armed_at), 105.0, 7.0)
	if director.stage < ThreatDirector.Stage.LATE or not layout.world_bounds.has_point(origin) or not layout.world_bounds.has_point(target) \
			or origin.distance_to(target) >= ScreamerPolicyV1.RANGE or not ToxicV1.line_clear(origin, target, layout.shot_obstacles()):
		return "SCREAMER_INTENT_TARGET"
	if value.phase == "windup" and (active.state.activity != FieldActor.Activity.IDLE or not active.state.path.is_empty() \
			or SortieSnapshot._vec(active.state.position) != origin \
			or float(world.sim.elapsed) + 0.0001 < float(value.armed_at) + ScreamerPolicyV1.WINDUP - float(value.remaining)):
		return "SCREAMER_INTENT_LOCK"
	return ""


static func _sources_problem(value: Dictionary, world: Dictionary, receipt: Dictionary) -> String:
	var accounted: Dictionary = {}
	var first: int = -1
	for key: String in world.combat.spawns:
		var id: int = int(key)
		var source: Dictionary = world.combat.spawns[key]
		accounted[id] = true
		if int(source.stage) >= ThreatDirector.Stage.LATE and CombatEnemyRules.pick(receipt.transaction_id, id, int(source.stage)) == EnemyRules.NORMAL:
			if first == -1 or id < first:
				first = id
	if value.actor_id != first or (first >= 0 and world.combat.spawns[str(first)].kind != ScreamerPolicyV1.KIND):
		return "SCREAMER_FIRST_NORMAL_SOURCE"
	for row: Dictionary in world.task_event.resolutions:
		if row.reason != "spawned":
			continue
		var id: int = int(row.enemy_id)
		if accounted.has(id):
			return "SCREAMER_DUPLICATE_TASK_SOURCE"
		accounted[id] = true
	for id: int in summon_ids(world):
		if accounted.has(id):
			return "SCREAMER_DUPLICATE_SPAWN_SOURCE"
		accounted[id] = true
		for row: Dictionary in world.enemies:
			if row.state.actor_id == id and (row.behavior.kind != EnemyRules.NORMAL or row.behavior.spawn_stage != value.event.stage):
				return "SCREAMER_REINFORCEMENT_KIND"
	return "" if accounted.size() == int(world.sim._spawn_count) else "SCREAMER_MISSING_SPAWN_SOURCE"
