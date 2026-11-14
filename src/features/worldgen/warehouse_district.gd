class_name WarehouseDistrict
extends RefCounted
## R2 fits real buildings into the R1 road parcels. Walks and courts reserve land before infill.

const HALL: String = "warehouse_hall"
const SHED: String = "warehouse_shed"
const OFFICE: String = "warehouse_office"
const MODULES: Dictionary = {
	HALL: {"size":Vector2(704, 288), "depth":240.0, "roof":194, "door":550.0, "title":"仓储主库"},
	SHED: {"size":Vector2(352, 224), "depth":184.0, "roof":154, "door":173.0, "title":"仓房与检修棚"},
	OFFICE: {"size":Vector2(192, 148), "depth":112.0, "roof":100, "door":96.0, "title":"配套房"},
}
const FRONT: float = 64.0
const REAR: float = 24.0
const SIDE: float = 32.0
const PERIMETER: float = 32.0
const MIN_LOT: Vector2 = Vector2(256, 236)
const ANCHOR_TOLERANCE: float = 0.004


static func populate(parcels: Array, roads: Array, bus: Dictionary, seed: String) -> Dictionary:
	var sample: Dictionary = _sample(parcels, roads, bus)
	if sample.is_empty():
		return {}
	var entities: Array = []
	var barriers: Array = []
	var gates: Array = []
	var random: RandomNumberGenerator = RogueLayout.rng("BH_WAREHOUSE_DISTRICT:" + seed)
	var route: Dictionary = _main(sample.main, entities)
	_rows(sample.frontage, entities)
	_repair(sample.repair, entities)
	_cargo_yard(sample.yard, entities, barriers, gates)

	var reserved: Array[Rect2] = OpenStreetsV1.swept_rects(bus, 32.0)
	reserved.append(OpenStreetsV1.boarding_paving(bus).grow(20.0))
	for road: Array in roads:
		reserved.append(WorldLayout.rect(road).grow(PERIMETER))
	for wall: Array in barriers:
		reserved.append(WorldLayout.rect(wall).grow(20.0))
	for parcel: Dictionary in parcels:
		if parcel not in sample.values():
			_service_court(parcel)
		_infill(parcel, entities, reserved, random)
		var area: Rect2 = WorldLayout.rect(parcel.rect)
		parcel.entrance = _point(Vector2(area.position.x + 18.0, area.end.y - 18.0))
		parcel.frontage.scope = "street" if parcel.road_edges[1] else "internal"
	var roles: Dictionary = {}
	for key: String in sample:
		roles[key] = sample[key].id
	return {"entities":entities, "barriers":barriers, "gates":gates, "district":{
		"roles":roles, "approaches":route, "food":["r2_main", "r2_spares"]}}


static func _sample(parcels: Array, roads: Array, bus: Dictionary) -> Dictionary:
	var arterial: Rect2 = WorldLayout.rect(roads[1])
	var stop: Vector2 = WorldLayout.point(bus.stop)
	var crossing: Rect2
	for row: Array in roads:
		var road: Rect2 = WorldLayout.rect(row)
		if road.size.y == 128.0 and road.position.y > stop.y and road.position.y < stop.y + 360.0 \
				and road.has_point(Vector2(arterial.get_center().x, road.get_center().y)):
			crossing = road
			break
	if not crossing.has_area():
		return {}
	var roles: Dictionary = {}
	for parcel: Dictionary in parcels:
		var plot: Rect2 = WorldLayout.rect(parcel.rect)
		if plot.end.y == crossing.position.y:
			if plot.end.x == arterial.position.x: roles.main = parcel
			if plot.position.x == arterial.end.x: roles.frontage = parcel
		if plot.position.y == crossing.end.y:
			if plot.end.x == arterial.position.x: roles.repair = parcel
			if plot.position.x == arterial.end.x: roles.yard = parcel
	if roles.size() != 4 or float(roles.main.rect[3]) < 820.0 or float(roles.frontage.rect[3]) < 612.0 \
			or float(roles.repair.rect[3]) < 512.0 or float(roles.yard.rect[3]) < 472.0:
		return {}
	return roles


