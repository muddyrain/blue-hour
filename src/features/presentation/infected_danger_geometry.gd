class_name InfectedDangerGeometry
extends RefCounted
## Map-space danger footprints projected exactly once into the isometric canvas.

const INK: Color = Color("22201e")
const AMBER: Color = Color("efbe73")
const CREAM: Color = Color("e8dcc4")


static func unshaded() -> CanvasItemMaterial:
	var material: CanvasItemMaterial = CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return material


static func circle(center: Vector2, radius: float, fraction: float = 1.0) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var segments: int = maxi(2, ceili(64.0 * fraction))
	for index: int in range(segments + 1):
		var angle: float = -PI * 0.5 + TAU * fraction * float(index) / float(segments)
		points.append(IsoSpace.to_view(center + Vector2.from_angle(angle) * radius))
	return points


static func rim(canvas: CanvasItem, center: Vector2, radius: float, colour: Color,
		fill: float = 0.09, progress: float = -1.0) -> void:
	var boundary: PackedVector2Array = circle(center, radius)
	canvas.draw_colored_polygon(boundary, Color(colour, fill))
	canvas.draw_polyline(boundary, Color(INK, colour.a), 5.0, true)
	canvas.draw_polyline(boundary, colour, 2.5, true)
	if progress > 0.0:
		canvas.draw_polyline(circle(center, radius - 4.0, clampf(progress, 0.0, 1.0)),
			Color(CREAM, colour.a), 2.2, true)
