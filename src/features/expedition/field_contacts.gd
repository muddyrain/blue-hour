class_name FieldContacts
extends RefCounted
## Stateless foot-disc motion. Stable IDs, bounded work and no saved solver caches.

const BUILD: String = "M5-CONTACT-01-1"
const DISTANCE: float = FieldNavigation.FOOT_RADIUS * 2.0
const APPROACH: float = 24.0
const RECHASE: float = 26.0
const STEP_DISTANCE: float = 4.0
const MAX_STEPS: int = 64
const MAX_PATH_PARTS: int = 16
const PASS_DOT: float = 0.5
const RECOVERY_SPEED: float = 80.0
const MAX_RECOVERY: float = 8.0
const RECOVERY_PASSES: int = 6
const YIELD_SPEED: float = 50.0
const ANGLES: Array[float] = [0.0,-PI/6.0,PI/6.0,-PI/3.0,PI/3.0,-PI/2.0,PI/2.0]


static func participates(actor: FieldActor) -> bool:
	return actor.health > 0.0 and actor.visible and actor.activity not in [FieldActor.Activity.DOWN,FieldActor.Activity.SEARCHING]


static func identity(actor: FieldActor) -> int:
	return actor.actor_id * 2 + 1 if actor.is_enemy else actor.member_id * 2


static func _ordered(values: Array[FieldActor]) -> Array[FieldActor]:
	var result: Array[FieldActor] = []
	for actor: FieldActor in values:
		if participates(actor): result.append(actor)
	result.sort_custom(func(a: FieldActor,b: FieldActor) -> bool: return identity(a) < identity(b))
	return result


static func move(movers: Array[FieldActor], occupants: Array[FieldActor], navigation: FieldNavigation,
		delta: float, recover: bool = false, before_move: Callable = Callable()) -> Dictionary:
	var stats: Dictionary = {"substeps":0,"recovery_max":0.0,"recovery_actor_max":0.0,"motion_deviation_max":0.0,"minimum_distance":-1.0}
	if delta <= 0.0: return stats
	var bodies: Array[FieldActor] = _ordered(occupants)
	var ordered: Array[FieldActor] = _ordered(movers)
	var fastest: float = 1.0
	for actor: FieldActor in ordered:
		if actor.activity == FieldActor.Activity.MOVING: fastest = maxf(fastest,actor.speed)
	# A very large caller delta cannot create an unbounded solve or a tunnelling leap.
	var motion_time: float = minf(delta,STEP_DISTANCE * MAX_STEPS / fastest)
	var steps: int = clampi(ceili(fastest * motion_time / STEP_DISTANCE),1,MAX_STEPS)
	var slice: float = motion_time / steps
	var recovery: Dictionary = {}
	var allowance: float = minf(MAX_RECOVERY,RECOVERY_SPEED * delta)
	for actor: FieldActor in bodies: recovery[identity(actor)] = allowance
	for step: int in range(steps):
		if recover: _recover(bodies,navigation,recovery,stats)
		for actor: FieldActor in ordered:
			var remaining: float = actor.speed * slice
			# Reaching a waypoint must not discard the rest of this motion budget.
			# Every piece is still swept; steering/blocked motion ends this microstep.
			for part: int in range(MAX_PATH_PARTS):
				if remaining <= 0.00001: break
				if before_move.is_valid(): before_move.call(actor)
				_skip_occupied_waypoints(actor,bodies,navigation)
				var wish: Vector2 = actor.path_motion(remaining,navigation)
				if wish.is_zero_approx(): break
				var accepted: Vector2 = _steer(actor,wish,bodies,navigation)
				if part==0 and not actor.is_enemy and accepted.dot(wish.normalized()) < wish.length() * 0.2:
					_yield_ally(actor,wish,bodies,navigation,minf(STEP_DISTANCE,YIELD_SPEED * slice),step==0 and part==0)
					accepted = _steer(actor,wish,bodies,navigation)
				actor.position += accepted
				actor.path_motion(0.0,navigation)
				stats.motion_deviation_max = maxf(stats.motion_deviation_max,(accepted-wish).length())
				for other: FieldActor in bodies:
					if other != actor:
						var distance: float = actor.position.distance_to(other.position)
						stats.minimum_distance = distance if stats.minimum_distance<0.0 else minf(stats.minimum_distance,distance)
				remaining -= wish.length()
				if accepted.distance_to(wish)>0.0001: break
	stats.substeps = steps
	for key: int in recovery: stats.recovery_actor_max = maxf(stats.recovery_actor_max,allowance-float(recovery[key]))
	return stats


