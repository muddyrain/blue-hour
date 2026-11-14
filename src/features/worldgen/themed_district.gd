class_name ThemedDistrict
extends RefCounted
## Commercial and residential landmarks share the same road cuts and pedestrian envelopes.

const FAMILIES: Dictionary = {
	"commercial":["through_market", "market_square", "supermarket_service"],
	"residential":["row_courts", "offset_alley", "enclosed_group"],
}


static func family(seed: String, topology: String) -> String:
	var random: RandomNumberGenerator = RogueLayout.rng("theme-family:" + seed + ":" + topology)
	return FAMILIES[topology][random.randi_range(0, 2)]


static func partition(leaves: Array, segments: Array, bus: Dictionary, seed: String, attempt: int,
		topology: String) -> Dictionary:
	var style: String = family(seed, topology)
	var south: bool = style in ["market_square", "supermarket_service", "offset_alley"]
	var index: int = int(south) * 2 + int(topology == "residential")
	var plot: Dictionary = leaves[index]
	var area: Rect2 = WorldLayout.rect(plot.rect)
	var stop: Vector2 = WorldLayout.point(bus.stop)
	var random: RandomNumberGenerator = RogueLayout.rng("theme-roads:" + seed + ":" + str(attempt))
	var left: int = maxi(int(area.position.x) + 192, int(stop.x) - 576 - 32 * random.randi_range(0, 2))
	var right: int = mini(int(area.end.x) - 192, int(stop.x) + 544 + 32 * random.randi_range(0, 2))
	# The first split takes the farther side. The other side can use the existing
	# arterial as its boundary when the bus stops close to the junction.
	if left > stop.x - 480:
		left = int(area.position.x)
	if right < stop.x + 480:
		right = int(area.end.x)
	var first_local: int = segments.size()
	if style == "market_square":
		var opposite: Dictionary = leaves[0]
		_cut(leaves, segments, opposite, true, left - int(opposite.rect[0]), random)
	if left > area.position.x:
		plot = _cut(leaves, segments, plot, true, left - int(area.position.x), random)[1]
	if right < area.end.x:
		plot = _cut(leaves, segments, plot, true, right - int(plot.rect[0]), random)[0]
	if style not in ["through_market", "row_courts"]:
		var depth: int = 848 + 32 * random.randi_range(0, 2)
		var cross_at: int = depth if south else int(plot.rect[3]) - depth
		plot = _cut(leaves, segments, plot, false, cross_at, random)[0 if south else 1]
	plot.district_role = "main"
	return {"family":style, "local_segments":segments.slice(first_local), "south":south}


static func _cut(leaves: Array, segments: Array, plot: Dictionary, vertical: bool,
		offset: int, random: RandomNumberGenerator) -> Array:
	leaves.erase(plot)
	WorldgenGeometry._split(plot, vertical, random, leaves, segments, offset)
	return leaves.slice(-2)


