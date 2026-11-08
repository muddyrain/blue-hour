extends SceneTree
## Fixed map contracts exercised against production navigation and shot geometry.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	var frozen: Dictionary = PumpStationLayout.freeze()
	var map: StreetLayout = PumpStationLayout.resource(frozen)
	_expect(map != null and PumpStationLayout.problem(frozen).is_empty(), "canonical fixed layout builds a StreetLayout")
	var forged: Dictionary = frozen.duplicate(true)
	forged.barriers.pop_back()
	_expect(not PumpStationLayout.problem(forged).is_empty(), "moving a cover wall invalidates the frozen layout")
	_expect(not PumpStationAction.stopped({"cash":true}) and not PumpStationAction.stopped([]),
		"malformed stop facts cannot arm the encounter")
	var forged_action: Dictionary = {"version":9,"finale_policy":1,"seed":"0".repeat(32),
		"day":5,"slot":0,"campaign":{"run_id":"invalid","preparations":4}}
	_expect(PumpStationAction.problem(forged_action) == "PUMP_ACTION_CONTEXT",
		"malformed run identity is rejected before rebuilding the action")
	if map != null:
		_verify_routes(frozen.pump_station, map)
	print("PUMP_STATION_LAYOUT " + JSON.stringify({"checks": _checks, "failures": _failures}))
	quit(0 if _failures == 0 else 1)


func _verify_routes(station: Dictionary, map: StreetLayout) -> void:
	var nav: FieldNavigation = FieldNavigation.new()
	nav.configure(map.blockers(), map.world_bounds)
	var console: Vector2 = WorldLayout.point(station.console)
	var boss: Vector2 = WorldLayout.point(station.boss)
	var front: Vector2 = WorldLayout.point(station.front_gate)
	var side: Vector2 = WorldLayout.point(station.side_gate)
	_expect(nav.is_clear(console) and nav.is_clear(boss), "console foot and boss spawn clear their actual blockers")
	_expect(not nav.is_clear(WorldLayout.rect(station.channel).get_center()), "the visible water is not walkable")
	_expect(_reaches(nav, console, map.bus_door), "console stays connected to the actual bus gathering point")
	var lengths: Dictionary[String, float] = {}
	for key: String in ["front_path", "side_path"]:
		var guide: Array = station[key]
		var distance: float = 0.0
		_expect(_reaches(nav, map.bus_door, WorldLayout.point(guide[0])), "%s landing reachable from bus" % key)
		for index: int in range(1, guide.size()):
			var start: Vector2 = WorldLayout.point(guide[index - 1])
			var end: Vector2 = WorldLayout.point(guide[index])
			_expect(nav._segment_is_clear(start, end), "%s marked section %d is genuinely clear" % [key, index])
			distance += start.distance_to(end)
		lengths[key] = distance
	_expect(lengths.side_path > lengths.front_path, "service lane is longer")
	_expect(_reaches(nav, front + Vector2.UP * 46.0, console), "a normal console order works from loading lane")
	var around: PackedVector2Array = nav.path_between(side + Vector2.UP * 46.0, console)
	_expect(_reaches(nav, side + Vector2.UP * 46.0, console), "a normal console order works from service lane")
	_expect(around.size() > 1 and Array(around).all(func(foot: Vector2) -> bool: return foot.y < side.y),
		"normal service approach rounds the L without returning to the street")
	_expect(_sight(front, boss, map.shot_obstacles()).targetable, "loading entry sees the boss")
	var side_sight: AttackRules.Decision = _sight(side, boss, map.shot_obstacles())
	_expect(side_sight.reason == &"blocked" and side_sight.blocker_id.begins_with("yard_wall_"),
		"actual cover wall blocks the service entry's shot")


func _reaches(nav: FieldNavigation, from: Vector2, to: Vector2) -> bool:
	var path: PackedVector2Array = nav.path_between(from, to)
	return not path.is_empty() and path[-1].distance_to(to) <= FieldNavigation.CELL * 0.71


func _sight(from: Vector2, to: Vector2, walls: Array[ShotObstacle]) -> AttackRules.Decision:
	return AttackRules.evaluate(AttackRules.Combatant.new(from, true, true, false),
		AttackRules.Combatant.new(to, true, true, true), from + Vector2.UP * AttackRules.HIT_HEIGHT, 600.0, 0.0, walls)


func _expect(passed: bool, label: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("PUMP_STATION_LAYOUT_FAIL " + label)