static func _skip_occupied_waypoints(actor: FieldActor, bodies: Array[FieldActor], navigation: FieldNavigation) -> void:
	# A grid point inside another foot disc is unreachable, even when the goal
	# beyond it is clear. Advance only co-directed intermediate segments; keep
	# deliberate passing-pocket turns and every static-obstacle constraint.
	for part: int in range(MAX_PATH_PARTS):
		var index: int = actor._path_index
		if actor.activity!=FieldActor.Activity.MOVING or index<=0 or index+1>=actor.path.size(): return
		var point: Vector2 = actor.path[index]
		if (point-actor.path[index-1]).normalized().dot((actor.path[index+1]-point).normalized())<PASS_DOT: return
		if not navigation._segment_is_clear(actor.position,actor.path[index+1]): return
		var occupied: bool = false
		for other: FieldActor in bodies:
			if other!=actor and other.position.distance_squared_to(point)<DISTANCE*DISTANCE: occupied = true
		if not occupied: return
		actor._path_index += 1


static func _steer(actor: FieldActor, wish: Vector2, bodies: Array[FieldActor], navigation: FieldNavigation) -> Vector2:
	var result: Vector2 = Vector2.ZERO
	var score: float = 0.0
	var direction: Vector2 = wish.normalized()
	for angle: float in ANGLES:
		var candidate: Vector2 = _limited(actor,wish.rotated(angle),bodies,navigation)
		var value: float = candidate.dot(direction) + candidate.length() * 0.15
		if value > score + 0.00001:
			result = candidate
			score = value
		if angle == 0.0 and candidate.distance_to(wish) < 0.0001: break
	return result


static func _limited(actor: FieldActor, offset: Vector2, bodies: Array[FieldActor], navigation: FieldNavigation, recovering: bool = false) -> Vector2:
	var fraction: float = 1.0
	if not navigation._segment_is_clear(actor.position,actor.position+offset):
		var low: float = 0.0
		var high: float = 1.0
		for iteration: int in range(8):
			var middle: float = (low+high)*0.5
			if navigation._segment_is_clear(actor.position,actor.position+offset*middle): low = middle
			else: high = middle
		fraction = low
	for other: FieldActor in bodies:
		if other == actor: continue
		# Bounded position projections must propagate through an already bad pile;
		# sweeping them against the pile's outer shell would lock its inner bodies.
		# Normal path motion always uses the full sweep, including during recovery.
		if recovering: continue
		fraction = minf(fraction,_sweep(actor.position-other.position,offset))
	return offset * fraction


static func _sweep(relative: Vector2, motion: Vector2) -> float:
	var squared: float = motion.length_squared()
	if squared < 0.00000001: return 1.0
	var distance: float = relative.length_squared() - DISTANCE * DISTANCE
	var closing: float = relative.dot(motion)
	if distance < -0.001:
		# Existing bad initial overlap may only move outwards; never deepen it.
		return 0.0 if closing < -0.00001 else 1.0
	if closing >= 0.0: return 1.0
	var discriminant: float = closing * closing - squared * maxf(distance,0.0)
	if discriminant <= 0.0: return 1.0
	return clampf((-closing-sqrt(discriminant))/squared-0.0001,0.0,1.0)


static func _recover(bodies: Array[FieldActor], navigation: FieldNavigation, budgets: Dictionary, stats: Dictionary) -> void:
	for iteration: int in range(RECOVERY_PASSES):
		var changed: bool = false
		for a: int in range(bodies.size()):
			for b: int in range(a+1,bodies.size()):
				var first: FieldActor = bodies[a]
				var second: FieldActor = bodies[b]
				var offset: Vector2 = first.position-second.position
				var missing: float = DISTANCE-offset.length()
				if missing <= 0.001: continue
				var normal: Vector2 = offset.normalized() if offset.length_squared()>0.000001 else Vector2.RIGHT.rotated(float((identity(first)*31+identity(second)*17)%16)*TAU/16.0)
				for entry: Array in [[first,normal],[second,-normal]]:
					var actor: FieldActor = entry[0]
					var key: int = identity(actor)
					var amount: float = minf(missing*0.5,minf(2.0,float(budgets[key])))
					if amount <= 0.00001: continue
					var correction: Vector2 = _recovery_offset(actor,Vector2(entry[1]),amount,bodies,navigation)
					actor.position += correction
					budgets[key] = maxf(0.0,float(budgets[key])-correction.length())
					stats.recovery_max = maxf(stats.recovery_max,correction.length())
					changed = changed or correction.length_squared()>0.00000001
		if not changed: break


