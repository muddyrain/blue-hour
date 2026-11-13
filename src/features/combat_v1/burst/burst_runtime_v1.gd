class_name BurstRuntimeV1
extends RefCounted
## The field owns windup. The original journal owns the one release and its damage.

const VERSION: int = 1
const KIND: String = "burst_infected_v1"
const WINDUP: float = 0.90
const RADIUS: float = 68.0
const DAMAGE: float = 20.0
const POLICY: Dictionary = {"version":VERSION, "kind":KIND, "windup":WINDUP, "radius":RADIUS, "damage":DAMAGE}

var state: Dictionary = initial()


static func initial() -> Dictionary:
	return {"version":VERSION, "actor_id":-1, "phase":"unused", "remaining":0.0,
		"origin":[], "target":[], "target_id":0, "armed_at":0.0, "event":{}}


func holds(actor: FieldActor) -> bool:
	return state.actor_id == actor.actor_id and state.phase in ["windup", "confirming"]


func warning_text() -> String:
	match state.phase:
		"windup":
			return "爆囊冲击 · %.1f 秒" % (ceilf(float(state.remaining) * 10.0) / 10.0)
		"confirming":
			return "爆囊冲击 · 确认中"
	return ""


func spawned(world: Expedition, actor: FieldActor) -> void:
	state.actor_id = actor.actor_id
	state.phase = "chase"
	feedback(world, "burst_spawn")


func advance(world: Expedition, delta: float) -> void:
	if world.power_frozen or state.phase not in ["chase", "windup"]:
		return
	var actor: FieldActor = world.combat._enemy(world, int(state.actor_id))
	if actor == null:
		return
	if state.phase == "chase":
		var target: FieldActor = _target(world, actor)
		if target == null:
			return
		state.phase = "windup"
		state.origin = _pair(actor.position)
		state.target = _pair(target.position)
		state.target_id = target.member_id
		state.armed_at = world.elapsed
		state.remaining = WINDUP
		actor.clear_order()
		actor.motion_locked = true
		actor.aim = actor.position.direction_to(target.position)
		feedback(world, "burst_windup")
		world._show_notice("爆囊蓄势 · 离开警圈或躲到墙后。")
		return
	state.remaining = maxf(0.0, float(state.remaining) - delta)
	if state.remaining <= 0.000000001:
		state.phase = "confirming"
		state.remaining = 0.0
		world.accept_burst(world.support_world())


func removed(world: Expedition, actor_id: int) -> void:
	if cancel(state, actor_id):
		feedback(world, "burst_cancelled")
		if state.target_id != 0:
			world._show_notice("爆囊已击倒 · 冲击取消。")


static func cancel(value: Dictionary, actor_id: int) -> bool:
	if value.get("actor_id") != actor_id or value.get("phase") not in ["chase", "windup"]:
		return false
	value.phase = "cancelled"
	value.remaining = 0.0
	return true


func draw_warning(world: Expedition) -> void:
	if world.phase == Expedition.Phase.FINISHED or state.phase not in ["windup", "confirming", "released"]:
		return
	var released: bool = state.phase == "released"
	if released and world.elapsed - float(state.event.at) >= 0.30:
		return
	var foot: Vector2 = IsoSpace.to_view(SortieSnapshot._vec(state.origin))
	var tint: Color = Color("ffb44b")
	world.draw_circle(foot, RADIUS, Color(tint, 0.16 if released else 0.09))
	world.draw_arc(foot, RADIUS, 0.0, TAU, 64, tint, 3.0, true)
	if not released:
		var fraction: float = clampf(1.0 - float(state.remaining) / WINDUP, 0.0, 1.0)
		if fraction > 0.0:
			world.draw_arc(foot, RADIUS - 6.0, -PI / 2.0, -PI / 2.0 + TAU * fraction,
				64, Color("ffe1a1"), 4.0, true)


func feedback(world: Expedition, kind: String) -> void:
	var event: Dictionary = {"kind":kind, "actor_id":state.actor_id, "elapsed":world.elapsed,
		"remaining":state.remaining, "event":state.event.duplicate(true)}
	world.combat_feedback.emit(event)


func _target(world: Expedition, actor: FieldActor) -> FieldActor:
	var closest: FieldActor = null
	var distance: float = INF
	for member: FieldActor in world.survivors:
		if member.health <= 0.0 or not member.visible or member.activity == FieldActor.Activity.SEARCHING:
			continue
		var candidate: float = actor.position.distance_squared_to(member.position)
		if (candidate < distance or (candidate == distance and closest != null and member.member_id < closest.member_id)) \
				and reaches(actor.position, member.position, world.shot_obstacles):
			closest = member
			distance = candidate
	return closest


