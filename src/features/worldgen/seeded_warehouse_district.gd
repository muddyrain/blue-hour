class_name SeededWarehouseDistrict
extends RefCounted
## Local roads are cut before the city subdivides. Each family reserves its own task blocks.

const FAMILIES: Array[String] = ["street_axis", "loop_court", "offset_lanes"]


static func partition(leaves: Array, segments: Array, bus: Dictionary, seed: String, attempt: int,
		fallback: bool) -> Dictionary:
	var family: String = FAMILIES[RogueLayout.rng("warehouse-family:" + seed).randi_range(0, FAMILIES.size() - 1)]
	var form: RandomNumberGenerator = RogueLayout.rng("warehouse-blocks:" + seed + ":" + str(attempt))
	var stop_y: int = int(bus.stop[1])
	var south_y: int = stop_y + 352 + 32 * form.randi_range(0, 2)
	var north_y: int = stop_y - 448 - 32 * form.randi_range(0, 2)
	var west: Dictionary = _inner(leaves[0], true, 1216 + 32 * form.randi_range(0, 2), form, leaves, segments)
	var east: Dictionary = _inner(leaves[0], false, 1152 + 32 * form.randi_range(0, 2), form, leaves, segments)
	var first_local: int = segments.size()
	var west_halves: Array = _cut(west, false, south_y, form, leaves, segments)
	match family:
		"street_axis":
			var east_halves: Array = _cut(east, false, south_y, form, leaves, segments)
			east_halves[0].district_role = "main"
			west_halves[0].district_role = "support"
			east_halves[1].district_role = "service"
		"loop_court":
			var west_north: Array = _cut(west_halves[0], false, north_y, form, leaves, segments)
			west_north[1].district_role = "main"
			west_north[0].district_role = "support"
			west_halves[1].district_role = "service"
		"offset_lanes":
			var east_halves: Array = _cut(east, false, north_y, form, leaves, segments)
			west_halves[0].district_role = "main"
			east_halves[1].district_role = "support"
			west_halves[1].district_role = "service"
	return {"family":family, "plots":{}, "crossings":[north_y, south_y],
		"local_segments":[segments[2], segments[3]] + segments.slice(first_local),
		"canonical_roads":fallback}


static func _inner(quarter: Dictionary, west: bool, width: int, random: RandomNumberGenerator,
		leaves: Array, segments: Array) -> Dictionary:
	var offset: int = int(quarter.rect[2]) - width if west else width
	return _cut(quarter, true, offset, random, leaves, segments)[1 if west else 0]


static func _cut(plot: Dictionary, vertical: bool, offset: int, random: RandomNumberGenerator,
		leaves: Array, segments: Array) -> Array:
	leaves.erase(plot)
	WorldgenGeometry._split(plot, vertical, random, leaves, segments, offset)
	return leaves.slice(-2)


