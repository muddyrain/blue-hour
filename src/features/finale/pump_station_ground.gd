class_name PumpStationGround
extends Node2D
## Original floor and opening markers, drawn from the collision-backed layout.

const LINE: Color = Color("a79064")
const CONCRETE: Color = Color("4a5661")

var layout: StreetLayout
var _lamp_texture: GradientTexture2D


func _ready() -> void:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.27, 0.65, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.68), Color(1, 1, 1, 0.39), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])
	_lamp_texture = GradientTexture2D.new()
	_lamp_texture.gradient = gradient
	_lamp_texture.fill = GradientTexture2D.FILL_RADIAL
	_lamp_texture.fill_from = Vector2(0.5, 0.5)
	_lamp_texture.fill_to = Vector2(1, 0.5)


func _draw() -> void:
	if layout == null:
		return
	var station: Dictionary = layout.world_data.pump_station
	IsoDraw.ground(self, layout, [], true)
	IsoDraw.fill(self, WorldLayout.rect(station.channel), Color("3a6a80"))
	IsoDraw.fill(self, WorldLayout.rect(station.yard).grow(-8), Color("4a5560"))
	IsoDraw.fill(self, WorldLayout.rect(station.arena), Color("5a656e"))
	IsoDraw.stroke(self, WorldLayout.rect(station.yard), Color("8a9096"), 1.5)
	IsoDraw.marker(self, WorldLayout.point(station.front_gate), IsoDraw.AMBER)
	IsoDraw.marker(self, WorldLayout.point(station.side_gate), Color("8acbc0"))


func _draw_channel(water: Rect2, quay_end: float) -> void:
	draw_rect(water, Color("223d50"))
	for index: int in range(92):
		var point: Vector2 = Vector2(float((index * 219) % int(water.size.x)), water.position.y + float((index * 19) % int(water.size.y)))
		var length: float = minf(float(22 + index % 9 * 6), water.end.x - point.x)
		draw_line(point, point + Vector2(length, 0), Color(0.46, 0.62, 0.70, 0.14), 1.0)
	var retaining: Rect2 = Rect2(Vector2(0, water.end.y), Vector2(water.size.x, quay_end - water.end.y))
	_paving(retaining, Color("394953"))
	draw_line(retaining.position, Vector2(retaining.end.x, retaining.position.y), Color("6c838b"), 3.0)


func _draw_road(road: Rect2) -> void:
	draw_rect(road, Color("293949"))
	draw_texture_rect(StreetBlock.AsphaltTexture, road, true, Color(0.62, 0.76, 0.92, 0.38))
	for edge: float in [road.position.y, road.end.y]:
		draw_line(Vector2(road.position.x, edge), Vector2(road.end.x, edge), Color("76858b"), 3.0)
		for step: int in range(24, int(road.size.x), 48):
			draw_line(Vector2(step, edge - 3), Vector2(step, edge + 3), Color("3b4a55"), 1.0)
	for step: int in range(24, int(road.size.x) - 60, 96):
		var start: Vector2 = Vector2(step, road.get_center().y)
		if not layout.bus_block.grow(52).has_point(start):
			draw_line(start, start + Vector2(45, 0), Color("8f8161"), 2.0)
	var bus_stop: Rect2 = layout.bus_block.grow(11)
	for corner: Vector2 in [bus_stop.position, Vector2(bus_stop.end.x, bus_stop.position.y)]:
		var direction: float = 1.0 if corner.x < bus_stop.get_center().x else -1.0
		draw_line(corner, corner + Vector2(26 * direction, 0), Color("707461"), 2.0)
	_lamp(layout.bus_foot() + Vector2(118, -29), Vector2(140, 72), 0.46)


