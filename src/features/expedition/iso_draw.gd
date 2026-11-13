class_name IsoDraw
extends RefCounted
## Procedural 2:1 placeholder art. Not a stretch of the old top-down textures.

const GRASS: Color = Color("6f9a62")
const GRASS_LINE: Color = Color("5c8652", 0.35)
const SIDEWALK: Color = Color("c4bba8")
const ASPHALT: Color = Color("4a5560")
const MARKING: Color = Color("d8d0b0")
const COURT: Color = Color("9aa392")
const AMBER: Color = Color("d9a24a")
const WALL_LEFT: Color = Color("d7cbb4")
const WALL_RIGHT: Color = Color("b9ad96")
const ROOF: Color = Color("6a5c52")
const SHOP_LEFT: Color = Color("efe7d4")
const SHOP_RIGHT: Color = Color("cfc4ab")
const SHOP_ROOF: Color = Color("3f6b4e")
const WARE_LEFT: Color = Color("b7c0c4")
const WARE_RIGHT: Color = Color("8f9aa0")
const WARE_ROOF: Color = Color("4d5a66")


static func fill(canvas: CanvasItem, map_rect: Rect2, color: Color) -> void:
	canvas.draw_colored_polygon(IsoSpace.polygon(map_rect), color)


static func stroke(canvas: CanvasItem, map_rect: Rect2, color: Color, width: float = 1.0) -> void:
	var poly: PackedVector2Array = IsoSpace.polygon(map_rect)
	for index: int in range(poly.size()):
		canvas.draw_line(poly[index], poly[(index + 1) % poly.size()], color, width, true)


static func grid(canvas: CanvasItem, bounds: Rect2, step: float, color: Color) -> void:
	var x: float = bounds.position.x
	while x <= bounds.end.x + 0.5:
		canvas.draw_line(IsoSpace.to_view(Vector2(x, bounds.position.y)), IsoSpace.to_view(Vector2(x, bounds.end.y)), color, 1.0, true)
		x += step
	var y: float = bounds.position.y
	while y <= bounds.end.y + 0.5:
		canvas.draw_line(IsoSpace.to_view(Vector2(bounds.position.x, y)), IsoSpace.to_view(Vector2(bounds.end.x, y)), color, 1.0, true)
		y += step


static func ground(canvas: CanvasItem, layout: StreetLayout, doors: Array[Vector2] = [], food_visible: bool = true) -> void:
	var bounds: Rect2 = layout.world_bounds if layout.world_bounds.size.x > 0.0 else StreetBlock.BOUNDS
	fill(canvas, bounds, GRASS)
	grid(canvas, bounds, 48.0, GRASS_LINE)
	for yard: Rect2 in layout.yards:
		fill(canvas, yard, COURT)
		stroke(canvas, yard, Color("7f8778"), 1.0)
	if not layout.world_data.is_empty():
		for row: Dictionary in layout.world_data.get("entities", []):
			var body: Rect2 = WorldLayout.rect(row.rect)
			var court: Rect2 = Rect2(body.position - Vector2(24, 16), body.size + Vector2(48, 100))
			fill(canvas, court, Color("8b9890"))
	for road: Rect2 in layout.roads:
		fill(canvas, road.grow(32), SIDEWALK)
	for road: Rect2 in layout.roads:
		fill(canvas, road, ASPHALT)
		_markings(canvas, layout, road)
	_crossings(canvas, layout)
	for door: Vector2 in doors:
		if door == layout.food_door and not food_visible:
			continue
		_marker(canvas, door, AMBER if door == layout.food_door else Color("8acbc0"))
	if layout.bus_block.size.x > 0.0:
		stroke(canvas, layout.bus_block.grow(14), Color("ddd2a3"), 2.0)
	stroke(canvas, bounds, Color("3e5348"), 3.0)


static func marker(canvas: CanvasItem, map_point: Vector2, color: Color = AMBER) -> void:
	_marker(canvas, map_point, color)


