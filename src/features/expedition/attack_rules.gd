class_name AttackRules
extends RefCounted
## Pure candidate/commit predicate. TMP-123..TMP-125, not a verified reference algorithm.

# Same target height as the existing tracer. Geometry is projected onto this plane too.
const HIT_HEIGHT: float = 28.0


static func evaluate(shooter: Combatant, target: Combatant, muzzle: Vector2,
		shot_range: float, cooldown: float, obstacles: Array[ShotObstacle]) -> Decision:
	var result: Decision = Decision.new()
	result.shot_from = muzzle
	result.hit_to = target.foot + Vector2.UP * HIT_HEIGHT
	result.distance = shooter.foot.distance_to(target.foot)
	if not shooter.alive or not shooter.available:
		result.reason = &"shooter_unavailable"
		return result
	if not target.alive:
		result.reason = &"dead"
		return result
	if not target.available:
		result.reason = &"target_unavailable"
		return result
	if shooter.is_enemy == target.is_enemy:
		result.reason = &"friendly"
		return result
	# Preserve TMP101's strict foot-distance boundary; muzzle length grants no extra range.
	if result.distance >= shot_range:
		result.reason = &"out_of_range"
		return result
	var first: float = INF
	for obstacle: ShotObstacle in obstacles:
		if not obstacle.blocks_shots:
			continue
		var bounds: Rect2 = obstacle.footprint
		bounds.position.y -= HIT_HEIGHT
		var entry: float = _segment_entry(muzzle, result.hit_to, bounds)
		if entry < first:
			first = entry
			result.blocker_id = obstacle.id
	if first < INF:
		result.reason = &"blocked"
		result.blocked_at = muzzle.lerp(result.hit_to, first)
		return result
	result.targetable = true
	result.can_fire = cooldown <= 0.0
	result.reason = &"valid" if result.can_fire else &"cooldown"
	return result


static func _segment_entry(start: Vector2, end: Vector2, bounds: Rect2) -> float:
	var near: float = 0.0
	var far: float = 1.0
	var direction: Vector2 = end - start
	for axis: int in range(2):
		if is_zero_approx(direction[axis]):
			if start[axis] < bounds.position[axis] or start[axis] > bounds.end[axis]:
				return INF
			continue
		var a: float = (bounds.position[axis] - start[axis]) / direction[axis]
		var b: float = (bounds.end[axis] - start[axis]) / direction[axis]
		near = maxf(near, minf(a, b))
		far = minf(far, maxf(a, b))
		if near > far:
			return INF
	return near


class Combatant extends RefCounted:
	var foot: Vector2
	var alive: bool
	var available: bool
	var is_enemy: bool


	func _init(point: Vector2, living: bool, active: bool, enemy: bool) -> void:
		foot = point
		alive = living
		available = active
		is_enemy = enemy


class Decision extends RefCounted:
	var targetable: bool = false
	var can_fire: bool = false
	var reason: StringName = &"unavailable"
	var blocker_id: StringName = &""
	var distance: float = 0.0
	var shot_from: Vector2
	var hit_to: Vector2
	var blocked_at: Vector2
