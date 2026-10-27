class_name FieldNavigation
extends RefCounted
## A conservative footprint grid keeps paths outside static obstacles.

const CELL: float = 16.0
const BOUNDS: Rect2 = StreetBlock.BOUNDS
const FOOT_RADIUS: float = 10.0

var obstacles: Array[Rect2] = []
var _grid: AStarGrid2D = AStarGrid2D.new()


func configure(blockers: Array[Rect2]) -> void:
	obstacles = blockers.duplicate()
	_grid.region = Rect2i(0, 0, int(BOUNDS.size.x / CELL), int(BOUNDS.size.y / CELL))
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.offset = BOUNDS.position + Vector2.ONE * CELL * 0.5
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()
	for x: int in range(_grid.region.size.x):
		for y: int in range(_grid.region.size.y):
			var id: Vector2i = Vector2i(x, y)
			var point: Vector2 = _grid.get_point_position(id)
			if not is_clear(point):
				_grid.set_point_solid(id, true)


func is_clear(point: Vector2) -> bool:
	if not BOUNDS.grow(-FOOT_RADIUS).has_point(point):
		return false
	for blocker: Rect2 in obstacles:
		if blocker.grow(FOOT_RADIUS + CELL * 0.5).has_point(point):
			return false
	return true


func path_between(start: Vector2, goal: Vector2) -> PackedVector2Array:
	var from_id: Vector2i = _nearest_walkable(start)
	var to_id: Vector2i = _nearest_walkable(goal)
	var points: PackedVector2Array = _grid.get_point_path(from_id, to_id)
	# Replanning must not first pull a moving actor backwards to its cell centre.
	# Keep the conservative grid entry when the real start cannot reach the next cell safely.
	if points.size() > 1 and start.distance_to(points[0]) <= CELL * 0.71:
		if _segment_is_clear(start, points[1]):
			points[0] = start
	return points


func _segment_is_clear(start: Vector2, end: Vector2) -> bool:
	var steps: int = maxi(1, ceili(start.distance_to(end) / 4.0))
	for index: int in range(steps + 1):
		if not is_clear(start.lerp(end, float(index) / steps)):
			return false
	return true


func _nearest_walkable(point: Vector2) -> Vector2i:
	# Normal replans already stand on clear ground. Preserve the old scan's lower-index
	# tie break while avoiding two full-grid scans for every active enemy path.
	var grid_point: Vector2 = (point - _grid.offset) / CELL - Vector2.ONE * 0.5
	var direct: Vector2i = Vector2i(ceili(grid_point.x),ceili(grid_point.y))
	direct = direct.clamp(_grid.region.position,_grid.region.end - Vector2i.ONE)
	if not _grid.is_point_solid(direct):
		return direct
	var closest: Vector2i = Vector2i.ZERO
	var distance: float = INF
	for x: int in range(_grid.region.size.x):
		for y: int in range(_grid.region.size.y):
			var id: Vector2i = Vector2i(x, y)
			if _grid.is_point_solid(id):
				continue
			var candidate: float = point.distance_squared_to(_grid.get_point_position(id))
			if candidate < distance:
				distance = candidate
				closest = id
	return closest
