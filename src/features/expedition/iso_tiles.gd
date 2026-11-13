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
	queue_redraw()


func _stamp_rects(rows: Array, name: String) -> void:
	for row: Variant in rows:
		_stamp_rect(WorldLayout.rect(row) if row is Array else row, name)


func _store_crosswalks(rows: Array, axis: String) -> void:
	for row: Variant in rows:
		_crosswalks.append({"rect": WorldLayout.rect(row) if row is Array else row, "axis": axis})


func _stamp_rect(area: Rect2, name: String) -> void:
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
				cells[Vector2i(x, y)] = name


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
