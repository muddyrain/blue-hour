class_name MissionCardMark
extends Control
## Small geometric marks identify the action category without baked text or UI images.

var role: String = ""


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var scale_factor: float = minf(size.x, size.y) / 34.0
	if scale_factor <= 0.0:
		return
	draw_set_transform(size * 0.5, 0.0, Vector2.ONE * scale_factor)
	var accent: Color = CampStyle.CORAL if role == "finale" else CampStyle.TEAL
	match role:
		"supply":
			draw_line(Vector2(-10, 0), Vector2(10, 0), accent, 1.6, true)
			draw_arc(Vector2(0, 0), 9, 0.12, PI - 0.12, 14, accent, 1.6, true)
			for x: float in [-5.0, 0.0, 5.0]:
				draw_line(Vector2(x, -3), Vector2(x + 1.5, -8), accent, 1.3, true)
		"equipment":
			draw_rect(Rect2(-10, -6, 20, 15), accent, false, 1.6)
			draw_line(Vector2(-10, -1), Vector2(10, -1), accent, 1.6)
			draw_line(Vector2(0, -6), Vector2(0, 9), accent, 2.6)
		"event":
			draw_line(Vector2(0, 10), Vector2(0, 0), accent, 2.0, true)
			draw_line(Vector2(0, 0), Vector2(-8, -8), accent, 2.0, true)
			draw_line(Vector2(0, 0), Vector2(8, -8), CampStyle.AMBER, 2.0, true)
			draw_circle(Vector2(-8, -8), 2.4, accent)
			draw_circle(Vector2(8, -8), 2.4, CampStyle.AMBER)
		"investigation":
			var paper: PackedVector2Array = PackedVector2Array([Vector2(-8, -12), Vector2(3, -12),
				Vector2(9, -6), Vector2(9, 12), Vector2(-8, 12), Vector2(-8, -12)])
			draw_polyline(paper, accent, 1.5, true)
			draw_polyline(PackedVector2Array([Vector2(3, -12), Vector2(3, -6), Vector2(9, -6)]), accent, 1.5, true)
			for y: float in [-2.0, 3.0, 7.0]:
				draw_line(Vector2(-4, y), Vector2(5, y), accent, 1.2, true)
		"rescue":
			draw_line(Vector2(-8, 0), Vector2(8, 0), accent, 3.0)
			draw_line(Vector2(0, -8), Vector2(0, 8), accent, 3.0)
		"finale":
			draw_line(Vector2(-6, -11), Vector2(-6, 11), accent, 1.8, true)
			draw_polyline(PackedVector2Array([Vector2(-6, -10), Vector2(10, -7), Vector2(-6, 0)]), accent, 1.8, true)
