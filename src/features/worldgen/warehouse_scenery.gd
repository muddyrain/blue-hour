class_name WarehouseScenery
extends RefCounted
## R3 adds to the R2 parcels. Fixed roles are found from doors and shared road edges.

const SIDE_GAP: float = 24.0


static func attach(data: Dictionary) -> bool:
	var district: Dictionary = data.warehouse_district
	var main: Dictionary = _parcel(data, district.roles.main)
	var frontage: Dictionary = _parcel(data, district.roles.frontage)
	var west: Dictionary = _west_neighbor(data, main)
	if west.is_empty():
		return false
	var threshold: float = WorldLayout.rect(main.rect).end.y
	var parent: Dictionary = _wall_near(data, west, threshold + 248.0)
	var row_end: Dictionary = _entity(data, "r2_row_b")
	if parent.is_empty() or row_end.is_empty():
		return false
	if not _annex(data, west, parent, WarehouseSlots.NARROW, "west_annex"):
		return false
	if not _annex(data, frontage, row_end, WarehouseSlots.END, "end_annex"):
		return false
	var alley: Rect2 = _side_alley(data, frontage)
	if not alley.has_area():
		return false
	var street_y: float = float(row_end.door[1])
	var outlet: Rect2 = Rect2(alley.end.x - 18.0, alley.end.y, 24.0, street_y - alley.end.y)
	district.alley = _rect(alley)
	district.alley_outlet = _rect(outlet)
	district.west_service = west.id
	frontage.walks.append(district.alley)
	frontage.walks.append(district.alley_outlet)
	var added: int = 0
	for plot: Dictionary in data.parcels:
		if added == 3:
			break
		if plot.id == west.id or plot.id in district.roles.values() or not plot.road_edges[3]:
			continue
		var wall: Dictionary = _wall_near(data, plot, WorldLayout.rect(plot.rect).end.y - 96.0)
		if not wall.is_empty() and _annex(data, plot, wall, WarehouseSlots.NARROW, "edge_annex"):
			added += 1
	return true


static func dress(data: Dictionary) -> bool:
	var district: Dictionary = data.warehouse_district
	var main: Dictionary = _parcel(data, district.roles.main)
	var frontage: Dictionary = _parcel(data, district.roles.frontage)
	var hall: Rect2 = WorldLayout.rect(_entity(data, "r2_main").rect)
	var path_y: float = float(district.approaches.detour[0][1])
	var work: Rect2 = Rect2(hall.position.x + 30.0, path_y - 190.0, hall.size.x - 100.0, 136.0)
	var occupied: Array[Rect2] = _occupied(data)
	var reserved: Array[Rect2] = ExplorationLayout._reserved(data)
	_surface(main, "work_floor", WarehouseSlots.MAT, work)
	if not _upright(main, "work_rack", WarehouseSlots.RACK, Vector2(work.position.x + 268.0, work.position.y + 83.0), occupied, reserved):
		return false
	_upright(main, "work_cargo", WarehouseSlots.CARGO, Vector2(work.position.x + 432.0, work.position.y + 96.0), occupied, reserved)

	var alley: Rect2 = WorldLayout.rect(district.alley)
	_surface(frontage, "side_walk", WarehouseSlots.PAVING, alley)
	_surface(frontage, "side_outlet", WarehouseSlots.PAVING, WorldLayout.rect(district.alley_outlet))
	_upright(frontage, "side_lamp", WarehouseSlots.LAMP, alley.position + Vector2(-6, 84), occupied, reserved)
	_upright(frontage, "side_pipe", WarehouseSlots.EDGE, alley.position + Vector2(-5, 240), occupied, reserved)
	for plot: Dictionary in data.parcels:
		for court: Dictionary in plot.courtyards:
			if court.kind == "loading":
				_loading(plot, WorldLayout.rect(court.rect), occupied, reserved)
				break
		_repair(data, plot, occupied, reserved)
	return true