static func populate(plot: Dictionary, entities: Array, roads: Array, bus: Dictionary,
		plan: Dictionary, topology: String, task: String) -> Dictionary:
	var area: Rect2 = WorldLayout.rect(plot.rect)
	var start: Vector2 = WorldLayout.point(bus.door)
	var artery: Rect2 = WorldLayout.rect(roads[0])
	var style: String = plan.family
	var south: bool = plan.south
	var linear: bool = style in ["through_market", "row_courts"]
	var west: float = area.position.x + 48.0
	var east: float = area.end.x - 48.0
	var foot: float = area.position.y + (480.0 if style != "offset_alley" else 546.0) if south \
		else area.end.y - (120.0 if style == "through_market" else 216.0 if linear else 320.0)
	var commercial: bool = topology == "commercial"
	var main_type: String = "supermarket" if commercial else "convenience_store"
	if task in ["airdrop", "equipment"]:
		main_type = "garage"
	var side_type: String = "convenience_store" if commercial else "eatery"
	var x: float = area.position.x + (144.0 if style == "market_square" else 112.0)
	if not WorldgenGeometry._add_building(main_type, 0, x, foot, plot, entities, roads, bus):
		return {}
	var main: Dictionary = entities[-1]
	var main_block: Rect2 = WorldLayout.rect(main.rect)
	var side_foot: float = foot + (0.0 if linear else 32.0 if style == "enclosed_group" else 96.0)
	if not WorldgenGeometry._add_building(side_type, 1, main_block.end.x + 48.0, side_foot,
			plot, entities, roads, bus):
		return {}
	var spare: Dictionary = entities[-1]
	var door: Vector2 = WorldLayout.point(main.door)
	var side_door: Vector2 = WorldLayout.point(spare.door)
	var sidewalk_y: float = artery.end.y + 48.0 if south else artery.position.y - 48.0
	var from_other_side: bool = (start.y > artery.end.y) != south
	var cross_x: float = west if absf(west - start.x) > absf(east - start.x) else east
	var shoulder: float = artery.position.y - 8.0 if south else artery.end.y + 8.0
	var crossing: Array[Vector2] = [Vector2(start.x, shoulder), Vector2(cross_x, shoulder), Vector2(cross_x, sidewalk_y)]
	var paths: Dictionary = {}
	var fences: Array = []
	var front: float = maxf(door.y, side_door.y) + 48.0
	var gate_y: float = sidewalk_y
	var side_x: float = east if style in ["supermarket_service", "offset_alley"] else west
	var front_path: Array[Vector2] = []
	if from_other_side:
		front_path.append_array(crossing)
	if linear:
		front_path.append_array([Vector2(door.x, sidewalk_y), door])
	else:
		front_path.append_array([Vector2(side_x, gate_y), Vector2(side_x, front),
			Vector2(door.x, front), door])
	paths.direct = front_path
	if style in ["market_square", "supermarket_service", "enclosed_group"]:
		var other: float = west if side_x == east else east
		var detour: Array[Vector2] = []
		if from_other_side:
			detour.append_array(crossing)
		detour.append(Vector2(other, sidewalk_y))
		if style == "supermarket_service":
			var rear_street: float = area.end.y + 32.0
			detour.append_array([Vector2(other, rear_street), Vector2(door.x, rear_street)])
		else:
			detour.append_array([Vector2(other, front), Vector2(door.x, front)])
		detour.append(door)
		paths.detour = detour
	if style in ["offset_alley", "supermarket_service"]:
		var fence_y: float = area.position.y + 152.0
		fences.append(WarehouseDistrict._rect(Rect2(Vector2(west + 36.0, fence_y),
			Vector2(east - west - 72.0, 16.0))))
	if style == "enclosed_group":
		var fence_y: float = area.end.y - 144.0
		fences.append(WarehouseDistrict._rect(Rect2(Vector2(west + 48.0, fence_y),
			Vector2(east - west - 96.0, 16.0))))
	# The front of a south block is reached through either side lane. North
	# frontages face the main road; their front paths stay on the sidewalk.
	WarehouseDistrict._walk(plot, Vector2(west, front), Vector2(east, front), 48.0)
	WarehouseDistrict._walk(plot, Vector2(side_door.x, front), side_door, 48.0)
	var yard: Rect2 = Rect2(Vector2(main_block.position.x + 16.0, door.y + 16.0),
		Vector2(main_block.size.x - 32.0, minf(104.0, area.end.y - door.y - 28.0)))
	var court_kind: String = "garden" if not commercial else "parking" if style == "supermarket_service" else "court"
	if style == "market_square":
		var plaza_top: float = area.position.y + 116.0
		var plaza_bottom: float = WorldgenScale.visible_rect(main).position.y - 24.0
		yard = Rect2(Vector2(west + 48.0, plaza_top),
			Vector2(east - west - 96.0, plaza_bottom - plaza_top))
	if yard.has_area():
		var yard_entry: Vector2 = Vector2(west, yard.get_center().y) if style == "market_square" else door
		WarehouseDistrict._court(plot, yard, court_kind, yard_entry)
	if not commercial:
		var home_foot: float = area.position.y + 408.0 if south else foot - 250.0
		var home_x: float = main_block.end.x + 48.0
		if home_foot < foot - 120.0:
			WorldgenGeometry._add_building("row_house", 1, home_x, home_foot, plot, entities, roads, bus)
		if linear:
			WorldgenGeometry._add_building("row_house", 0, x, home_foot, plot, entities, roads, bus)
		# Pack remaining residential frontage so enclosed courts are not two shops on a lawn.
		if home_foot < foot - 80.0:
			var homes: Array[String] = ["detached_home", "row_house", "detached_home"]
			_fill_front(plot, entities, roads, bus, west, east, home_foot, homes, 4)
	var fillers: Array[String] = []
	if commercial:
		fillers.assign(["convenience_store", "eatery", "garage"])
	else:
		fillers.assign(["detached_home", "row_house"])
	_fill_front(plot, entities, roads, bus, west, east, foot if linear else side_foot, fillers, 4)
	var approaches: Dictionary = {}
	for name: String in paths:
		var point: Vector2 = start
		for next: Vector2 in paths[name]:
			var paving: Rect2 = SeededWarehouseDistrict.corridor(point, next).intersection(area)
			if paving.has_area():
				plot.walks.append(WarehouseDistrict._rect(paving))
			point = next
		approaches[name] = paths[name].map(WarehouseDistrict._point)
	plot.entrance = WarehouseDistrict._point(Vector2(west, front))
	plot.frontage = {"scope":"street" if linear else "internal", "available":east - west,
		"occupied":main_block.size.x + float(spare.rect[2]), "coverage":(main_block.size.x + float(spare.rect[2])) / (east - west)}
	plot.kind = "shopfront" if commercial else "garden"
	return {"family":style, "roles":{"main":plot.id}, "approaches":approaches,
		"food":[main.id, spare.id], "local_segments":plan.local_segments, "barriers":fences}


static func _fill_front(plot: Dictionary, entities: Array, roads: Array, bus: Dictionary,
		west: float, east: float, foot: float, types: Array[String], limit: int) -> void:
	var added: int = 0
	var cursor: float = west + 16.0
	var index: int = 0
	while cursor + 200.0 < east and added < limit and index < 28:
		var typ: String = types[index % types.size()]
		var width: float = float(WorldgenScale.WIDTH[typ])
		if cursor + width > east - 8.0:
			index += 1
			if width > east - cursor - 8.0:
				break
			continue
		if WorldgenGeometry._add_building(typ, index + 2, cursor, foot, plot, entities, roads, bus):
			cursor += width + 28.0
			added += 1
		else:
			cursor += 48.0
		index += 1