static func box(canvas: CanvasItem, size: Vector2, height: float, roof: Color, left: Color, right: Color, roof_alpha: float = 1.0) -> void:
	# Local origin is the south-edge center already projected to view.
	var w: float = maxf(size.x, 24.0)
	var d: float = maxf(size.y, 20.0)
	var sw: Vector2 = IsoSpace.to_view(Vector2(-w * 0.5, 0))
	var se: Vector2 = IsoSpace.to_view(Vector2(w * 0.5, 0))
	var nw: Vector2 = IsoSpace.to_view(Vector2(-w * 0.5, -d))
	var ne: Vector2 = IsoSpace.to_view(Vector2(w * 0.5, -d))
	var up: Vector2 = Vector2(0, -height)
	var roof_c: Color = Color(roof, roof_alpha)
	canvas.draw_colored_polygon(PackedVector2Array([sw, se, se + up, sw + up]), Color(0.12, 0.1, 0.08, 0.22))
	canvas.draw_colored_polygon(PackedVector2Array([sw, nw, nw + up, sw + up]), left)
	canvas.draw_colored_polygon(PackedVector2Array([se, ne, ne + up, se + up]), right)
	canvas.draw_colored_polygon(PackedVector2Array([sw + up, se + up, ne + up, nw + up]), roof_c)
	canvas.draw_line(sw + up, se + up, Color(roof_c, 0.9), 1.0, true)
	canvas.draw_line(se + up, ne + up, Color(0, 0, 0, 0.18), 1.0, true)
	canvas.draw_line(nw + up, ne + up, Color(0, 0, 0, 0.18), 1.0, true)
	canvas.draw_line(sw + up, nw + up, Color(1, 1, 1, 0.12), 1.0, true)


static func shop_stripe(canvas: CanvasItem, size: Vector2, height: float, color: Color) -> void:
	var w: float = maxf(size.x, 24.0)
	var d: float = maxf(size.y, 20.0)
	var se: Vector2 = IsoSpace.to_view(Vector2(w * 0.5, 0))
	var ne: Vector2 = IsoSpace.to_view(Vector2(w * 0.5, -d))
	var up0: Vector2 = Vector2(0, -height * 0.42)
	var up1: Vector2 = Vector2(0, -height * 0.62)
	canvas.draw_colored_polygon(PackedVector2Array([se + up0, ne + up0, ne + up1, se + up1]), color)


static func bus(canvas: CanvasItem) -> void:
	# Cream minibus, ~148x48 logical, cab toward -x. Not a school bus.
	var size: Vector2 = Vector2(148, 48)
	box(canvas, size, 44, Color("8a9096"), Color("efe6d4"), Color("d2c8b4"))
	var w: float = 148.0
	var d: float = 48.0
	var se: Vector2 = IsoSpace.to_view(Vector2(w * 0.5, 0))
	var ne: Vector2 = IsoSpace.to_view(Vector2(w * 0.5, -d))
	var sw: Vector2 = IsoSpace.to_view(Vector2(-w * 0.5, 0))
	var cab0: Vector2 = Vector2(0, -18)
	var cab1: Vector2 = Vector2(0, -34)
	canvas.draw_colored_polygon(PackedVector2Array([
		IsoSpace.to_view(Vector2(-w * 0.08, 0)) + cab0,
		IsoSpace.to_view(Vector2(w * 0.48, 0)) + cab0,
		IsoSpace.to_view(Vector2(w * 0.48, 0)) + cab1,
		IsoSpace.to_view(Vector2(-w * 0.08, 0)) + cab1,
	]), Color("8fb4c4", 0.85))
	# Wheels
	for offset: float in [-40.0, 36.0]:
		var at: Vector2 = IsoSpace.to_view(Vector2(offset, 6))
		canvas.draw_circle(at, 6, Color("2a2c30"))
		canvas.draw_circle(at + IsoSpace.to_view(Vector2(0, -d)), 5, Color("2a2c30"))
	# Headlight warm dots on the cab end
	canvas.draw_circle(se + Vector2(2, -14), 3, Color("ffa64a"))
	canvas.draw_circle(ne + Vector2(2, -14), 3, Color("ffa64a"))
	canvas.draw_circle((sw + se) * 0.5 + Vector2(0, -48), 3, Color("d9a24a"))


