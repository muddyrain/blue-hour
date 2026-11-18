extends SceneTree
## Cached certificate routes retain exact AStar output and follow every geometry change.

var checks: int = 0
var failures: int = 0

class CountingNavigation extends FieldNavigation:
	var clearance_queries: int = 0

	func is_clear(point: Vector2) -> bool:
		clearance_queries += 1
		return super.is_clear(point)


func _initialize() -> void:
	_grid_equivalence()
	var nav: FieldNavigation = FieldNavigation.new()
	var bounds: Rect2 = Rect2(0, 0, 320, 240)
	nav.configure([], bounds)
	var start: Vector2 = Vector2(40, 120)
	var goal: Vector2 = Vector2(280, 120)
	var original: PackedVector2Array = nav.path_between(start, goal)
	_expect(not original.is_empty() and nav.path_between(start, goal) == original, "repeated query retains exact route points")
	var exposed: PackedVector2Array = nav.path_between(start, goal)
	exposed[0] = Vector2(-999, -999)
	_expect(nav.path_between(start, goal) == original, "caller cannot mutate the cached path")
	var private_nav: FieldNavigation = nav.copy_navigation()
	var obstacle: Rect2 = Rect2(144, 72, 32, 96)
	private_nav.path_between(start, goal)
	private_nav.set_private_blocker(nav, obstacle)
	var detour: PackedVector2Array = private_nav.path_between(start, goal)
	var oracle: FieldNavigation = FieldNavigation.new()
	oracle.configure([obstacle], bounds)
	_expect(detour != original and detour == oracle.path_between(start, goal), "adding a private blocker invalidates the original route")
	_expect(nav.path_between(start, goal) == original, "private blocker leaves shared certificate routes untouched")
	private_nav.set_private_blocker(nav, Rect2())
	_expect(private_nav.path_between(start, goal) == original, "removing a private blocker invalidates its detour")
	nav.configure([Rect2(144, 0, 32, 240)], bounds)
	_expect(nav.path_between(start, goal).is_empty(), "reconfiguration cannot reuse a route through a solid divider")
	_expect(nav.path_between(start, goal).is_empty(), "empty route is also stable across repeated queries")
	nav.configure([], bounds)
	_expect(nav.path_between(start, goal) == original, "reopening geometry invalidates a cached unreachable result")
	print("BH_NAV_CACHE ", JSON.stringify({"checks":checks, "failures":failures}))
	quit(0 if failures == 0 else 1)


func _grid_equivalence() -> void:
	# Include half-open rectangle edges, overlapping/degenerate blockers and a
	# fractional last row/column that must remain clear when its center fits.
	var blocks: Array[Rect2] = [Rect2(40, 40, 32, 64), Rect2(56, 56, 80, 32),
		Rect2(-20, -20, 48, 48), Rect2(320, 0, 32, 48), Rect2(168, 104, 0, 0),
		Rect2(208.25, 80.5, 15.5, 31.25)]
	for limits: Rect2 in [Rect2(0, 0, 320, 240), Rect2(-37.5, 19.25, 327, 249), Rect2(16, 32, 48, 32)]:
		_compare_grid(blocks, limits)
	for layout: StreetLayout in [preload("res://src/features/expedition/repair_lane.tres"),
		preload("res://src/features/expedition/market_loop.tres")]:
		_compare_grid(layout.blockers(), layout.world_bounds)


func _compare_grid(blocks: Array[Rect2], limits: Rect2) -> void:
	var nav: CountingNavigation = CountingNavigation.new()
	nav.configure(blocks, limits)
	var size: Vector2i = nav._grid.region.size
	_expect(nav.clearance_queries <= 2 * (size.x + size.y),
		"grid construction avoids a whole-grid obstacle scan, independent of wallclock speed")
	var oracle: FieldNavigation = FieldNavigation.new()
	oracle.bounds = limits
	oracle.obstacles = blocks.duplicate()
	oracle._prepare_grid()
	var identical: bool = true
	# Original scalar construction is the oracle, not the new rectangle painter.
	for x: int in range(size.x):
		for y: int in range(size.y):
			var id: Vector2i = Vector2i(x, y)
			var solid: bool = not oracle.is_clear(oracle._grid.get_point_position(id))
			oracle._grid.set_point_solid(id, solid)
			identical = identical and nav._grid.is_point_solid(id) == solid
	_expect(identical, "every grid cell equals the original footprint predicate at " + str(limits))
	var start: Vector2 = limits.position + Vector2(24, 24)
	for end: Vector2 in [limits.end - Vector2(24, 24), limits.get_center(), limits.position + Vector2(8, 8)]:
		_expect(nav.path_between(start, end) == oracle.path_between(start, end),
			"complete AStar path and endpoint tie breaks equal the original solid mask")


func _expect(valid: bool, label: String) -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("BH_NAV_CACHE_FAIL ", label)
