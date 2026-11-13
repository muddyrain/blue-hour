class_name IndustrialYardWall
extends Node2D
## Wall caps follow each frozen obstruction, including north-south runs.

const CAP_RISE: float = 23.0
const FACE_SAMPLE: Rect2 = Rect2(4.0, 65.0, 171.0, 55.0)
const CAP_SAMPLE: Rect2 = Rect2(30.0, 46.0, 145.0, 15.0)
const WALL_TINT: Color = Color(0.68, 0.76, 0.85)

var footprint: Rect2


func _draw() -> void:
	IsoDraw.wall(self, footprint.size.x, maxf(footprint.size.y, 12.0))


func _masonry_strip(destination: Rect2, source: Rect2, repeat_width: float) -> void:
	var x: float = destination.position.x
	while x < destination.end.x:
		var width: float = minf(repeat_width, destination.end.x - x)
		var span: Rect2 = Rect2(x, destination.position.y, width, destination.size.y)
		var sample: Rect2 = Rect2(source.position, Vector2(source.size.x * width / repeat_width, source.size.y))
		draw_texture_rect_region(WorldgenArt.WALL, span, sample, WALL_TINT)
		x += width
