class_name IndustrialYard
extends RefCounted
## PROJECT_TEMP geometry for a loading apron and a narrow maintenance passage.

const WIDTH: float = 704.0
const NORTH_SPAN: float = 468.0
const FRONT_SETBACK: float = 48.0
const APRON: float = 36.0
const WALL: float = 16.0
const LOADING_X: float = 464.0
const SERVICE_X: float = 68.0
const LOADING_HALF_GAP: float = 78.0
const SERVICE_HALF_GAP: float = 44.0


static func plan(parcels: Array, roads: Array, bus: Dictionary, seed: String) -> Dictionary:
	var random: RandomNumberGenerator = RogueLayout.rng("industrial-yard:" + seed)
	var bus_point: Vector2 = WorldLayout.point(bus.door)
	var best_score: float = -INF
	var best: Dictionary = {}
	for parcel: Dictionary in parcels:
		if not parcel.road_edges[1] or parcel.dead_end:
			continue
		var plot: Rect2 = WorldLayout.rect(parcel.rect)
		if plot.size.x < WIDTH + 64.0 or plot.size.y < NORTH_SPAN + FRONT_SETBACK + 24.0:
			continue
		var left: float = plot.get_center().x - WIDTH * 0.5
		var front: float = plot.end.y - FRONT_SETBACK
		var bounds: Rect2 = Rect2(left, front - NORTH_SPAN, WIDTH, NORTH_SPAN + APRON)
		var loading_street: Vector2 = Vector2(left + LOADING_X, plot.end.y + 2.0)
		var service_street: Vector2 = Vector2(left + SERVICE_X, plot.end.y + 2.0)
		var front_road: bool = false
		var overlap: bool = false
		for value: Array in roads:
			var road: Rect2 = WorldLayout.rect(value)
			if road.size.x > road.size.y and road.has_point(service_street) and road.has_point(loading_street):
				front_road = true
			overlap = overlap or road.intersects(bounds)
		if not front_road or overlap or OpenStreetsV1.intersects_sweep(bus, bounds):
			continue
		# Prefer useful destinations, while seeded parcel topology and tie variation choose the yard.
		var distance: float = bus_point.distance_to(bounds.get_center())
		var score: float = (-absf(distance - 2300.0) if bus.has("stop") else distance) + random.randf_range(0.0, 128.0)
		if score > best_score:
			best_score = score
			best = _plan_parcel(parcel.id, bounds, front)
	return best


static func _plan_parcel(parcel: String, bounds: Rect2, front: float) -> Dictionary:
	var left: float = bounds.position.x
	var right: float = bounds.end.x
	var north: float = bounds.position.y
	var service: Vector2 = Vector2(left + SERVICE_X, front)
	var loading: Vector2 = Vector2(left + LOADING_X, front)
	var work: Vector2 = loading + Vector2(0.0, -164.0)
	var inside_y: float = front - 56.0
	var corner_y: float = front - 206.0
	var gate_y: float = front - WALL * 0.5
	var loading_paving: Array = [_box(Rect2(loading.x - 60.0, work.y - 30.0, 120.0, bounds.end.y - work.y + 30.0))]
	var service_paving: Array = [
		_box(Rect2(service.x - 28.0, corner_y - 28.0, 56.0, bounds.end.y - corner_y + 28.0)),
		_box(Rect2(service.x, corner_y - 28.0, work.x - service.x + 28.0, 56.0)),
		_box(Rect2(work.x - 28.0, corner_y, 56.0, work.y - corner_y + 24.0)),
	]
	return {
		"frozen": {
			"version": 1,
			"parcel": parcel,
			"bounds": _box(bounds),
			"work_point": _point(work),
			"loading": {
				"gate": _point(loading),
				"path": [[loading.x, bounds.end.y - 8.0], _point(loading), [loading.x, inside_y], _point(work)],
				"paving": loading_paving,
			},
			"service": {
				"gate": _point(service),
				"path": [
					[service.x, bounds.end.y - 8.0], _point(service), [service.x, inside_y],
					[service.x, corner_y], [work.x, corner_y], _point(work),
				],
				"paving": service_paving,
			},
		},
		"warehouse_foot": Vector2(left + 156.0, front - 260.0),
		"garage_foot": Vector2(left + 148.0, front - 80.0),
		"cargo_area": Rect2(left + 528.0, front - 160.0, 148.0, 124.0),
		"cargo_entry": Vector2(left + 552.0, front - 40.0),
		"barriers": [
			_box(Rect2(left, north, WIDTH, WALL)),
			_box(Rect2(left, north + WALL, WALL, front - north - WALL)),
			_box(Rect2(right - WALL, north + WALL, WALL, front - north - WALL)),
			_box(Rect2(left, gate_y, service.x - SERVICE_HALF_GAP - left, WALL)),
			_box(Rect2(service.x + SERVICE_HALF_GAP, gate_y, loading.x - LOADING_HALF_GAP - service.x - SERVICE_HALF_GAP, WALL)),
			_box(Rect2(loading.x + LOADING_HALF_GAP, gate_y, right - loading.x - LOADING_HALF_GAP, WALL)),
			# The divider makes the maintenance entry turn around the actual garage corner.
			_box(Rect2(left + 116.0, front - 176.0, WALL, 176.0)),
		],
	}