static func lamp(canvas: CanvasItem) -> void:
	canvas.draw_line(Vector2(0, 0), Vector2(0, -54), Color("5a5e62"), 3.0, true)
	canvas.draw_circle(Vector2(0, -58), 7, Color("d9a24a"))
	canvas.draw_circle(Vector2(0, -58), 4, Color("ffe2a8"))


static func tree(canvas: CanvasItem) -> void:
	canvas.draw_rect(Rect2(-3, -18, 6, 18), Color("5a4332"))
	canvas.draw_circle(Vector2(0, -28), 16, Color("3f6b45"))
	canvas.draw_circle(Vector2(-8, -24), 11, Color("4a7c4e"))
	canvas.draw_circle(Vector2(8, -22), 10, Color("35603c"))


static func vending(canvas: CanvasItem) -> void:
	box(canvas, Vector2(22, 16), 36, Color("3a3f45"), Color("c8553d"), Color("a34638"))
	canvas.draw_rect(Rect2(-6, -28, 12, 10), Color("8ec0e0", 0.8))


static func planter(canvas: CanvasItem) -> void:
	box(canvas, Vector2(28, 18), 10, Color("6a5c52"), Color("8a7a68"), Color("6e6050"))
	canvas.draw_circle(Vector2(0, -16), 8, Color("4a7c4e"))


static func crate(canvas: CanvasItem) -> void:
	box(canvas, Vector2(22, 18), 16, Color("8a6a40"), Color("c4a06a"), Color("a88852"))


static func wall(canvas: CanvasItem, length: float, thickness: float = 14.0) -> void:
	box(canvas, Vector2(maxf(length, 16.0), thickness), 22, Color("8b8680"), Color("c2bbb2"), Color("9b948c"))


static func _markings(canvas: CanvasItem, layout: StreetLayout, road: Rect2) -> void:
	var horizontal: bool = road.size.x > road.size.y
	var count: int = maxi(1, int((road.size.x if horizontal else road.size.y) / 88.0))
	for index: int in range(count):
		var point: Vector2 = Vector2(road.position.x + 16 + index * 88, road.get_center().y) if horizontal else Vector2(road.get_center().x, road.position.y + 16 + index * 88)
		var at_junction: bool = false
		for other: Rect2 in layout.roads:
			if other != road and other.grow(32).has_point(point):
				at_junction = true
		if not at_junction:
			var along: Vector2 = Vector2(28, 0) if horizontal else Vector2(0, 28)
			canvas.draw_line(IsoSpace.to_view(point), IsoSpace.to_view(point + along), MARKING, 2.0, true)


static func _crossings(canvas: CanvasItem, layout: StreetLayout) -> void:
	if layout.world_data.is_empty():
		return
	# Existing authored crossings on the large street maps; skip if off this layout.
	for x: int in [560, 1184, 1840]:
		if not layout.world_bounds.has_point(Vector2(x, 1240)):
			continue
		for stripe: int in range(8):
			fill(canvas, Rect2(x - 52, 1130 + stripe * 27, 40, 12), Color("b9bba8"))


static func _marker(canvas: CanvasItem, map_point: Vector2, color: Color) -> void:
	var diamond: PackedVector2Array = PackedVector2Array([
		IsoSpace.to_view(map_point + Vector2(0, -12)),
		IsoSpace.to_view(map_point + Vector2(14, 0)),
		IsoSpace.to_view(map_point + Vector2(0, 12)),
		IsoSpace.to_view(map_point + Vector2(-14, 0)),
	])
	canvas.draw_colored_polygon(diamond, Color(color, 0.22))
	for index: int in range(4):
		canvas.draw_line(diamond[index], diamond[(index + 1) % 4], color, 1.5, true)