static func _loading(plot: Dictionary, court: Rect2, occupied: Array[Rect2], reserved: Array[Rect2]) -> void:
	_surface(plot, "bay", WarehouseSlots.BAY, court.grow(-4.0))
	_surface(plot, "dock", WarehouseSlots.DOCK,
		Rect2(court.position + Vector2(12, 2), Vector2(court.size.x - 24.0, 12)))
	# Existing cargo remains the same obstruction. Replace its visual slot, then try one small companion stack.
	for detail: Dictionary in plot.dressing:
		if detail.get("kind") == "cargo" and court.has_point(WorldLayout.point(detail.point)):
			detail.slot = WarehouseSlots.CARGO
			detail.id = "%s_bay_cargo" % plot.id
			break
	_upright(plot, "loading_stack", WarehouseSlots.CARGO,
		court.end - Vector2(68, 18), occupied, reserved)


static func _repair(data: Dictionary, plot: Dictionary, occupied: Array[Rect2], reserved: Array[Rect2]) -> void:
	# Prefer a real annex. At an outside loading apron, use the nearest supporting building.
	var support: Dictionary = {}
	var best: float = INF
	var yard: Rect2
	for court: Dictionary in plot.courtyards:
		if court.kind == "loading":
			yard = WorldLayout.rect(court.rect)
			break
	for entity: Dictionary in data.entities:
		if entity.parcel != plot.id:
			continue
		if WarehouseSlots.BUILDINGS.has(entity.art):
			support = entity
			break
		if yard.has_area() and entity.art == WarehouseDistrict.OFFICE:
			var distance: float = WorldLayout.point(entity.door).distance_squared_to(yard.get_center())
			if distance < best:
				best = distance
				support = entity
	if support.is_empty():
		return
	var block: Rect2 = WorldLayout.rect(support.rect)
	for x: float in [block.position.x - 36.0, block.end.x + 36.0]:
		if _upright(plot, "repair_kit", WarehouseSlots.REPAIR, Vector2(x, block.end.y + 60.0), occupied, reserved):
			var mount: float = block.position.x + 22.0 if x < block.get_center().x else block.end.x - 22.0
			_upright(plot, "repair_lamp", WarehouseSlots.LAMP, Vector2(mount, block.end.y + 1.0), occupied, reserved)
			return


