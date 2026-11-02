class_name MotionHands
extends Node2D
## Small layered sleeve/hand rig adapts original art to the unchanged ballistic grip.

const SLEEVES: Array[Color] = [Color("334a62"), Color("6e8051"), Color("b25b48"), Color("ece1d3"), Color("bb873a")]
const GLOVES: Array[Color] = [Color("33444b"), Color("edc9a6"), Color("edc9a6"), Color("323140"), Color("3d3b38")]
var variant: int = 0
var facing: Vector2 = Vector2.RIGHT
var trigger: Vector2 = Vector2.ZERO
var support: Vector2 = Vector2.ZERO


func _draw() -> void:
	var side: float = -1.0 if facing.x < -0.1 else 1.0
	var shoulder: Vector2 = Vector2(side * 7.0, -36.0)
	var other: Vector2 = Vector2(-side * 5.0, -35.0)
	if facing.y < -0.4:
		shoulder.y = -40.0
		other.y = -40.0
	_arm(other, support, SLEEVES[variant])
	_arm(shoulder, trigger, SLEEVES[variant])
	for hand: Vector2 in [support, trigger]:
		draw_circle(hand, 2.5, Color("242d35"))
		draw_circle(hand, 1.6, GLOVES[variant])


func _arm(shoulder: Vector2, hand: Vector2, colour: Color) -> void:
	var elbow: Vector2 = shoulder.lerp(hand, 0.55) + Vector2(0, 3)
	var points: PackedVector2Array = PackedVector2Array([shoulder, elbow, hand])
	draw_polyline(points, Color("28313b"), 5.0, true)
	draw_polyline(points, colour, 3.2, true)
