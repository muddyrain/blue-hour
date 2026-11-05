class_name CombatPatternsV1
extends RefCounted
## PROJECT_ADAPTATION geometry; all V1 numbers are PROJECT_TEMP.

const AXE_ID: String = "fire_axe_v1"
const SHOTGUN_ID: String = "shotgun_v1"
const POLICY: Dictionary = {
	"axe":{"damage":34.0, "interval":1.0, "windup":0.18, "range":50.0,
		"angle_degrees":110.0, "max_targets":3, "repair_cost":10},
	"shotgun":{"damage":9.0, "pellets":5, "interval":1.10, "range":150.0,
		"capacity":4, "reload_seconds":2.40, "repair_cost":10, "radius":12.0,
		"angles_degrees":[-12.0, -6.0, 0.0, 6.0, 12.0]},
}


static func axe_plan(origin: Vector2, heading: Vector2, targets: Array[Dictionary],
		obstacles: Array[ShotObstacle], reach: float = 50.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _valid_frame(origin, heading, reach) or not _valid_targets(targets):
		return result
	var direction: Vector2 = heading.normalized()
	var candidates: Array[Dictionary] = []
	var threshold: float = cos(deg_to_rad(float(POLICY.axe.angle_degrees) * 0.5))
	for target: Dictionary in targets:
		var offset: Vector2 = target.foot - origin
		var distance: float = offset.length_squared()
		if not target.alive or not target.available or distance >= reach * reach:
			continue
		if distance > 0.0 and direction.dot(offset.normalized()) < threshold:
			continue
		var start: Vector2 = origin + Vector2.UP * AttackRules.HIT_HEIGHT
		var end: Vector2 = target.foot + Vector2.UP * AttackRules.HIT_HEIGHT
		if _first_wall(start, end, obstacles) < INF:
			continue
		candidates.append({"id":int(target.id), "distance":distance})
	candidates.sort_custom(_nearer)
	for candidate: Dictionary in candidates:
		result.append({"id":int(candidate.id), "hits":1})
		if result.size() == int(POLICY.axe.max_targets):
			break
	return result


static func shotgun_plan(origin: Vector2, muzzle: Vector2, heading: Vector2,
		targets: Array[Dictionary], obstacles: Array[ShotObstacle], reach: float = 150.0) -> Dictionary:
	var result: Dictionary = {"targets":[], "rays":[]}
	if not _valid_frame(origin, heading, reach) or not muzzle.is_finite() or not _valid_targets(targets):
		return result
	var counts: Dictionary = {}
	for angle: float in POLICY.shotgun.angles_degrees:
		var direction: Vector2 = heading.normalized().rotated(deg_to_rad(angle))
		var end: Vector2 = muzzle + direction * reach
		var wall: float = _first_wall(muzzle, end, obstacles)
		var first: float = INF
		var victim: int = -1
		for target: Dictionary in targets:
			# The foot boundary remains strict even when a muzzle or circle projects beyond it.
			if not target.alive or not target.available or origin.distance_squared_to(target.foot) >= reach * reach:
				continue
			var center: Vector2 = target.foot + Vector2.UP * AttackRules.HIT_HEIGHT
			var entry: float = _circle_entry(muzzle, end, center, float(POLICY.shotgun.radius))
			# A wall wins an exact collision tie; enemy ties use the stable identity.
			if entry >= wall or entry == INF:
				continue
			if entry < first or entry == first and (victim == -1 or int(target.id) < victim):
				first = entry
				victim = int(target.id)
		var stop: float = minf(first, wall)
		result.rays.append({"from":muzzle, "to":muzzle.lerp(end, stop) if stop < INF else end, "id":victim})
		if victim != -1:
			counts[victim] = int(counts.get(victim, 0)) + 1
	var identities: Array = counts.keys()
	identities.sort()
	for identity: int in identities:
		result.targets.append({"id":identity, "hits":int(counts[identity])})
	return result


static func _valid_frame(origin: Vector2, heading: Vector2, reach: float) -> bool:
	return origin.is_finite() and heading.is_finite() and heading.length_squared() > 0.0 and is_finite(reach) and reach > 0.0


static func _valid_targets(targets: Array[Dictionary]) -> bool:
	var identities: Dictionary = {}
	for target: Dictionary in targets:
		if not target.has_all(["id", "foot", "alive", "available"]):
			return false
		if not target.id is int or target.id < 0 or identities.has(target.id):
			return false
		if not target.foot is Vector2 or not target.foot.is_finite() or not target.alive is bool or not target.available is bool:
			return false
		identities[target.id] = true
	return true


static func _nearer(left: Dictionary, right: Dictionary) -> bool:
	return left.distance < right.distance or left.distance == right.distance and left.id < right.id


static func _first_wall(start: Vector2, end: Vector2, obstacles: Array[ShotObstacle]) -> float:
	var first: float = INF
	for obstacle: ShotObstacle in obstacles:
		if not obstacle.blocks_shots:
			continue
		var projected: Rect2 = obstacle.footprint
		projected.position.y -= AttackRules.HIT_HEIGHT
		first = minf(first, AttackRules._segment_entry(start, end, projected))
	return first


static func _circle_entry(start: Vector2, end: Vector2, center: Vector2, radius: float) -> float:
	var offset: Vector2 = start - center
	var c: float = offset.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var direction: Vector2 = end - start
	var a: float = direction.length_squared()
	if a == 0.0:
		return INF
	var b: float = offset.dot(direction)
	var discriminant: float = b * b - a * c
	if discriminant < 0.0:
		return INF
	var entry: float = (-b - sqrt(discriminant)) / a
	return entry if entry >= 0.0 and entry <= 1.0 else INF
