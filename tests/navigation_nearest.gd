extends SceneTree
## Equivalence to pre-M5-02 exhaustive nearest-cell selection, including exact ties.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	var timings: Array[Dictionary] = []
	for layout: StreetLayout in [preload("res://src/features/expedition/repair_lane.tres"),preload("res://src/features/expedition/market_loop.tres")]:
		var nav: FieldNavigation = FieldNavigation.new()
		nav.configure(layout.blockers())
		var points: Array[Vector2] = [Vector2(-1,-1),Vector2(0,0),Vector2(16,16),Vector2(48,48),Vector2(1919,1439),Vector2(2000,2000)]
		points.append_array(layout.arrivals)
		points.append_array(layout.enemy_points)
		for block: Rect2 in layout.blockers():
			points.append_array([block.position,block.end,block.get_center(),block.position - Vector2.ONE * 20.0])
		for index: int in range(80):
			points.append(Vector2((index * 137) % 1920,(index * 311) % 1440))
		for point: Vector2 in points:
			_expect(nav._nearest_walkable(point) == _oracle(nav,point), "nearest-cell result equals old exhaustive selection at map edge, obstacle, tie or clear ground")
		var started: int = Time.get_ticks_usec()
		for index: int in range(24):
			nav.path_between(Vector2(912,80) + Vector2(0,index * 16),Vector2(1240,1200))
		timings.append({"map":String(layout.id),"24_paths_ms":float(Time.get_ticks_usec() - started) / 1000.0})
	print("BH_NAV_NEAREST checks=%d failures=%d timings=%s" % [_checks,_failures,JSON.stringify(timings)])
	quit(0 if _failures == 0 else 1)


func _oracle(nav: FieldNavigation, point: Vector2) -> Vector2i:
	var best: Vector2i = Vector2i.ZERO
	var distance: float = INF
	for x: int in range(nav._grid.region.size.x):
		for y: int in range(nav._grid.region.size.y):
			var id: Vector2i = Vector2i(x,y)
			if nav._grid.is_point_solid(id):
				continue
			var current: float = point.distance_squared_to(nav._grid.get_point_position(id))
			if current < distance:
				distance = current
				best = id
	return best


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("BH_NAV_NEAREST " + label)