func _draw_arena(arena: Rect2) -> void:
	_paving(arena, Color("495565"))
	var rim: Rect2 = arena.grow(-14)
	for corner: Vector2 in [rim.position, Vector2(rim.end.x, rim.position.y), Vector2(rim.position.x, rim.end.y), rim.end]:
		var direction: Vector2 = (rim.get_center() - corner).sign()
		draw_line(corner, corner + Vector2(direction.x * 42, 0), LINE, 2.0)
		draw_line(corner, corner + Vector2(0, direction.y * 31), LINE, 2.0)
	for index: int in range(4):
		var grate: Vector2 = arena.position + Vector2(30 + index * 135, arena.size.y - 31)
		_draw_grate(grate)


func _draw_front_route(station: Dictionary) -> void:
	var gate: Vector2 = WorldLayout.point(station.front_gate)
	var turn: Vector2 = WorldLayout.point(station.front_path[2])
	var half: float = float(station.front_gap) * 0.5 - 14
	var ramp: Rect2 = Rect2(Vector2(gate.x - half, turn.y), Vector2(half * 2, gate.y - turn.y + 64))
	_paving(ramp, Color("56606a"))
	for side: float in [-1.0, 1.0]:
		var x: float = gate.x + (half - 12) * side
		draw_line(Vector2(x, ramp.position.y + 15), Vector2(x, ramp.end.y - 5), Color("8e805f"), 2.0)
	for fraction: float in [0.25, 0.43, 0.60]:
		_chevron(Vector2(gate.x, ramp.position.y + ramp.size.y * fraction), Vector2.UP, 16.0, Color("aca189"))
	_draw_grate(Vector2(ramp.position.x + 14, ramp.end.y - 22))


func _draw_side_route(station: Dictionary) -> void:
	var path: Array = station.side_path
	for index: int in range(1, path.size() - 1):
		var start: Vector2 = WorldLayout.point(path[index - 1])
		var end: Vector2 = WorldLayout.point(path[index])
		var strip: Rect2 = Rect2(start, Vector2.ZERO).expand(end).grow(35)
		_paving(strip, Color("505f68"))
		if index > 1:
			_chevron(start.lerp(end, 0.56), (end - start).normalized(), 13.0, Color("a6a18c"))
	_lamp(WorldLayout.point(path[2]) + Vector2(12, 8), Vector2(110, 104), 0.40)


func _draw_gate(gate: Vector2, gap: float, front: bool) -> void:
	var x: float = gate.x - gap * 0.5
	for step: int in range(8, int(gap) - 8, 19):
		var paint: Vector2 = Vector2(x + step, gate.y + 9)
		draw_line(paint, paint + Vector2(11, -11), LINE, 3.0, true)
	for side: float in [-1.0, 1.0]:
		var lamp: Vector2 = gate + Vector2((gap * 0.5 - 6) * side, 5)
		_lamp(lamp, Vector2(102, 124) if front else Vector2(84, 104), 0.69)
		draw_rect(Rect2(lamp - Vector2(5, 8), Vector2(10, 17)), Color("2e383e"))
		draw_rect(Rect2(lamp - Vector2(3, 4), Vector2(6, 7)), Color("edb770"))


func _paving(area: Rect2, tint: Color) -> void:
	draw_rect(area, tint)
	draw_texture_rect(StreetBlock.PavingTexture, area, true, Color(0.68, 0.78, 0.94, 0.33))


func _lamp(point: Vector2, size: Vector2, alpha: float) -> void:
	draw_texture_rect(_lamp_texture, Rect2(point - size * 0.5, size), false, Color(0.97, 0.62, 0.29, alpha))


func _chevron(point: Vector2, direction: Vector2, radius: float, tint: Color) -> void:
	var side: Vector2 = direction.orthogonal() * radius
	var tip: Vector2 = point + direction * radius
	draw_polyline(PackedVector2Array([point + side, tip, point - side]), tint, 2.0, true)


func _draw_grate(point: Vector2) -> void:
	draw_rect(Rect2(point, Vector2(25, 10)), Color("262f35"))
	for x: int in range(3, 24, 4):
		draw_line(point + Vector2(x, 2), point + Vector2(x, 8), Color("6b7475"), 1.0)
