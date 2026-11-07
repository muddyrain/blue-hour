class_name PumpStationArt
extends Node2D
## Original project linework. The caller provides collision footprint and console foot.

const BUS: Texture2D = preload("res://assets/candidates/bus_02.png")
const INK: Color = Color("182631")
const STEEL: Color = Color("465c6b")
const LIT_STEEL: Color = Color("728590")
const CONCRETE: Color = Color("64717b")
const LAMP: Color = Color("ffc16e")
const VICTORY_SIZE: Vector2 = Vector2(1000, 550)

var _console: CabinetView


static func draw_victory(canvas: CanvasItem, area: Rect2) -> void:
	if not area.has_area():
		return
	canvas.draw_set_transform(area.position, 0.0, area.size / VICTORY_SIZE)
	for strip: int in range(44):
		var sky: Color = Color("14283d").lerp(Color("4a6578"), float(strip) / 44.0)
		canvas.draw_rect(Rect2(0, strip * 12.5, 1000, 12.6), sky)
	_skyline(canvas)
	canvas.draw_rect(Rect2(0, 292, 1000, 258), Color("344957"))
	canvas.draw_rect(Rect2(0, 403, 1000, 147), Color("283d50"))
	canvas.draw_line(Vector2(0, 404), Vector2(1000, 404), Color("82939c"), 4.0)
	canvas.draw_line(Vector2(0, 414), Vector2(1000, 414), Color("4e6271"), 3.0)
	for mark: int in range(13):
		var x: float = 18.0 + mark * 77.0
		canvas.draw_line(Vector2(x, 517), Vector2(x + 34.0, 517), Color("7a7865"), 2.0)
	_surface_marks(canvas, Rect2(0, 299, 1000, 250), 122)
	canvas.draw_set_transform(area.position + Vector2(286, 305) * (area.size / VICTORY_SIZE),
		0.0, area.size / VICTORY_SIZE)
	_draw_house(canvas, 420.0, 142.0)
	_draw_cabinet(canvas, Vector2(185, 23), true)
	canvas.draw_set_transform(area.position, 0.0, area.size / VICTORY_SIZE)
	_draw_parapet(canvas, Rect2(0, 351, 358, 38))
	_draw_parapet(canvas, Rect2(538, 351, 462, 38))
	_draw_gate_lamp(canvas, Vector2(356, 382))
	_draw_gate_lamp(canvas, Vector2(540, 382))
	for i: int in range(9):
		var softness: float = float(i) / 8.0
		var x: float = 551.0 - 94.0 * softness
		_polygon(canvas, [Vector2(690, 507), Vector2(x, 479 - softness * 18),
			Vector2(x - 18, 526 + softness * 13), Vector2(698, 520)],
			Color(1.0, 0.62, 0.28, 0.026))
	var picture_scale: Vector2 = area.size / VICTORY_SIZE
	# Mirror the registered sprite so the headlights point out through the departure lane.
	canvas.draw_set_transform(area.position + Vector2(947, 0) * picture_scale, 0.0,
		Vector2(-picture_scale.x, picture_scale.y))
	canvas.draw_texture_rect_region(BUS, Rect2(0, 422, 266, 121), Rect2(32, 84, 448, 204))
	canvas.draw_set_transform(area.position, 0.0, picture_scale)
	for x: int in [727, 769, 812, 857, 897]:
		canvas.draw_rect(Rect2(x, 486, 19, 7), Color(1.0, 0.72, 0.36, 0.29))
	canvas.draw_line(Vector2(689, 513), Vector2(697, 513), LAMP, 3.0, true)
	canvas.draw_set_transform(Vector2.ZERO)


