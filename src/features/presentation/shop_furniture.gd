class_name ShopFurniture
extends Node2D
## Original cel-shaped props anchored INSIDE the existing supply shop blocker.


func _draw() -> void:
	for index: int in range(3):
		var origin: Vector2 = Vector2(-158 + index * 28, -4)
		var height: float = 24.0 + float(index % 2) * 10.0
		var body: Rect2 = Rect2(origin - Vector2(0,height),Vector2(25,height))
		draw_rect(body, Color("77664e"))
		draw_rect(body, Color("20333b"), false, 1.5)
		draw_line(body.position + Vector2(0,7),body.position + Vector2(25,7),Color("a79470"),2)
		draw_colored_polygon(PackedVector2Array([body.position,body.position+Vector2(5,-5),body.position+Vector2(29,-5),body.position+Vector2(25,0)]), Color("af9b72"))
		draw_line(body.position + Vector2(5,12),body.end - Vector2(5,5),Color("33454a"),2)
	# Freestanding wayfinding post on the already blocked forecourt edge.
	draw_rect(Rect2(-178,-72,4,68),Color("2c4249"))
	draw_rect(Rect2(-194,-84,42,24),Color("305761"))
	draw_rect(Rect2(-194,-84,42,24),Color("9dad9a"),false,1)
	draw_line(Vector2(-184,-72),Vector2(-162,-72),Color("e6dfbf"),2)
	draw_line(Vector2(-184,-72),Vector2(-178,-77),Color("e6dfbf"),2)
	draw_line(Vector2(-184,-72),Vector2(-178,-67),Color("e6dfbf"),2)
