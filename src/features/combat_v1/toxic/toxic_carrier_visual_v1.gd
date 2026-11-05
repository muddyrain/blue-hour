class_name ToxicCarrierVisualV1
extends Node2D
## Authored shoulder sacs and a directed casting heave, composed over the old body.

const SACS: Texture2D = preload("res://assets/combat_v1/toxic/carrier_sacs.svg")

var _heading: Vector2 = Vector2.RIGHT
var _casting: bool = false
var _progress: float = 0.0


func _draw() -> void:
	var side: float = -1.0 if _heading.x < 0.0 else 1.0
	var heave: float = sin(_progress * PI) if _casting else 0.0
	var shift: Vector2 = Vector2(-side * 3.0, -47.0 - heave * 5.0)
	var scale_x: float = 0.82 if absf(_heading.y) > absf(_heading.x) else 1.0
	draw_set_transform(shift, side * heave * -0.10, Vector2(side * scale_x, 1.0 + heave * 0.08))
	draw_texture_rect(SACS, Rect2(-23.0, -30.0, 46.0, 44.0), false)
	if _casting:
		# The arm/vent gesture points toward the frozen landing point.
		var local_heading: Vector2 = Vector2(_heading.x / (side * scale_x), _heading.y)
		var arm: Vector2 = local_heading * 18.0 + Vector2(0.0, -6.0 - heave * 7.0)
		draw_polyline(PackedVector2Array([Vector2(7.0, -1.0), Vector2(11.0, -6.0), arm]), Color("2b3e35"), 6.0, true)
		draw_polyline(PackedVector2Array([Vector2(7.0, -2.0), Vector2(11.0, -7.0), arm + Vector2(0.0, -1.0)]), Color("a0af72"), 2.2, true)
		for index: int in range(3):
			var point: Vector2 = arm + Vector2(float(index) * 4.0, -5.0 - float(index) * heave * 5.0)
			draw_circle(point, 1.2 + heave, Color(Color("c7df8b"), 0.35 + heave * 0.25))
	draw_set_transform(Vector2.ZERO)


func present(heading: Vector2, casting: bool, progress: float = 0.0) -> void:
	if heading.is_finite() and heading.length_squared() > 0.001:
		_heading = heading.normalized()
	_casting = casting
	_progress = clampf(progress, 0.0, 1.0)
	queue_redraw()
