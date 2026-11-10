class_name FieldNavigation
extends RefCounted
## A conservative footprint grid keeps paths outside static obstacles.

const CELL: float = 16.0
const BOUNDS: Rect2 = StreetBlock.BOUNDS
const FOOT_RADIUS: float = 10.0

var bounds: Rect2 = BOUNDS
var obstacles: Array[Rect2] = []
var _grid: AStarGrid2D = AStarGrid2D.new()


func configure(blockers: Array[Rect2], world_bounds: Rect2 = BOUNDS) -> void:
	bounds = world_bounds
	obstacles = blockers.duplicate()
	_prepare_grid()
	if _grid.jumping_enabled:
		# Paint each footprint once. The outer cell centers are 8 units from
		# the edge and fail the same 10-unit actor bounds test as legacy maps.
		for obstacle: Rect2 in obstacles:
			_paint_blocker(self, obstacle, true)
		var size: Vector2i = _grid.region.size
		for x: int in range(size.x):
			_grid.set_point_solid(Vector2i(x, 0), true)
			_grid.set_point_solid(Vector2i(x, size.y - 1), true)
		for y: int in range(size.y):
			_grid.set_point_solid(Vector2i(0, y), true)
			_grid.set_point_solid(Vector2i(size.x - 1, y), true)
		return
	for x: int in range(_grid.region.size.x):
		for y: int in range(_grid.region.size.y):
			var id: Vector2i = Vector2i(x, y)
			var point: Vector2 = _grid.get_point_position(id)
			if not is_clear(point):
				_grid.set_point_solid(id, true)


func _prepare_grid() -> void:
	_grid.region = Rect2i(0, 0, int(bounds.size.x / CELL), int(bounds.size.y / CELL))
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.offset = bounds.position + Vector2.ONE * CELL * 0.5
	_grid.jumping_enabled = bounds.size.x >= 12288.0
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()


func copy_navigation() -> FieldNavigation:
	# The cached base certificate is immutable. Copy its grid once, then modify
	# only the cells affected by the proposed overlay on the private copy.
	var copy: FieldNavigation = FieldNavigation.new()
	copy.bounds = bounds
	copy.obstacles = obstacles.duplicate()
	copy._prepare_grid()
	for y: int in range(_grid.region.size.y):
		for x: int in range(_grid.region.size.x):
			var id: Vector2i = Vector2i(x, y)
			if _grid.is_point_solid(id):
				copy._grid.set_point_solid(id, true)
	return copy


func set_private_blocker(base: FieldNavigation, blocker: Rect2) -> void:
	if obstacles.size() > base.obstacles.size():
		_paint_blocker(base, obstacles[-1], false)
		obstacles.pop_back()
	if blocker.has_area():
		obstacles.append(blocker)
		_paint_blocker(base, blocker, true)


func _paint_blocker(base: FieldNavigation, blocker: Rect2, solid: bool) -> void:
	var area: Rect2 = blocker.grow(FOOT_RADIUS + CELL * 0.5)
	var first: Vector2i = Vector2i(((area.position - _grid.offset) / CELL).floor()).max(Vector2i.ZERO)
	var end: Vector2i = Vector2i(((area.end - _grid.offset) / CELL).ceil()).min(_grid.region.end)
	for y: int in range(first.y, end.y):
		for x: int in range(first.x, end.x):
			var id: Vector2i = Vector2i(x, y)
			if area.has_point(_grid.get_point_position(id)):
				_grid.set_point_solid(id, solid or base._grid.is_point_solid(id))


func is_clear(point: Vector2) -> bool:
	if not bounds.grow(-FOOT_RADIUS).has_point(point):
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
	if _grid.jumping_enabled and start.distance_squared_to(end) > 96.0 * 96.0:
		return _long_segment_is_clear(start, end)
	var steps: int = maxi(1, ceili(start.distance_to(end) / 4.0))
	for index: int in range(steps + 1):
		if not is_clear(start.lerp(end, float(index) / steps)):
			return false
	return true


func _long_segment_is_clear(start: Vector2, end: Vector2) -> bool:
	var limits: Rect2 = bounds.grow(-FOOT_RADIUS)
	if not limits.has_point(start) or not limits.has_point(end):
		return false
	var span: Rect2 = Rect2(start.min(end), (end - start).abs()).grow(0.01)
	var movement: Vector2 = end - start
	for obstacle: Rect2 in obstacles:
		var block: Rect2 = obstacle.grow(FOOT_RADIUS + CELL * 0.5)
		if not span.intersects(block):
			continue
		var entry: float = 0.0
		var exit: float = 1.0
		for axis: int in range(2):
			if movement[axis] == 0.0:
				if start[axis] < block.position[axis] or start[axis] >= block.end[axis]:
					exit = -1.0
				continue
			var a: float = (block.position[axis] - start[axis]) / movement[axis]
			var b: float = (block.end[axis] - start[axis]) / movement[axis]
			entry = maxf(entry, minf(a, b))
			exit = minf(exit, maxf(a, b))
		if entry <= exit:
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
	if _grid.jumping_enabled:
		return _nearest_large_grid(point, direct)
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

func _nearest_large_grid(point: Vector2, direct: Vector2i) -> Vector2i:
	var closest: Vector2i = Vector2i.ZERO
	var distance: float = INF
	var displacement: Vector2 = (point - _grid.get_point_position(direct)).abs()
	var offset: float = maxf(displacement.x, displacement.y)
	var limit: int = maxi(_grid.region.size.x, _grid.region.size.y)
	for radius: int in range(1, limit):
		var low: Vector2i = (direct - Vector2i.ONE * radius).max(Vector2i.ZERO)
		var high: Vector2i = (direct + Vector2i.ONE * radius).min(_grid.region.end - Vector2i.ONE)
		for x: int in range(low.x, high.x + 1):
			var ys: Array = range(low.y, high.y + 1) if absi(x - direct.x) == radius else [direct.y - radius, direct.y + radius]
			for y: int in ys:
				var id: Vector2i = Vector2i(x, y)
				if not _grid.region.has_point(id) or _grid.is_point_solid(id):
					continue
				var candidate: float = point.distance_squared_to(_grid.get_point_position(id))
				if candidate < distance or (candidate == distance and (x < closest.x or (x == closest.x and y < closest.y))):
					distance = candidate
					closest = id
		# Every point beyond this ring is farther along at least one axis.
		var lower_bound: float = maxf(0.0, (radius + 1) * CELL - offset)
		if distance < lower_bound * lower_bound:
			return closest
	return closest
