class_name IsoTiles
extends Node2D
## Paints a 2:1 diamond grid from authored or inferred ground kinds.

const TILE: float = 64.0
var layout: StreetLayout
var cells: Dictionary = {} # Vector2i -> String tile name


func _ready() -> void:
	z_index = -10
	if layout != null and cells.is_empty():
		fill_from_layout(layout)
	queue_redraw()


func fill_from_layout(source: StreetLayout) -> void:
	layout = source
	cells.clear()
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
		var name: String = "road_ew" if road.size.x >= road.size.y else "road_ns"
		_stamp_rect(road, name)
	_stamp_rects(grounds.get("crosswalks_ew", []), "crosswalk_ew")
	_stamp_rects(grounds.get("crosswalks_ns", []), "crosswalk_ns")
	_stamp_rects(grounds.get("road", []), "road")
	queue_redraw()


func _stamp_rects(rows: Array, name: String) -> void:
	for row: Variant in rows:
		_stamp_rect(WorldLayout.rect(row) if row is Array else row, name)


func _stamp_rect(area: Rect2, name: String) -> void:
	var min_c: Vector2i = Vector2i(int(floor(area.position.x / TILE)), int(floor(area.position.y / TILE)))
	var max_c: Vector2i = Vector2i(int(ceil(area.end.x / TILE)) - 1, int(ceil(area.end.y / TILE)) - 1)
	for y: int in range(min_c.y, max_c.y + 1):
		for x: int in range(min_c.x, max_c.x + 1):
			var cell: Rect2 = Rect2(Vector2(x, y) * TILE, Vector2(TILE, TILE))
			if cell.intersects(area):
				cells[Vector2i(x, y)] = name


func _draw() -> void:
	for cell: Vector2i in cells:
		IsoAtlas.stamp_cell(self, "tiles/%s.png" % cells[cell], cell, TILE)
