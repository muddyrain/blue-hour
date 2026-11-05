class_name NeighborhoodWall
extends Node2D
## The visible low brick wall is the same footprint used by navigation and LOS.
var footprint: Rect2
func _draw() -> void:
	var width: float=footprint.size.x
	draw_rect(Rect2(8,-10,width,15),Color(0.08,0.15,0.18,0.28))
	draw_rect(Rect2(0,-42,width,42),Color("536461"))
	draw_rect(Rect2(0,-46,width,8),Color("9caaa0"))
	for y: int in [-28,-14]:
		draw_line(Vector2(0,y),Vector2(width,y),Color("7d8980"),1)
		for x: int in range(0,int(width),40):draw_line(Vector2(x+(16 if y==-14 else 0),y),Vector2(x+(16 if y==-14 else 0),y+12),Color("425553"),1)