static func populate(parcels: Array, roads: Array, bus: Dictionary, seed: String, plan: Dictionary, task: String) -> Dictionary:
	var plots: Dictionary = plan.plots
	var main_plot: Dictionary = plots.main
	var main_area: Rect2 = WorldLayout.rect(main_plot.rect)
	var service_area: Rect2 = WorldLayout.rect(plots.service.rect)
	var start: Vector2 = WorldLayout.point(bus.door)
	var arterial: Rect2 = WorldLayout.rect(roads[1])
	var crossing: float = plan.crossings[1]
	var family: String = plan.family
	var foot: float = main_area.end.y - 168.0
	var x: float = main_area.position.x + (64.0 if family == "street_axis" else 144.0)
	if family == "offset_lanes":
		foot = start.y + 48.0
		x = main_area.end.x - 1056.0
	var entities: Array = []
	var main: Dictionary = WarehouseDistrict._module(main_plot, entities, WarehouseDistrict.HALL,
		x, foot, "warehouse" if task in ["equipment", "airdrop"] else "convenience_store", main_plot.id + "_task_hall")
	var door: Vector2 = WorldLayout.point(main.door)
	var spare: Dictionary
	var approaches: Dictionary = {}
	var east_walk: float = arterial.end.x + 38.0
	var west_walk: float = arterial.position.x - 38.0
	var court: Rect2 = Rect2(x + 12.0, foot + 70.0, 680.0, 80.0)
	match family:
		"street_axis":
			spare = WarehouseDistrict._module(main_plot, entities, WarehouseDistrict.OFFICE,
				x + 800.0, foot - 48.0, "convenience_store", main_plot.id + "_spares")
			approaches.direct = [Vector2(west_walk, crossing), Vector2(east_walk, crossing),
				Vector2(door.x, crossing), door]
		"loop_court":
			spare = WarehouseDistrict._module(main_plot, entities, WarehouseDistrict.OFFICE,
				x + 432.0, foot - 376.0, "convenience_store", main_plot.id + "_rear_stores")
			var rear: Vector2 = WorldLayout.point(spare.door)
			var outer_x: float = main_area.position.x - 32.0
			var north_y: float = plan.crossings[0]
			approaches.direct = [Vector2(west_walk, start.y), Vector2(west_walk, door.y), door]
			approaches.rear = [Vector2(west_walk, start.y), Vector2(west_walk, rear.y), rear]
			approaches.detour = [Vector2(west_walk, start.y), Vector2(west_walk, north_y),
				Vector2(outer_x, north_y), Vector2(outer_x, crossing),
				Vector2(door.x, crossing), door]
		"offset_lanes":
			WarehouseDistrict._module(main_plot, entities, WarehouseDistrict.OFFICE,
				main_area.end.x - 332.0, start.y + 162.0, "garage", main_plot.id + "_lane_office", true)
			var spare_plot: Dictionary = plots.service if service_area.size.y >= 288.0 else main_plot
			var spare_foot: float = service_area.position.y + 206.0 if spare_plot == plots.service else foot - 352.0
			spare = WarehouseDistrict._module(spare_plot, entities, WarehouseDistrict.OFFICE,
				door.x - 96.0, spare_foot, "convenience_store", spare_plot.id + "_spares")
			var turn_y: float = start.y + 208.0
			approaches.direct = [Vector2(west_walk, start.y), Vector2(west_walk, turn_y),
				Vector2(door.x, turn_y), door]
			court.position.x -= 24.0
			court.size.x = 520.0
	main_plot.kind = "loading"
	WarehouseDistrict._court(main_plot, court, "loading", door)
	var support: Dictionary = plots.support
	var support_area: Rect2 = WorldLayout.rect(support.rect)
	var support_x: float = support_area.end.x - 496.0 if support_area.end.x < arterial.get_center().x else support_area.position.x + 126.0
	var support_foot: float = clampf(start.y + 32.0, support_area.position.y + 264.0, support_area.end.y - 80.0)
	WarehouseDistrict._module(support, entities, WarehouseDistrict.SHED, support_x, support_foot,
		"garage", support.id + "_repair")
	var reserved: Array[Rect2] = OpenStreetsV1.swept_rects(bus, 32.0)
	reserved.append(OpenStreetsV1.boarding_paving(bus).grow(24.0))
	for road: Array in roads:
		reserved.append(WorldLayout.rect(road).grow(32.0))
	for route: Array in approaches.values():
		var from: Vector2 = start
		for point: Vector2 in route:
			var path: Rect2 = corridor(from, point)
			reserved.append(path)
			for plot: Dictionary in parcels:
				var paving: Rect2 = path.intersection(WorldLayout.rect(plot.rect))
				if paving.has_area():
					plot.walks.append(WarehouseDistrict._rect(paving))
			from = point
	for building: Dictionary in entities:
		reserved.append(WorldgenScale.visible_rect(building).grow_individual(32.0, 24.0, 32.0, 84.0))
	var random: RandomNumberGenerator = RogueLayout.rng("warehouse-infill:" + seed)
	for plot: Dictionary in parcels:
		var area: Rect2 = WorldLayout.rect(plot.rect)
		plot.entrance = WarehouseDistrict._point(Vector2(area.position.x + 18.0, area.end.y - 18.0))
		reserved.append(Rect2(WorldLayout.point(plot.entrance) - Vector2.ONE * 40.0, Vector2.ONE * 80.0))
		if plot not in plots.values():
			WarehouseDistrict._service_court(plot)
		var limit: int = clampi(int(area.get_area() / 230000.0), 1, 10)
		WarehouseDistrict._infill(plot, entities, reserved, random, limit)
		plot.frontage.scope = "street" if plot.road_edges[1] else "internal"
	var roles: Dictionary = {}
	for role: String in plots:
		roles[role] = plots[role].id
	var routes: Dictionary = {}
	for route: String in approaches:
		routes[route] = approaches[route].map(WarehouseDistrict._point)
	return {"entities":entities, "barriers":[], "gates":[], "district":{"family":family, "roles":roles,
		"food":[main.id, spare.id], "approaches":routes, "local_segments":plan.local_segments,
		"canonical_roads":plan.canonical_roads}}


static func corridor(from: Vector2, to: Vector2) -> Rect2:
	return Rect2(from.min(to), (to - from).abs()).grow(34.0)


static func certified(district: Dictionary, nav: FieldNavigation, start: Vector2) -> bool:
	for route: Array in district.approaches.values():
		var from: Vector2 = start
		for value: Array in route:
			var to: Vector2 = WorldLayout.point(value)
			if not nav._segment_is_clear(from, to):
				return false
			from = to
	return true