static func _skyline(canvas: CanvasItem) -> void:
	for i: int in range(16):
		var x: float = i * 63.0
		var top: float = 104.0 + 18.0 * sin(i * 1.6) + 21.0 * cos(i * 0.65)
		canvas.draw_rect(Rect2(x, top, minf(64.0, 1000.0 - x), 292 - top), Color("283c50"))
	for i: int in range(12):
		var x: float = 592.0 + i * 33.0
		canvas.draw_line(Vector2(x, 109), Vector2(x, 164), Color("637e8d"), 1.0)
		canvas.draw_line(Vector2(x, 121), Vector2(x, 124), Color("c3a581"), 2.0)
	canvas.draw_rect(Rect2(574, 152, 426, 124), Color("526576"))
	canvas.draw_line(Vector2(574, 115), Vector2(1000, 115), Color("627d8d"), 2.0)
	canvas.draw_line(Vector2(574, 130), Vector2(1000, 130), Color("627d8d"), 2.0)
	for bay: int in range(3):
		var x: float = 604.0 + bay * 134.0
		canvas.draw_rect(Rect2(x, 167, 102, 103), Color("1e3244"))
		for stream: int in range(17):
			var origin: Vector2 = Vector2(x + stream * 6, 187)
			var end: Vector2 = origin + Vector2(-12.0 + sin(stream * 1.5) * 7.0, 85.0)
			canvas.draw_line(origin, end, Color(0.48, 0.65, 0.76, 0.19 + 0.09 * cos(stream)), 2.0, true)
	canvas.draw_rect(Rect2(568, 273, 432, 19), Color("466273"))
	for i: int in range(24):
		var x: float = 571.0 + i * 17.0
		canvas.draw_line(Vector2(x, 283 + i % 3 * 2), Vector2(x + 12, 283 + i % 3 * 2),
			Color(0.63, 0.78, 0.80, 0.34), 1.0)


static func _draw_house(canvas: CanvasItem, width: float, depth: float) -> void:
	var left: float = -width / 2.0
	var right: float = width / 2.0
	var eave: float = -depth * 0.61
	var ridge: float = eave - depth * 0.37
	var base: Rect2 = Rect2(left, eave, width, -eave)
	canvas.draw_rect(base.grow(2.0), INK)
	canvas.draw_rect(base, CONCRETE)
	_surface_marks(canvas, base, 83)
	canvas.draw_rect(Rect2(left, -14, width, 14), Color("4b5963"))
	canvas.draw_line(Vector2(left, 0), Vector2(right, 0), Color("839198"), 2.0)
	for seam: int in range(12):
		var x: float = left + width * seam / 12.0
		canvas.draw_line(Vector2(x, eave), Vector2(x, -2), Color(0.14, 0.21, 0.27, 0.26), 1.0)
	_polygon(canvas, [Vector2(left - 12, eave), Vector2(left + 12, ridge),
		Vector2(right - 9, ridge), Vector2(right + 12, eave)], Color("293f54"))
	for seam: int in range(23):
		var progress: float = float(seam) / 22.0
		var origin: Vector2 = Vector2(lerpf(left + 12, right - 9, progress), ridge + 2)
		var end: Vector2 = Vector2(lerpf(left - 10, right + 10, progress), eave - 2)
		canvas.draw_line(origin, end, Color("435a70"), 1.5, true)
		canvas.draw_line(origin + Vector2(3, 0), end + Vector2(3, 0), Color("223445"), 1.0, true)
	_surface_marks(canvas, Rect2(left + 14, ridge + 3, width - 27, eave - ridge - 6), 90)
	for progress: float in [0.30, 0.76]:
		var vent: Vector2 = Vector2(left + width * progress, ridge + 17.0)
		canvas.draw_rect(Rect2(vent + Vector2(-19, -9), Vector2(41, 19)), Color("1d2f41"))
		canvas.draw_rect(Rect2(vent + Vector2(-17, -12), Vector2(35, 16)), Color("5a7180"))
		for slit: int in range(4):
			canvas.draw_line(vent + Vector2(-14, slit * 3 - 9), vent + Vector2(14, slit * 3 - 9), INK, 1.3)
	canvas.draw_line(Vector2(left - 12, eave), Vector2(right + 12, eave), Color("253747"), 7.0)
	canvas.draw_line(Vector2(left - 8, eave - 3), Vector2(right + 8, eave - 3), Color("566a7b"), 2.0)
	var stack_x: float = left + 24.0
	_pipe(canvas, PackedVector2Array([Vector2(stack_x, -2), Vector2(stack_x, eave + 8),
		Vector2(stack_x + 17, eave - 7), Vector2(stack_x + 53, eave - 7)]), 20.0)
	for bay: int in range(3):
		var x: float = left + width * (0.30 + 0.27 * bay)
		_draw_bay(canvas, Vector2(x, 0), width * 0.19, -eave)


