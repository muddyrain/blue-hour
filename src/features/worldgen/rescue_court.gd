class_name RescueCourt
extends RefCounted
## PROJECT_TEMP geometry shared by the real rescue doorway, two gates and their art.

const WIDTH: float = 704.0
const DEPTH: float = 464.0
const SETBACK: float = 48.0
const APRON: float = 36.0
const WALL: float = 16.0
const SIDE_X: float = 68.0
const FRONT_X: float = 552.0
const SIDE_HALF: float = 44.0
const FRONT_HALF: float = 78.0


static func plan(parcels: Array, roads: Array, bus: Dictionary, seed: String, world_width: float) -> Dictionary:
	var random: RandomNumberGenerator = RogueLayout.rng("rescue-court:" + seed)
	var bus_point: Vector2 = WorldLayout.point(bus.door)
	var preferred_distance: float = clampf(world_width * 0.38, 970.0, 1500.0)
	var best_score: float = -INF
	var best: Dictionary = {}
	for parcel: Dictionary in parcels:
		if not parcel.road_edges[1] or parcel.dead_end:
			continue
		var plot: Rect2 = WorldLayout.rect(parcel.rect)
		if plot.size.x < WIDTH + 64.0 or plot.size.y < DEPTH + SETBACK + 24.0:
			continue
		var left: float = plot.get_center().x - WIDTH * 0.5
		var front: float = plot.end.y - SETBACK
		var bounds: Rect2 = Rect2(left, front - DEPTH, WIDTH, DEPTH + APRON)
		var side_street: Vector2 = Vector2(left + SIDE_X, plot.end.y + 2.0)
		var front_street: Vector2 = Vector2(left + FRONT_X, plot.end.y + 2.0)
		var connected: bool = false
		var overlap: bool = false
		for row: Array in roads:
			var road: Rect2 = WorldLayout.rect(row)
			if road.size.x > road.size.y and road.has_point(side_street) and road.has_point(front_street):
				connected = true
			overlap = overlap or road.intersects(bounds)
		if not connected or overlap or bounds.intersects(WorldLayout.rect(bus.sweep)):
			continue
		var distance: float = bus_point.distance_to(Vector2(left + 460.0, front - 192.0))
		var score: float = -absf(distance - preferred_distance) + random.randf_range(0.0, 80.0)
		if score > best_score:
			best_score = score
			best = _parcel(parcel.id, bounds, front)
	return best


static func _parcel(parcel: String, bounds: Rect2, y: float) -> Dictionary:
	var left: float = bounds.position.x
	var north: float = bounds.position.y
	var side: Vector2 = Vector2(left + SIDE_X, y)
	var front: Vector2 = Vector2(left + FRONT_X, y)
	var gate_y: float = y - WALL * 0.5
	return {
		"frozen": {"version":1, "parcel":parcel, "bounds":_box(bounds)},
		"side":side,
		"front":front,
		"home":Vector2(left + 310.0, y - 240.0),
		"annex":Vector2(left + 146.0, y - 86.0),
		"barriers":[
			_box(Rect2(left, north, WIDTH, WALL)),
			_box(Rect2(left, north + WALL, WALL, DEPTH - WALL)),
			_box(Rect2(bounds.end.x - WALL, north + WALL, WALL, DEPTH - WALL)),
			_box(Rect2(left, gate_y, SIDE_X - SIDE_HALF, WALL)),
			_box(Rect2(side.x + SIDE_HALF, gate_y, front.x - FRONT_HALF - side.x - SIDE_HALF, WALL)),
			_box(Rect2(front.x + FRONT_HALF, gate_y, bounds.end.x - front.x - FRONT_HALF, WALL)),
			# The side approach passes this actual wall corner before turning right.
			_box(Rect2(left + 116.0, y - 174.0, WALL, 174.0)),
		],
	}


static func finish(court: Dictionary, plan_data: Dictionary, target: Vector2) -> void:
	var bounds: Rect2 = WorldLayout.rect(court.bounds)
	var side: Vector2 = plan_data.side
	var front: Vector2 = plan_data.front
	var turn_y: float = front.y - 210.0
	court.target = _point(target)
	court.front = {
		"gate":_point(front),
		"path":[[front.x, bounds.end.y - 8.0], _point(front), [front.x, front.y - 56.0], _point(target)],
		"paving":[_box(Rect2(target.x - 28.0, target.y - 18.0, front.x - target.x + 91.0, bounds.end.y - target.y + 18.0))],
	}
	court.side = {
		"gate":_point(side),
		"path":[[side.x, bounds.end.y - 8.0], _point(side), [side.x, side.y - 56.0],
			[side.x, turn_y], [target.x, turn_y], _point(target)],
		"paving":[
			_box(Rect2(side.x - 28.0, turn_y - 26.0, 56.0, bounds.end.y - turn_y + 26.0)),
			_box(Rect2(side.x, turn_y - 26.0, target.x - side.x + 28.0, 52.0)),
		],
	}


static func certified(data: Dictionary, nav: FieldNavigation, obstacles: Array[ShotObstacle]) -> bool:
	var court: Dictionary = data.rescue_court
	var target: Vector2 = WorldLayout.point(data.rescue)
	var bus: Vector2 = WorldLayout.point(data.bus.door)
	var front: Vector2 = WorldLayout.point(court.front.gate)
	var side: Vector2 = WorldLayout.point(court.side.gate)
	if not _sees(front, target, obstacles) or _sees(side, target, obstacles):
		return false
	for approach: Dictionary in [court.front, court.side]:
		var route: Array = approach.path
		for index: int in range(1, route.size()):
			if not nav._segment_is_clear(WorldLayout.point(route[index - 1]), WorldLayout.point(route[index])):
				return false
		if not _reaches(nav, bus, WorldLayout.point(route[2])):
			return false
	# RescueTarget sends its worker just left of the NPC, rather than into their feet.
	var worker_point: Vector2 = target - Vector2(40.0, 0.0)
	var side_landing: Vector2 = WorldLayout.point(court.side.path[2])
	if not nav.is_clear(worker_point) or not _reaches(nav, WorldLayout.point(court.front.path[2]), worker_point):
		return false
	var side_to_home: PackedVector2Array = nav.path_between(side_landing, worker_point)
	if side_to_home.is_empty() or side_to_home[-1].distance_to(worker_point) > FieldNavigation.CELL * 0.71:
		return false
	for point: Vector2 in side_to_home:
		if point.y >= side.y:
			return false
	return _reaches(nav, target, bus)


static func _sees(origin: Vector2, target: Vector2, obstacles: Array[ShotObstacle]) -> bool:
	var attacker: AttackRules.Combatant = AttackRules.Combatant.new(origin, true, true, false)
	var receiver: AttackRules.Combatant = AttackRules.Combatant.new(target, true, true, true)
	return AttackRules.evaluate(attacker, receiver, origin + Vector2.UP * AttackRules.HIT_HEIGHT,
		WIDTH * 2.0, 0.0, obstacles).targetable


static func _reaches(nav: FieldNavigation, from: Vector2, to: Vector2) -> bool:
	var route: PackedVector2Array = nav.path_between(from, to)
	return not route.is_empty() and route[0].distance_to(from) <= FieldNavigation.CELL * 0.71 \
		and route[-1].distance_to(to) <= FieldNavigation.CELL * 0.71


static func _box(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


static func _point(point: Vector2) -> Array:
	return [point.x, point.y]
