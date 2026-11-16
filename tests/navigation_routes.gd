extends SceneTree
## Exact output regression against c65fa3a's unmodified navigation implementation.

const Oracle = preload("res://tests/support/navigation_oracle.gd")
var checks: int = 0
var failures: int = 0
var compared: int = 0


func _initialize() -> void:
	_exhaustive()
	_seeded_grids()
	_boundaries()
	_authored()
	_generated()
	print("BH_NAV_ROUTES ", JSON.stringify({"checks":checks, "failures":failures, "paths":compared}))
	quit(0 if failures == 0 else 1)


func _expect(valid: bool, label: String) -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("BH_NAV_ROUTES_FAIL ", label)


func _compare(grid: AStarGrid2D, search: FieldRouteSearch, from: Vector2i, to: Vector2i) -> void:
	compared += 1
	var expected: PackedVector2Array = grid.get_point_path(from, to)
	var actual: PackedVector2Array = search.path(grid, from, to)
	_expect(actual == expected, "raw JPS complete sequence %s -> %s" % [from, to])
	_expect(ExplorationLayout._length(actual) == ExplorationLayout._length(expected), "exact accumulated segment lengths")


func _search_for(grid: AStarGrid2D) -> FieldRouteSearch:
	var solids: Array[Rect2i] = []
	for y: int in range(grid.region.size.y):
		for x: int in range(grid.region.size.x):
			if grid.is_point_solid(Vector2i(x, y)):
				solids.append(Rect2i(x, y, 1, 1))
	var search: FieldRouteSearch = FieldRouteSearch.new()
	search.configure(grid.region.size, solids)
	return search


func _exhaustive() -> void:
	var nav: FieldNavigation = FieldNavigation.new()
	nav.configure([Rect2(64, 64, 80, 80), Rect2(160, 0, 32, 96), Rect2(160, 144, 32, 100)], Rect2(0, 0, 320, 240))
	nav._grid.jumping_enabled = true
	var search: FieldRouteSearch = _search_for(nav._grid)
	# Every pair includes same-cell, solid, disconnected, equal-cost and corner cases.
	for ay: int in range(1, 14):
		for ax: int in range(1, 19):
			for by: int in range(1, 14):
				for bx: int in range(1, 19):
					_compare(nav._grid, search, Vector2i(ax, ay), Vector2i(bx, by))


func _seeded_grids() -> void:
	for seed_value: int in [83, 20261116, 7321, 9205]:
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = seed_value
		var grid: AStarGrid2D = AStarGrid2D.new()
		grid.region = Rect2i(0, 0, 31, 23)
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.jumping_enabled = true
		grid.update()
		for y: int in range(23):
			for x: int in range(31):
				grid.set_point_solid(Vector2i(x, y), random.randf() < 0.25)
		var search: FieldRouteSearch = _search_for(grid)
		for index: int in range(600):
			_compare(grid, search, Vector2i(random.randi_range(0, 30), random.randi_range(0, 22)),
				Vector2i(random.randi_range(0, 30), random.randi_range(0, 22)))
		grid.fill_solid_region(grid.region)
		search = _search_for(grid)
		_compare(grid, search, Vector2i.ZERO, Vector2i(30, 22))


