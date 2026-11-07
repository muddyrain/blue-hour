class_name PumpBreacherArt
extends Node2D
## Asymmetric loading brace attached to the existing heavy motion atlas, at logical feet.

const EDGE: Color = Color("25292d")
const STEEL: Color = Color("505c60")
const RIM: Color = Color("9ba09a")
const RUST: Color = Color("bd8a50")

var _direction: Vector2 = Vector2.RIGHT
var _winding: bool = false
var _down: bool = false


func _draw() -> void:
	var shoulder: Vector2 = Vector2(-19, -59)
	var mirror_x: float = -1.0 if _direction.x < -0.15 else 1.0
	var pitch: float = 0.0
	if _down:
		shoulder = Vector2(-23, -11)
		pitch = -0.72
	elif _winding:
		shoulder += Vector2(-5, 8)
		pitch = 0.33
	elif _direction.y < -0.6:
		shoulder.y -= 4.0
	draw_set_transform(Vector2(shoulder.x * mirror_x, shoulder.y), pitch * mirror_x, Vector2(mirror_x, 1))
	_draw_brace()
	draw_set_transform(Vector2.ZERO)


func update_pose(facing: Vector2, winding: bool, down: bool) -> void:
	var previous: Vector2 = _direction
	if facing.length_squared() > 0.001:
		_direction = Vector2.from_angle(roundf(facing.angle() / (PI / 4.0)) * (PI / 4.0))
	if not _direction.is_equal_approx(previous) or winding != _winding or down != _down:
		_winding = winding
		_down = down
		queue_redraw()


func _draw_brace() -> void:
	var outer: PackedVector2Array = PackedVector2Array([
		Vector2(-22, -11), Vector2(-15, -22), Vector2(0, -24), Vector2(12, -16),
		Vector2(19, -8), Vector2(13, 3), Vector2(-10, 7), Vector2(-22, 1)])
	draw_colored_polygon(outer, EDGE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-19, -10), Vector2(-13, -19), Vector2(0, -20),
		Vector2(13, -12), Vector2(16, -7), Vector2(11, 0), Vector2(-10, 4), Vector2(-19, -1)]), STEEL)
	draw_polyline(PackedVector2Array([Vector2(-19, -10), Vector2(-13, -19), Vector2(0, -20), Vector2(13, -12)]),
		RIM, 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(-20, 1), Vector2(-27, 14), Vector2(-22, 29), Vector2(-10, 32)]),
		EDGE, 7.0, true)
	draw_polyline(PackedVector2Array([Vector2(-20, 1), Vector2(-27, 14), Vector2(-22, 29), Vector2(-10, 32)]),
		RUST, 3.0, true)
	draw_line(Vector2(-15, 5), Vector2(10, 22), EDGE, 8.0, true)
	draw_line(Vector2(-15, 5), Vector2(10, 22), Color("776247"), 3.0, true)
	draw_circle(Vector2(-12, -7), 8.0, EDGE, true)
	draw_arc(Vector2(-12, -7), 5.3, 0.0, TAU, 20, RUST, 2.0, true)
	draw_circle(Vector2(-12, -7), 2.7, Color("ffc47b") if _winding else Color("80634d"), true)
	for rivet: Vector2 in [Vector2(-15, -15), Vector2(0, -16), Vector2(10, -11), Vector2(10, -2)]:
		draw_circle(rivet, 1.3, Color("adb0a2"), true)
	for i: int in range(3):
		var point: Vector2 = Vector2(-2 + i * 4, -5)
		draw_line(point, point + Vector2(2, -4), Color("c29354"), 2.0, true)