static func reserved_rects(data: Dictionary) -> Array[Rect2]:
	var yard: Dictionary = data.get("loading_yard", {})
	var result: Array[Rect2] = []
	if yard.is_empty():
		return result
	for name: String in ["loading", "service"]:
		for paving: Array in yard[name].paving:
			result.append(WorldLayout.rect(paving))
	var work: Vector2 = WorldLayout.point(yard.work_point)
	result.append(Rect2(work - Vector2(36.0, 36.0), Vector2(72.0, 72.0)))
	return result


static func certified(data: Dictionary, nav: FieldNavigation) -> bool:
	var yard: Dictionary = data.get("loading_yard", {})
	if yard.is_empty():
		return true
	var work: Vector2 = WorldLayout.point(yard.work_point)
	var bus: Vector2 = WorldLayout.point(data.bus.door)
	var loading: Vector2 = WorldLayout.point(yard.loading.gate)
	var service: Vector2 = WorldLayout.point(yard.service.gate)
	if not nav._segment_is_clear(loading, work) or nav._segment_is_clear(service, work):
		return false
	for name: String in ["loading", "service"]:
		var route: Array = yard[name].path
		if route.size() < 4 or route[1] != yard[name].gate or route.back() != yard.work_point:
			return false
		for index: int in range(1, route.size()):
			if not nav._segment_is_clear(WorldLayout.point(route[index - 1]), WorldLayout.point(route[index])):
				return false
		if not _reachable(nav, bus, WorldLayout.point(route[0])) or not _reachable(nav, bus, WorldLayout.point(route[1])):
			return false
	# A normal search order from the inside landing must use the bend, not walk
	# back outside to the other entrance despite the authored lane being clear.
	var service_path: PackedVector2Array = nav.path_between(WorldLayout.point(yard.service.path[2]), work)
	if service_path.is_empty() or service_path[-1].distance_to(work) > FieldNavigation.CELL * 0.71:
		return false
	for point: Vector2 in service_path:
		if point.y >= service.y:
			return false
	return _reachable(nav, work, bus)


static func _reachable(nav: FieldNavigation, start: Vector2, target: Vector2) -> bool:
	var path: PackedVector2Array = nav.path_between(start, target)
	var cell_diagonal: float = FieldNavigation.CELL * 0.71
	return not path.is_empty() and path[0].distance_to(start) <= cell_diagonal \
		and path[-1].distance_to(target) <= cell_diagonal


static func _box(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


static func _point(point: Vector2) -> Array:
	return [point.x, point.y]