static func reaches(origin: Vector2, point: Vector2, obstacles: Array[ShotObstacle]) -> bool:
	if origin.distance_squared_to(point) > RADIUS * RADIUS:
		return false
	var source: AttackRules.Combatant = AttackRules.Combatant.new(origin, true, true, true)
	var target: AttackRules.Combatant = AttackRules.Combatant.new(point, true, true, false)
	return AttackRules.evaluate(source, target, origin + Vector2.UP * AttackRules.HIT_HEIGHT,
		INF, 0.0, obstacles).targetable


static func _pair(point: Vector2) -> Array[float]:
	return [point.x, point.y]


static func problem(value: Variant, world: Dictionary, receipt: Dictionary, layout: StreetLayout) -> String:
	if not value is Dictionary or value.size() != 9 or not value.has_all(initial().keys()) \
			or not SurvivalContracts.integer(value.version, VERSION, VERSION) \
			or not SurvivalContracts.integer(value.actor_id, -1, int(world.sim._spawn_count) - 1) \
			or value.phase not in ["unused", "chase", "windup", "confirming", "cancelled", "released"] \
			or not SurvivalContracts.number(value.remaining) or value.remaining < 0.0 or value.remaining > WINDUP \
			or not SurvivalContracts.number(value.armed_at) or value.armed_at < 0.0 or value.armed_at > world.sim.elapsed \
			or not SurvivalContracts.integer(value.target_id, 0, SurvivalContracts.MAX_ID) \
			or not value.origin is Array or not value.target is Array or not value.event is Dictionary:
		return "BURST_WORLD_FIELDS"
	if (value.phase == "windup") != (value.remaining > 0.0) or (value.phase == "released") == value.event.is_empty() \
			or not BurstAuthorityV1.same_event(value.event, receipt.get("burst")):
		return "BURST_WORLD_PHASE_OR_PROOF"
	var first: int = -1
	for key: String in world.combat.spawns:
		var id: int = int(key)
		var row: Dictionary = world.combat.spawns[key]
		if int(row.stage) == ThreatDirector.Stage.LATE and row.kind != ScreamerPolicyV1.KIND \
				and CombatEnemyRules.pick(receipt.transaction_id, id, int(row.stage)) == EnemyRules.NORMAL \
				and (first < 0 or id < first):
			first = id
	if value.actor_id != first or (first >= 0 and world.combat.spawns[str(first)].kind != KIND):
		return "BURST_FIRST_NORMAL_SOURCE"
	var active: Dictionary = {}
	for row: Dictionary in world.enemies:
		if row.state.actor_id == value.actor_id:
			active = row
		if (row.behavior.kind == KIND) != (row.state.actor_id == value.actor_id):
			return "BURST_ACTOR_SOURCE"
	if value.phase == "unused":
		return "" if TransactionReceipt.same(value, initial()) else "BURST_UNUSED_FIELDS"
	if value.actor_id < 0 or (value.phase in ["chase", "windup", "confirming"] and active.is_empty()) \
			or (value.phase == "cancelled" and not active.is_empty()):
		return "BURST_ACTOR_PHASE"
	if value.target_id == 0:
		return "" if value.phase in ["chase", "cancelled"] and value.armed_at == 0.0 \
			and value.origin.is_empty() and value.target.is_empty() else "BURST_EMPTY_INTENT"
	if value.phase == "chase" or not SortieSnapshot._vector(value.origin) or not SortieSnapshot._vector(value.target) \
			or SortieSnapshot._member(world.survivors, int(value.target_id)).is_empty():
		return "BURST_INTENT"
	var origin: Vector2 = SortieSnapshot._vec(value.origin)
	var target: Vector2 = SortieSnapshot._vec(value.target)
	if not layout.world_bounds.has_point(origin) or not layout.world_bounds.has_point(target) \
			or not reaches(origin, target, layout.shot_obstacles()):
		return "BURST_INTENT_TARGET"
	if value.phase in ["windup", "confirming"] and (active.state.activity != FieldActor.Activity.IDLE \
			or not active.state.path.is_empty() or SortieSnapshot._vec(active.state.position) != origin \
			or float(world.sim.elapsed) + 0.000001 < float(value.armed_at) + WINDUP - float(value.remaining)):
		return "BURST_INTENT_LOCK"
	if value.phase == "released" and (value.event.source_id != value.actor_id or value.event.origin != value.origin \
			or value.event.at + 0.000001 < value.armed_at + WINDUP or value.event.at > world.sim.elapsed):
		return "BURST_RELEASE_SOURCE"
	return ""