static func reserved_walks(data: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var district: Dictionary = data.warehouse_district
	result.append(WorldLayout.rect(district.alley))
	result.append(WorldLayout.rect(district.alley_outlet).grow(6.0))
	for route: Array in district.approaches.values():
		var previous: Vector2 = WorldLayout.point(data.bus.door)
		for raw: Array in route:
			var point: Vector2 = WorldLayout.point(raw)
			result.append(Rect2(previous.min(point), (point-previous).abs()).grow(21.0))
			previous = point
	return result


static func _side_alley(data: Dictionary, plot: Dictionary) -> Rect2:
	var bounds: Rect2 = WorldLayout.rect(plot.rect)
	var back: Rect2 = WorldLayout.rect(_entity(data, "r2_backstore").rect)
	var top: float = back.end.y - 264.0
	var bottom: float = back.end.y + 48.0
	var east: Rect2 = Rect2(bounds.end.x - 240.0, top, 240.0, bottom - top)
	var left: float = bounds.end.x - 128.0
	for entity: Dictionary in data.entities:
		if entity.parcel == plot.id:
			var visible: Rect2 = WorldgenScale.visible_rect(entity)
			if visible.intersects(east):
				left = maxf(left, visible.end.x + 8.0)
	var width: float = minf(76.0, bounds.end.x - 6.0 - left)
	if width < 52.0:
		return Rect2()
	return Rect2(bounds.end.x - width - 6.0, top, width, bottom - top)


static func _annex(data: Dictionary, plot: Dictionary, parent: Dictionary, slot: String, suffix: String) -> bool:
	var form: Dictionary = WarehouseSlots.BUILDINGS[slot]
	var size: Vector2 = form.size
	var yard: Rect2 = WorldLayout.rect(plot.rect)
	var wall: Rect2 = WorldLayout.rect(parent.rect)
	var foot: Vector2 = Vector2(wall.end.x + (18.0 if slot == WarehouseSlots.END else SIDE_GAP), wall.end.y)
	var visible: Rect2 = Rect2(foot - Vector2(0, size.y), size)
	var block: Rect2 = Rect2(foot - Vector2(0, form.depth), Vector2(size.x, form.depth))
	var door: Vector2 = foot + Vector2(form.door, 48.0)
	if not yard.grow(-20.0).encloses(visible) or not yard.grow(-12.0).has_point(door):
		return false
	var reservation: Rect2 = block.grow(18.0)
	if OpenStreetsV1.intersects_sweep(data.bus, reservation, 32.0) or reservation.intersects(OpenStreetsV1.boarding_paving(data.bus).grow(20.0)):
		return false
	for entity: Dictionary in data.entities:
		var other: Rect2 = WorldLayout.rect(entity.rect)
		if visible.grow(12.0).intersects(WorldgenScale.visible_rect(entity)) or reservation.intersects(other) \
				or reservation.grow(20.0).has_point(WorldLayout.point(entity.door)) or other.grow(24.0).has_point(door):
			return false
	for rect: Array in data.barriers + data.roads:
		if reservation.intersects(WorldLayout.rect(rect)):
			return false
	for court: Dictionary in plot.courtyards:
		if visible.intersects(WorldLayout.rect(court.rect)):
			return false
	var id: String = "%s_%s" % [plot.id, suffix]
	data.entities.append({"id":id,"archetype":"garage","rect":_rect(block),"door":_point(door),
		"variant":0,"parcel":plot.id,"art":slot,"service_only":true})
	plot.buildings.append(id)
	return true


static func _west_neighbor(data: Dictionary, main: Dictionary) -> Dictionary:
	var area: Rect2 = WorldLayout.rect(main.rect)
	for plot: Dictionary in data.parcels:
		var other: Rect2 = WorldLayout.rect(plot.rect)
		if area.position.x - other.end.x == 128.0 and other.position.y < area.end.y and other.end.y > area.end.y + 320.0:
			return plot
	return {}


static func _wall_near(data: Dictionary, plot: Dictionary, y: float) -> Dictionary:
	var edge: float = WorldLayout.rect(plot.rect).end.x
	var chosen: Dictionary = {}
	var best: float = INF
	for entity: Dictionary in data.entities:
		if entity.parcel != plot.id or entity.art not in [WarehouseDistrict.HALL, WarehouseDistrict.SHED]:
			continue
		var rect: Rect2 = WorldLayout.rect(entity.rect)
		if edge - rect.end.x < 160.0:
			continue
		var score: float = absf(rect.end.y - y) + (edge - rect.end.x) * 0.25
		if score < best:
			best = score
			chosen = entity
	return chosen


static func _occupied(data: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for entity: Dictionary in data.entities:
		result.append(WorldLayout.rect(entity.rect).grow(10.0))
	for value: Array in data.roads + data.barriers:
		result.append(WorldLayout.rect(value).grow(12.0))
	for plot: Dictionary in data.parcels:
		for detail: Dictionary in plot.dressing:
			for value: Array in detail.get("collisions", [detail.collision] if detail.has("collision") else []):
				result.append(WorldLayout.rect(value).grow(10.0))
	return result


static func _upright(plot: Dictionary, name: String, slot: String, point: Vector2,
		occupied: Array[Rect2], reserved: Array[Rect2]) -> bool:
	var size: Vector2 = WarehouseSlots.FOOTPRINTS[slot]
	var row: Dictionary = {"id":"%s_%s" % [plot.id,name], "slot":slot, "point":_point(point)}
	if size != Vector2.ZERO:
		var block: Rect2 = Rect2(point - Vector2(size.x * 0.5, size.y), size)
		if not WorldLayout.rect(plot.rect).encloses(block):
			return false
		for other: Rect2 in occupied + reserved:
			if block.grow(12.0).intersects(other):
				return false
		row.collision = _rect(block)
		occupied.append(block.grow(10.0))
	plot.dressing.append(row)
	return true


static func _surface(plot: Dictionary, name: String, slot: String, rect: Rect2) -> void:
	plot.dressing.append({"id":"%s_%s" % [plot.id,name], "slot":slot, "surface":_rect(rect)})


static func _parcel(data: Dictionary, id: String) -> Dictionary:
	for plot: Dictionary in data.parcels:
		if plot.id == id:
			return plot
	return {}


static func _entity(data: Dictionary, id: String) -> Dictionary:
	for entity: Dictionary in data.entities:
		if entity.id == id:
			return entity
	return {}


static func _rect(rect: Rect2) -> Array:
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]


static func _point(point: Vector2) -> Array:
	return [point.x,point.y]
