class_name IndustrialYardWall
extends Node2D
## Wall caps follow each frozen obstruction, including north-south runs.

const CAP_RISE: float = 23.0
const FACE_SAMPLE: Rect2 = Rect2(4.0, 65.0, 171.0, 55.0)
const CAP_SAMPLE: Rect2 = Rect2(30.0, 46.0, 145.0, 15.0)
const WALL_TINT: Color = Color(0.68, 0.76, 0.85)

var footprint: Rect2


func _draw() -> void:
	var base: Rect2 = Rect2(Vector2(-footprint.size.x * 0.5, -footprint.size.y), footprint.size)
	draw_rect(Rect2(base.position + Vector2(4.0, 5.0), base.size), Color(0.08, 0.12, 0.18, 0.25))
	var cap: Rect2 = Rect2(base.position - Vector2(0, CAP_RISE), base.size)
	var facade: Rect2 = Rect2(Vector2(cap.position.x, cap.end.y), Vector2(cap.size.x, CAP_RISE))
	if base.size.x >= base.size.y:
		_masonry_strip(facade, FACE_SAMPLE, 75.0)
		_masonry_strip(cap, CAP_SAMPLE, 75.0)
	else:
		# The thin end face and shaded return establish height without widening the blocker.
		draw_rect(facade, Color("555f64"))
		draw_line(Vector2(facade.position.x, -7.0), Vector2(facade.end.x, -7.0), Color("414f55"), 1.0)
		draw_rect(cap, Color("7b8790"))
		draw_rect(Rect2(cap.end.x - 4.0, cap.position.y, 4.0, cap.size.y), Color("5a6772"))
		draw_line(cap.position, Vector2(cap.position.x, cap.end.y), Color("a1a9a8"), 1.0)
		for offset: int in range(16, int(cap.size.y), 27):
			var seam: Vector2 = cap.position + Vector2(0, offset)
			draw_line(seam, seam + Vector2(cap.size.x, 0.0), Color("55636e"), 1.0)
	draw_line(Vector2(cap.position.x, cap.end.y), cap.end, Color("57616a"), 1.0)


func _masonry_strip(destination: Rect2, source: Rect2, repeat_width: float) -> void:
	var x: float = destination.position.x
	while x < destination.end.x:
		var width: float = minf(repeat_width, destination.end.x - x)
		var span: Rect2 = Rect2(x, destination.position.y, width, destination.size.y)
		var sample: Rect2 = Rect2(source.position, Vector2(source.size.x * width / repeat_width, source.size.y))
		draw_texture_rect_region(WorldgenArt.WALL, span, sample, WALL_TINT)
		x += width