static func _recovery_offset(actor: FieldActor, normal: Vector2, amount: float, bodies: Array[FieldActor], navigation: FieldNavigation) -> Vector2:
	var best: Vector2 = _limited(actor,normal*amount,bodies,navigation,true)
	if best.length() >= amount*0.5: return best
	# At a map corner both opposite diagonal projections can be blocked.
	# Try bounded tangents in a fixed order, always outside the inward half-plane.
	for angle: float in [-PI/4.0,PI/4.0,-PI/2.0,PI/2.0]:
		var candidate: Vector2 = _limited(actor,normal.rotated(angle)*amount,bodies,navigation,true)
		if candidate.length_squared()>best.length_squared()+0.000001: best = candidate
	return best


static func _yield_ally(mover: FieldActor, wish: Vector2, bodies: Array[FieldActor], navigation: FieldNavigation, limit: float, allow_plan: bool) -> void:
	for actor: FieldActor in bodies:
		if actor == mover or actor.is_enemy or actor.position.distance_to(mover.position)>DISTANCE+STEP_DISTANCE: continue
		if allow_plan and actor.activity == FieldActor.Activity.MOVING and identity(mover)<identity(actor):
			var heading: Vector2 = actor.path[mini(actor._path_index,actor.path.size()-1)]-actor.position if not actor.path.is_empty() else Vector2.ZERO
			if heading.normalized().dot(wish.normalized()) < -0.5 and _passing_paths(mover,actor,wish.normalized(),navigation): return
		if actor.activity != FieldActor.Activity.IDLE: continue
		var direction: Vector2 = wish.normalized().orthogonal()
		for side: float in [-1.0,1.0]:
			var offset: Vector2 = _limited(actor,direction*side*limit,bodies,navigation)
			if offset.length() >= limit * 0.5:
				actor.position += offset
				break


static func _passing_paths(first: FieldActor, second: FieldActor, direction: Vector2, navigation: FieldNavigation) -> bool:
	var side: Vector2 = direction.orthogonal()
	if navigation._segment_is_clear(first.position,first.position+side*DISTANCE) or navigation._segment_is_clear(first.position,first.position-side*DISTANCE): return false
	var first_goal: Vector2 = first.path[-1]
	var second_goal: Vector2 = second.path[-1]
	# At most six candidate pockets. The cooperative detour is ordinary saved
	# path intent, not a hidden yield flag/timer that would disappear on restore.
	for distance: float in [48.0,80.0,112.0,144.0,176.0,208.0]:
		var pocket: Vector2 = second.position+direction*distance
		if not navigation.is_clear(pocket) or not navigation._segment_is_clear(pocket-side*DISTANCE,pocket+side*DISTANCE): continue
		var first_path: PackedVector2Array = _via(navigation,first.position,pocket-side*30.0,first_goal)
		var second_path: PackedVector2Array = _via(navigation,second.position,pocket,second_goal)
		if first_path.is_empty() or second_path.is_empty(): continue
		first.command_path(first_path)
		second.command_path(second_path)
		return true
	return false


static func _via(navigation: FieldNavigation, start: Vector2, pocket: Vector2, goal: Vector2) -> PackedVector2Array:
	if not navigation.is_clear(pocket): return PackedVector2Array()
	var route: PackedVector2Array = navigation.path_between(start,pocket)
	var back: PackedVector2Array = navigation.path_between(pocket,goal)
	if route.is_empty() or back.is_empty() or not navigation._segment_is_clear(route[-1],pocket): return PackedVector2Array()
	route.append(pocket)
	route.append_array(back)
	if navigation._segment_is_clear(route[-1],goal): route.append(goal)
	return route if route.size()<=512 else PackedVector2Array()
