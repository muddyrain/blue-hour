class_name HarborGround
extends Node2D
## Flat quay masonry, fenders and working-area paint. The layout owns collision.

var layout: StreetLayout
var _water_clock: float = 0.0
var _water_refresh: float = 0.0


func _ready() -> void:
	z_index = -9


func _process(delta: float) -> void:
	_water_clock += delta
	_water_refresh += delta
	# Only this small ground overlay redraws, at ten Hz; the tile layer stays cached.
	if _water_refresh >= 0.1:
		_water_refresh = fmod(_water_refresh, 0.1)
		queue_redraw()


func _draw() -> void:
	if layout == null:
		return
	var shimmer: float = 0.12 + 0.06 * sin(_water_clock * 0.24)
	# Ordinary canvas colour follows the existing night tint; no emissive layer.
	for ripple: PackedVector2Array in water_ripples(_water_clock):
		draw_polyline(ripple, Color(0.62, 0.73, 0.73, shimmer), 1.2, true)
	var edge: Color = Color("c6c3a8")
	for segment: Vector2 in [Vector2(0, 384), Vector2(576, 1024), Vector2(1184, 1312)]:
		_line(Vector2(1792, segment.x), Vector2(1792, segment.y), edge, 5.0)
		for y: int in range(int(segment.x) + 16, int(segment.y), 40):
			_line(Vector2(1792, y), Vector2(1802, y + 12), Color("657c7d"), 4.0)
	for pier: Rect2 in [Rect2(1792, 384, 384, 192), Rect2(1792, 1024, 512, 160)]:
		var poly: PackedVector2Array = IsoSpace.polygon(pier)
		draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), edge, 3.0, true)
		for x: int in range(int(pier.position.x) + 48, int(pier.end.x), 64):
			_line(Vector2(x, pier.end.y), Vector2(x, pier.end.y + 8), Color("455655"), 6.0)
	# Apron seams use the same axes as the roofs; they never resemble a road.
	for x: int in range(480, 1792, 128):
		_line(Vector2(x, 40), Vector2(x, 1312), Color(0.30, 0.36, 0.34, 0.20), 1.0)
	for y: int in range(64, 1312, 128):
		_line(Vector2(448, y), Vector2(1792, y), Color(0.30, 0.36, 0.34, 0.20), 1.0)
	for x: int in range(1504, 1760, 32):
		_line(Vector2(x, 576), Vector2(x + 16, 560), Color("d4b776"), 3.0)
	for area: Rect2 in [Rect2(96, 1424, 172, 64), Rect2(1504, 576, 256, 224)]:
		var poly: PackedVector2Array = IsoSpace.polygon(area)
		draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), Color("d7c494"), 1.5, true)
	# The southern seawall ends above the through road, so the bus never drives on water.
	_line(Vector2(1792, 1312), Vector2(2560, 1312), edge, 5.0)


func water_ripples(at: float) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if layout == null:
		return result
	for row: Array in layout.world_data.grounds.harbor_water:
		var sea: Rect2 = WorldLayout.rect(row)
		for y: int in range(int(sea.position.y) + 24, int(sea.end.y) - 24, 88):
			for x: int in range(int(sea.position.x) + 24, int(sea.end.x) - 80, 128):
				var phase: float = at * 0.20 + float(x) * 0.031 + float(y) * 0.017
				var drift: Vector2 = Vector2(sin(phase) * 9.0, cos(phase * 0.8) * 8.0)
				var span: Rect2 = Rect2(Vector2(x, y) + drift - Vector2(2, 5), Vector2(48, 10))
				var on_pier: bool = false
				for pier: Array in layout.world_data.grounds.harbor_wood:
					if WorldLayout.rect(pier).grow(8.0).intersects(span):
						on_pier = true
						break
				if on_pier:
					continue
				var points: PackedVector2Array = PackedVector2Array()
				for step: int in range(5):
					var point: Vector2 = Vector2(x + step * 11, y) + drift
					point.y += sin(phase + float(step) * 0.7) * 2.5
					points.append(IsoSpace.to_view(point))
				result.append(points)
	return result


func _line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	draw_line(IsoSpace.to_view(from), IsoSpace.to_view(to), color, width, true)
