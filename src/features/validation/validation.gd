extends Node2D
## A display/input probe. Clicking is not a proposed squad control scheme.

const FIELD: Rect2 = Rect2(96.0, 152.0, 1088.0, 448.0)
const GRID_SIZE: int = 64

@onready var _marker: Sprite2D = $Marker


func _draw() -> void:
	draw_rect(FIELD, Color("102632"))
	for x: int in range(96, 1185, GRID_SIZE):
		draw_line(Vector2(x, 152), Vector2(x, 600), Color("1a3642"))
	for y: int in range(152, 601, GRID_SIZE):
		draw_line(Vector2(96, y), Vector2(1184, y), Color("1a3642"))
	draw_rect(FIELD, Color("437482"), false, 2.0)
	draw_circle(Vector2(640, 376), 72.0, Color("193c49"))
	draw_line(Vector2(620, 376), Vector2(660, 376), Color("8acbc8"), 2.0)
	draw_line(Vector2(640, 356), Vector2(640, 396), Color("8acbc8"), 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("place_probe"):
		var point: Vector2 = get_global_mouse_position()
		if FIELD.has_point(point):
			_marker.position = point
			print("BH_PROBE placed=%s" % point)
			get_viewport().set_input_as_handled()
