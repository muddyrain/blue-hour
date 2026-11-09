class_name BurstAuthorityV1
extends RefCounted
## Certifies the entire pulse before exposing any of its hits or death facts.


static func mode(rules: Variant) -> bool:
	return rules is Dictionary and rules.get("mission") is Dictionary \
		and rules.mission.get("generated") is Dictionary and ContentWaveV1.eligible(rules.mission.generated)


static func same_event(left: Variant, right: Variant) -> bool:
	var fingerprint: String = RecordEncoding.fingerprint({"burst":left})
	return not fingerprint.is_empty() and fingerprint == RecordEncoding.fingerprint({"burst":right})


static func receipt_problem(receipt: Dictionary) -> String:
	var event: Variant = receipt.get("burst")
	if not event is Dictionary or (receipt.phase == "STARTED" and not event.is_empty()):
		return "BURST_RECEIPT_FIELDS"
	if event.is_empty():
		return ""
	if event.size() != 6 or not event.has_all(["id", "source_id", "sequence", "at", "origin", "hits"]) \
			or not SurvivalContracts.integer(event.source_id, 0, RunSave.MAX_COUNTER) \
			or event.id != "%s:burst:%d:1" % [receipt.transaction_id, int(event.source_id)] \
			or not SurvivalContracts.integer(event.sequence, 1, 1) \
			or not SurvivalContracts.number(event.at) or event.at < BurstRuntimeV1.WINDUP \
			or not SortieSnapshot._vector(event.origin) or not event.hits is Array:
		return "BURST_EVENT_FIELDS"
	var amount: float = _amount(receipt.rules.mission.generated)
	var prior_id: int = 0
	var origin: Vector2 = SortieSnapshot._vec(event.origin)
	for hit: Variant in event.hits:
		if not hit is Dictionary or hit.size() != 5 or not hit.has_all(["member_id", "point", "before", "after", "amount"]) \
				or not SurvivalContracts.integer(hit.member_id, prior_id + 1, SurvivalContracts.MAX_ID) \
				or SurvivorRoster.member(receipt.participants, int(hit.member_id)).is_empty() \
				or not SortieSnapshot._vector(hit.point) or origin.distance_to(SortieSnapshot._vec(hit.point)) > BurstRuntimeV1.RADIUS \
				or not SurvivalContracts.number(hit.before) or hit.before <= 0.0 \
				or not SurvivalContracts.number(hit.after) or hit.after != maxf(0.0, float(hit.before) - amount) \
				or not SurvivalContracts.number(hit.amount) or hit.amount != amount:
			return "BURST_HIT_FIELDS"
		prior_id = int(hit.member_id)
	return ""