static func _main(parcel: Dictionary, entities: Array) -> Dictionary:
	var plot: Rect2 = WorldLayout.rect(parcel.rect)
	var foot: float = plot.end.y - 224.0
	var east: float = plot.end.x - 52.0
	var west: float = plot.position.x + 40.0
	var north: float = foot - 344.0
	var front: float = foot + 48.0
	var main_x: float = plot.end.x - 940.0
	var main: Dictionary = _module(parcel, entities, HALL, main_x, foot, "convenience_store", "r2_main")
	_module(parcel, entities, OFFICE, plot.end.x - 248.0, foot - 416.0, "garage", "r2_guard", true)
	var door: Vector2 = WorldLayout.point(main.door)
	var entry: Vector2 = Vector2(east, front)
	var side: Vector2 = Vector2(west, front)
	_court(parcel, Rect2(main_x, foot + 80.0, 704.0, 112.0), "loading", Vector2(main_x - 8.0, front))
	var direct: Array[Vector2] = [entry, door]
	var detour: Array[Vector2] = [Vector2(east, north), Vector2(west, north), side, door]
	_walk(parcel, entry, Vector2(east, north), 56.0)
	_walk(parcel, entry, door, 56.0)
	_walk(parcel, detour[0], detour[1], 56.0)
	_walk(parcel, detour[1], side, 56.0)
	_walk(parcel, side, door, 56.0)
	return {"direct":direct.map(_point), "detour":detour.map(_point)}


static func _rows(parcel: Dictionary, entities: Array) -> void:
	var plot: Rect2 = WorldLayout.rect(parcel.rect)
	var foot: float = plot.end.y - 64.0
	var x: float = plot.position.x + 96.0
	_module(parcel, entities, SHED, x, foot, "warehouse", "r2_row_a")
	_module(parcel, entities, SHED, x + 408.0, foot, "warehouse", "r2_row_b")
	_module(parcel, entities, SHED, x, foot - 292.0, "warehouse", "r2_backstore", true)
	_module(parcel, entities, OFFICE, x + 408.0, foot - 292.0, "garage", "r2_toolroom", true)
	_walk(parcel, Vector2(plot.position.x + 40.0, foot + 48.0), Vector2(plot.end.x - 40.0, foot + 48.0), 48.0)
	_walk(parcel, Vector2(plot.position.x + 40.0, foot - 244.0), Vector2(plot.end.x - 40.0, foot - 244.0), 48.0)


static func _repair(parcel: Dictionary, entities: Array) -> void:
	var plot: Rect2 = WorldLayout.rect(parcel.rect)
	var x: float = plot.position.x
	var foot: float = plot.position.y + 240.0
	_module(parcel, entities, SHED, x + 64.0, foot, "garage", "r2_repair")
	_module(parcel, entities, OFFICE, x + 488.0, foot, "convenience_store", "r2_spares")
	_module(parcel, entities, OFFICE, x + 64.0, foot + 216.0, "garage", "r2_power", true)
	_module(parcel, entities, OFFICE, x + 320.0, foot + 216.0, "garage", "r2_materials", true)
	_walk(parcel, Vector2(x + 32.0, foot + 48.0), Vector2(plot.end.x - 32.0, foot + 48.0), 56.0)


static func _cargo_yard(parcel: Dictionary, entities: Array, barriers: Array, gates: Array) -> void:
	var plot: Rect2 = WorldLayout.rect(parcel.rect)
	var x: float = plot.position.x
	var foot: float = plot.position.y + 240.0
	_module(parcel, entities, OFFICE, x + 136.0, foot, "garage", "r2_yard_office", true)
	_module(parcel, entities, SHED, plot.end.x - 416.0, foot, "warehouse", "r2_yard_shed")
	var yard: Rect2 = Rect2(x + 136.0, foot + 72.0, plot.size.x - 208.0, 132.0)
	var gate_x: float = yard.get_center().x
	var gap: float = 112.0
	_court(parcel, yard, "loading", Vector2(gate_x, yard.get_center().y))
	for y: float in [yard.position.y, yard.end.y - 12.0]:
		barriers.append(_rect(Rect2(yard.position.x, y, gate_x - gap * 0.5 - yard.position.x, 12.0)))
		barriers.append(_rect(Rect2(gate_x + gap * 0.5, y, yard.end.x - gate_x - gap * 0.5, 12.0)))
		gates.append(_point(Vector2(gate_x, y + 6.0)))
	barriers.append(_rect(Rect2(yard.position, Vector2(12.0, yard.size.y))))
	barriers.append(_rect(Rect2(yard.position + Vector2(yard.size.x - 12.0, 0), Vector2(12.0, yard.size.y))))
	_walk(parcel, Vector2(gate_x, foot + 42.0), Vector2(gate_x, yard.end.y + 32.0), 56.0)


