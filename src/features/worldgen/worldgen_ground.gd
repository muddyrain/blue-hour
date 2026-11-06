class_name WorldgenGround
extends Node2D
## Flat materials read the frozen roads/parcels; no independent collision geometry.
var layout: StreetLayout

func _draw() -> void:
	draw_rect(layout.world_bounds,Color("586b60"))
	draw_texture_rect(StreetBlock.GrassTexture,layout.world_bounds,true,Color(0.77,0.88,0.76,0.42))
	for parcel: Dictionary in layout.world_data.parcels:
		var area: Rect2=WorldLayout.rect(parcel.rect)
		var paved: bool=parcel.kind in ["shopfront","loading","service","parking"]
		draw_rect(area,Color("788079") if paved else Color("63745e"))
		draw_texture_rect(StreetBlock.ConcreteTexture if paved else StreetBlock.GrassTexture,area,true,Color(0.9,0.94,0.88,0.28))
		if parcel.kind in ["parking","loading"]:
			var court: Rect2=Rect2(area.position.x+40,area.end.y-150,area.size.x-80,120)
			draw_rect(court,Color("626d6d"))
			draw_texture_rect(StreetBlock.ConcreteTexture,court,true,Color(0.92,0.95,0.92,0.4))
			for x: int in range(int(court.position.x)+32,int(court.end.x)-80,104):
				draw_line(Vector2(x,court.position.y+12),Vector2(x,court.end.y-24),Color("b2b6a5"),2)
				draw_line(Vector2(x,court.end.y-24),Vector2(x+58,court.end.y-24),Color("b2b6a5"),2)
	# Shared court access follows the same final navigation used by the actors.
	var routes: Dictionary=ExplorationLayout._routing(layout.world_data)
	var nav: FieldNavigation=routes.nav
	for parcel: Dictionary in layout.world_data.parcels:
		for entity: Dictionary in layout.world_data.entities:
			if entity.id not in parcel.buildings: continue
			var path: PackedVector2Array=nav.path_between(WorldLayout.point(parcel.entrance),WorldLayout.point(entity.door))
			if path.size()>1:
				draw_polyline(path,Color("7b8777"),38,true)
				draw_polyline(path,Color("949b87"),30,true)
	# One continuous verge on each street, cut by all actual connections.
	for road: Rect2 in layout.roads:
		var paving: Rect2=road.grow(32).intersection(layout.world_bounds)
		draw_rect(paving,Color("93998a"))
		draw_texture_rect(StreetBlock.PavingTexture,paving,true,Color(0.88,0.91,0.86,0.52))
	for entity: Dictionary in layout.world_data.entities:
		var block: Rect2=WorldLayout.rect(entity.rect)
		var door: Vector2=WorldLayout.point(entity.door)
		var apron: Rect2=Rect2(block.position.x-8,block.end.y-3,block.size.x+16,80)
		draw_rect(apron,Color("969b8c"))
		draw_texture_rect(StreetBlock.PavingTexture,apron,true,Color(0.9,0.94,0.87,0.56))
		draw_rect(Rect2(block.position.x-5,block.end.y-5,block.size.x+10,10),Color("434e48"))
		draw_rect(Rect2(door-Vector2(29,48),Vector2(58,8)),Color("c1bdac"))
		draw_rect(Rect2(door-Vector2(32,40),Vector2(64,7)),Color("7a8177"))
	for road: Rect2 in layout.roads:
		draw_rect(road,Color("34434b"))
		draw_texture_rect(StreetBlock.AsphaltTexture,road,true,Color(0.73,0.8,0.82,0.45))
	for road: Rect2 in layout.roads:
		var horizontal: bool=road.size.x>road.size.y
		var length: int=int(road.size.x if horizontal else road.size.y)
		for step: int in range(12,length-12,32):
			for side: int in [-1,1]:
				var p: Vector2=road.position+(Vector2(step,-3 if side<0 else road.size.y+1) if horizontal else Vector2(-3 if side<0 else road.size.x+1,step))
				if _junction(p,road): continue
				draw_line(p,p+(Vector2(26,0) if horizontal else Vector2(0,26)),Color("b6b6a4"),3)
				if step%160==12: draw_rect(Rect2(p+Vector2(1,5),Vector2(18,4)),Color("28363a"))
		for step: int in range(32,length-32,88):
			var p: Vector2=Vector2(road.position.x+step,road.get_center().y) if horizontal else Vector2(road.get_center().x,road.position.y+step)
			if not _junction(p,road): draw_line(p,p+(Vector2(32,0) if horizontal else Vector2(0,32)),Color("c3b27d"),2)
	# Crossings mark the actual perpendicular road connections, never a collision.
	for a: Rect2 in layout.roads:
		if a.size.x<=a.size.y: continue
		for b: Rect2 in layout.roads:
			if b.size.x>=b.size.y or not a.intersects(b): continue
			for stripe: int in range(8,int(b.size.x)-8,17):
				var y: float=a.position.y-25 if b.position.y<a.position.y else a.end.y+8
				draw_rect(Rect2(b.position.x+stripe,y,9,18),Color("b9bca9"))

func _junction(point: Vector2,current: Rect2) -> bool:
	for other: Rect2 in layout.roads:
		if other!=current and other.grow(5).has_point(point): return true
	return false