func _boundaries() -> void:
	var blockers: Array[Rect2] = [Rect2(40, 40, 32, 64), Rect2(56, 56, 80, 32),
		Rect2(-100, -100, 48, 48), Rect2(12290, 0, 32, 48), Rect2(168, 104, 0, 0),
		Rect2(208.25, 80.5, 15.5, 31.25), Rect2(6000, -100, 32, 1400)]
	var limits: Rect2 = Rect2(-37.5, 19.25, 12295, 265)
	var nav: FieldNavigation = FieldNavigation.new()
	var oracle: Oracle = Oracle.new()
	nav.configure(blockers, limits)
	oracle.configure(blockers, limits)
	var search: FieldRouteSearch = FieldRouteSearch.new()
	search.configure(nav._grid.region.size, nav._route_solids())
	var mask_equal: bool = true
	for y: int in range(nav._grid.region.size.y):
		for x: int in range(nav._grid.region.size.x):
			var id: Vector2i = Vector2i(x, y)
			var actual: bool = not search.path(nav._grid, id, id).is_empty()
			mask_equal = mask_equal and actual == not nav._grid.is_point_solid(id)
	_expect(mask_equal, "indexed mask equals every native cell at offset, fractional and half-open boundaries")
	var endpoints: Array[Vector2] = [limits.position - Vector2(100, 100), limits.position,
		limits.end, Vector2(16, 16), Vector2(200, 200), Vector2(9000, 200), Vector2(64, 64)]
	for a: Vector2 in endpoints:
		for b: Vector2 in endpoints:
			_expect(nav.path_between(a, b) == oracle.path_between(a, b), "nearest-cell ties, real-start adjustment and unreachable divider")
	var copy: FieldNavigation = nav.copy_navigation()
	var before: PackedVector2Array = copy.path_between(Vector2(100, 200), Vector2(400, 200))
	copy.set_private_blocker(nav, Rect2(260, 100, 32, 100))
	var changed: Oracle = Oracle.new()
	var extra: Array[Rect2] = blockers.duplicate()
	extra.append(Rect2(260, 100, 32, 100))
	changed.configure(extra, limits)
	_expect(copy.path_between(Vector2(100, 200), Vector2(400, 200)) == changed.path_between(Vector2(100, 200), Vector2(400, 200)), "private overlay rebuilds successor fields")
	copy.set_private_blocker(nav, Rect2())
	_expect(copy.path_between(Vector2(100, 200), Vector2(400, 200)) == before, "removing overlay restores the exact original sequence")


func _authored() -> void:
	var generated: Dictionary = {"sites":[], "layout":{"id":"route-oracle", "size":"small"}}
	for street: StreetLayout in [SeasideTown.layout(generated), HarborWarehouse.layout(generated), CapeStation.layout(generated)]:
		var endpoints: Array[Vector2] = [street.bus_door]
		endpoints.append_array(street.arrivals)
		endpoints.append_array(street.enemy_points)
		for entity: Dictionary in street.world_data.entities:
			endpoints.append(WorldLayout.point(entity.door))
		endpoints.append(street.rescue_point)
		_street(street, endpoints)


func _generated() -> void:
	# Include original full fallback plus three different open-street seeds/themes.
	for fixture: Array in [["m15-explicit-fallback", "medium", "commercial", true, 0],
		["astar-commercial", "large", "commercial", false, OpenStreetsV1.VERSION],
		["astar-residential", "large", "residential", false, OpenStreetsV1.VERSION],
		["astar-industrial", "large", "industrial", true, OpenStreetsV1.VERSION]]:
		var data: Dictionary = WorldgenLayout._assemble(fixture[0], fixture[1], fixture[2], 0, fixture[3], "supply", false, false, fixture[4])
		_expect(not data.is_empty(), "generated/fallback fixture exists " + fixture[0])
		if data.is_empty():
			continue
		var street: StreetLayout = NeighborhoodLayout.resource(data)
		var endpoints: Array[Vector2] = [street.bus_door]
		for entity: Dictionary in data.entities:
			endpoints.append(WorldLayout.point(entity.door))
		for point: Array in data.arrivals + [data.rescue]:
			endpoints.append(WorldLayout.point(point))
		for object: Dictionary in data.objects:
			endpoints.append(WorldLayout.point(object.work_point))
		_street(street, endpoints)


func _street(street: StreetLayout, endpoints: Array[Vector2]) -> void:
	var nav: FieldNavigation = FieldNavigation.new()
	var oracle: Oracle = Oracle.new()
	nav.configure(street.blockers(), street.world_bounds)
	oracle.configure(street.blockers(), street.world_bounds)
	for index: int in range(endpoints.size()):
		for pair: Array in [[endpoints[0], endpoints[index]], [endpoints[index], endpoints[0]],
			[endpoints[index], endpoints[(index + 1) % endpoints.size()]]]:
			compared += 1
			var actual: PackedVector2Array = nav.path_between(pair[0], pair[1])
			var expected: PackedVector2Array = oracle.path_between(pair[0], pair[1])
			_expect(actual == expected, "complete route in " + String(street.id))
			_expect(ExplorationLayout._length(actual) == ExplorationLayout._length(expected), "exact distance in " + String(street.id))
