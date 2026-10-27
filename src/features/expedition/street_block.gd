class_name StreetBlock
extends Node2D
## Authored ground is presentation; the same layout supplies every navigation blocker.

const BOUNDS: Rect2 = Rect2(0, 0, 1920, 1440)
const AsphaltTexture: Texture2D = preload("res://assets/m402/asphalt.png")
const PavingTexture: Texture2D = preload("res://assets/m402/paving.png")
const GrassTexture: Texture2D = preload("res://assets/m402/grass.png")
const ConcreteTexture: Texture2D = preload("res://assets/m402/concrete.png")

var layout: StreetLayout
var food_source_visible: bool = true


func _draw() -> void:
	draw_rect(BOUNDS, Color("718478"))
	draw_texture_rect(GrassTexture, BOUNDS, true, Color(0.91, 1.0, 0.96, 0.24))
	# Connected public yards replace per-building rectangular mats.
	for yard: Rect2 in layout.yards:
		draw_rect(yard, Color("9ba89a"))
		draw_texture_rect(ConcreteTexture, yard, true, Color(0.94, 1.0, 0.96, 0.32))
	for road: Rect2 in layout.roads:
		draw_rect(road.grow(32), Color("a7b1a0"))
		draw_texture_rect(PavingTexture, road.grow(32), true, Color(1, 1, 1, 0.40))
	for road: Rect2 in layout.roads:
		draw_rect(road, Color("40555e"))
		draw_texture_rect(AsphaltTexture, road, true, Color(0.90, 1.0, 1.0, 0.38))
	for road: Rect2 in layout.roads:
		_draw_markings(road)
	for door: Vector2 in [layout.cash_door, layout.food_door]:
		if door == layout.food_door and not food_source_visible:
			continue
		var colour: Color = Color("e3c879") if door == layout.food_door else Color("8acbc0")
		draw_circle(door, 18, Color(colour, 0.12))
		draw_arc(door, 18, 0, TAU, 32, colour, 2)
		for step: int in range(3):
			var point: Vector2 = door + Vector2(30 + step * 22, 0)
			draw_line(point, point + Vector2(10, 0), Color("c5c5a3"), 2)
	var parking: Rect2 = layout.bus_block.grow(24)
	for corner: Vector2 in [parking.position, Vector2(parking.end.x, parking.position.y), parking.end, Vector2(parking.position.x, parking.end.y)]:
		var inward: Vector2 = (parking.get_center() - corner).sign()
		draw_line(corner, corner + Vector2(inward.x * 20, 0), Color("cad0b3"), 2)
		draw_line(corner, corner + Vector2(0, inward.y * 16), Color("cad0b3"), 2)
	draw_line(layout.bus_door + Vector2(44, 0), layout.bus_door + Vector2(16, 0), Color("e1c78f"), 3)
	draw_line(layout.bus_door + Vector2(16, 0), layout.bus_door + Vector2(24, -7), Color("e1c78f"), 3)
	draw_line(layout.bus_door + Vector2(16, 0), layout.bus_door + Vector2(24, 7), Color("e1c78f"), 3)
	draw_rect(BOUNDS.grow(-3), Color("536f6b"), false, 6)


func _draw_markings(road: Rect2) -> void:
	var horizontal: bool = road.size.x > road.size.y
	var count: int = int((road.size.x if horizontal else road.size.y) / 88)
	for index: int in range(count):
		var point: Vector2 = Vector2(road.position.x + 16 + index * 88, road.get_center().y) if horizontal else Vector2(road.get_center().x, road.position.y + 16 + index * 88)
		var at_junction: bool = false
		for other: Rect2 in layout.roads:
			if other != road and other.grow(32).has_point(point):
				at_junction = true
		if not at_junction:
			draw_line(point, point + (Vector2(36, 0) if horizontal else Vector2(0, 36)), Color("cebd8b"), 2)
	# A few verge leaves and drainage grooves, all flat and traversable.
	for index: int in range(count):
		var point: Vector2 = road.position + (Vector2(24 + index * 88, -15) if horizontal else Vector2(-15, 24 + index * 88))
		draw_line(point, point + Vector2(5, 2), Color("9b956b"), 2)
		if index % 5 == 0:
			draw_rect(Rect2(point + Vector2(8, 2), Vector2(18, 10)), Color("62746e"))
			for groove: int in range(3):
				draw_line(point + Vector2(11 + groove * 5, 3), point + Vector2(11 + groove * 5, 10), Color("384f54"), 1)