static func _draw_bay(canvas: CanvasItem, foot: Vector2, width: float, height: float) -> void:
	var pane: Rect2 = Rect2(foot.x - width * 0.51, -height + 9, width * 1.02, height * 0.20)
	canvas.draw_rect(pane.grow(2), INK)
	canvas.draw_rect(pane, Color("8e7358"))
	for i: int in range(4):
		var x: float = pane.position.x + i * width * 0.25
		canvas.draw_rect(Rect2(x + 1, pane.position.y + 1, width * 0.13, pane.size.y - 2),
			Color(1.0, 0.72, 0.39, 0.29 if i % 2 == 0 else 0.16))
		canvas.draw_line(Vector2(x, pane.position.y), Vector2(x, pane.end.y), INK, 2.0)
	var frame: Rect2 = Rect2(foot.x - width * 0.43, -height * 0.58, width * 0.86, height * 0.56)
	canvas.draw_rect(frame.grow(4), Color("455763"))
	canvas.draw_rect(frame, Color("253747"))
	_pipe(canvas, PackedVector2Array([Vector2(foot.x - width * 0.22, -5),
		Vector2(foot.x - width * 0.22, -height * 0.24), Vector2(foot.x, -height * 0.38),
		Vector2(foot.x + width * 0.20, -height * 0.38)]), clampf(width * 0.21, 12.0, 25.0))
	for rail: int in range(2):
		var y: float = -5.0 - rail * 11.0
		canvas.draw_line(Vector2(frame.position.x, y), Vector2(frame.end.x, y), Color("b18b55"), 2.0, true)
	for i: int in range(4):
		var x: float = frame.position.x + frame.size.x * float(i) / 3.0
		canvas.draw_line(Vector2(x, -1), Vector2(x, -16), Color("7e6547"), 2.0)
	var lamp: Vector2 = Vector2(foot.x, -height * 0.62)
	_glow(canvas, lamp + Vector2(0, 8), Vector2(width * 0.49, height * 0.35), LAMP)
	canvas.draw_rect(Rect2(lamp - Vector2(7, 2), Vector2(14, 3)), Color("ffe0ab"))


static func _draw_cabinet(canvas: CanvasItem, foot: Vector2, stopped: bool) -> void:
	var top: Vector2 = foot + Vector2(0, -51)
	var active: Color = Color("93d6c0") if stopped else LAMP
	canvas.draw_rect(Rect2(foot + Vector2(-23, -5), Vector2(46, 9)), Color("253744"))
	canvas.draw_rect(Rect2(top + Vector2(-21, 0), Vector2(42, 48)), Color("263642"))
	canvas.draw_rect(Rect2(top + Vector2(-18, 3), Vector2(36, 41)), Color("53636a"))
	_polygon(canvas, [top + Vector2(-21, 0), top + Vector2(-12, -7), top + Vector2(26, -7),
		top + Vector2(21, 0)], Color("7b898d"))
	_polygon(canvas, [top + Vector2(21, 0), top + Vector2(26, -7), top + Vector2(26, 39),
		top + Vector2(21, 48)], Color("313f46"))
	canvas.draw_rect(Rect2(top + Vector2(-13, 7), Vector2(26, 17)), INK)
	_glow(canvas, top + Vector2(0, 11), Vector2(23, 14), active)
	canvas.draw_rect(Rect2(top + Vector2(-9, 11), Vector2(18, 7)), active)
	for i: int in range(3):
		var x: float = i * 8.0 - 8.0
		canvas.draw_circle(top + Vector2(x, 30), 2.1, active if i == 0 else Color("263845"), true)
	var lever: Vector2 = top + Vector2(10, 34)
	canvas.draw_line(lever, lever + (Vector2(-7, 5) if stopped else Vector2(5, -8)), INK, 3.0, true)
	canvas.draw_circle(lever, 2.5, Color("8a9694"), true)
	if stopped:
		canvas.draw_line(top + Vector2(-5, 14), top + Vector2(-1, 17), INK, 2.0)
		canvas.draw_line(top + Vector2(-1, 17), top + Vector2(5, 12), INK, 2.0)
	else:
		canvas.draw_line(top + Vector2(0, 12), top + Vector2(0, 17), INK, 2.0)