static func _service_court(parcel: Dictionary) -> void:
	var plot: Rect2 = WorldLayout.rect(parcel.rect)
	if parcel.kind == "loading" and plot.size.x >= 640.0 and plot.size.y >= 552.0:
		var entry: Vector2 = Vector2(plot.position.x + 60.0, plot.end.y - 80.0)
		_court(parcel, Rect2(entry + Vector2(20.0, -96.0), Vector2(416.0, 136.0)), "loading", entry)
	elif parcel.road_edges[0] and plot.size.x >= 3200.0 and plot.size.y >= 720.0:
		# One street-facing apron breaks up long sheds and gives service vehicles a place to turn.
		var area: Rect2 = Rect2(plot.position + Vector2(160.0, 32.0), Vector2(576.0, 216.0))
		_court(parcel, area, "loading", area.position + Vector2(32.0, 24.0))


static func _infill(parcel: Dictionary, entities: Array, reserved: Array[Rect2], random: RandomNumberGenerator,
		limit: int = -1) -> void:
	var plot: Rect2 = WorldLayout.rect(parcel.rect)
	var interior: Rect2 = plot.grow(-PERIMETER)
	var occupied: Array[Rect2] = []
	for area: Rect2 in reserved:
		if area.intersects(plot):
			occupied.append(area)
	for walk: Array in parcel.walks:
		occupied.append(WorldLayout.rect(walk))
	for court: Dictionary in parcel.courtyards:
		occupied.append(WorldLayout.rect(court.rect).grow(20.0))
		occupied.append(Rect2(WorldLayout.point(court.entrance) - Vector2.ONE * 32.0, Vector2.ONE * 64.0))
	for entity: Dictionary in entities:
		if entity.parcel == parcel.id:
			occupied.append(WorldgenScale.visible_rect(entity).grow_individual(SIDE, REAR, SIDE, FRONT))
	var free: Array[Rect2] = [interior]
	for area: Rect2 in occupied:
		free = _subtract(free, area)

	var added: int = 0
	while not free.is_empty() and (limit < 0 or added < limit):
		var area: Rect2 = free.pop_back()
		if area.size.x < MIN_LOT.x or area.size.y < MIN_LOT.y:
			continue
		for art: String in [HALL, SHED, OFFICE]:
			var size: Vector2 = MODULES[art].size
			var lot: Vector2 = size + Vector2(SIDE * 2.0, REAR + FRONT)
			if area.size.x < lot.x or area.size.y < lot.y:
				continue
			var foot: float = area.end.y - FRONT
			var kind: String = "convenience_store" if random.randi_range(0, 5) == 0 else "garage" if art == OFFICE else "warehouse"
			var id: String = "%s_store_%02d" % [parcel.id, added]
			_module(parcel, entities, art, area.position.x + SIDE, foot, kind, id, art == OFFICE and kind == "garage")
			added += 1
			_walk(parcel, Vector2(area.position.x + 8.0, foot + 48.0),
				Vector2(area.position.x + lot.x - 8.0, foot + 48.0), 32.0)
			var used: Rect2 = Rect2(Vector2(area.position.x, area.end.y - lot.y), lot)
			occupied.append(used)
			free.append_array(_subtract([area], used))
			break
	var already: int = 0
	for entity: Dictionary in entities:
		if entity.get("parcel", "") == parcel.id:
			already += 1
	if limit < 0:
		_fill_across_cuts(parcel, entities, interior, occupied)
	elif already < 4:
		_fill_across_cuts(parcel, entities, interior, occupied, 2)


static func _fill_across_cuts(parcel: Dictionary, entities: Array, interior: Rect2,
		occupied: Array[Rect2], cap: int = -1) -> void:
	# A small room can straddle the artificial cuts used to pack the larger modules.
	# In anchor space, each occupied rectangle excludes the positions whose lot would overlap it.
	var span: Vector2 = interior.size - MIN_LOT
	if span.x < 0.0 or span.y < 0.0:
		return
	var anchors: Array[Rect2] = [Rect2(interior.position, span + Vector2.ONE * ANCHOR_TOLERANCE)]
	for area: Rect2 in occupied:
		anchors = _subtract(anchors, _excluded_anchors(area), Vector2.ZERO)
	var serial: int = 0
	while not anchors.is_empty() and (cap < 0 or serial < cap):
		var lot: Rect2 = Rect2(anchors[0].position, MIN_LOT)
		var foot: float = lot.end.y - FRONT
		_module(parcel, entities, OFFICE, lot.position.x + SIDE, foot,
			"garage", "%s_service_%02d" % [parcel.id, serial], true)
		_walk(parcel, Vector2(lot.position.x + 8.0, foot + 48.0), Vector2(lot.end.x - 8.0, foot + 48.0), 32.0)
		anchors = _subtract(anchors, _excluded_anchors(lot), Vector2.ZERO)
		serial += 1


