class_name IsoTiles
extends Node2D
## Paints a 2:1 diamond grid from authored or inferred ground kinds.
## 32-unit cells keep 32-wide sidewalks, banks, and 96-wide canals on-size.

const TILE: float = 32.0
var layout: StreetLayout
var cells: Dictionary = {} # Vector2i -> String tile name
var _road_edges: Array[Rect2] = []
var _crosswalks: Array[Dictionary] = []


func _ready() -> void:
	z_index = -10
	if layout != null and cells.is_empty():
		fill_from_layout(layout)
	queue_redraw()


func fill_from_layout(source: StreetLayout) -> void:
	layout = source
	cells.clear()
	_road_edges.clear()
	_crosswalks.clear()
	var bounds: Rect2 = source.world_bounds
	var min_c: Vector2i = Vector2i(int(floor(bounds.position.x / TILE)), int(floor(bounds.position.y / TILE)))
	var max_c: Vector2i = Vector2i(int(ceil(bounds.end.x / TILE)), int(ceil(bounds.end.y / TILE)))
	for y: int in range(min_c.y, max_c.y):
		for x: int in range(min_c.x, max_c.x):
			cells[Vector2i(x, y)] = "grass"
	var grounds: Dictionary = source.world_data.get("grounds", {})
	_stamp_rects(grounds.get("sidewalks", []), "sidewalk")
	_stamp_rects(grounds.get("banks", []), "bank")
	_stamp_rects(grounds.get("canal", []), "canal")
	for road: Rect2 in source.roads:
		_road_edges.append(road)
		# Plain asphalt first so a 64-wide single lane stays unmarked.
		_stamp_rect(road, "road")
		# A 96-wide dual lane (and any wider road) gets one center dashed
		# strip, not a dash in the middle of every 32-cell.
		if minf(road.size.x, road.size.y) > 64.0:
			var name: String = "road_ew" if road.size.x >= road.size.y else "road_ns"
			var strip: Rect2
			if road.size.x >= road.size.y:
				strip = Rect2(road.position.x, road.get_center().y - TILE * 0.5, road.size.x, TILE)
			else:
				strip = Rect2(road.get_center().x - TILE * 0.5, road.position.y, TILE, road.size.y)
			_stamp_rect(strip, name)
	# Crosswalks are drawn as true-width iso quads so 16-unit stripes stay 16-unit.
	_store_crosswalks(grounds.get("crosswalks_ew", []), "ew")
	_store_crosswalks(grounds.get("crosswalks_ns", []), "ns")
	_stamp_rects(grounds.get("road", []), "road")
	# Authored sidewalks and roads keep priority; generated door paths only replace grass.
	_stamp_rects(grounds.get("gravel", []), "gravel", "grass")
	_stamp_rects(grounds.get("concrete", []), "concrete", "grass")
	_stamp_generated_paths(source)
	queue_redraw()


func _stamp_rects(rows: Array, name: String, only: String = "") -> void:
	for row: Variant in rows:
		_stamp_rect(WorldLayout.rect(row) if row is Array else row, name, only)


func _store_crosswalks(rows: Array, axis: String) -> void:
	for row: Variant in rows:
		_crosswalks.append({"rect": WorldLayout.rect(row) if row is Array else row, "axis": axis})


func _stamp_rect(area: Rect2, name: String, only: String = "") -> void:
	# A cell is painted only when it is mostly inside the authored rect, so a
	# 32-wide bank or sidewalk cannot inflate to a neighboring 64-unit tile.
	var min_c: Vector2i = Vector2i(int(floor(area.position.x / TILE)), int(floor(area.position.y / TILE)))
	var max_c: Vector2i = Vector2i(int(ceil(area.end.x / TILE)) - 1, int(ceil(area.end.y / TILE)) - 1)
	var need: float = TILE * TILE * 0.5
	for y: int in range(min_c.y, max_c.y + 1):
		for x: int in range(min_c.x, max_c.x + 1):
			var cell: Rect2 = Rect2(Vector2(x, y) * TILE, Vector2(TILE, TILE))
			var overlap: Rect2 = cell.intersection(area)
			if overlap.has_area() and overlap.get_area() + 0.01 >= need:
				var key: Vector2i = Vector2i(x, y)
				if only.is_empty() or String(cells.get(key, "")) == only:
					cells[key] = name



func _stamp_generated_paths(source: StreetLayout) -> void:
	# Presentation only: existing walks and door approaches become narrow paths.
	# Seaside town keeps its authored grounds; layout data and navigation are unchanged.
	if source.world_data.get("seaside_town") or int(source.world_data.get("version", 0)) != 5:
		return
	var topology: String = String(source.world_data.get("topology", ""))
	var parcels: Array = source.world_data.get("parcels", [])
	var entities: Array = source.world_data.get("entities", [])
	var roads: Array[Rect2] = source.roads.duplicate()
	var walks: Array[Rect2] = []
	var footprints: Array[Rect2] = []
	for entity: Dictionary in entities:
		footprints.append(WorldLayout.rect(entity.rect))
	for parcel: Dictionary in parcels:
		var tile: String = _path_tile(String(parcel.get("kind", "")), "", topology)
		for walk: Array in parcel.get("walks", []):
			var lane: Rect2 = _narrow_walk(WorldLayout.rect(walk))
			if lane.has_area():
				walks.append(lane)
				_stamp_rect(lane, tile, "grass")
	for entity: Dictionary in entities:
		if not entity.has("door"):
			continue
		var door: Vector2 = WorldLayout.point(entity.door)
		var kind: String = ""
		for parcel: Dictionary in parcels:
			if String(parcel.get("id", "")) == String(entity.get("parcel", "")):
				kind = String(parcel.get("kind", ""))
				break
		var tile: String = _path_tile(kind, String(entity.get("archetype", "")), topology)
		var body: Rect2 = WorldLayout.rect(entity.rect)
		for area: Rect2 in _door_paths(door, roads, walks, footprints, body):
			_stamp_rect(area, tile, "grass")


