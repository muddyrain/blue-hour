class_name WorldFurniture
extends Node2D
## Small original vector environment modules. Decorative and traversable by design.
var kind: String = "lamp"
var refined: bool = false
var variant: int = 0
func _draw() -> void:
	if refined:
		if kind == "planter":
			_draw_planter()
		else:
			_draw_lamp()
		return
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


func _draw_planter() -> void:
	# A shallow, readable ceramic bowl, with individual leaves rather than a green cloud.
	draw_set_transform(Vector2(7, 2), 0, Vector2(1, 0.19))
	draw_circle(Vector2.ZERO, 24, Color(0.06, 0.12, 0.14, 0.24))
	draw_set_transform(Vector2.ZERO)
	var clay: Color = Color("896b56") if variant % 2 == 0 else Color("667875")
	draw_colored_polygon(PackedVector2Array([Vector2(-20,-15), Vector2(20,-15), Vector2(15,0), Vector2(-15,0)]), clay)
	draw_line(Vector2(-15,-2), Vector2(15,-2), clay.darkened(0.25), 2)
	draw_line(Vector2(-20,-15), Vector2(20,-15), clay.lightened(0.2), 3)
	draw_set_transform(Vector2(0,-15), 0, Vector2(1,0.22))
	draw_circle(Vector2.ZERO, 18, Color("3c4438"))
	draw_set_transform(Vector2.ZERO)
	for i: int in range(8):
		var root: Vector2 = Vector2(-13+i*3.5,-15)
		var tip: Vector2 = root+Vector2((i%3-1)*8,-12-(i*7+variant)%13)
		var bend: Vector2 = root.lerp(tip,0.55)
		var wing: Vector2 = (tip-root).normalized().orthogonal()*3
		draw_line(root,tip,Color("526746"),1.2)
		draw_colored_polygon(PackedVector2Array([root.lerp(tip,0.25),bend+wing,tip,bend-wing]),Color("778c60") if i%2 else Color("596f51"))
		if i in [2,5]:
			draw_circle(tip,2.5,Color("c4a986") if variant%2 else Color("b7baa0"))
	for i: int in range(5):
		draw_line(Vector2(-12+i*6,-10),Vector2(-11+i*6,-5),clay.lightened(0.08),1)


func _draw_lamp() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(-4,0),Vector2(4,0),Vector2(56,18),Vector2(47,18)]),Color(0.09,0.15,0.17,0.18))
	draw_rect(Rect2(-6,-5,12,6),Color("48585d"))
	draw_line(Vector2.ZERO,Vector2(0,-107),Color("253d46"),5)
	draw_line(Vector2(-1,-5),Vector2(-1,-106),Color("768280"),1)
	draw_polyline(PackedVector2Array([Vector2(0,-103),Vector2(6,-119),Vector2(29,-119),Vector2(35,-108)]),Color("465b61"),4)
	for i: int in range(4):
		draw_circle(Vector2(35,-100),13+i*8,Color(1,0.75,0.41,0.014))
	draw_colored_polygon(PackedVector2Array([Vector2(26,-111),Vector2(44,-111),Vector2(41,-92),Vector2(29,-92)]),Color("66736b"))
	draw_rect(Rect2(29,-108,12,14),Color("e2c38e"))
	draw_rect(Rect2(31,-106,8,10),Color("ffe0a1"))
	draw_line(Vector2(35,-110),Vector2(35,-93),Color("8d8167"),1)