static func _draw_parapet(canvas: CanvasItem, wall: Rect2) -> void:
	canvas.draw_rect(wall, Color("455665"))
	canvas.draw_rect(Rect2(wall.position, Vector2(wall.size.x, 5)), Color("708089"))
	for joint: int in range(int(wall.size.x / 26.0)):
		var x: float = wall.position.x + joint * 26.0 + 12.0
		canvas.draw_line(Vector2(x, wall.position.y + 5), Vector2(x, wall.end.y), Color("354653"), 1.0)
	canvas.draw_line(Vector2(wall.position.x, wall.end.y), wall.end, Color("22323f"), 3.0)


static func _draw_gate_lamp(canvas: CanvasItem, foot: Vector2) -> void:
	canvas.draw_rect(Rect2(foot + Vector2(-4, -41), Vector2(8, 41)), Color("374955"))
	_glow(canvas, foot + Vector2(0, -11), Vector2(37, 38), LAMP)
	canvas.draw_rect(Rect2(foot + Vector2(-4, -34), Vector2(8, 11)), Color("ffe2ab"))


static func _pipe(canvas: CanvasItem, route: PackedVector2Array, width: float) -> void:
	canvas.draw_polyline(route, INK, width + 4.0, true)
	canvas.draw_polyline(route, STEEL, width, true)
	var gleam: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in route:
		gleam.append(point + Vector2(-width * 0.18, -width * 0.18))
	canvas.draw_polyline(gleam, LIT_STEEL, width * 0.22, true)
	for i: int in range(1, route.size()):
		var direction: Vector2 = (route[i] - route[i - 1]).normalized()
		var band: Vector2 = direction.orthogonal() * (width * 0.52)
		var ring: Vector2 = route[i - 1].lerp(route[i], 0.31)
		canvas.draw_line(ring - band, ring + band, Color("825c47"), 3.0, true)


static func _glow(canvas: CanvasItem, center: Vector2, radius: Vector2, hue: Color) -> void:
	for layer: int in range(5, 0, -1):
		var fraction: float = float(layer) / 5.0
		var ring: PackedVector2Array = PackedVector2Array()
		for sample: int in range(20):
			var phase: float = TAU * float(sample) / 20.0
			ring.append(center + Vector2(cos(phase), sin(phase)) * radius * fraction)
		canvas.draw_colored_polygon(ring, Color(hue.r, hue.g, hue.b, 0.048))


static func _surface_marks(canvas: CanvasItem, area: Rect2, count: int) -> void:
	for i: int in range(count):
		var fx: float = float(posmod(i * 241 + 43, 997)) / 997.0
		var fy: float = float(posmod(i * 157 + 19, 919)) / 919.0
		var point: Vector2 = area.position + area.size * Vector2(fx, fy)
		var length: float = minf(3.0 + i % 13, area.end.x - point.x)
		var hue: Color = Color(0.76, 0.73, 0.65, 0.13) if i % 3 == 0 else Color(0.14, 0.20, 0.26, 0.22)
		canvas.draw_line(point, point + Vector2(length, 0), hue, 1.0)


static func _polygon(canvas: CanvasItem, points: Array[Vector2], hue: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array(points), hue)


func configure(power_house: Rect2, console_at: Vector2, stopped: bool = false) -> void:
	y_sort_enabled = true
	var house: HouseView = HouseView.new()
	house.width = power_house.size.x
	house.depth = power_house.size.y
	house.position = Vector2(power_house.get_center().x, power_house.end.y)
	add_child(house)
	_console = CabinetView.new()
	_console.position = console_at
	_console.stopped = stopped
	add_child(_console)


func set_stopped(stopped: bool) -> void:
	if _console != null and _console.stopped != stopped:
		_console.stopped = stopped
		_console.queue_redraw()


class HouseView extends Node2D:
	var width: float
	var depth: float

	func _draw() -> void:
		PumpStationArt._draw_house(self, width, depth)


class CabinetView extends Node2D:
	var stopped: bool

	func _draw() -> void:
		PumpStationArt._draw_cabinet(self, Vector2.ZERO, stopped)
