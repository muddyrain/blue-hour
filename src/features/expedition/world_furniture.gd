class_name WorldFurniture
extends Node2D
## Small original vector environment modules. Decorative and traversable by design.
var kind: String = "lamp"
func _draw() -> void:
	match kind:
		"lamp":
			draw_set_transform(Vector2(12,0),0,Vector2(1,0.22)); draw_circle(Vector2.ZERO,22,Color(0.08,0.16,0.18,0.25)); draw_set_transform(Vector2.ZERO)
			draw_line(Vector2.ZERO,Vector2(0,-110),Color("263e49"),6)
			draw_polyline(PackedVector2Array([Vector2(0,-106),Vector2(8,-124),Vector2(32,-124),Vector2(40,-110)]),Color("435760"),5)
			for i: int in range(5): draw_circle(Vector2(40,-102),18+i*9,Color(1,0.76,0.4,0.018))
			draw_rect(Rect2(31,-114,18,22),Color("c4a678")); draw_rect(Rect2(34,-111,12,16),Color("ffe1a1"))
		"planter":
			draw_rect(Rect2(-25,-16,50,18),Color("3c5255")); draw_rect(Rect2(-28,-20,56,6),Color("819087"))
			for i: int in range(7): draw_circle(Vector2(-20+i*7,-25-(i%3)*5),10,Color("536f5b") if i%2 else Color("748268"))
		"crate":
			draw_rect(Rect2(-18,-30,36,30),Color("776a51")); draw_rect(Rect2(-18,-30,36,30),Color("394d4e"),false,2)
			for x: int in [-12,0,12]: draw_line(Vector2(x,-28),Vector2(x,-2),Color("9d8c67"),2)
			draw_line(Vector2(-16,-26),Vector2(16,-4),Color("a18b61"),4)
		"fence":
			for x: int in range(-48,49,12): draw_line(Vector2(x,0),Vector2(x,-40),Color("596b66"),4)
			for y: int in [-32,-12]: draw_line(Vector2(-50,y),Vector2(50,y),Color("819083"),4)
