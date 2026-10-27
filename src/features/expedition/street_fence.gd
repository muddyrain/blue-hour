class_name StreetFence
extends Node2D
## The visible posts and rail sit exactly on the authored navigation blocker.

var footprint: Rect2


func _draw() -> void:
	var width: float = footprint.size.x
	draw_rect(Rect2(0,-footprint.size.y,width,footprint.size.y),Color("2b4145"))
	for x: int in range(0,int(width)+1,24):
		draw_line(Vector2(x,-4),Vector2(x,-46),Color("344a4d"),4)
		draw_line(Vector2(x,-44),Vector2(minf(x+24,width),-20),Color("82918a"),1)
		draw_line(Vector2(x,-20),Vector2(minf(x+24,width),-44),Color("82918a"),1)
	draw_line(Vector2(0,-44),Vector2(width,-44),Color("b1b4a0"),3)
	draw_line(Vector2(0,-18),Vector2(width,-18),Color("596f6d"),2)