func _path_tile(kind: String, archetype: String = "", topology: String = "") -> String:
	if archetype in ["warehouse", "garage", "convenience_store", "eatery", "supermarket"]:
		return "concrete"
	if archetype in ["detached_home", "row_house", "small_apartment", "shrine"]:
		return "gravel"
	if kind in ["loading", "parking", "service", "shopfront"] or topology in ["industrial", "commercial"]:
		return "concrete"
	return "gravel"


func _narrow_walk(area: Rect2) -> Rect2:
	# Existing walks already reserve a lane; wide leftover rectangles stay grass except a 48-wide spine.
	const MAX_SHORT: float = 80.0
	const LANE: float = 48.0
	if minf(area.size.x, area.size.y) <= MAX_SHORT:
		return area
	if area.size.x >= area.size.y:
		return Rect2(area.position.x, area.get_center().y - LANE * 0.5, area.size.x, LANE)
	return Rect2(area.get_center().x - LANE * 0.5, area.position.y, LANE, area.size.y)


func _door_paths(door: Vector2, roads: Array[Rect2], walks: Array[Rect2], footprints: Array[Rect2], body: Rect2) -> Array[Rect2]:
	var paths: Array[Rect2] = []
	# A short landing at the threshold, then a 32-wide walk onward to the roadside.
	# Sitting on a yard lane is not enough if grass still remains between the door and the curb.
	var apron: Rect2 = Rect2(door.x - 24.0, door.y - 16.0, 48.0, 48.0)
	paths.append(apron)
	if _connect(paths, door, roads, footprints, body, 8.0, 168.0):
		return paths
	_connect(paths, door, walks, footprints, body, 8.0, 280.0)
	return paths


func _connect(paths: Array[Rect2], door: Vector2, goals: Array[Rect2], footprints: Array[Rect2], body: Rect2, near: float, limit: float) -> bool:
	if goals.is_empty():
		return false
	var goal: Rect2 = _nearest_goal(door, goals)
	if not goal.has_area():
		return false
	var target: Vector2 = Vector2(clampf(door.x, goal.position.x, goal.end.x), clampf(door.y, goal.position.y, goal.end.y))
	if door.distance_to(target) <= near:
		return true
	if door.distance_to(target) > limit:
		return false
	var vertical_first: Array[Rect2] = _elbow(door, target, true)
	var horizontal_first: Array[Rect2] = _elbow(door, target, false)
	if not _blocked(vertical_first, footprints, body):
		paths.append_array(vertical_first)
		return true
	if not _blocked(horizontal_first, footprints, body):
		paths.append_array(horizontal_first)
		return true
	return false


func _elbow(door: Vector2, target: Vector2, vertical_first: bool) -> Array[Rect2]:
	var half: float = 16.0
	var mid: Vector2 = Vector2(door.x, target.y) if vertical_first else Vector2(target.x, door.y)
	var segments: Array[Rect2] = []
	segments.append(_span(door, mid, half))
	segments.append(_span(mid, target, half))
	return segments


func _span(a: Vector2, b: Vector2, half: float) -> Rect2:
	var left: float = minf(a.x, b.x) - half
	var top: float = minf(a.y, b.y) - half
	return Rect2(left, top, absf(a.x - b.x) + half * 2.0, absf(a.y - b.y) + half * 2.0)


func _nearest_goal(point: Vector2, goals: Array[Rect2]) -> Rect2:
	var best: Rect2 = Rect2()
	var best_d: float = INF
	for goal: Rect2 in goals:
		if not goal.has_area():
			continue
		var clamped: Vector2 = Vector2(clampf(point.x, goal.position.x, goal.end.x), clampf(point.y, goal.position.y, goal.end.y))
		var distance: float = point.distance_squared_to(clamped)
		if distance < best_d:
			best_d = distance
			best = goal
	return best


func _blocked(areas: Array[Rect2], footprints: Array[Rect2], ignore: Rect2) -> bool:
	for area: Rect2 in areas:
		for body: Rect2 in footprints:
			if body == ignore:
				continue
			if area.intersects(body):
				return true
	return false


func _draw() -> void:
	for cell: Vector2i in cells:
		IsoAtlas.stamp_cell(self, "tiles/%s.png" % cells[cell], cell, TILE)
	for road: Rect2 in _road_edges:
		var poly: PackedVector2Array = IsoSpace.polygon(road)
		draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), Color(0.62, 0.65, 0.68, 0.9), 1.25, true)
	for mark: Dictionary in _crosswalks:
		_draw_crosswalk(mark.rect, String(mark.axis))


func _draw_crosswalk(area: Rect2, axis: String) -> void:
	var stripe: float = 8.0
	var gap: float = 8.0
	var paint: Color = Color(0.90, 0.88, 0.80, 0.92)
	if axis == "ew":
		var x: float = area.position.x
		while x < area.end.x - 0.5:
			var width: float = minf(stripe, area.end.x - x)
			draw_colored_polygon(IsoSpace.polygon(Rect2(x, area.position.y, width, area.size.y)), paint)
			x += stripe + gap
	else:
		var y: float = area.position.y
		while y < area.end.y - 0.5:
			var height: float = minf(stripe, area.end.y - y)
			draw_colored_polygon(IsoSpace.polygon(Rect2(area.position.x, y, area.size.x, height)), paint)
			y += stripe + gap