static func _excluded_anchors(area: Rect2) -> Rect2:
	return Rect2(area.position - MIN_LOT + Vector2.ONE * ANCHOR_TOLERANCE,
		area.size + MIN_LOT - Vector2.ONE * ANCHOR_TOLERANCE)


static func _subtract(areas: Array[Rect2], occupied: Rect2, minimum: Vector2 = MIN_LOT) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for area: Rect2 in areas:
		var cut: Rect2 = area.intersection(occupied)
		if not cut.has_area():
			result.append(area)
			continue
		var pieces: Array[Rect2] = [
			Rect2(area.position, Vector2(area.size.x, cut.position.y - area.position.y)),
			Rect2(Vector2(area.position.x, cut.end.y), Vector2(area.size.x, area.end.y - cut.end.y)),
			Rect2(Vector2(area.position.x, cut.position.y), Vector2(cut.position.x - area.position.x, cut.size.y)),
			Rect2(Vector2(cut.end.x, cut.position.y), Vector2(area.end.x - cut.end.x, cut.size.y)),
		]
		for piece: Rect2 in pieces:
			if piece.has_area() and piece.size.x >= minimum.x and piece.size.y >= minimum.y:
				result.append(piece)
	return result


static func _module(parcel: Dictionary, entities: Array, art: String, x: float, foot: float,
		kind: String, id: String, service_only: bool = false) -> Dictionary:
	var form: Dictionary = MODULES[art]
	var block: Rect2 = Rect2(x, foot - form.depth, form.size.x, form.depth)
	var entity: Dictionary = {"id":id, "archetype":kind, "rect":_rect(block),
		"door":[x + form.door, foot + 48.0], "variant":int(id.sha256_text().left(2).hex_to_int() % 3),
		"parcel":parcel.id, "art":art}
	if service_only:
		entity.service_only = true
	entities.append(entity)
	parcel.buildings.append(id)
	return entity


static func _walk(parcel: Dictionary, a: Vector2, b: Vector2, width: float) -> void:
	var area: Rect2 = Rect2(a.min(b), (a-b).abs()).grow(width * 0.5).intersection(WorldLayout.rect(parcel.rect))
	if area.has_area():
		parcel.walks.append(_rect(area))


static func _court(parcel: Dictionary, area: Rect2, kind: String, entrance: Vector2) -> void:
	parcel.courtyards.append({"rect":_rect(area), "kind":kind, "entrance":_point(entrance)})


static func certified(district: Dictionary, gates: Array, nav: FieldNavigation, start: Vector2) -> bool:
	if gates.size() != 2 or not nav._segment_is_clear(WorldLayout.point(gates[0]), WorldLayout.point(gates[1])):
		return false
	var entries: Array = gates.duplicate()
	if district.has("alley"):
		var alley: Rect2 = WorldLayout.rect(district.alley)
		var top: Vector2 = Vector2(alley.get_center().x, alley.position.y)
		var bottom: Vector2 = Vector2(top.x, alley.end.y)
		var outlet: Rect2 = WorldLayout.rect(district.alley_outlet)
		var corner: Vector2 = Vector2(outlet.get_center().x, bottom.y)
		var street: Vector2 = Vector2(corner.x, outlet.end.y)
		if not nav._segment_is_clear(top, bottom) or not nav._segment_is_clear(bottom, corner) \
				or not nav._segment_is_clear(corner, street):
			return false
		entries.append(_point(top))
		entries.append(_point(street))
	for value: Array in entries:
		var target: Vector2 = WorldLayout.point(value)
		var path: PackedVector2Array = nav.path_between(start, target)
		if path.is_empty() or path[-1].distance_to(target) > 14.0:
			return false
	for route: Array in district.approaches.values():
		var from: Vector2 = start
		for value: Array in route:
			var point: Vector2 = WorldLayout.point(value)
			if not nav._segment_is_clear(from, point):
				return false
			from = point
	return true


static func prop_anchors(entities: Array) -> Array[String]:
	# Props need representative route distances across the map. The final certificate
	# still routes to every door after the props have been placed.
	var by_parcel: Dictionary = {}
	for entity: Dictionary in entities:
		if entity.get("service_only", false):
			continue
		if not by_parcel.has(entity.parcel):
			by_parcel[entity.parcel] = [entity.id, entity.id]
		else:
			by_parcel[entity.parcel][1] = entity.id
	var result: Array[String] = []
	for pair: Array in by_parcel.values():
		result.append(pair[0])
		if pair[0] != pair[1]:
			result.append(pair[1])
	return result


static func _rect(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


static func _point(point: Vector2) -> Array:
	return [point.x, point.y]
