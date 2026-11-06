class_name NeighborhoodGround
extends Node2D
## Shared street surfaces and court bands replace per-building paving islands.
var layout: StreetLayout
func _draw() -> void:
	var bounds: Rect2=layout.world_bounds
	draw_rect(bounds,Color("65756e"))
	draw_texture_rect(StreetBlock.ConcreteTexture,bounds,true,Color(0.62,0.77,0.74,0.32))
	var cols: int=NeighborhoodLayout.SIZES.find(layout.world_data["size"])+(4 if layout.world_data.get("version")==4 else 3)
	for index: int in range(0,layout.world_data.entities.size(),cols):
		var foot: float=0
		for i: int in range(cols):foot+=float(layout.world_data.entities[index+i].rect[1]+layout.world_data.entities[index+i].rect[3])/cols
		var forecourt: Rect2=Rect2(48,foot-12,bounds.size.x-96,112)
		draw_rect(forecourt,Color("8b9387"));draw_texture_rect(StreetBlock.PavingTexture,forecourt,true,Color(0.88,0.94,0.88,0.55))
		for x: int in range(64,int(bounds.size.x)-64,48):draw_line(Vector2(x,foot+4),Vector2(x,foot+96),Color(0.26,0.36,0.35,0.18),1)
	for road: Rect2 in layout.roads:
		draw_rect(road.grow(24),Color("74857e"));draw_texture_rect(StreetBlock.PavingTexture,road.grow(22),true,Color(0.9,0.96,0.9,0.45))
	for road: Rect2 in layout.roads:
		draw_rect(road,Color("344b57"));draw_texture_rect(StreetBlock.AsphaltTexture,road,true,Color(0.74,0.86,0.93,0.55))
		if road.size.x>road.size.y and road.size.y>=200:
			for x: int in range(24,int(road.size.x),96):draw_line(Vector2(x,road.get_center().y),Vector2(x+40,road.get_center().y),Color("bbb99a"),2)
	for road: Rect2 in layout.roads:
		var horizontal: bool=road.size.x>road.size.y
		for offset: int in range(0,int(road.size.x if horizontal else road.size.y),32):
			var p: Vector2=road.position+(Vector2(offset,-5) if horizontal else Vector2(-5,offset))
			var junction: bool=false
			for other: Rect2 in layout.roads:
				if other!=road and other.grow(4).has_point(p):junction=true
			if not junction:
				draw_line(p,p+(Vector2(26,0) if horizontal else Vector2(0,26)),Color("a8aea0"),4)
				if offset%160==0:
					draw_rect(Rect2(p+Vector2(6,8),Vector2(18,6)),Color("233d46"))
	for e: Dictionary in layout.world_data.entities:
		var door: Vector2=WorldLayout.point(e.door)
		draw_rect(Rect2(door-Vector2(30,48),Vector2(60,10)),Color("abb0a0"))
		draw_rect(Rect2(door-Vector2(32,38),Vector2(64,7)),Color("657873"))
		draw_colored_polygon(PackedVector2Array([door+Vector2(-20,-40),door+Vector2(20,-40),door+Vector2(58,18),door+Vector2(-40,18)]),Color(1,0.77,0.42,0.065))
		# Plants live at the wall/curb seams; deterministic clusters do not affect navigation.
		for i: int in range(7):
			var p: Vector2=Vector2(e.rect[0]+e.rect[2]-18+i*4,e.rect[1]+e.rect[3]+6)
			draw_line(p,p+Vector2((i%3-1)*5,-6-i%4),Color("667e59"),2)