static func propose(before: Dictionary, previous: Dictionary) -> Dictionary:
	if not mode(previous.rules) or not previous.get("burst") is Dictionary or not previous.burst.is_empty() \
			or not before.get("survivors") is Array or not before.get("combat") is Dictionary \
			or not before.combat.get("burst") is Dictionary or before.combat.burst.get("phase") != "confirming":
		return {}
	var checkpoint: Dictionary = previous.duplicate(true)
	for row: Variant in before.survivors:
		if not row is Dictionary or not row.get("state") is Dictionary \
				or not SurvivalContracts.integer(row.state.get("member_id"), 1, SurvivalContracts.MAX_ID) \
				or not SurvivalContracts.number(row.state.get("health")):
			return {}
		var member: Dictionary = SurvivorRoster.member(checkpoint.health, int(row.state.member_id))
		if member.is_empty() or row.state.health > member.health:
			return {}
		member.health = row.state.health
	if not SortieSnapshot.problem(before, checkpoint).is_empty() \
			or SpecialPowers.frozen(before.powers, float(before.sim.elapsed)):
		return {}
	var supply: MissionSupply = SortieSnapshot.supply_for_world(before)
	if supply == null:
		return {}
	var after: Dictionary = before.duplicate(true)
	var burst: Dictionary = after.combat.burst
	var origin: Vector2 = SortieSnapshot._vec(burst.origin)
	var obstacles: Array[ShotObstacle] = supply.layout.shot_obstacles()
	var amount: float = _amount(after.generated)
	var members: Array = after.survivors.duplicate()
	members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.state.member_id < b.state.member_id)
	var context: Dictionary = FieldJoinRules.context(previous)
	var hits: Array[Dictionary] = []
	var deaths: Array[Dictionary] = []
	var down: Array[int] = []
	for row: Dictionary in members:
		var actor: Dictionary = row.state
		var point: Vector2 = SortieSnapshot._vec(actor.position)
		if actor.health <= 0.0 or not actor.visible or actor.activity == FieldActor.Activity.SEARCHING \
				or not BurstRuntimeV1.reaches(origin, point, obstacles):
			continue
		var member_id: int = int(actor.member_id)
		var health: float = float(actor.health)
		var remaining: float = maxf(0.0, health - amount)
		hits.append({"member_id":member_id, "point":actor.position.duplicate(),
			"before":health, "after":remaining, "amount":amount})
		actor.health = remaining
		actor.damage_received += health - remaining
		row.visual._hit_clock = 0.18
		row.visual._hit_direction = BurstRuntimeV1._pair(origin.direction_to(point))
		if remaining > 0.0:
			continue
		var member: Dictionary = SurvivorRoster.member(context.crew, member_id).duplicate(true)
		member.health = health
		var death: Dictionary = DeathRules.propose(member, remaining, "BATTLE", previous.transaction_id, {}, true)
		if not death.get("created", false):
			return {}
		deaths.append({"death":death.death, "health_before":health})
		down.append(member_id)
		actor.activity = FieldActor.Activity.DOWN
		actor.permanent_death = true
		actor.path = []
		row.visual._is_defeated = true
		row.visual._defeat_clock = 0.0
		var action: Dictionary = after.combat.actions.get(str(member_id), {})
		if not action.is_empty():
			action.remaining = 0.0
	_release_dead_targets(after, down)
	burst.phase = "released"
	burst.event = {"id":"%s:burst:%d:1" % [previous.transaction_id, int(burst.actor_id)],
		"source_id":int(burst.actor_id), "sequence":1, "at":after.sim.elapsed,
		"origin":burst.origin.duplicate(), "hits":hits}
	return {"world":after, "deaths":deaths, "event":burst.event}


static func _release_dead_targets(world: Dictionary, down: Array[int]) -> void:
	if down.is_empty():
		return
	var jobs: Array = world.jobs.assignments
	for index: int in range(jobs.size() - 1, -1, -1):
		var job: Dictionary = jobs[index]
		if int(job.member_id) in down:
			world.sites[job.site_id].progress = 0.0
			jobs.remove_at(index)
	for row: Dictionary in world.enemies:
		if int(row.behavior.target_id) not in down:
			continue
		if row.behavior.state == "windup":
			row.state.cooldown = ExpeditionTuning.new().enemy_interval
		row.behavior.target_id = 0
		row.behavior.state = "chase"
		row.behavior.windup_remaining = 0.0
		row.state.speed = EnemyRules.speed(row.behavior.kind, false, 34.0)
		row.state.aim = [0.0, 0.0]


static func _amount(generated: Dictionary) -> float:
	return BurstRuntimeV1.DAMAGE * float(BuildItems.frozen_factors(generated.build).get("burst", 1.0))


static func transition(previous: Dictionary, next: Dictionary) -> String:
	if same_event(previous.burst, next.burst):
		if next.envelope.has("burst_proposal") and not (previous.phase == "SUSPEND_READY" and next.phase == "RESUME_CLAIMED"):
			return "BURST_PROOF_WITHOUT_RELEASE"
		return ""
	if not previous.burst.is_empty() or next.burst.is_empty() or next.phase != "SUSPEND_READY":
		return "BURST_EVENT_RETRACTED_OR_PHASE"
	var before: Variant = next.envelope.get("burst_proposal")
	if not before is Dictionary:
		return "BURST_PROOF_MISSING"
	var proposed: Dictionary = propose(before, previous)
	if proposed.is_empty() or not same_event(proposed.event, next.burst) \
			or not same_event(proposed.world, next.envelope.get("world")) \
			or not same_event(previous.deaths + proposed.deaths, next.deaths):
		return "BURST_PROOF_CONFLICT"
	return ""
